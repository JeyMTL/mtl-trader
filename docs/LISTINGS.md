# MTL Trader — Ready-to-Paste Listings

Copy-paste pack for listing the project for sale. Edit the **price** and any
`[...]` placeholders, then post. Keep the disclosures (Section 10) in every
listing — honesty here protects you from disputes and refund demands.

**Suggested ask:** $1,950 (open to serious offers). With zero users/revenue the
realistic band is $300–$1,500, up to ~$2,500–$5,000 once there's a live demo and
a few real users. Do not lead with $4,500 on marketplaces — it reads as
unserious for a pre-revenue MVP. Raise it after you add traction.

---

## Section 0 — Asset facts sheet (reuse anywhere)

- **Name:** MTL Trader
- **What it is:** Trading-journal + analytics SaaS for MT5-style trade data
- **Revenue:** None
- **Users:** None (pre-launch MVP)
- **Stack:** Next.js 16 (App Router), React 19, TypeScript, Tailwind CSS 4
- **Backend:** Supabase (Postgres, Auth, RLS policies, SQL triggers)
- **Hosting:** Vercel-ready (cron jobs configured in `vercel.json`)
- **Payments:** PayPal subscriptions + bank-transfer flow with admin approval
- **Email:** Resend — daily/weekly/monthly summaries + weekday journal reminders
- **Mobile:** Capacitor wrapper (Android + iOS projects present)
- **Tests:** 86 automated tests (Vitest), all passing
- **Quality:** `tsc` clean, ESLint clean, production build OK
- **Included docs:** README, project notes, repo map, seller brief, IP-transfer
  template, and two integration check scripts
- **Transfer:** full source + git history (personal account data already removed)

---

## Section 1 — Taglines / one-liners

Short (pick one):

1. "Trading-journal SaaS MVP — Next.js + Supabase, PayPal billing, admin flows, 86 passing tests."
2. "Pre-revenue trading analytics starter: import MT5 trades, full dashboard, subscription + quota logic."
3. "A real SaaS codebase, not a tutorial — auth, payments, DB-enforced limits, mobile wrapper."

Pitch paragraph:

> MTL Trader is a working early-stage MVP for a trading journal and analytics
> product. Traders import MT5-era trade history (CSV/XLSX/XML), then review P&L,
> equity curves, a trading calendar, and performance analytics. It includes
> Supabase auth with row-level security, PayPal subscriptions plus a
> bank-transfer approval flow, database-enforced plan quotas, optional email
> summaries, and a Capacitor mobile shell. No users or revenue yet — it is a
> ready-to-continue foundation, not a finished business.

---

## Section 2 — SideProjectors listing

**Title:** MTL Trader — trading journal SaaS MVP (Next.js + Supabase, pre-revenue)

**Price:** $1,950 (open to offers)

**Description:**

```
MTL Trader is a working trading-journal / analytics SaaS MVP built with
Next.js 16, React 19, TypeScript, Tailwind 4 and Supabase. It is pre-revenue
with no users — I built it and did not take it to market. Selling because I
lack the time/capital to run the go-to-market.

What's built and working:
• Trade import for MT5-style CSV, XLSX and XML (parser is unit tested)
• Dashboard, analytics, equity curve, trading calendar, monthly overview
• Supabase auth + row-level security; email-verified accounts
• PayPal subscriptions (Basic / Pro) + bank-transfer flow with admin approval
• Plan/trial quotas enforced in the database (SQL trigger), not just the UI
• Optional email summaries + weekday journal reminders (Resend)
• MT5 auto-sync workflow via an agent token
• Capacitor mobile wrapper (Android + iOS projects included)
• Admin dashboard for reviewing payments
• 86 automated tests, clean type-check and lint, production build passes

What it needs from a buyer:
• Supabase project (migrations included, apply in filename order)
• PayPal REST app + webhook ID
• Optional: Resend key for emails, BANK_* for bank-transfer display
• Deploy to Vercel (cron config included)

Included: full source, git history, README/docs, an IP-transfer template, and
two scripts to verify the payment/email integrations.

Stack: Next.js, React, TypeScript, Tailwind, Supabase, Vercel, PayPal, Resend,
Capacitor. Happy to walk a serious buyer through the repo.
```

**Tags:** saas, nextjs, supabase, typescript, fintech, trading, boilerplate, mvp

---

## Section 3 — Microns.io listing

**Title:** Trading journal & analytics SaaS MVP — Next.js + Supabase + PayPal

**Asking price:** $1,950

**Category:** SaaS / Starter

**Summary:**

```
A pre-revenue MVP of a trading journal and analytics platform. Real business
logic already implemented: Supabase auth + RLS, server-validated payments
(PayPal + bank transfer with admin approval), idempotent payment application
and reconciliation, DB-enforced plan quotas, and timezone-aware notification
emails. 86 tests pass; build/typecheck/lint are clean.

Built for MT5-style traders: import CSV/XLSX/XML, dashboard + analytics +
calendar, equity curve, and a Capacitor mobile wrapper. No users and no
revenue — this is a codebase/asset sale for a buyer who wants a serious
head start in the trading/fintech niche.
```

**Highlights (bullet the platform may ask for):**
- Full-stack, production-style architecture
- Payments hardening + idempotency + webhook verification
- Database-level business rules (RLS + triggers)
- Automated test suite
- Docs + integration check scripts + IP-transfer template

---

## Section 4 — failedups.com listing

**Title:** Trading journal SaaS MVP for sale (Next.js/Supabase) — never launched

**Description:**

```
I built MTL Trader, a trading-journal SaaS, and never took it to market. It
works and is tested, but I don't have the capital or time for go-to-market, so
I'm selling it as-is.

It's a genuinely functional MVP, not a mockup:
• MT5 import (CSV/XLSX/XML) + dashboard, analytics, calendar
• Supabase auth/RLS + subscription + trial + DB-enforced quotas
• PayPal subscriptions and a bank-transfer approval flow
• Email summaries + journal reminders (optional)
• Capacitor Android/iOS wrapper
• 86 passing tests, clean build

Buyer needs their own Supabase + PayPal (+ optional Resend) accounts. Comes
with docs, migrations, an IP-transfer template, and check scripts. Open to
offers and happy to answer questions.
```

---

## Section 5 — Reddit posts

> Check each subreddit's rules and use the right flair. Do **not** copy the same
> text verbatim across subs. Lead with the story, not the price.

### r/SideProject

**Title:** I built a trading-journal SaaS MVP, never launched it — selling the codebase

```
Spent a few months building MTL Trader, a trading journal + analytics SaaS
(Next.js, Supabase, PayPal). It's finished enough to run: trade import,
dashboard/analytics/calendar, subscriptions with trial + quotas enforced in
Postgres, admin payment approval, optional email summaries, and a Capacitor
mobile wrapper. 86 tests pass.

I never launched or got users, and I don't have the budget to market it, so I'm
selling the project as a codebase rather than pretending it's a business.

Asking ~$[PRICE], open to offers. Repo walkthrough and screenshots available.
If you've bought/sold pre-revenue MVPs, I'd also love advice on how to price it.
```

### r/SaaS

**Title:** Pre-revenue MVP (trading journal + analytics) — realistic price for a code-only sale?

```
Context: I have a working MVP for a trading journal SaaS (Next.js + Supabase +
PayPal). Real logic: auth, RLS, subscription/trial/quota enforcement in the DB,
payments with idempotent application + reconciliation, admin approval, and
notification emails. 86 tests, clean build. Zero users, zero revenue.

I'm trying to sell it as an asset/codebase. [If selling: asking ~$[PRICE].] What
have people actually seen no-revenue MVPs go for, and which marketplaces are
worth listing on? Not looking to overprice it.
```

### r/forhire (use [FOR SALE] / appropriate tag)

**Title:** [FOR SALE] Trading journal SaaS MVP — full Next.js + Supabase codebase

```
Selling a complete, tested MVP codebase for a trading journal/analytics SaaS.

• Next.js 16 + React 19 + TypeScript + Tailwind 4
• Supabase auth + RLS + SQL triggers for plan quotas
• PayPal subscriptions + bank-transfer approval flow
• Admin dashboard, optional Resend email summaries
• Capacitor Android/iOS wrapper
• 86 passing tests; build/typecheck/lint clean

Pre-revenue, no users. Includes docs, migrations, IP-transfer template, and
integration check scripts. ~$[PRICE] or best offer. DM for a repo walkthrough.
```

---

## Section 6 — Indie Hackers / X / Hacker News

### Indie Hackers (post in "Products" or "Selling")

```
Built MTL Trader — a trading journal + analytics SaaS (Next.js/Supabase/PayPal).
Pre-revenue, no users; selling it as a codebase because I don't have the runway
to grow it. 86 tests, clean build, subscription + DB-enforced quotas, admin
payment flow, mobile wrapper. Asking ~$[PRICE] OBO. Happy to walk through the
repo. Also open to advice from anyone who's sold a pre-revenue MVP.
```

### X / Twitter (single post + thread)

```
I built a trading-journal SaaS MVP and never launched it.

Next.js + Supabase + PayPal. Subscriptions, trial + DB-enforced quotas,
admin payment approval, 86 passing tests, mobile wrapper.

No users, no revenue. Selling it as a codebase, ~$[PRICE] OBO.
DM for a walkthrough. 🧵
```

### Hacker News (in an "Ask HN" or Show HN-adjacent thread)

```
Ask HN: what's the realistic price for a pre-revenue MVP codebase?
I have a working trading-journal SaaS (Next.js/Supabase, PayPal billing,
DB-enforced quotas, 86 tests) but no users. Selling as an asset. Any data
points on price and best venues would help.
```

---

## Section 7 — Template / source-code marketplaces

Sell as a **boilerplate/template** (many buyers, lower price each) on
Sell My Code, Codester, or CodeCanyon. Non-exclusive listing is fine.

**Title:** Trading Journal SaaS Starter — Next.js + Supabase + PayPal (TypeScript)

```
A production-style Next.js boilerplate for a trading/fintech SaaS. Clone it and
have auth, billing, admin, and analytics flows ready to customize.

Includes:
• Supabase auth + row-level security + SQL triggers (plan quotas)
• PayPal subscription checkout + bank-transfer approval flow
• Idempotent payment application + reconciliation job
• Dashboard, analytics, calendar, import (CSV/XLSX/XML)
• Notification emails (Resend) + cron setup
• Capacitor Android/iOS wrapper
• Vitest test suite, README, migrations

Requirements: your own Supabase + PayPal (and optional Resend) accounts.
```

> Note licensing: a template sale lets multiple buyers use the code. If you
> instead sell exclusive rights, do not also list it on template markets.

---

## Section 8 — Direct outreach to agencies/devs

**DM / email:**

```
Hi [Name] — I saw [you build trading/fintech apps]. I'm selling the source of a
working trading-journal SaaS MVP (Next.js + Supabase + PayPal): import,
dashboard/analytics, subscriptions with trial + DB-enforced quotas, admin
payment approval, optional email summaries, mobile wrapper, 86 tests. No users —
selling the codebase/asset. Asking ~$[PRICE] OBO.

Would a walkthrough be useful? Happy to send a demo link and repo map.
```

---

## Section 9 — Be ready for these questions

- **"Any users or revenue?"** → "None. This is a pre-revenue codebase sale." Never imply otherwise.
- **"Why selling?"** → "No capital/time for go-to-market."
- **"Can I see it live?"** → Have a hosted demo ready (Vercel) with sample data.
- **"What will I have to build/configure?"** → Supabase project + migrations, PayPal app + webhook ID, optional Resend/bank config.
- **"Any legal/compliance issues?"** → Trading/finance niche; the buyer should handle their own compliance. The project is a journal/analytics tool and does not place trades or give financial advice.
- **"Is the code original?"** → Yes, original code; third-party libraries under their own licenses are not transferred.
- **"Did you remove personal data?"** → Yes — personal broker exports were removed from the repository and its history.

---

## Section 10 — Mandatory disclosures (keep in every listing)

- Pre-revenue, **no users**.
- Early-stage **MVP**, sold **as-is**, no warranty of fitness or revenue.
- Requires the buyer's own **Supabase, PayPal** (and optionally **Resend/bank**) setup.
- **Mobile wrapper is a shell** — push notifications are not configured.
- **Bank-transfer activation is manual** (admin approval).
- **Email notifications and webhook reconciliation are inert** until the related
  environment variables are set.
- Third-party services/libraries are **not** part of the sale.
- The IP-transfer document is a **template**, not legal advice.

---

## Appendix — Negotiation notes

- Anchor at $1,950, accept $1,200–$1,800 for a clean quick sale.
- A live demo + 5–10 real users justifies $3,000–$5,000.
- Bundle a 60-minute onboarding call as a value-add (costs you nothing) to close.
- Never transfer live credentials. Rotate `CRON_SECRET`, PayPal keys, Supabase
  service-role key, and Resend key before handoff.
