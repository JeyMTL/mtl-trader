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
export const TRIAL_DAYS = 3
/** One wording for the trial across the hero, pricing cards and checkout CTAs. */
export const TRIAL_CTA = `Start ${TRIAL_DAYS}-day free trial`
export const TRIAL_TRUST_LINE = `${TRIAL_DAYS}-day free trial · No credit card required · Web + Android`
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
 * to -1 for every paid tier, so volume is never what a plan withholds), and
 * everything else falls back to the free tier's monthly allowance. This mirrors
 * the `enforce_trade_quota` trigger.
 *
 * The free tier is a real tier now, not a read-only tombstone: a trader whose
 * trial or paid period ended keeps logging up to `maxTradesForPlan('free')`
 * trades a month, and keeps the prop-firm simulator, instead of hitting a wall
 * that leaves the product with nothing to judge.
 */
export function effectiveMaxTrades(account: AccountState, now: Date = new Date()): number {
  if (isTrialActive(account, now)) return UNLIMITED
  if (isSubscriptionActive(account, now)) return account.max_trades ?? UNLIMITED
  return maxTradesForPlan('free')
}

/** ISO timestamp for a fresh trial ending `TRIAL_DAYS` from `now`. */
export function trialEndsAtFrom(now: Date = new Date()): string {
  return new Date(now.getTime() + TRIAL_DAYS * MS_PER_DAY).toISOString()
}

export interface TrialRemaining {
  expired: boolean
  days: number
  hours: number
  minutes: number
}

/**
 * How much of the trial is left, measured against the clock.
 *
 * The trial ends at a fixed instant, so the answer depends on `now` and not on
 * whether the app is open. Callers re-read it on a timer; nothing here pauses
 * the countdown for inactivity.
 */
export function trialRemaining(
  endsAt: string | null | undefined,
  now: Date = new Date()
): TrialRemaining | null {
  if (!endsAt) return null
  const end = new Date(endsAt).getTime()
  if (!Number.isFinite(end)) return null
  const ms = end - now.getTime()
  if (ms <= 0) return { expired: true, days: 0, hours: 0, minutes: 0 }
  const totalMinutes = Math.floor(ms / 60_000)
  return {
    expired: false,
    days: Math.floor(totalMinutes / 1440),
    hours: Math.floor((totalMinutes % 1440) / 60),
    minutes: totalMinutes % 60,
  }
}

/** The countdown as a short label: `6d 23h left`, `23h 40m left`, `7m left`. */
export function formatTrialRemaining(
  endsAt: string | null | undefined,
  now: Date = new Date()
): string {
  const remaining = trialRemaining(endsAt, now)
  if (!remaining) return ''
  if (remaining.expired) return 'Trial ended'
  if (remaining.days > 0) return `${remaining.days}d ${remaining.hours}h left`
  if (remaining.hours > 0) return `${remaining.hours}h ${remaining.minutes}m left`
  return `${Math.max(1, remaining.minutes)}m left`
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
    // A running trial is unlimited; the free tier's cap only starts when the
    // trial ends, which is what `effectiveMaxTrades` and the trigger apply.
    max_trades: UNLIMITED,
    trades_remaining: UNLIMITED,
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

/**
 * Column values for an account whose paid period has lapsed (used by tests/admin).
 *
 * A lapsed account is a free account, so it keeps the free tier's monthly
 * allowance instead of being set to zero.
 */
export function expiredFields() {
  const free = maxTradesForPlan('free')
  return {
    subscription_tier: 'free',
    subscription_status: 'expired' as const,
    max_trades: free,
    trades_remaining: free,
    cancel_at_period_end: false,
  }
}

/**
 * Column values for an immediate revocation (refund, chargeback, abuse).
 *
 * Revoking ends the paid plan, not the account: the tier drops back to free and
 * its allowance with it, so a refunded customer is treated exactly like any
 * other free account rather than locked out of the journal they wrote.
 */
export function revokedFields() {
  const free = maxTradesForPlan('free')
  return {
    subscription_tier: 'free',
    subscription_status: 'cancelled' as const,
    max_trades: free,
    trades_remaining: free,
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
 * Whether the account may open Pro tools right now: a running trial, or an
 * active paid period on Pro.
 *
 * `canUseFeature` is the server gate; this is the same answer shaped for the
 * client. The chart desk and the playbook use it to decide what to show without
 * asking the server per render, and the server still refuses the write itself.
 */
export function hasProTools(account: AccountState, now: Date = new Date()): boolean {
  if (isTrialActive(account, now)) return true
  if (!isSubscriptionActive(account, now)) return false
  return planRank(account.subscription_tier) >= planRank('pro')
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
export type PlanFeature =
  | 'ai_review'
  | 'replay'
  | 'backtest'
  | 'sync'
  | 'fast_timeframes'
  | 'push_alerts'
  | 'hard_lock'

/**
 * The features only Pro may use.
 *
 * The split is deliberately "record your own trading" against "sell the
 * analysis": Basic carries the journal, the chart desk and the automation a
 * trader needs to be accurate — autosync, the soft lock, level pinning, photos
 * and voice notes, the time-edge and setup analytics, and 30s/45s candles.
 * Pro adds what is beyond journalling: the analysis workbench (backtester,
 * replay), the AI review, push notifications, the hard lock and the 5s/10s/15s
 * candles. Autosync stays on Basic on purpose: it is the one thing a trader
 * cannot do by hand, so gating it at the entry price is what makes Basic worth
 * paying for.
 */
const PRO_ONLY: readonly PlanFeature[] = [
  'ai_review',
  'replay',
  'backtest',
  'fast_timeframes',
  'push_alerts',
  'hard_lock',
]

/**
 * Second-level candle sizes sold with Pro. Basic keeps 30s and 45s, and every
 * size from one minute up: the fast sizes are the ones a scalper pays for.
 */
export const PRO_TIMEFRAMES = ['5s', '10s', '15s'] as const

/** Whether a candle size is one of the Pro-only seconds sizes. */
export function isProTimeframe(key: string): boolean {
  return (PRO_TIMEFRAMES as readonly string[]).includes(key)
}

/**
 * The sub-minute sizes Basic buys. The free plan's chart runs from a minute up,
 * so a second-based size is always either Basic or Pro — never free.
 */
export const BASIC_TIMEFRAMES = ['30s', '45s'] as const

/** Whether a candle size is one Basic pays for. */
export function isBasicTimeframe(key: string): boolean {
  return (BASIC_TIMEFRAMES as readonly string[]).includes(key)
}

/** Whether a candle size is open to an account with the given access. */
export function isTimeframeOpen(
  key: string,
  access: { pro: boolean; paid: boolean }
): boolean {
  if (isProTimeframe(key)) return access.pro
  if (isBasicTimeframe(key)) return access.paid
  return true
}

/**
 * Whether the account holds any paid access right now: a running trial, or an
 * active paid period on Basic or Pro.
 *
 * `hasProTools` answers the narrower question the Pro features ask. The chart's
 * seconds sizes split across both paid plans, so they need this one: Basic pays
 * for 30s and 45s, and a trial counts as either plan while it runs.
 */
export function hasPaidPlan(account: AccountState, now: Date = new Date()): boolean {
  if (isTrialActive(account, now)) return true
  if (!isSubscriptionActive(account, now)) return false
  return planRank(account.subscription_tier) >= planRank('basic')
}

export type FeatureRefusal = 'ok' | 'trial' | 'subscription_required' | 'pro_required'

export interface FeatureAccess {
  allowed: boolean
  reason: FeatureRefusal
}

/**
 * Whether an account may use a feature.
 *
 * A trial is allowed every feature on purpose: a trial that cannot try the paid
 * tools converts nobody. How *much* of the two per-call tools it gets is a
 * separate question — `trialDailyLimit` caps the AI review and the backtester at
 * one a day, and the routes check that after this gate says yes. A lapsed account
 * is refused even though its stored tier may still say `pro`, because the period
 * — not the label — is what ends access.
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
 * How many times a running trial may use a Pro tool in one UTC day.
 *
 * A trial used to hand over the whole Pro allowance — forty AI reviews and an
 * unlimited backtester — so three days of trial were worth more than a paid
 * month, and a new account never had a reason to look at the price. These are
 * the two tools that cost money per call, so the trial now samples them: one a
 * day for each of the three trial days. Everything else the trial opens (replay,
 * the hard lock, the fast candles, push) is unchanged.
 */
export const TRIAL_DAILY_LIMITS: Partial<Record<PlanFeature, number>> = {
  ai_review: 1,
  backtest: 1,
}

/**
 * The daily cap a running trial puts on [feature], or null for anything a trial
 * does not cap (and for every account that is not on a trial).
 */
export function trialDailyLimit(
  feature: PlanFeature,
  account: AccountState,
  now: Date = new Date()
): number | null {
  if (!isTrialActive(account, now)) return null
  return TRIAL_DAILY_LIMITS[feature] ?? null
}

/**
 * Monthly AI review allowance.
 *
 * The AI review is sold with Pro, so Basic has no allowance and forty a month is
 * what Pro buys. A trial gets one a day (`TRIAL_DAILY_LIMITS`), which over its
 * `TRIAL_DAYS` is the total below — the route enforces the daily part, this
 * number is what the UI and the monthly count compare against.
 * `PRO_ONLY` is what actually refuses the route; this table is only how much of
 * an allowed feature is left.
 */
export const AI_REVIEW_QUOTA: Record<string, number> = { free: 0, basic: 0, pro: 40 }

/** How many AI reviews the account may generate this month. */
export function aiReviewQuota(account: AccountState, now: Date = new Date()): number {
  if (isTrialActive(account, now)) {
    return TRIAL_DAYS * (TRIAL_DAILY_LIMITS.ai_review ?? 0)
  }
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
