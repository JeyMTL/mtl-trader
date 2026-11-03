# IndieMaker Submission — Fully Filled

Copy each block straight into the matching field. All copy is compliant with IndieMaker's rule:
**no product name, no web address, no handle, no logo in any text field.**

Anything in `[confirm: ...]` is the only thing I couldn't determine — everything else is ready.

---

## Step 1 — Start

**Does it make money today?** → select **"No, not right now"**
The listing is pre-revenue. The "Yes" option requires income in each of the last three months — you have none, so this is the only honest answer.

**Is anyone using it?** → select **"Not yet"**
No users, visitors, downloads, or subscribers.

**What kind of project is it?** → pick **SaaS**
This is the field throwing *"Pick the kind of project."* It's a subscription-based web app, so **SaaS** is the correct bucket and it lines you up against the right comparison set. (Mobile App is the only other defensible pick, but the core product is the web app.)

**Where you'll be paid** → `[confirm: select your payout country]`
IndieMaker pays through Escrow.com and can't pay every country, so pick the country where you can actually receive funds. This validates before you can finish the listing.

**Consistency note:** answering "Not yet" to users here matches the recommendation to leave `Users` / `Audience` / `Content` **unchecked** in Step 5.

---

## Step 2 — Basics

**Listing title**

```
MT5 Trading Journal SaaS with Mobile App and AI Coach
```

**Short summary / tagline** (if a field asks for one)

```
A complete, turnkey trading journal and analytics SaaS with a companion mobile app, built for active Forex traders. Pre-revenue, 200+ hours of development, ready for a buyer to launch.
```

**Category:** `SaaS` (as selected in Step 1)
**Stage:** `Pre-revenue`

---

## Step 3 — About it

**Product pitch** (1,336 / 2,000 chars)

```
A turnkey trading journal and analytics SaaS with a companion mobile app, built for active Forex and CFD traders who want to measure and improve their performance.

What it does:
Traders log trades by hand, bulk-import broker exports (CSV, XLSX, and SpreadsheetML XML), or let an automated Python background agent sync closed trades every 60 seconds with correct entry/exit pairing. An AI coaching endpoint reads the trader's own notes alongside deterministic edge statistics to surface recurring mistakes and patterns. The dashboard converts raw trades into win rate, profit factor, expectancy, equity curve, and max drawdown, with a visual P&L calendar heatmap and per-symbol breakdowns.

How it earns:
Automated subscription billing turns an unlimited 30-day free trial into a low-cost tier or a higher tier that adds the backtester and market replay; trade volume is unlimited on both, so paying never means logging fewer trades than the trial allowed. Trials, entitlements, and plan upgrades are enforced server-side, and payments are applied idempotently so a dropped payment webhook never loses a sale.

Under the hood:
A modern TypeScript web app on a hosted Postgres database, a database-level quota trigger, signature-verified payment webhooks, an admin approval flow for bank transfers, and timezone-aware email performance summaries. Includes a mobile wrapper and a test suite covering the import parser, billing rules, and notification scheduling.
```

**Key features** (one per box, 3–5)

```
Automated background sync agent plus multi-format CSV/XLSX/XML trade import
```

```
AI-powered trade review that narrates the trader's own notes against edge statistics
```

```
Real-time analytics: win rate, profit factor, expectancy, equity curve, and drawdown
```

```
Server-enforced subscriptions — 30-day trial and plan quotas applied idempotently
```

```
Companion mobile app and timezone-aware email performance summaries
```

---

## Step 4 — Running it

**Your time on it each week:** `5 - 10 hours`
**Support after the sale:** `14 Days`
**Reason for selling:** `Time Constraints`
**Where the code lives:** `GitHub`  ← host only, never the repo URL

**Setup and handover** (593 chars)

```
Setup is straightforward for any developer. Create a hosted Postgres project, run the included migrations in order to provision the schema, security policies, and the server-side quota trigger, then set environment variables for the payment provider, email service, and app URL. Deploy the web app to any Node-compatible host. The buyer receives the full source, all database migrations, the mobile wrapper project, an environment-variable template, and setup documentation. No proprietary services are required beyond the hosting, database, and payment accounts the buyer creates themselves.
```

**Current challenges** (477 chars)

```
The product is pre-launch with no paying users, so the first challenge is distribution — the buyer needs a repeatable acquisition channel into the trading niche. On the engineering side, trial and subscription statuses are set at purchase time and do not auto-expire yet, so scheduled expiry is the first fix. Bank-transfer upgrades are approved manually by an admin rather than through a bank API, and the AI features stay inert until the buyer supplies an AI provider key.
```

---

## Step 5 — Assets included

**What transfers:** check `Code`, `Data`, `Domain`, `Brand`.
`[confirm: leave Users, Audience, and Content UNCHECKED unless you genuinely have real users/subscribers/content. The listing is pre-revenue with 0 users — claiming user or audience assets that don't exist is the fastest way to get a listing pulled.]`

**Asset description**

```
Included: the full application source code, all database migrations, the mobile app wrapper project, and deployment configuration. The product's registered domain and brand transfer with the sale. The only data included is demo/seed data used for development — there are no customer records. Because the product has not launched, there are no user accounts, subscriber lists, or audience assets attached.
```

---

## Step 6 — Price

**Asking price:** `$7,000`
**Built over:** `200+ hrs`

**Price rationale** (if a field asks)

```
The asking price is based on build cost rather than revenue, since the product is pre-revenue. It reflects roughly 200 hours of development across the web application, the mobile wrapper, the database layer and security policies, two payment flows, the AI review pipeline, the notification system, and the automated test suite. A buyer rebuilding this would pay a comparable or higher amount to a developer and would spend weeks on components that are already working. The price is negotiable for a serious buyer.
```

---

## Step 7 — Finish / Review

**Final note** (if a field asks for anything else)

```
The product is live and functional but has not been marketed, so there are no customers and no revenue yet. Value here is the working foundation: authentication, server-enforced subscriptions, payment handling with idempotent reconciliation, analytics, and the mobile app are all built and tested. It is best suited to a buyer who wants to launch a trading-journal or trading-analytics product without starting from an empty repo.
```

---

## Pre-submit checklist

- [ ] Clear every field first — leftover text is what triggered both rejections
- [ ] No product name, URL, handle, or logo in any field
- [ ] "Where the code lives" = `GitHub` (host), not the repo link
- [ ] Reconsider the Users / Audience / Content asset checkboxes
- [ ] Fix the price mismatch in your own docs (`docs/SELLER_PAGE.md` and `sales.html` still say $4,500)
