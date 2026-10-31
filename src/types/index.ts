/**
 * Billing-plan shape used by `@/lib/plans`.
 *
 * The trade and user shapes live in `@/types/journal` (derived from the RPC
 * payloads); they used to be duplicated here and drifted from the database.
 */
export interface SubscriptionPlan {
  id: string
  name: string
  price: number
  max_trades: number
  features: string[]
  popular?: boolean
}
