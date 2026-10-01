# Seller Brief

## Product summary

MTL Trader is a trading journal and analytics SaaS focused on tracking MT5-style trade activity, displaying P&L analytics, and enforcing subscription-based usage rules.

## Key features

- Trade import from CSV and Excel-style files
- Dashboard overview and analytics
- Trading calendar and performance summaries
- MT5 sync automation
- User subscription and quota enforcement
- Payment flow and admin approval flow
- Mobile-ready app shell via Capacitor

## Tech stack

- Next.js
- React + TypeScript
- Supabase PostgreSQL
- Vercel hosting
- PayPal checkout integration
- Capacitor mobile app wrapper

## Why it is interesting to a buyer

This is not just a static dashboard. It includes:

- real user flows
- auth and billing logic
- database enforcement for limits
- admin review workflows
- app structure ready for further extension

## Risks to disclose

- It is still best described as an MVP or early-stage product.
- Some store or environment configuration still needs a fresh setup.
- The app depends on external services such as Supabase and PayPal.
- Trial and quota logic is enforced in the database, so the migration files should be reviewed carefully before a production handoff.

## Suggested sales framing

> Working MVP for a trading journal SaaS with Supabase auth, dashboard analytics, MT5 sync, subscription logic, and mobile wrapper. Includes production-style backend rules and app routing, ready for a buyer who wants to continue product development or customize the niche.

## Best buyer type

- founders building a trading or portfolio analytics product
- developers wanting a SaaS starter with real features
- agencies or product teams who want an operational MVP foundation
