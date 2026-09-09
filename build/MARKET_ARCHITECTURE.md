# Market Page Architecture

Documents the route structure, template pattern, and data model for
`/market/[make]/[model]/[variant]` pages. This is a technical reference for
whoever builds out real model pages next — it is not published to visitors.

## Route structure

```
/market                              → hub page (build/pages/market/index.html)
/market/[make]                       → make-level index (not yet built)
/market/[make]/[model]               → model-level page (example: /market/porsche/911)
/market/[make]/[model]/[variant]     → variant-level page, for cases that warrant it
                                        (e.g. /market/porsche/911/turbo-930,
                                        /market/bentley/continental/r)
```

Because this site is plain static HTML with `cleanUrls: true` in
`vercel.json`, each route is a physical file: `/market/porsche/911` is
served from `landing/market/porsche/911.html`. A variant page would live at
`landing/market/porsche/911/turbo-930.html`. Slugs are lowercase,
hyphenated, and stable — they become the permanent URL, so avoid renaming
a slug once it's indexed.

Not every model needs a variant-level page. Use one only where a specific
variant is distinct enough to search for on its own (a 930 Turbo, a
Bentley Continental R) — not as a mechanical rule to generate one page per
trim. This is the "taxonomy-aware, not mass-generated" principle from the
Phase 2 brief: a handful of real, well-populated pages beat hundreds of
thin ones.

## Data interface

A model/variant page is driven by a single data object. Whether that's
hand-authored (as with the current illustrative example) or eventually
pulled from `comparables_shared` at build time, the shape should be:

```ts
interface MarketPageData {
  make: string;                 // "Porsche"
  model: string;                // "911"
  variant?: string;             // "Turbo (930)" — omit for model-level pages
  generation?: string;          // "930"
  bodyStyles?: string[];        // ["Coupe", "Cabriolet", "Targa"]
  yearsProduced?: string;       // "1975–1989"
  matchedListingCount?: number; // real count from comparables_shared, or undefined
  estimatedRangeLow?: number;   // EUR, or undefined
  estimatedRangeHigh?: number;  // EUR, or undefined
  relatedModels?: { label: string; href: string }[];
  isIllustrative: boolean;      // true = no real aggregate data yet
}
```

## Empty-state handling

`matchedListingCount` / `estimatedRangeLow` / `estimatedRangeHigh` are
optional and must never be fabricated. When real data isn't available for
a given make/model:

- Render `—` in place of the figure (see `.market-overview-stat .val` in
  `/market/porsche/911`), never an invented number.
- Set `isIllustrative: true`, which should:
  - show the `.example-banner` component at the top of the page,
    stating plainly that the page is a format example, not live data
  - add `<meta name="robots" content="noindex, follow">` to the page head
    (an illustrative page should not compete in search results against
    the real page it will eventually become — but its links should still
    be crawled)
  - be excluded from `sitemap.xml`
- Once real aggregate data exists for that make/model, flip
  `isIllustrative` to `false`, remove the `noindex` meta tag, fill in the
  real figures, and add the URL to `sitemap.xml`.

## SEO metadata pattern

Every market page follows the same metadata shape used across the rest of
the site (see any `build/pages/*.html` head for the full pattern):
unique `<title>`, unique meta description, self-referencing canonical,
Open Graph + Twitter tags, and a `BreadcrumbList` JSON-LD block. Title
pattern: `{Make} {Model}{, Variant if present} Market Data | Car Collector
Studio` (add `(Example)` only for illustrative pages, and drop it the
moment real data lands).

Only add `Product`/`Offer`-style structured data to a market page once it
carries real, verifiable aggregate figures — never on an illustrative
page, and never with invented price ranges.

## Breadcrumb component + BreadcrumbList JSON-LD

Visible breadcrumbs use the shared `.breadcrumbs` markup (see any
interior page's `<nav class="breadcrumbs">` block) and must exactly
mirror the JSON-LD `BreadcrumbList` items — same labels, same order,
same URLs. A variant page adds one more level:

```
Home / Market Overview / Porsche / 911 / Turbo (930)
```

## Internal-link strategy

- The `/market` hub links down to real make/model pages as they're built
  (currently just `/market/porsche/911`).
- Each model/variant page links back up to `/market` and sideways to
  `relatedModels` (other models from the same make, or closely comparable
  models) using the existing `.market-related` component.
- Every market page links out to `/market-data` (the methodology page)
  and `/car-intelligence` (how the matching feeds a valuation) — this is
  what turns a taxonomy of thin pages into pages that support each other
  and the product pages, rather than an isolated silo.
- The homepage and footer link to `/market` (hub) and to the one real
  example (`/market/porsche/911`) only — never to a make/model page that
  doesn't exist yet.

## Structured-data strategy summary

| Page type            | JSON-LD                                    |
|-----------------------|---------------------------------------------|
| `/market` hub          | BreadcrumbList                              |
| Illustrative model page | BreadcrumbList only (no Product/Offer data) |
| Real model page (future) | BreadcrumbList; consider ItemList of listings if genuinely populated |

Never add `AggregateOffer`, `Review`, or `AggregateRating` to a market
page — there are no verified reviews or offer aggregates behind this
data, and adding that schema without backing content would be exactly
the kind of fabrication the Phase 2 brief prohibits.
