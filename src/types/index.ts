/**
 * Billing-plan shape used by `@/lib/plans`.
 *
 * The trade and user shapes live in `@/types/journal` (derived from the RPC
 * payloads); they used to be duplicated here and drifted from the database.
 */
/** Billing cadence. Only `paddle` sells yearly periods today. */
export type BillingInterval = 'month' | 'year'

export interface SubscriptionPlan {
  id: string
  name: string
  price: number
  /** Yearly price in the same currency. Absent means the plan is monthly only. */
  annual_price?: number
  max_trades: number
  features: string[]
  popular?: boolean
}
