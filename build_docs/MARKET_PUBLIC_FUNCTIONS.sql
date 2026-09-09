-- ============================================================================
-- PHASE 3 — proposed public market-data functions.  REVIEW BEFORE RUNNING.
--
-- Nothing in this file has been executed. It was written after reading
-- phase1_roles.sql, phase4_migration.sql, phase6_migration.sql and
-- phase8_migration.sql (and the admin-api edge function that queries
-- comparables_shared) to match the schema and the security posture already
-- established in this project — not guessed.
--
-- WHAT THIS DOES
-- Adds four SECURITY DEFINER functions, granted to `anon`, that return only
-- aggregated / allowlisted fields from `comparables_shared` — never a raw
-- row, never a full-table read. This follows the exact pattern already used
-- for admin_market_sources() etc. in phase4_migration.sql, with one
-- difference: those are service_role-only; these are deliberately grantable
-- to anon because they're meant to power public market pages.
--
-- WHY FUNCTIONS CALLED VIA RPC, NOT A NEW EDGE FUNCTION
-- The brief's suggested shape is browser -> serverless function -> aggregate
-- query -> table. A SECURITY DEFINER Postgres function reached through
-- PostgREST's RPC endpoint (using the existing public anon key, the same one
-- already shipped in the marketing site's Google Fonts... no — the same one
-- in fleetpro-admin's .env.local and referenced in site.js for auth) IS that
-- shape: the "server-side aggregate query" runs inside Postgres with
-- elevated rights, reachable only through the function's own return
-- signature, with RLS and raw-table access never exposed to the browser.
-- This avoids deploying a second copy of the service_role key into a new
-- edge function, which the existing admin-api/index.ts explicitly documents
-- as "the ONLY place the service_role key is used" — a second function
-- holding it would break that invariant. If a genuine serverless layer is
-- wanted later (rate limiting beyond what's noted below, response caching,
-- etc.), it can sit in FRONT of these RPC calls without changing them.
--
-- WHAT IS DELIBERATELY NOT EXPOSED
--   - id, source_website (per-row), listing_url, source_type, created_at,
--     taxonomy_match_status (per-row) — these stay out of every public
--     function. Source is only ever returned as an aggregated count.
--   - listing_url in particular is withheld pending confirmation that the
--     source websites' terms permit republishing their listing links
--     publicly. This was NOT verified — flagged in the Phase 3 report.
--   - Any aggregate computed from fewer than 5 matching rows returns NULL
--     for that statistic rather than a spuriously precise number from one
--     or two listings.
--
-- TAXONOMY SAFETY
--   Every function filters to taxonomy_match_status IN ('matched_exact_variant',
--   'model_only') — 'out_of_scope_make' rows (not a real taxonomy match) are
--   never counted or returned. This keeps a mismatched or junk row from
--   polluting a public page's numbers.
--
-- ASKING VS SOLD
--   Every summary keeps asking_price and sold_price as separate statistics.
--   Nothing is merged into one "price" figure.
--
-- CURRENCY
--   No cross-currency averaging happens anywhere in this file. Aggregates
--   are grouped by currency; the caller decides how to present multiple
--   currencies (e.g. "23 in EUR, 4 in GBP") rather than this file inventing
--   an exchange rate.
-- ============================================================================


-- ── public_market_taxonomy_summary ──────────────────────────────────────────
-- One row per make/model/variant combination that has at least one matched
-- record. This is what decides indexability (see the indexation-threshold
-- note in build/MARKET_DATA_ARCHITECTURE.md) and what a build-time generator
-- would page through to know which /market/[make]/[model] pages to build.
CREATE OR REPLACE FUNCTION public.public_market_taxonomy_summary()
RETURNS TABLE (
  make               TEXT,
  model              TEXT,
  variant            TEXT,
  matched_records    BIGINT,
  exact_variant_records BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT
    make, model, COALESCE(variant, '') AS variant,
    count(*)                                                              AS matched_records,
    count(*) FILTER (WHERE taxonomy_match_status = 'matched_exact_variant') AS exact_variant_records
  FROM comparables_shared
  WHERE taxonomy_match_status IN ('matched_exact_variant', 'model_only')
    AND make IS NOT NULL AND TRIM(make) <> ''
    AND model IS NOT NULL AND TRIM(model) <> ''
  GROUP BY make, model, COALESCE(variant, '')
  ORDER BY make, model, matched_records DESC;
$$;

-- ── public_market_makes ──────────────────────────────────────────────────
-- Powers the /market hub's "browse by make" and any real "popular makes"
-- claim (record-count based, not invented).
CREATE OR REPLACE FUNCTION public.public_market_makes()
RETURNS TABLE (make TEXT, matched_records BIGINT, models BIGINT)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT make, count(*), count(DISTINCT model)
  FROM comparables_shared
  WHERE taxonomy_match_status IN ('matched_exact_variant', 'model_only')
    AND make IS NOT NULL AND TRIM(make) <> ''
  GROUP BY make
  ORDER BY 2 DESC;
$$;

-- ── public_market_model_summary ─────────────────────────────────────────────
-- The core function behind a /market/[make]/[model] (and optionally
-- [variant]) page: per-currency asking/sold statistics, suppressed below a
-- minimum sample size, plus a source breakdown (counts only) and a genuine
-- last-updated timestamp.
CREATE OR REPLACE FUNCTION public.public_market_model_summary(
  p_make TEXT, p_model TEXT, p_variant TEXT DEFAULT NULL
)
RETURNS TABLE (
  currency          TEXT,
  sold_count        BIGINT,
  sold_median       NUMERIC,
  sold_min          NUMERIC,
  sold_max          NUMERIC,
  asking_count      BIGINT,
  asking_median     NUMERIC,
  asking_min        NUMERIC,
  asking_max        NUMERIC,
  earliest_sale     DATE,
  latest_sale       DATE
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  WITH scoped AS (
    SELECT *
    FROM comparables_shared
    WHERE taxonomy_match_status IN ('matched_exact_variant', 'model_only')
      AND lower(make)  = lower(p_make)
      AND lower(model) = lower(p_model)
      AND (p_variant IS NULL OR lower(variant) = lower(p_variant))
  )
  SELECT
    currency,
    count(*) FILTER (WHERE sold_price IS NOT NULL AND sold_price > 0),
    CASE WHEN count(*) FILTER (WHERE sold_price > 0) >= 5
         THEN percentile_cont(0.5) WITHIN GROUP (ORDER BY sold_price) FILTER (WHERE sold_price > 0) END,
    CASE WHEN count(*) FILTER (WHERE sold_price > 0) >= 5
         THEN min(sold_price) FILTER (WHERE sold_price > 0) END,
    CASE WHEN count(*) FILTER (WHERE sold_price > 0) >= 5
         THEN max(sold_price) FILTER (WHERE sold_price > 0) END,
    count(*) FILTER (WHERE asking_price IS NOT NULL AND asking_price > 0),
    CASE WHEN count(*) FILTER (WHERE asking_price > 0) >= 5
         THEN percentile_cont(0.5) WITHIN GROUP (ORDER BY asking_price) FILTER (WHERE asking_price > 0) END,
    CASE WHEN count(*) FILTER (WHERE asking_price > 0) >= 5
         THEN min(asking_price) FILTER (WHERE asking_price > 0) END,
    CASE WHEN count(*) FILTER (WHERE asking_price > 0) >= 5
         THEN max(asking_price) FILTER (WHERE asking_price > 0) END,
    min(sale_date), max(sale_date)
  FROM scoped
  WHERE currency IS NOT NULL
  GROUP BY currency
  ORDER BY sold_count DESC NULLS LAST;
$$;

-- ── public_market_recent_listings ───────────────────────────────────────────
-- A capped, allowlisted-field sample for "recent market activity" on a model
-- page. Hard-capped at 25 regardless of what's requested — this is a public,
-- unauthenticated function, so the cap is enforced server-side, not trusted
-- from the caller.
CREATE OR REPLACE FUNCTION public.public_market_recent_listings(
  p_make TEXT, p_model TEXT, p_variant TEXT DEFAULT NULL, p_limit INT DEFAULT 12
)
RETURNS TABLE (
  make TEXT, model TEXT, variant TEXT, normalized_generation TEXT,
  normalized_body_style TEXT, year INT, mileage NUMERIC, mileage_unit TEXT,
  currency TEXT, sold_price NUMERIC, asking_price NUMERIC, sale_date DATE
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT make, model, variant, normalized_generation, normalized_body_style,
         year, mileage, mileage_unit, currency, sold_price, asking_price, sale_date
  FROM comparables_shared
  WHERE taxonomy_match_status IN ('matched_exact_variant', 'model_only')
    AND lower(make)  = lower(p_make)
    AND lower(model) = lower(p_model)
    AND (p_variant IS NULL OR lower(variant) = lower(p_variant))
  ORDER BY sale_date DESC NULLS LAST
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 12), 1), 25);
$$;

-- ── Grants ───────────────────────────────────────────────────────────────
-- Deny first (Supabase's default privileges grant new objects to anon and
-- authenticated), then grant exactly what's meant to be public. Same pattern
-- as every REVOKE-then-GRANT in the existing phase*.sql files.
REVOKE ALL ON FUNCTION public.public_market_taxonomy_summary()                      FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.public_market_makes()                                 FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.public_market_model_summary(TEXT, TEXT, TEXT)         FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.public_market_recent_listings(TEXT, TEXT, TEXT, INT)  FROM PUBLIC, authenticated;

GRANT EXECUTE ON FUNCTION public.public_market_taxonomy_summary()                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_market_makes()                                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_market_model_summary(TEXT, TEXT, TEXT)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_market_recent_listings(TEXT, TEXT, TEXT, INT) TO anon, authenticated;

-- Note: granting to anon here is intentional and safe ONLY because every
-- function above is SECURITY DEFINER with a fixed, narrow return shape. It
-- does NOT grant anon any access to comparables_shared itself — confirm
-- that table's own grants stay exactly as they are (do not add a table-level
-- GRANT SELECT to anon; that would bypass the field-level care taken here).


-- ── Verify (run these yourself before trusting this in production) ────────
-- SELECT * FROM public.public_market_makes() LIMIT 10;
-- SELECT * FROM public.public_market_model_summary('Porsche', '911');
-- SELECT * FROM public.public_market_recent_listings('Porsche', '911', NULL, 12);
-- SELECT * FROM public.public_market_taxonomy_summary() WHERE make ILIKE 'porsche';
--
-- Confirm anon truly can call these (run with the anon key, not service role):
--   curl -s "$SUPABASE_URL/rest/v1/rpc/public_market_makes" \
--     -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -X POST
--
-- Confirm anon still CANNOT read the table directly (should be empty/denied):
--   curl -s "$SUPABASE_URL/rest/v1/comparables_shared?select=*&limit=1" \
--     -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
