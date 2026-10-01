import { PLANS } from '@/lib/plans'

/**
 * Single source of truth for plan limits, trial state, and quota math.
 *
 * Everything that used to inline `planId === 'pro' ? -1 : planId === 'basic' ? 50 : 10`
 * or recompute "active trial" now calls these helpers, so the server routes, the
 * Postgres-visible values, and the client UI can no longer drift apart.
 */

export const UNLIMITED = -1
export const TRIAL_DAYS = 30
const MS_PER_DAY = 24 * 60 * 60 * 1000

export interface AccountState {
  subscription_tier?: string | null
  subscription_status?: string | null
  trial_ends_at?: string | null
  max_trades?: number | null
}

/** Monthly trade allowance for a plan id. Unknown plans get no allowance. */
export function maxTradesForPlan(planId: string): number {
  const plan = PLANS.find((p) => p.id === planId)
  return plan ? plan.max_trades : 0
}

/** A trial is active only while its status is `trial` and it has not expired. */
export function isTrialActive(account: AccountState, now: Date = new Date()): boolean {
  if (account.subscription_status !== 'trial' || !account.trial_ends_at) return false
  return new Date(account.trial_ends_at).getTime() > now.getTime()
}

/**
 * The allowance actually in force for an account: an active trial is unlimited,
 * otherwise the stored `max_trades`. This mirrors the `enforce_trade_quota` trigger.
 */
export function effectiveMaxTrades(account: AccountState, now: Date = new Date()): number {
  if (isTrialActive(account, now)) return UNLIMITED
  return account.max_trades ?? 0
}

/** ISO timestamp for a fresh trial ending `TRIAL_DAYS` from `now`. */
export function trialEndsAtFrom(now: Date = new Date()): string {
  return new Date(now.getTime() + TRIAL_DAYS * MS_PER_DAY).toISOString()
}

/** Column values to apply when a user starts/keeps their free trial. */
export function trialFields(now: Date = new Date()) {
  return {
    subscription_tier: 'free',
    subscription_status: 'trial',
    max_trades: maxTradesForPlan('free'),
    trades_remaining: maxTradesForPlan('free'),
    trial_ends_at: trialEndsAtFrom(now),
  }
}

/** Column values to apply when a paid plan is activated (PayPal, bank, admin). */
export function planFields(planId: string) {
  const maxTrades = maxTradesForPlan(planId)
  return {
    subscription_tier: planId,
    subscription_status: 'active' as const,
    max_trades: maxTrades,
    trades_remaining: maxTrades,
  }
}

/**
 * Column values to apply when a subscription is cancelled. Access stops
 * immediately (no paid period is stored), which matches the current product
 * behaviour and is now explicit in one place.
 */
export function cancelledFields() {
  return {
    subscription_tier: 'free',
    subscription_status: 'cancelled' as const,
    max_trades: 0,
    trades_remaining: 0,
  }
}

/**
 * Whether `count` trades already exist this month and one more would exceed the
 * allowance. `remaining` is -1 when unlimited.
 */
export function monthlyRemaining(account: AccountState, tradesThisMonth: number, now: Date = new Date()): number {
  const max = effectiveMaxTrades(account, now)
  if (max === UNLIMITED) return UNLIMITED
  return Math.max(0, max - tradesThisMonth)
}

/** Ordering of paid plans, used to prevent a stale payment downgrading an account. */
export function planRank(planId: string | null | undefined): number {
  switch (planId) {
    case 'pro':
      return 2
    case 'basic':
      return 1
    default:
      return 0
  }
}

/**
 * Whether a paid order for `planId` may be applied to `account`. Paid orders are
 * only ever applied by the server; this rejects unknown plans and refuses to
 * downgrade an account that is already on a higher active plan (e.g. an old Basic
 * capture replayed by reconciliation after the user upgraded to Pro).
 */
export function shouldApplyPlan(account: AccountState, planId: string): boolean {
  if (!PLANS.some((p) => p.id === planId && p.price > 0)) return false
  const onActivePaid = account.subscription_status === 'active'
  if (onActivePaid && planRank(account.subscription_tier) > planRank(planId)) return false
  return true
}
