# Analytics — Phase 3

## Current state

No analytics provider is configured anywhere in this project. Specifically checked:

- `fleetpro-landing` (this marketing site): no `package.json`, no build step, no `.env` file, no existing tracking script in `nav.html`, `footer.html`, `site.js`, or any page `<head>`.
- `fleetpro-admin` (the internal admin dashboard): `.env.local` contains only `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` — no GA4, Plausible, Fathom or Vercel Analytics keys.
- No `vercel.json` analytics flags, no `_vercel/insights` script tag anywhere in the built HTML.

Per the Phase 3 brief, no credentials were invented and no third-party script was added speculatively. Instead, a small **provider-agnostic event hook** was added so instrumentation is a one-time, one-file change whenever a provider is chosen.

## The hook

`assets/site.js` now defines, near the top of the file:

```js
function track(event, props = {}) {
  if (window.__CCS_DEBUG_ANALYTICS__) console.log('[analytics]', event, props);
}
```

Today it does nothing except an opt-in console log (`window.__CCS_DEBUG_ANALYTICS__ = true` in the browser console) for local verification. To wire in a real provider, fill in this one function — nothing else needs to change:

```js
function track(event, props = {}) {
  window.gtag && window.gtag('event', event, props);                 // GA4
  window.plausible && window.plausible(event, { props });             // Plausible
  window.fathom && window.fathom.trackEvent(event);                   // Fathom (no custom props)
  window.va && window.va('event', { name: event, ...props });         // Vercel Analytics
}
```

Whichever provider is chosen still needs its loader script added to each page's `<head>` (or, more likely, added once to `build/partials/` if a shared head partial is introduced) and, for GA4/Plausible, a real property ID / domain — that account-level setup is outside what this pass could safely do without inventing a credential.

## Events wired in this pass

All nine events named in the Phase 3 brief are already firing from real call sites:

| Event | Fires from | Props |
|---|---|---|
| `hero_start_free` | Homepage hero "Start Free" button | — |
| `nav_start_free` | Nav bar "Start Free" (desktop + mobile drawer) | — |
| `pricing_plan_selected` | Each of the 3 pricing plan buttons | `{ plan: 'Enthusiast' \| 'Collector' \| 'Curator' }` |
| `car_intelligence_cta` | Both CTAs on `/car-intelligence` | — |
| `market_data_cta` | Both CTAs on `/market-data` | — |
| `collector_score_cta` | Both CTAs on `/collector-score` | — |
| `insights_article_cta` | The CTA on each of the 3 insight articles | — |
| `market_page_analyse_car` | "Analyse your car" CTA on `/market` and `/market/porsche/911` | — |
| `signup_outbound` | `submitAuth()` in `site.js`, right after a **signup** (not signin) succeeds against Supabase | `{ confirmation_required: true \| false }` |

`signup_outbound` fires in both signup branches — immediate handoff to the app, and "check your email to confirm" — since the account is genuinely created in both cases.

## What is deliberately not tracked

Per the brief, nothing beyond the event name and the listed props above is sent: no VIN, no registration number, no uploaded document names, no private collection values, no user identity beyond whatever the eventual provider's own script attaches. `track()` never receives a vehicle record, a user object, or anything read from the app subdomain — the marketing site has no access to that data in the first place.

## Cookie consent

No cookie-consent banner exists on the site today, and none was added in this pass — because no cookie-based analytics provider is active yet, there is nothing to gate consent on. Whichever provider is chosen, the standard pattern is: only call the real tracking script (not just `track()`, which stays inert either way) after consent is recorded, and respect a "do not track" / declined state by leaving `track()`'s provider calls unset. Revisit this before turning on GA4 or any other cookie-based tool, particularly for EU/UK visitors.

## Verifying locally

Open any page with the browser console open, run `window.__CCS_DEBUG_ANALYTICS__ = true`, then click a tracked CTA — you'll see `[analytics] <event> <props>` logged. This does not require a provider and produces no network requests.
