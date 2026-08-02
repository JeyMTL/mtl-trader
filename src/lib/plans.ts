import { SubscriptionPlan } from '@/types'

export const PLANS: SubscriptionPlan[] = [
  {
    id: 'free',
    name: 'Free Trial',
    price: 0,
    max_trades: 10,
    features: [
      '10 trades per month',
      'Basic P&L tracking',
      'Win rate statistics',
      '7-day trial period',
    ],
  },
  {
    id: 'basic',
    name: 'Basic',
    price: 9.99,
    max_trades: 50,
    features: [
      '50 trades per month',
      'Advanced analytics',
      'Equity curve charts',
      'Strategy tagging',
      'CSV import/export',
      'Email support',
    ],
    popular: true,
  },
  {
    id: 'pro',
    name: 'Pro',
    price: 29.99,
    max_trades: -1,
    features: [
      'Unlimited trades',
      'Everything in Basic',
      'Real-time MT5 sync',
      'Advanced risk management',
      'Custom reports',
      'Priority support',
      'API access',
    ],
  },
]
