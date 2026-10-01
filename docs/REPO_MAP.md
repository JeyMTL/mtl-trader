# Repository Map

This project is a trading journal SaaS built with Next.js and Supabase. It is organized around a standard app shell, API routes for the business logic, and database migrations for account, trade, and billing rules.

## Top-level structure

- `src/app` — Next.js app router pages and route handlers
- `src/components` — shared UI components
- `src/lib` — config, utilities, auth helpers, pricing data
- `src/types` — TypeScript models used across the app
- `supabase/migrations` — database schema and trigger logic
- `public` — static files and sample data
- `mobile` — Capacitor mobile wrapper
- `scripts` — helper scripts

## Main business flows

### 1. Authentication and account setup
The app uses Supabase Auth and app-level user metadata. The user flows live under `src/app/auth` and the startup logic is supported by `src/lib/server-auth.ts` and `src/lib/supabase.ts`.

### 2. Trade import and journal workflow
Trade uploads are handled in the dashboard import flow and then stored in the `trades` table. The app can ingest CSV/XLSX data and then display it in dashboard, analytics, and calendar views.

### 3. MT5 sync automation
The app includes a sync process for MT5 trade exports. The Python agent under `public/mt5_agent.py` is the automation layer that pulls trade data and updates the journal.

### 4. Subscription and payment logic
The billing and plan logic is spread across:

- `src/app/api/checkout/route.ts`
- `src/app/api/paypal/capture/route.ts`
- `src/app/api/plans/route.ts`
- `src/app/api/subscription/cancel/route.ts`
- `src/lib/plans.ts`

The quota enforcement is implemented with PostgreSQL triggers in `supabase/migrations`.

### 5. Admin and review flows
The app contains admin-only approval routes for payment review and account actions. Use the `is_admin` flag for the admin dashboard.

## Operational notes

- This project expects a Supabase project and matching environment variables.
- Database migrations should be applied in filename order.
- The app is designed for Vercel hosting, but the mobile wrapper uses Capacitor.
- Trial and plan enforcement is controlled by user metadata and database logic rather than application-only checks.

## How to understand it quickly

1. Start with `README.md`.
2. Read the route structure under `src/app`.
3. Check `supabase/migrations` for the real business rules.
4. Review `src/lib/plans.ts` and `src/lib/server-auth.ts` for gating and auth behavior.
5. Check `public/mt5_agent.py` for the sync automation path.

## Good buyer summary

This is a SaaS trading journal MVP with:

- user auth
- trading journal UI
- CSV/XLSX import
- MT5 sync workflow
- paid plan logic
- admin review layer
- mobile-ready wrapper
