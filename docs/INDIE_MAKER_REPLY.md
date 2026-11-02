# Reply to IndieMaker

Subject: Re: MTL Trader listing — live product, pre-revenue, and where the price comes from



Hi,

Thanks for asking directly — I'd rather answer it straight than talk around it.

Where it lives

The product is live right now at https://mtl-trader.vercel.app (returns HTTP 200 — this is a running app, not a mockup or a landing page):

- App: Vercel — Next.js 16 / React 19 / TypeScript
-Database + auth:** Supabase Postgres. Schema, row-level security, and the monthly-quota trigger all live in versioned migrations under `supabase/migrations/`
- Mobile: Capacitor wrapper pointed at the same URL (Android project included, iOS config present)

You can create an account and get a 30-day trial yourself — no credit card required.

On "no revenue"

That's accurate, and it's deliberate. The app was built and hardened, not marketed. There are no customers because it was never launched for acquisition, not because it doesn't work. Pre-revenue here means pre-launch, and the price is based on what's already built and working, not on a projection.

What the $7,000 actually buys

A working SaaS foundation, not a template:

- Auth with enforced email verification before dashboard/API access
- Plan/trial/quota rules enforced in a Postgres trigger, not just in the UI
- PayPal checkout + signature-verified webhook + idempotent payment reconciliation (a `payment_events` table makes capture, webhook, and the daily cron safe to run in any order — a dropped webhook doesn't lose a payment)
- Bank-transfer flow with unique per-user references and an admin approval panel
- AI journal review pipeline (Gemini / Anthropic / OpenAI-compatible gateways) with grounded edge statistics, caching, and structured-output validation
- Timezone-aware daily/weekly/monthly P&L email summaries plus weekday journal reminders (Resend + Vercel cron)
- MT5 auto-sync agent and a CSV / .xlsx / SpreadsheetML import parser
- 15 test files covering the import parser, P&L math, plan/quota rules, the notifications cron, and the AI pipeline
- Capacitor mobile shell for Android/iOS

That's a rebrand-and-launch foundation for someone already in the trading niche, which is a different thing from an empty boilerplate.

On the price

I'm flexible for a serious buyer and happy to walk you through the app or screenshots of any flow you want to see. An earlier version of my seller brief listed $4,500; the higher figure reflects the work added since then (AI reviews, payment reconciliation, and the notification system).


Best,
Jeremiah Chipeta,
+260771151230
