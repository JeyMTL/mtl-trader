import { getAdminClient } from '@/lib/server-auth'
import { applyPaidOrder, priceForPlan } from '@/lib/payments'
import { acknowledgeSubscription, verifyPlaySubscription, type PlaySubscription } from '@/lib/google-play'
import { logEvent } from '@/lib/log'
import type { BillingInterval } from '@/types'

/**
 * Turns a Play purchase token into a plan on an account.
 *
 * Everything the client says is ignored except the token: the product, the
 * cadence and the expiry all come from Google. That is the whole point of
 * server-side verification — a modified app can send any token it likes, and the
 * worst it can do is re-state a purchase already made.
 *
 * Idempotent by construction: the order event is keyed on the token *and* the
 * period end, so re-verifying inside the same period records nothing new, while a
 * renewal (a new period end) grants once and once only.
 */

export interface GoogleSyncResult {
  status: 'active' | 'inactive' | 'ignored'
  planId: string | null
  interval: BillingInterval
  expiresAt: string | null
  applied: boolean
  /** True when the token is already bound to a different account. */
  conflict?: boolean
}

export async function syncGoogleSubscription(params: {
  userId: string
  purchaseToken: string
  productId?: string | null
}): Promise<GoogleSyncResult> {
  const subscription = await verifyPlaySubscription(params.purchaseToken)
  const admin = getAdminClient()

  // A Play purchase token belongs to exactly one Google account, and therefore
  // to exactly one subscription. Without this check, a token copied from another
  // device could be re-verified here: the first grant would be a duplicate, but
  // a later renewal could land on the wrong account and the two rows would
  // compete for ownership. Refuse before any entitlement work.
  const { data: tokenOwners, error: ownerError } = await admin
    .from('google_play_subscriptions')
    .select('user_id')
    .eq('purchase_token', params.purchaseToken)

  if (ownerError) {
    // Fail closed: a database hiccup must not become an ownership bypass.
    logEvent('error', 'google.subscription.owner_lookup', {
      error: ownerError,
      userId: params.userId,
    })
    throw new Error(`Could not check the purchase owner: ${ownerError.message}`)
  }
  if ((tokenOwners ?? []).some((row) => String(row.user_id) !== params.userId)) {
    logEvent('warn', 'google.subscription.token_conflict', {
      userId: params.userId,
    })
    return {
      status: 'ignored',
      planId: null,
      interval: subscription.interval,
      expiresAt: subscription.expiryTime,
      applied: false,
      conflict: true,
    }
  }

  const productId = subscription.productId
  if (!subscription.planId || !productId) {
    logEvent('warn', 'google.subscription.unknown_product', {
      userId: params.userId,
      productId: productId ?? params.productId ?? null,
      state: subscription.state,
    })
    return {
      status: 'ignored',
      planId: null,
      interval: subscription.interval,
      expiresAt: subscription.expiryTime,
      applied: false,
    }
  }

  // Claim the token before granting anything. The pre-check above cannot stop
  // two concurrent requests from both seeing an unowned token; the unique
  // index can, but only if the insert happens before `applyPaidOrder`. A
  // conflict or a failed write must not fall through to a grant.
  const claim = await recordGoogleSubscription({
    userId: params.userId,
    purchaseToken: params.purchaseToken,
    subscription,
    acknowledged: subscription.acknowledged,
  })
  if (claim === 'conflict') {
    logEvent('warn', 'google.subscription.token_claim_conflict', {
      userId: params.userId,
    })
    return {
      status: 'ignored',
      planId: null,
      interval: subscription.interval,
      expiresAt: subscription.expiryTime,
      applied: false,
      conflict: true,
    }
  }
  if (claim === 'failed') {
    throw new Error('Could not record the Google Play purchase before granting it')
  }

  let applied = false
  let entitlementSettled = false
  if (subscription.active) {
    const amount = priceForPlan(subscription.planId, subscription.interval)
    if (!amount) {
      logEvent('error', 'google.subscription.missing_price', {
        userId: params.userId,
        planId: subscription.planId,
        interval: subscription.interval,
      })
    } else {
      const result = await applyPaidOrder({
        userId: params.userId,
        planId: subscription.planId,
        amount,
        interval: subscription.interval,
        provider: 'google',
        providerEventId: `google:${params.purchaseToken}:${subscription.expiryTime ?? subscription.state}`,
      })
      applied = result.applied
      // A duplicate or a would-downgrade is a settled entitlement: the account
      // already has at least what this purchase paid for. A mismatch, invalid
      // plan or unknown account is not, and acknowledging those would tell
      // Google to keep a payment this deployment never granted.
      entitlementSettled =
        result.applied ||
        result.reason === 'duplicate' ||
        result.reason === 'would_downgrade'
      logEvent('info', 'google.subscription.applied', {
        userId: params.userId,
        planId: subscription.planId,
        interval: subscription.interval,
        result: result.reason,
      })
    }
  }

  // Google refunds a purchase it never sees acknowledged after three days, so a
  // failure here is a paying customer about to be refunded. The row keeps
  // `acknowledged: false` and the next sync retries it. Only acknowledge once
  // the entitlement behind the purchase has actually been settled.
  let acknowledged = subscription.acknowledged
  if (!acknowledged && subscription.active && entitlementSettled) {
    try {
      acknowledged = await acknowledgeSubscription(params.purchaseToken, productId)
      if (!acknowledged) {
        logEvent('warn', 'google.subscription.acknowledge_failed', { userId: params.userId })
      }
    } catch (error: unknown) {
      logEvent('error', 'google.subscription.acknowledge', { error, userId: params.userId })
    }
  }

  // Cancelling stops the renewal, not the access already paid for: the daily
  // expiry job downgrades the account when the period Google reported ends.
  if (subscription.state === 'SUBSCRIPTION_STATE_CANCELED') {
    await admin.from('users').update({ cancel_at_period_end: true }).eq('id', params.userId)
  }

  if (acknowledged !== subscription.acknowledged) {
    // Best effort: the claim already exists and access is granted, so a failed
    // acknowledgement-state update only means the next sync re-records it.
    await recordGoogleSubscription({
      userId: params.userId,
      purchaseToken: params.purchaseToken,
      subscription,
      acknowledged,
    })
  }

  return {
    status: subscription.active ? 'active' : 'inactive',
    planId: subscription.planId,
    interval: subscription.interval,
    expiresAt: subscription.expiryTime,
    applied,
  }
}

async function recordGoogleSubscription(params: {
  userId: string
  purchaseToken: string
  subscription: PlaySubscription
  acknowledged: boolean
}): Promise<'recorded' | 'conflict' | 'failed'> {
  const { error } = await getAdminClient().from('google_play_subscriptions').upsert(
    {
      user_id: params.userId,
      purchase_token: params.purchaseToken,
      product_id: params.subscription.productId,
      plan_id: params.subscription.planId,
      interval: params.subscription.interval,
      state: params.subscription.state,
      expires_at: params.subscription.expiryTime,
      acknowledged: params.acknowledged,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' }
  )
  if (!error) return 'recorded'

  const duplicate =
    error.code === '23505' || /duplicate key|unique constraint/i.test(error.message)
  if (duplicate) return 'conflict'

  logEvent('error', 'google.subscription.record', { error, userId: params.userId })
  return 'failed'
}

/**
 * Re-checks stored subscriptions, which is how renewals reach the database
 * without Google pushing events to us. Play's real-time developer notifications
 * would be faster, but they need a Pub/Sub topic and a billing account; a daily
 * sweep of the tokens we already hold costs nothing and only has to be right
 * within a day, because access runs to the period end Google reported.
 */
export async function syncStoredGoogleSubscriptions(
  limit = 100
): Promise<{ checked: number; applied: number; failed: number }> {
  const admin = getAdminClient()
  const { data, error } = await admin
    .from('google_play_subscriptions')
    .select('user_id, purchase_token')
    // Two days of slack: a subscription that lapsed yesterday may have renewed,
    // and dropping it from the sweep would downgrade a paying customer.
    .gte('expires_at', new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString())
    .order('expires_at', { ascending: true })
    .limit(limit)

  if (error) throw new Error(`Could not read Google Play subscriptions: ${error.message}`)

  let checked = 0
  let applied = 0
  let failed = 0

  for (const row of data ?? []) {
    checked++
    try {
      const result = await syncGoogleSubscription({
        userId: String(row.user_id),
        purchaseToken: String(row.purchase_token),
      })
      if (result.applied) applied++
    } catch (syncError: unknown) {
      failed++
      logEvent('error', 'google.subscription.sync', { error: syncError, userId: row.user_id })
    }
  }

  return { checked, applied, failed }
}
