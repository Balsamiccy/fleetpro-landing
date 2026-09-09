# Market-data architecture — Phase 3 findings and plan

This document covers items 9–31 of the Phase 3 brief: the real market-data layer. It's written so you can review the reasoning, not just the conclusion, since this is the part of Phase 3 that touches your database.

**Nothing in this document has been executed against your database or deployed anywhere.** The two `.sql` files beside this one are proposals to review and run yourself, the same way your own `phase1_roles.sql` through `phase8_migration.sql` are written to be reviewed before running.

## 1. What was inspected, and how

This session doesn't have a database connection or the Supabase CLI — everything below comes from reading files in `fleetpro-admin` (your internal admin dashboard repo), specifically:

- `phase1_roles.sql`, `phase4_migration.sql`, `phase6_migration.sql`, `phase8_migration.sql` — actual schema and RLS changes, with the developer's own comments explaining intent.
- `admin-api-index.ts` — the Supabase Edge Function that is, by its own header comment, "the ONLY place the service_role key is used." Every query it makes was read to see which tables and fields the admin tooling actually touches.
- `src/lib/supabase.js`, `src/lib/api.js`, `src/lib/permissions.js` — confirms the admin app's browser client only ever holds the public/anon key, and every privileged action is routed server-side.
- `.env.local` — confirms only `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` are present; no service-role key in any file this session could read.

The consumer-facing application (the actual product customers use to manage their collections) was **not** in the connected folders — only the admin dashboard and the marketing site were. That limits what could be verified about customer-facing RLS specifically; see §3.

## 2. The market-listings table

`comparables_shared` — confirmed via `admin-api-index.ts` queries and `phase4_migration.sql`. Fields seen in actual use:

`id, source_website, source_type, make, model, variant, normalized_generation, normalized_body_style, year, mileage, mileage_unit, currency, sold_price, asking_price, sale_date, listing_url, taxonomy_match_status, created_at, exterior_colour`

`taxonomy_match_status` takes at least three values: `matched_exact_variant`, `model_only`, `out_of_scope_make` — this is the field that makes taxonomy-safe filtering possible (§5).

The table holds roughly 438,000 rows (the number already used publicly on your site, and consistent with counts referenced in the admin tooling).

**What this table does not appear to contain**: no seller name, phone, email, address, account ID, or internal scraper token in any field referenced anywhere in the admin code. It reads as a genuinely public-safe aggregated dataset — distinct in kind from `vehicles`, `vehicle_valuations`, `documents`, `insurance_records` etc., which are customer data and were not touched by anything in this phase.

## 3. RLS status — what's confirmed vs. assumed

**Confirmed directly**: every query against `comparables_shared` in `admin-api-index.ts` goes through the service-role client (`admin.from('comparables_shared')...`), never the browser-side anon client. The admin app's aggregate functions (`admin_market_sources()`, `admin_duplicate_listings()`, `admin_failed_records()`) are explicitly `SECURITY DEFINER`, explicitly `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, and explicitly `GRANT EXECUTE ... TO service_role` only.

**Not directly confirmed**: whether `comparables_shared` itself currently has RLS enabled, and if so what policy (if any) it carries — that would have been set up before the four migration files available to this session (an earlier, un-reviewed migration, or configured directly in the Supabase dashboard). I did not find its `CREATE TABLE` or its RLS policy in anything this session could read.

Per your own instruction — *"If any data source is ambiguous, treat it as private until proven otherwise"* — this phase treats the table itself as **not** safely readable by `anon` until you confirm otherwise, and does not propose granting `anon` any table-level access. Section 6 explains why the proposed approach doesn't need that grant anyway.

**Also not confirmed**: RLS policies on the consumer tables (`vehicles`, `vehicle_valuations`, `documents`, etc.) themselves — only the service-role-only *views* built on top of them (`admin_user_directory`, `admin_valuation_directory`) were visible. The Security page written in this phase deliberately doesn't claim a specific RLS policy exists on those tables, for this reason — see its "What we do not claim" section.

## 4. Proposed architecture

```
Browser (anon key, same one already in the marketing site)
  → PostgREST RPC call: /rest/v1/rpc/public_market_model_summary
  → SECURITY DEFINER Postgres function (runs with elevated rights,
    but returns only the fixed, narrow shape it defines)
  → comparables_shared (read internally, never exposed as a raw table)
  → aggregated JSON response only
```

This is a refinement of the brief's suggested "browser → serverless function → aggregate query" shape, not a departure from it: a `SECURITY DEFINER` function reached through PostgREST's RPC endpoint **is** a server-side aggregate query — it runs inside Postgres with elevated rights, and the browser never sees more than the function's declared return columns. The alternative — a second Supabase Edge Function holding its own copy of the service-role key — was deliberately avoided, because `admin-api/index.ts` states outright that it is "the ONLY place the service_role key is used." Adding a second function with that key would quietly break an invariant your own codebase documents as deliberate. If you later want a real edge-function layer in front of these RPC calls (for response caching or more elaborate rate limiting), it can sit in front without changing the functions themselves.

Full proposed SQL: `build/MARKET_PUBLIC_FUNCTIONS.sql`. Four functions:

- `public_market_makes()` — make-level counts, for the market hub.
- `public_market_taxonomy_summary()` — every make/model/variant with at least one matched record, and how many — this is what decides which pages are worth building (§8).
- `public_market_model_summary(make, model, variant?)` — per-currency asking/sold counts, medians, min/max, sale-date range. Statistics are suppressed (`NULL`) when fewer than 5 matching rows exist, rather than showing a median computed from one or two listings.
- `public_market_recent_listings(make, model, variant?, limit?)` — a capped (max 25, enforced server-side), allowlisted-field sample of recent listings.

## 5. Taxonomy safety

Every function filters to `taxonomy_match_status IN ('matched_exact_variant', 'model_only')`. `out_of_scope_make` rows — records that didn't genuinely match your taxonomy — are never counted or returned, so they can't pollute a public page's numbers or create a page for something that isn't really in scope. Grouping is by the raw `make`/`model`/`variant` strings as stored (case-insensitively matched), not by a destructively normalized slug — an Aston Martin Virage Widebody stays distinguishable from a standard Virage as long as `variant` distinguishes them in your data, exactly as instructed.

## 6. Asking vs. sold

`public_market_model_summary` returns `sold_*` and `asking_*` as entirely separate columns, never merged. `public_market_recent_listings` returns both `sold_price` and `asking_price` per row so the caller can label each listing correctly rather than inferring status. No function anywhere computes a single blended "price."

## 7. Currency

No exchange-rate conversion happens anywhere in this layer. `public_market_model_summary` groups its statistics by `currency` — the caller renders "14 sold in EUR, 3 in GBP" rather than one misleading blended number. This matches your instruction that, absent a verified normalization system, separate-currency aggregation is the safer default. (I did not find an existing currency-normalization system in the code reviewed.)

## 8. Indexation threshold

Proposed rule, using `public_market_taxonomy_summary()`'s `matched_records` count:

> Index a `/market/[make]/[model]` (or `[variant]`) page only when **`matched_records` ≥ 8** for that combination, and the page has real summary content to show (at least one currency group with a non-suppressed sold or asking statistic).

8 sits in the 5–10 range your brief suggested as a conservative starting point — low enough that genuinely under-covered models (which are most of a 438k-row dataset once split across every make, model and variant) aren't all excluded, high enough that a page never presents one or two listings as if they were a market. Below the threshold, a page should still be reachable (useful for a visitor who lands there) but carry `noindex, follow` and be left out of the sitemap — exactly the pattern already in place for `/market/porsche/911` today.

This number is a starting recommendation, not a measured one — you may want to revisit it once you can see the actual distribution of `matched_records` across your real taxonomy via `public_market_taxonomy_summary()`.

## 9. The honest gap: this site can't do `/market/[make]/[model]` yet

This is the most important finding in this document, and it wasn't something I could safely paper over.

`fleetpro-landing` is a plain static site: HTML files on disk, assembled from partials by a small Python script (`build/assemble.py`), deployed to Vercel with `cleanUrls: true`. There is no framework, no server-side rendering, and no build-time or request-time templating beyond that one script substituting `{{NAV}}`/`{{FOOTER}}`/`{{AUTHMODAL}}`. That's a deliberate, reasonable choice for a marketing site — but it means a true dynamic route like `/market/porsche/911-turbo-930` for every real make/model/variant combination in a 438,000-row dataset isn't something the current architecture can serve on its own. Genuinely dynamic routing needs either a server that renders HTML per-request (a framework migration, or a Vercel Edge/Serverless Function sitting in front of `/market/*`), or pages generated ahead of time.

**The buildable path that fits what you already have**: extend the existing static-generation approach. At build time — the same moment `assemble.py` already runs — a new script would:

1. Call `public_market_taxonomy_summary()` (once the SQL above is reviewed and run) to get every make/model/variant with real data.
2. For each entity meeting the §8 threshold, call `public_market_model_summary()` and `public_market_recent_listings()`, and render a static HTML page from a template (breadcrumbs, H1, price overview, recent activity, FAQ, disclaimer — the sections in item 16 of the brief), written to `landing/market/<make>/<model>.html`.
3. For entities below the threshold that are still real taxonomy entries, optionally generate a page anyway with `noindex, follow` and an honest "limited market data" state (brief item 29) rather than a 404.
4. Regenerate `sitemap.xml` from only the pages that passed the threshold.

This is a natural extension of `assemble.py`'s existing job, not a new system — but it depends on the SQL functions existing in your database first, and needs its own review pass once that's true. **It was not built in this session**, for two reasons: the underlying functions don't exist in your database yet (there's nothing live to call), and generating and committing potentially hundreds of new HTML files without you first reviewing the SQL they depend on would be exactly the kind of scale-without-review the brief explicitly warned against ("Never create thousands of thin pages").

`/market/porsche/911` stays exactly as it was left in Phase 2 — a hand-written, clearly illustrative example, `noindex, follow`, excluded from the sitemap. It has not been wired to real data in this pass.

## 10. Rate limiting / abuse protection

No existing rate-limit helper was found in either repo. Given that, and per your instruction not to add a complex new dependency unless needed, the mitigations built into the proposed functions themselves are:

- Every function takes only scalar text/int parameters — no free-form query or filter object a caller could use to construct an arbitrary search.
- `public_market_recent_listings`'s `limit` is clamped server-side to 25 regardless of what's requested.
- No function can return more than one make/model/variant's data per call — there's no "give me everything" shape.
- Supabase's platform-level PostgREST rate limiting (org/project-level, configured in the Supabase dashboard, not in code) is your first real line of defense against volumetric abuse and wasn't something this session could see or change. Worth confirming it's configured sensibly for your project tier.

There is still no dedicated per-IP application-level rate limit on these functions. If abuse becomes a real concern once this is live, that's the next thing to add — likely via a Vercel Edge Function or Supabase's own rate-limiting features, evaluated against actual traffic rather than guessed at now.

## 11. Error handling for future pages

Once real pages exist (§9), they should handle: an invalid make/model slug (404 — no taxonomy match at all), a valid taxonomy entity below the indexation threshold ("limited market data" state, `noindex`, not a 404), and a failed RPC call (friendly error state, not a blank page). None of this required a database change to plan, so it's specified here for whoever builds the generator next, but wasn't implemented since the pages themselves don't exist yet.

## 12. What this phase did NOT do, and why

- Did not run `MARKET_PUBLIC_FUNCTIONS.sql` or `MARKET_INDEX_RECOMMENDATIONS.sql` against your database — no tool in this session has a database connection, and even if one existed, these are exactly the kind of schema change your own project convention (and the brief) says should be reviewed by you first.
- Did not build the static-generation script described in §9 — it depends on the SQL above existing in your database first.
- Did not change `/market/porsche/911` or wire any live data into it.
- Did not confirm whether `listing_url` is safe to show publicly (source websites' terms weren't something this session could evaluate) — the proposed functions withhold it until you confirm.
- Did not verify RLS on the consumer-facing tables (`vehicles`, `vehicle_valuations`, etc.) — that codebase wasn't in the connected folders this session could read.

## Next steps, in order

1. Review `build/MARKET_PUBLIC_FUNCTIONS.sql` and `build/MARKET_INDEX_RECOMMENDATIONS.sql` yourself (or with whoever else reviews schema changes on this project).
2. Run them against a staging/dev environment first if you have one; verify with the `curl` checks at the bottom of the functions file that `anon` can call the functions but still cannot read `comparables_shared` directly.
3. Decide on `listing_url` exposure once you've checked your sources' terms.
4. Come back and ask for the static-generation script from §9 — at that point real `/market/[make]/[model]` pages, a scaled sitemap, and the richer page content from brief item 16 can all be built against functions that actually exist.
