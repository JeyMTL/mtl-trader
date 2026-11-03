import { SubscriptionPlan } from '@/types'

/**
 * The plan catalogue: the single source every surface reads — the pricing page,
 * Settings, the PayPal checkout, the Paddle checkout, `apply_paid_order`
 * and the Flutter app (`mobile_flutter/lib/core/plans.dart`).
 *
 * What a plan covers is now genuinely split: Basic adds the desk (calendar, time
 * edge, journal media, charts, import/export) and a review a day, Pro adds the
 * analysis workflow (backtester, replay) and the full review allowance. MT5
 * autosync is not listed on any plan while the hosted agent is unfunded — see
 * `MT5_SYNC_ENABLED` in `src/lib/features.ts`. Trade volume is
 * deliberately *not* a differentiator: capping Basic below the unlimited trial
 * made paying worse than not paying, and a trader doing two trades a day hit the
 * old 50 cap three weeks in. Both paid tiers are unlimited, and
 * `trg_normalize_paid_allowance` in Postgres pins that for the account row. The
 * remaining gates live in `canUseFeature` (`src/lib/subscription.ts`) and are
 * enforced server-side, so these lines must never promise something a Basic
 * account cannot open.
 *
 * Keep prices here and in `PAID_PLAN_PRICES` / `ANNUAL_PLAN_PRICES`
 * (`src/lib/payments.ts`) identical, and the annual ones with the Paddle price
 * ids; `__tests__/plans-consistency.test.ts` fails the build if they drift.
 */
export const PLANS: SubscriptionPlan[] = [
  {
    id: 'free',
    name: 'Free',
    price: 0,
    max_trades: -1,
    features: [
      '30-day unlimited trial, no card',
      'Everything in Pro during the trial',
      'Journal and analytics stay readable afterwards',
      'Journal photos and voice notes',
      'Import your full MT5 history any time',
    ],
  },
  {
    id: 'basic',
    name: 'Basic',
    price: 12,
    annual_price: 120,
    max_trades: -1,
    features: [
      'Unlimited trades',
      'Dashboard, journal and calendar',
      'Equity curve, daily and monthly P&L',
      'Time edge: best hours and sessions',
      'OANDA chart with SMA, EMA, RSI and MACD',
      'Journal photos and voice notes',
      '30 AI reviews a month',
      'Strategy tags and CSV import/export',
      'Email daily and weekly summaries',
    ],
    popular: true,
  },
  {
    id: 'pro',
    name: 'Pro',
    price: 29,
    annual_price: 290,
    max_trades: -1,
    features: [
      'Unlimited trades',
      'Everything in Basic',
      'AI journal review (200 a month)',
      'Backtester with saved runs',
      'Market replay with saved drawings',
      'API access and sync token',
      'Priority support',
    ],
  },
]
