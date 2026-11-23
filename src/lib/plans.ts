import { SubscriptionPlan } from '@/types'

/**
 * The plan catalogue: the single source every surface reads — the pricing page,
 * Settings, the Paddle checkout, `apply_paid_order`
 * and the Flutter app (`mobile_flutter/lib/core/plans.dart`).
 *
 * What a plan covers is genuinely split: Basic carries the whole journal, the
 * analytics desk and the chart workspace, with fifteen AI journal summaries a
 * month; Pro adds the analysis workbench (backtester, rules builder, replay)
 * and forty reviews. Each line below describes something the tier can actually
 * open — the gate list is in `PRO_ONLY` (`src/lib/subscription.ts`). MT5
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
      '3-day unlimited trial, no card',
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
      'Unlimited trades and unlimited history',
      'Journal with photos, voice notes, tags, setups and mistakes',
      'Dashboard: equity curve, P&L calendar, daily and monthly results',
      'Session, symbol, tag and setup analytics, plus your time edge',
      'Chart desk on phone and web, from seconds to daily candles',
      'VWAP, session high/low levels and drawing tools',
      'Pin entry, stop and target levels straight off the live chart',
      'Price alert lines on the chart, with push alerts in the Android app',
      'The Android app in 30+ languages, on the same account as the web',
      'Drawings, layouts and templates that sync across phone and web',
      'The same journal on phone and web for one email',
      'Compare a second instrument on the web chart',
      'MT5 auto sync, plus XML, CSV and XLSX import',
      'Playbook, prop-firm rules and the daily-stop lock',
      'CSV and full account export',
      '15 AI journal summaries a month, written from your own logged trades',
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
      'Everything in Basic',
      'Backtester with saved runs, simulating past sessions only',
      'Write your own entry and exit rules, then test them on past sessions',
      'Market replay that steps candle by candle through a session',
      '40 AI journal summaries a month, written from your own logged trades',
      'API access and a sync token per account',
      'Priority support',
    ],
  },
]
