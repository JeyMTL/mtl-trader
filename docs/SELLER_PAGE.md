# MTL Trader — Trading Journal SaaS MVP

## Product overview

MTL Trader is a trading journal and analytics web app for traders who want to bring trade history together, review performance, and keep a consistent record of their decisions. It combines trade entry and import with analytics, subscription rules, and payment workflows in a buyer-ready codebase.

**Stage:** Pre-launch; the seller reports no customers or revenue.
**Asking price:** USD $4,500 (negotiable).

## What the product does

- **Record trades:** Enter trades manually, edit existing records, or import broker and MT5 history from CSV, XLSX, and supported SpreadsheetML XML exports.
- **Review performance:** Track win rate, profit factor, expectancy, equity curve, drawdown, monthly and daily P&L, and results by symbol.
- **Keep a journal:** Add trade notes and strategies, then review activity in a P&L calendar.
- **Sync MT5 trades:** An optional Python agent can sync closed trades on a 60-second interval and pair entries and exits. The buyer must configure and run the agent.
- **Manage paid plans:** Includes a 30-day trial, monthly trade quotas, PayPal checkout, and bank-transfer requests with admin approval. Trade quotas are enforced in Postgres; PayPal payment events are verified and applied idempotently.
- **Send optional email updates:** Daily, weekly, or monthly performance summaries and weekday journal reminders can be scheduled when the buyer configures Resend and the deployment cron.
- **Review trades with AI:** An optional AI review endpoint uses the trader's notes and performance statistics. It requires an AI provider key and is unavailable until configured.
- **Extend to mobile:** A Capacitor wrapper and native project structure are included; this is not represented as a published app-store product.

## Why it is useful

The value is in the integrated foundation, not a customer base or proven revenue stream. A buyer can start from working application flows for authentication, trade ingestion, analytics, billing, database-enforced quotas, administration, and optional notifications, then focus on product direction and distribution.

## What's included

- Next.js, React, and TypeScript web application
- Supabase/PostgreSQL schema, migrations, and row-level security policies
- Trade import and analytics features
- PayPal and bank-transfer payment workflows
- Capacitor mobile wrapper and native project structure
- Optional MT5 sync agent
- Environment-variable template and setup documentation
- Automated tests for core business logic and selected workflows

The buyer will need to provide their own hosting, Supabase, payment, email, and optional AI provider accounts and credentials. Third-party accounts, credentials, customer data, and any domain or brand transfer are not included unless separately agreed.

## Current limitations and handover considerations

- This is an early-stage MVP, not a mature or revenue-generating business. The seller reports no users or paying customers.
- A buyer must configure and verify deployment, database, payment, email, and any optional AI or sync services.
- Bank-transfer payments require manual admin approval.
- Trial and subscription expiry automation is not implemented yet; expiry should be addressed before relying on paid-plan lifecycle automation.
- AI review, email delivery, and MT5 sync depend on external configuration and are not active automatically in a fresh deployment.
- The Capacitor wrapper is a starting point for mobile development, not evidence of a published or store-approved mobile app.

## Setup at a glance

Create a Supabase project, apply the included migrations in order, configure the required environment variables, and deploy the web app to a compatible Node.js host. Configure PayPal webhooks and scheduled jobs as needed. Follow the repository README and mobile setup guide for detailed steps.

## Ideal buyer

- A founder building a trading journal or analytics product
- A developer looking for a SaaS foundation with real trade, billing, and quota logic
- An agency or product team seeking a customizable MVP for the trading niche

## Asking price

**USD $4,500**, negotiable for a serious buyer. This is the seller's asking price for the codebase and included assets, not a revenue-based valuation.
