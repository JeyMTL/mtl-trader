import { SubscriptionPlan } from '@/types'

/** One-line positioning for the marketing pricing cards. */
export const PLAN_TAGLINES: Record<string, string> = {
  free: 'Try the Pro tools for 3 days, then keep 30 trades a month.',
  basic: 'The full journal, the analytics and the daily-stop guard.',
  pro: 'Add AI reviews, the backtester and priority support.',
}

/**
 * The plan catalogue: the single source every surface reads — the pricing page,
 * Settings, the Paddle checkout, `apply_paid_order`
 * and the Flutter app (`mobile_flutter/lib/core/plans.dart`).
 *
 * What a plan covers is genuinely split: Basic is the journal and the automation
 * that keeps the record accurate — autosync, the soft daily lock, photos and
 * voice notes, the time edge, the setup matrix and the dashboard. Pro is what
 * goes beyond journalling — the hard lock, the AI review, the backtester and
 * notifications. Each line below describes something the tier can actually open
 * — the gate list is in `PRO_ONLY` (`src/lib/subscription.ts`). The licensed
 * chart desk is off (`MARKET_CHARTS_ENABLED` in `src/lib/features.ts`), so no
 * plan line sells candles, drawings or replay: every tier gets the same market
 * view instead. MT5
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
    // The free tier is a real tier: 30 trades a month, every month, with the
    // prop-firm simulator. It is the tier a lapsed trial or paid period falls
    // back to, so it cannot be a read-only tombstone.
    max_trades: 30,
    features: [
      '3-day trial: every Pro tool, unlimited trades, 1 AI review and 1 backtest a day',
      '30 trades a month after the trial',
      'Prop-firm simulator: daily loss, drawdown, target and consistency rules',
      'Journal with photos, voice notes, tags, setups and mistakes',
      'Live market view: an interactive chart for every symbol and timeframe',
      'Time edge and setup matrix on your own trades',
      'Import your full MT5 history at any time',
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
      'MT5 auto sync, from the hosted agent or your own terminal with a sync token',
      'Daily stop with the soft lock: the guard clears resting orders and closes fills opened after the stop; the journal stays open',
      'Time edge: the sessions and weekdays your results actually come from',
      "Setup matrix: each setup's win rate and expectancy by session and symbol",
      'Dashboard: equity curve, P&L calendar, daily and monthly results',
      'Live market view on web and Android, on every symbol and timeframe',
      'XML, CSV and XLSX import, plus CSV and full account export',
      'The Android app in 30+ languages, on the same account as the web',
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
      'Daily stop with the hard lock: the same guard, and the journal closes until the reset',
      '40 AI journal reviews a month, written from your own logged trades',
      'Backtester with saved runs, simulating past sessions only',
      'Write your own entry and exit rules, then test them on past sessions',
      'Notifications on your phone: prop-firm breaches and session reminders',
      'Priority support',
    ],
  },
]
