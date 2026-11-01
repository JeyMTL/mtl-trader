import { SubscriptionPlan } from '@/types'

/**
 * The plan catalogue: the single source every surface reads — the pricing page,
 * Settings, the PayPal checkout, the Flutterwave checkout, `apply_paid_order`
 * and the Flutter app (`mobile_flutter/lib/core/plans.dart`).
 *
 * What actually differs between paid tiers today is the monthly trade
 * allowance: `enforce_trade_quota` is the one gate in the product, so `pro`'s
 * unlimited allowance is the real upgrade. The feature lines below therefore
 * describe what a plan *covers*, not a lock — no screen is hidden behind a tier,
 * and none of these should be written to promise otherwise until a feature flag
 * exists. Keep prices here and in `PAID_PLAN_PRICES` (`src/lib/payments.ts`)
 * identical; `__tests__/plans-consistency.test.ts` fails the build if they drift.
 */
export const PLANS: SubscriptionPlan[] = [
  {
    id: 'free',
    name: 'Free Trial',
    price: 0,
    max_trades: -1,
    features: [
      'Unlimited trades for 30 days',
      'Everything in Pro during the trial',
      'Journal photos and voice notes',
      'No credit card required',
    ],
  },
  {
    id: 'basic',
    name: 'Basic',
    price: 2.5,
    max_trades: 50,
    features: [
      '50 trades per month',
      'Dashboard, journal and calendar',
      'Equity curve, daily and monthly P&L',
      'Time edge: best hours and sessions',
      'OANDA chart with SMA, EMA, RSI and MACD',
      'Journal photos and voice notes',
      'Strategy tags and CSV import/export',
      'Email daily and weekly summaries',
    ],
    popular: true,
  },
  {
    id: 'pro',
    name: 'Pro',
    price: 5,
    max_trades: -1,
    features: [
      'Unlimited trades',
      'Everything in Basic',
      'AI journal review',
      'Market replay with saved drawings',
      'MT5 broker sync and API access',
      'Priority support',
    ],
  },
]
