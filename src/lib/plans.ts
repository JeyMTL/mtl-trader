import { SubscriptionPlan } from '@/types'

/**
 * The plan catalogue: the single source every surface reads — the pricing page,
 * Settings, the PayPal checkout, the Flutterwave checkout, `apply_paid_order`
 * and the Flutter app (`mobile_flutter/lib/core/plans.dart`).
 *
 * What a plan covers is now genuinely split: Basic adds MT5 autosync (the one
 * thing a trader cannot do by hand) and a review a day, Pro adds the analysis
 * workflow (backtester, replay) and unlimited volume. The remaining gates live
 * in `canUseFeature` (`src/lib/subscription.ts`) and are enforced server-side, so
 * these lines must never promise something a Basic account cannot open.
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
    max_trades: 50,
    features: [
      '50 trades per month',
      'Dashboard, journal and calendar',
      'Equity curve, daily and monthly P&L',
      'Time edge: best hours and sessions',
      'OANDA chart with SMA, EMA, RSI and MACD',
      'Journal photos and voice notes',
      'MT5 broker sync',
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
