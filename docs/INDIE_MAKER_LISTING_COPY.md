# IndieMaker Listing Copy (compliant — no name, address, or handle)

IndieMaker rejects any listing that names or discloses the product in a text field.
That includes the product name, its web address, an @handle, or a logo in a screenshot.

Rules followed here:
- No product/brand name anywhere
- No URL, domain, or "vercel.app" reference
- No social handle, email, or contact detail
- No logo in the pitch text
- Describes the product generically, by what it does and how it earns

---

## Product pitch (≈1,400 chars — limit is 2,000, min 100)

A turnkey trading journal and analytics SaaS with a companion mobile app, built for active Forex and CFD traders who want to measure and improve their performance.

What it does:
Traders log trades by hand, bulk-import broker exports (CSV, XLSX, and SpreadsheetML XML), or let an automated Python background agent sync closed trades every 60 seconds with correct entry/exit pairing. An AI coaching endpoint reads the trader's own notes alongside deterministic edge statistics to surface recurring mistakes and patterns. The dashboard converts raw trades into win rate, profit factor, expectancy, equity curve, and max drawdown, with a visual P&L calendar heatmap and per-symbol breakdowns.

How it earns:
Automated subscription billing turns an unlimited 30-day free trial into a low-cost tier (50 trades per month) or an unlimited tier. Trials, quotas, and plan upgrades are enforced server-side, and payments are applied idempotently so a dropped payment webhook never loses a sale.

Under the hood:
A modern TypeScript web app on a hosted Postgres database, a database-level quota trigger, signature-verified payment webhooks, an admin approval flow for bank transfers, and timezone-aware email performance summaries. Includes a mobile wrapper and a test suite covering the import parser, billing rules, and notification scheduling.

---

## Key features (one per box)

1. Automated background sync agent plus multi-format CSV/XLSX/XML trade import
2. AI-powered trade review that narrates the trader's own notes against edge statistics
3. Real-time analytics: win rate, profit factor, expectancy, equity curve, and drawdown
4. Server-enforced subscriptions — 30-day trial and plan quotas applied idempotently
5. Companion mobile app and timezone-aware email performance summaries

---

## Step 7 — Running it (Setup & handover / Current challenges)

Form guidance on this step:
- Where the code lives = the host, not the address.** Put `GitHub` (or `Vercel`, `Supabase`) — never the repo URL. "The address stays in the data room."
- Same naming rule as before: no product name, URL, handle, or logo anywhere in the text fields.
a
### Setup and handover (compliant draft)

Setup is straightforward for any developer. Create a hosted Postgres project, run the included migrations in order to provision the schema, security policies, and the server-side quota trigger, then set environment variables for the payment provider, email service, and app URL. Deploy the web app to any Node-compatible host. The buyer receives the full source, all database migrations, the mobile wrapper project, an environment-variable template, and setup documentation. No proprietary services are required beyond the hosting, database, and payment accounts the buyer creates themselves.

### Current challenges (compliant draft)

The product is pre-launch with no paying users, so the first challenge is distribution — the buyer needs a repeatable acquisition channel into the trading niche. On the engineering side, trial and subscription statuses are set at purchase time and do not auto-expire yet, so scheduled expiry is the first fix. Bank-transfer upgrades are approved manually by an admin rather than through a bank API, and the AI features stay inert until the buyer supplies an AI provider key.

---

## Checklist before submitting

- [ ] Remove the product name and any brand handle from every field
- [ ] Remove every URL / domain (including any screenshot showing the address bar)
- [ ] Re-read the parts of the pitch you can't see on screen — the violation is usually there
- [ ] Strip logos from any attached screenshots
- [ ] Confirm "Built over" hours and asking price match your seller docs ($7,000 vs the $4,500 in `docs/SELLER_PAGE.md` and `sales.html`)
