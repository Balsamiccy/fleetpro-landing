-- ============================================================================
-- PHASE 3 — index recommendations for comparables_shared.
--
-- RECOMMENDATIONS ONLY. Nothing here has been run. Do not execute against
-- production without reviewing against the table's actual current indexes
-- and size (438,000+ rows per the admin tooling) — check with:
--   SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'comparables_shared';
-- before adding anything, in case some of these already exist under a
-- different name.
--
-- Already known to exist (from phase4_migration.sql):
--   comparables_source_idx    ON comparables_shared (source_website)
--   comparables_saledate_idx  ON comparables_shared (sale_date DESC NULLS LAST)
--
-- What's proposed below supports the new public_market_* functions in
-- build/MARKET_PUBLIC_FUNCTIONS.sql, which all filter on
-- (make, model[, variant]) plus taxonomy_match_status, and group by currency.
-- Without an index, each call to public_market_model_summary() or
-- public_market_recent_listings() does a sequential scan of the full table.
-- ============================================================================

-- Composite index for the make/model/variant lookups every public_market_*
-- function performs. Lower() is used in the functions for case-insensitive
-- matching, so the index needs to match on the same expression to be used.
CREATE INDEX IF NOT EXISTS comparables_taxonomy_lookup_idx
  ON comparables_shared (lower(make), lower(model), lower(variant));

-- Speeds up the WHERE taxonomy_match_status IN (...) filter present in every
-- public_market_* function and in the existing admin_failed_records().
CREATE INDEX IF NOT EXISTS comparables_taxonomy_status_idx
  ON comparables_shared (taxonomy_match_status);

-- Speeds up currency-grouped aggregates in public_market_model_summary().
CREATE INDEX IF NOT EXISTS comparables_currency_idx
  ON comparables_shared (currency);

-- Partial index over rows that actually have a sold price, used by every
-- median/min/max FILTER (WHERE sold_price > 0) in public_market_model_summary.
-- Partial because most rows may not have a confirmed sale (see
-- admin_failed_records()'s "No sale price recorded" reason) — indexing only
-- the rows that matter keeps this smaller than a full-column index.
CREATE INDEX IF NOT EXISTS comparables_sold_price_idx
  ON comparables_shared (sold_price) WHERE sold_price IS NOT NULL AND sold_price > 0;

CREATE INDEX IF NOT EXISTS comparables_asking_price_idx
  ON comparables_shared (asking_price) WHERE asking_price IS NOT NULL AND asking_price > 0;

-- ── Before running ──────────────────────────────────────────────────────
-- On a table this size, CREATE INDEX takes a write lock by default (blocking
-- writes for the duration) unless you use CREATE INDEX CONCURRENTLY, which
-- cannot run inside a transaction block. If imports or admin writes to this
-- table happen on any regular schedule, prefer the CONCURRENTLY form and run
-- each statement separately, e.g.:
--
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS comparables_taxonomy_lookup_idx
--     ON comparables_shared (lower(make), lower(model), lower(variant));
--
-- CONCURRENTLY is intentionally not used above so this file can still be
-- reviewed and run as a single straightforward script if a maintenance
-- window is acceptable — swap it in if not.
