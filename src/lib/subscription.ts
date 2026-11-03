import { PLANS } from '@/lib/plans'
import type { BillingInterval } from '@/types'

/**
 * Single source of truth for plan limits, billing periods, trial state, and
 * quota math.
 *
 * Everything that used to inline `planId === 'pro' ? -1 : planId === 'basic' ? 50 : 10`
 * or recompute "active trial" now calls these helpers, so the server routes, the
 * Postgres-visible values, and the client UI can no longer drift apart.
 *
 * A paid plan is a *period*, not a permanent flag: `current_period_end` is what
 * ends access. The `expire_lapsed_subscriptions()` job downgrades lapsed
 * accounts daily, and `enforce_trade_quota` refuses writes the moment the period
 * has passed, so a lapsed account cannot keep trading in the gap.
 */

export const UNLIMITED = -1
export const TRIAL_DAYS = 30
/** Length of one paid billing period, in days. Renewals stack onto unexpired time. */
export const PERIOD_DAYS = 30
const MS_PER_DAY = 24 * 60 * 60 * 1000

export interface AccountState {
  subscription_tier?: string | null
  subscription_status?: string | null
  trial_ends_at?: string | null
  max_trades?: number | null
  current_period_end?: string | null
  cancel_at_period_end?: boolean | null
}

/** Monthly trade allowance for a plan id. Unknown plans get no allowance. */
export function maxTradesForPlan(planId: string): number {
  const plan = PLANS.find((p) => p.id === planId)
  return plan ? plan.max_trades : 0
}

/** Whether the id belongs to a paid plan (free/trial excluded). */
export function isPaidPlan(planId: string | null | undefined): boolean {
  return PLANS.some((plan) => plan.id === planId && plan.price > 0)
}

/** A trial is active only while its status is `trial` and it has not expired. */
export function isTrialActive(account: AccountState, now: Date = new Date()): boolean {
  if (account.subscription_status !== 'trial' || !account.trial_ends_at) return false
  return new Date(account.trial_ends_at).getTime() > now.getTime()
}

/**
 * A paid subscription is active only while it is paid, on a paid tier, and its
 * period has not ended. Missing period data (pre-period accounts) is treated as
 * expired so a one-time payment can never act like a lifetime grant.
 */
export function isSubscriptionActive(account: AccountState, now: Date = new Date()): boolean {
  if (account.subscription_status !== 'active') return false
  if (!isPaidPlan(account.subscription_tier)) return false
  if (!account.current_period_end) return false
  return new Date(account.current_period_end).getTime() > now.getTime()
}

/** How many days remain in the current paid period (0 when none). */
export function daysLeftInPeriod(account: AccountState, now: Date = new Date()): number {
  if (!isSubscriptionActive(account, now)) return 0
  const end = new Date(account.current_period_end as string).getTime()
  return Math.max(0, Math.ceil((end - now.getTime()) / MS_PER_DAY))
}

/**
 * The allowance actually in force for an account: an active trial is unlimited,
 * an active paid period uses the stored `max_trades` (a users trigger pins that
 * to -1 for every paid tier, so volume is never what a plan withholds), anything
 * else has none. This mirrors the `enforce_trade_quota` trigger.
 */
export function effectiveMaxTrades(account: AccountState, now: Date = new Date()): number {
  if (isTrialActive(account, now)) return UNLIMITED
  if (isSubscriptionActive(account, now)) return account.max_trades ?? 0
  return 0
}

/** ISO timestamp for a fresh trial ending `TRIAL_DAYS` from `now`. */
export function trialEndsAtFrom(now: Date = new Date()): string {
  return new Date(now.getTime() + TRIAL_DAYS * MS_PER_DAY).toISOString()
}

/** ISO timestamp for the first paid period ending `PERIOD_DAYS` from `now`. */
export function periodEndFrom(now: Date = new Date()): string {
  return new Date(now.getTime() + PERIOD_DAYS * MS_PER_DAY).toISOString()
}

/**
 * End of the next paid period. Paying early stacks a full period onto the time
 * already bought, so a renewal never costs the user their remaining days.
 */
export function nextPeriodEnd(account: AccountState, now: Date = new Date()): string {
  const current = account.current_period_end ? new Date(account.current_period_end).getTime() : 0
  const base = Math.max(now.getTime(), current)
  return new Date(base + PERIOD_DAYS * MS_PER_DAY).toISOString()
}

/** Column values to apply when a user starts/keeps their free trial. */
export function trialFields(now: Date = new Date()) {
  return {
    subscription_tier: 'free',
    subscription_status: 'trial',
    max_trades: maxTradesForPlan('free'),
    trades_remaining: maxTradesForPlan('free'),
    trial_ends_at: trialEndsAtFrom(now),
    current_period_start: null,
    current_period_end: null,
    cancel_at_period_end: false,
  }
}

/**
 * Column values to apply when a paid plan is activated.
 *
 * The database's `apply_paid_order` is the authoritative writer (it locks the
 * row and records the payment event); this builder exists for admin/server paths
 * and mirrors exactly what that function applies.
 */
export function planFields(
  planId: string,
  options: { now?: Date; currentPeriodEnd?: string | null; periodActive?: boolean } = {}
) {
  const now = options.now ?? new Date()
  const maxTrades = maxTradesForPlan(planId)
  const periodActive = options.periodActive ?? false
  return {
    subscription_tier: planId,
    subscription_status: 'active' as const,
    max_trades: maxTrades,
    trades_remaining: maxTrades,
    current_period_start: periodActive ? undefined : now.toISOString(),
    current_period_end: nextPeriodEnd({ current_period_end: options.currentPeriodEnd ?? null }, now),
    cancel_at_period_end: false,
    last_payment_at: now.toISOString(),
  }
}

/**
 * Cancelling stops the renewal, not the access the user already paid for. The
 * period job downgrades the account when `current_period_end` passes.
 */
export function cancelAtPeriodEndFields() {
  return { cancel_at_period_end: true }
}

/** Column values for an account whose paid period has lapsed (used by tests/admin). */
export function expiredFields() {
  return {
    subscription_tier: 'free',
    subscription_status: 'expired' as const,
    max_trades: 0,
    trades_remaining: 0,
    cancel_at_period_end: false,
  }
}

/** Column values for an immediate revocation (refund, chargeback, abuse). */
export function revokedFields() {
  return {
    subscription_tier: 'free',
    subscription_status: 'cancelled' as const,
    max_trades: 0,
    trades_remaining: 0,
    cancel_at_period_end: false,
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
 * downgrade an account that is still inside a higher paid period (e.g. an old
 * Basic capture replayed by reconciliation after the user upgraded to Pro).
 */
export function shouldApplyPlan(account: AccountState, planId: string, now: Date = new Date()): boolean {
  if (!isPaidPlan(planId)) return false
  if (isSubscriptionActive(account, now) && planRank(account.subscription_tier) > planRank(planId)) return false
  return true
}

/**
 * Whether a purchase would repeat the subscription the account already has.
 *
 * The mistake this prevents: a Basic subscriber taps the same plan again and is
 * charged a second time for a period they already own. A yearly purchase is never
 * a repeat — buying a year is precisely how a monthly customer upgrades, and
 * `apply_annual_order` stacks the 365 days onto the days already paid, so nobody
 * loses the remainder of their month. A cancelled subscription is also let
 * through, because re-buying is how a customer who stopped the renewal returns.
 */
export function isDuplicatePurchase(
  account: AccountState,
  planId: string,
  interval: BillingInterval = 'month',
  now: Date = new Date()
): boolean {
  if (interval === 'year') return false
  if (!isSubscriptionActive(account, now)) return false
  if (account.subscription_tier !== planId) return false
  if (account.cancel_at_period_end) return false
  return true
}

export type SubscriptionState = 'trial' | 'active' | 'cancelled' | 'expired'

/** Features that can be withheld by plan. */
export type PlanFeature = 'ai_review' | 'replay' | 'backtest' | 'sync'

/**
 * The features only Pro may use.
 *
 * Everything needed to record and review your own trading stays available on
 * every plan: journalling, charts, analytics, import and export. Autosync is
 * deliberately *not* here any more: it is the one thing a trader cannot do by
 * hand, so it belongs at the entry price — gating it at Pro left Basic paying
 * for a nicer view of data they still had to type in. What remains is the
 * advanced analysis workflow, which is genuinely a step beyond journalling.
 */
const PRO_ONLY: readonly PlanFeature[] = ['replay', 'backtest']

export type FeatureRefusal = 'ok' | 'trial' | 'subscription_required' | 'pro_required'

export interface FeatureAccess {
  allowed: boolean
  reason: FeatureRefusal
}

/**
 * Whether an account may use a feature.
 *
 * A trial is allowed everything on purpose: a trial that cannot try the paid
 * features converts nobody. A lapsed account is refused even though its stored
 * tier may still say `pro`, because the period — not the label — is what ends
 * access.
 */
export function canUseFeature(
  account: AccountState,
  feature: PlanFeature,
  now: Date = new Date()
): FeatureAccess {
  if (isTrialActive(account, now)) return { allowed: true, reason: 'trial' }
  if (!isSubscriptionActive(account, now)) {
    return { allowed: false, reason: 'subscription_required' }
  }
  if (PRO_ONLY.includes(feature) && planRank(account.subscription_tier) < planRank('pro')) {
    return { allowed: false, reason: 'pro_required' }
  }
  return { allowed: true, reason: 'ok' }
}

/**
 * Monthly AI review allowance. The trial is treated as Pro.
 *
 * Basic gets a review a day rather than a token few: a review costs well under a
 * cent on the default model and cached journals do not bill at all, so a tight
 * cap saved no real money and cost the paid tier its best demonstration.
 */
export const AI_REVIEW_QUOTA: Record<string, number> = { free: 0, basic: 30, pro: 200 }

/** How many AI reviews the account may generate this month. */
export function aiReviewQuota(account: AccountState, now: Date = new Date()): number {
  if (isTrialActive(account, now)) return AI_REVIEW_QUOTA.pro
  if (!isSubscriptionActive(account, now)) return 0
  return AI_REVIEW_QUOTA[account.subscription_tier ?? 'free'] ?? 0
}

/**
 * The state to show in the UI and to reason about in routes. It resolves the
 * stored status against the clock so a lapsed period reads as expired even
 * before the daily job rewrites the row.
 */
export function subscriptionState(account: AccountState, now: Date = new Date()): SubscriptionState {
  if (isTrialActive(account, now)) return 'trial'
  if (isSubscriptionActive(account, now)) return 'active'
  if (account.subscription_status === 'cancelled') return 'cancelled'
  if (account.subscription_status === 'active' || account.subscription_status === 'expired') return 'expired'
  if (account.subscription_status === 'trial') return 'expired'
  return 'expired'
}
