# Google Search Console setup — Car Collector Studio

This is a manual setup guide for the site owner. No verification was attempted and no token was generated or guessed — Search Console verification has to come from you, using access this session doesn't have (the Vercel dashboard, or DNS for the domain).

## What was checked and fixed before writing this guide

- **Sitemap** (`sitemap.xml`): contains every indexable page — homepage, the 6 feature/landing pages, `/market`, `/insights` and its 3 (soon 5) articles, and the 4 new pages added this phase (`/about`, `/security`, `/privacy`, `/terms`). It deliberately does **not** include `/market/porsche/911` (see below) or `/404`.
- **robots.txt**: allows all crawling and points to the sitemap (`Sitemap: https://carcollectorstudio.com/sitemap.xml`). No changes were needed.
- **Canonical tags**: every page carries a self-referencing `<link rel="canonical">` using the apex domain, no `www.` — confirm this matches how the domain is actually configured in Vercel (see the `www` vs apex step below).
- **noindex on illustrative content**: `/market/porsche/911` is a hand-written illustrative example (Phase 2), not backed by real market-listing data yet, and correctly carries `<meta name="robots" content="noindex, follow">`. It stays out of the sitemap for the same reason. `/404` also carries `noindex, follow`. Do not remove either until `/market/porsche/911` is genuinely backed by real aggregated data meeting the indexation threshold (see Phase 3 report).
- **Structured data**: BreadcrumbList on every inner page, FAQPage where a page has a real FAQ section, Organization + SoftwareApplication on the homepage. Validated by parsing every `<script type="application/ld+json">` block as JSON during QA — all well-formed.
- **HTTP → HTTPS**: `vercel.json` doesn't declare a redirect, because Vercel redirects HTTP to HTTPS automatically for all deployments — nothing to configure here.

## What is NOT yet verified (needs your action in Vercel)

- **`www` vs apex domain**: canonical tags and the sitemap consistently use `https://carcollectorstudio.com/` (no `www`). Check the Vercel project's Domains settings and confirm `www.carcollectorstudio.com` (if it resolves at all) 308-redirects to the apex domain, not the other way around, and not served as a duplicate. If the primary domain in Vercel is actually the `www` version, the canonical tags across every page need to be swapped to match — flag this back before the next deploy if so.

## Step-by-step: adding the property

1. **Add the domain property.** Go to [Google Search Console](https://search.google.com/search-console), choose "Add property," and use the **Domain** property type (covers `http://`, `https://`, `www` and non-`www` in one property) rather than a URL-prefix property.
2. **Verify ownership via DNS.** Search Console will give you a TXT record to add at your DNS provider (wherever `carcollectorstudio.com`'s nameservers are managed — check the Vercel Domains tab if unsure who that is). Add the exact TXT record Search Console shows you; do not reuse a token from anywhere else. DNS propagation can take anywhere from a few minutes to a few hours — Search Console's "Verify" button will simply fail until it propagates, which is normal.
3. **Submit the sitemap.** Once verified, go to Sitemaps in the left nav and submit `sitemap.xml` (Search Console will resolve it to `https://carcollectorstudio.com/sitemap.xml`). It will show as "Success" once Google fetches and parses it — this can take a few hours.
4. **Inspect key URLs.** Use the URL Inspection tool on at minimum: the homepage, `/pricing`, `/car-intelligence`, `/market-data`, `/collector-score`, `/collection-management`, `/insights`, and the new `/about`, `/security`, `/privacy`, `/terms`. Confirm each shows "URL is on Google" (after indexing) or, before that, that the live test shows no crawl errors and the correct canonical.
5. **Request indexing** for pages you want crawled sooner than Google's natural schedule — most useful right after this deploy for the 4 new pages and any page whose content changed materially (the homepage carousel caption fix, the footer). Use "Request Indexing" from the URL Inspection tool, one URL at a time; there's a daily quota, so prioritize the homepage and the highest-value landing pages first.
6. **Monitor Coverage / Indexing.** Under Indexing → Pages, watch for pages marked "Excluded" that you expect to be indexed, and check the reason given (noindex, duplicate, crawl error, etc.). The `/market/porsche/911` and `/404` pages will correctly show as "Excluded by noindex tag" — that's expected, not a bug.
7. **Monitor Core Web Vitals.** Under Experience → Core Web Vitals, check back a couple of weeks after launch once enough real-user data has accumulated (it needs field data from actual visitors, not just the initial deploy). The site currently ships static HTML with no client-side framework and a single shared stylesheet/script, which should help on this front — but genuinely verify rather than assuming.
8. **Monitor Search queries.** Under Performance → Search Results, track which queries drive impressions and clicks. This is the main signal for whether the new landing pages, insight articles and (once live) real market pages are earning organic visibility — revisit it periodically rather than once.

## Ongoing hygiene

- Re-submit the sitemap after any batch of new pages is added (new insight articles, new real market pages once the database-backed system in the Phase 3 report goes live).
- If real market pages go live behind the indexation threshold described in the Phase 3 report, the sitemap generation needs to become dynamic rather than hand-maintained — that's flagged as a follow-up in the Phase 3 report, not done in this pass.
- Keep noindex on any page that's illustrative, low-data, or a duplicate — removing noindex should be a deliberate decision tied to real content existing on that page, not automatic.
