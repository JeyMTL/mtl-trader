import { getAdminClient } from '@/lib/server-auth'
import {
  aiReviewQuota,
  canUseFeature,
  type AccountState,
  type FeatureAccess,
  type PlanFeature,
} from '@/lib/subscription'

/**
 * Server-side entitlement checks.
 *
 * A gate that lives in the UI is decoration: anyone can call the route. This is
 * the single place a route asks "may this account use this?", so the answer can
 * never differ between the AI review, the backtester and the sync agent.
 *
 * 402 is used rather than 403 because the caller is authenticated and not
 * forbidden — they simply have not bought the feature. A 403 says "never", a 402
 * says "upgrade", which is the truth and gives the client something to show.
 */

const ACCOUNT_COLUMNS =
  'subscription_tier, subscription_status, trial_ends_at, max_trades, current_period_end, cancel_at_period_end'

export interface FeatureGuard extends FeatureAccess {
  status: 200 | 402
  /** Shown verbatim to the customer; never leaks internal detail. */
  message: string
  account: AccountState | null
  /** Monthly AI allowance in force (0 for everything else). */
  quota: number
}

const MESSAGES: Record<string, string> = {
  subscription_required:
    'Your paid period has ended. Choose a plan to keep using this feature.',
  pro_required: 'This is a Pro feature. Upgrade to Pro to use it.',
}

/**
 * Loads the caller's account and decides.
 *
 * Throws when the account cannot be read: granting access because the database
 * hiccuped would silently hand out a paid feature, and the caller turns that
 * into a 500 the user can retry.
 */
export async function checkFeature(
  userId: string,
  feature: PlanFeature,
  now: Date = new Date()
): Promise<FeatureGuard> {
  const { data, error } = await getAdminClient()
    .from('users')
    .select(ACCOUNT_COLUMNS)
    .eq('id', userId)
    .maybeSingle()

  if (error) throw new Error(`Could not read the account: ${error.message}`)

  if (!data) {
    return {
      allowed: false,
      reason: 'subscription_required',
      status: 402,
      message: 'Account not found.',
      account: null,
      quota: 0,
    }
  }

  const account = data as AccountState
  const access = canUseFeature(account, feature, now)

  return {
    ...access,
    status: access.allowed ? 200 : 402,
    message: access.allowed ? '' : MESSAGES[access.reason] || MESSAGES.subscription_required,
    account,
    quota: feature === 'ai_review' ? aiReviewQuota(account, now) : 0,
  }
}

/**
 * The caller's billing row, or null when it cannot be read.
 *
 * A purchase route only needs to know whether the account already owns the plan
 * being bought. Returning null rather than throwing keeps a database hiccup from
 * turning into a failed sale: the payment is idempotent and the webhook is what
 * grants access, so a missing row here must not block the checkout.
 */
export async function loadAccount(userId: string): Promise<AccountState | null> {
  const { data, error } = await getAdminClient()
    .from('users')
    .select(ACCOUNT_COLUMNS)
    .eq('id', userId)
    .maybeSingle()

  if (error || !data) return null
  return data as AccountState
}

/**
 * AI reviews generated since the first of the month (UTC).
 *
 * Every generation writes a row to `ai_reviews`, so the existing table is the
 * meter — no separate usage table to keep in sync with the quota. Cached reads
 * do not insert, which is why the route checks the cache *before* this count.
 */
export async function aiReviewsThisMonth(
  userId: string,
  now: Date = new Date()
): Promise<number> {
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString()
  const { count, error } = await getAdminClient()
    .from('ai_reviews')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', monthStart)

  if (error) throw new Error(`Could not count this month's reviews: ${error.message}`)
  return count ?? 0
}
