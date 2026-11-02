import { NextResponse } from 'next/server'
import { getAdminClient } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { applyPaidOrder, priceForPlan, revokePaidOrder } from '@/lib/payments'
import {
  isValidPaddleSignature,
  paddleCurrency,
  parseAdjustmentEvent,
  parseTransactionEvent,
  priceIdFor,
  webhookSecretConfigured,
} from '@/lib/paddle'
import { apiError, logEvent } from '@/lib/log'

/**
 * Paddle notifications.
 *
 * Paddle retries any non-2xx response, so a failure here means "come back
 * later"; an event we cannot use is acknowledged with 200 and a reason, because
 * retrying it forever would only hide the next real one.
 *
 * Access is granted by `transaction.completed` only. The amount applied comes
 * from the plan catalogue, not the transaction total, since Paddle adds sales tax
 * on top; the transaction must instead carry the price id this deployment
 * configured for that plan.
 */

export const runtime = 'nodejs'

const PAID_PLANS = PLANS.filter((plan) => plan.price > 0).map((plan) => plan.id)

interface PaddleEvent {
  event_id?: string
  event_type?: string
  data?: unknown
}

export async function POST(req: Request) {
  if (!webhookSecretConfigured()) {
    return NextResponse.json(
      { error: 'Paddle webhook is not configured' },
      { status: 503 }
    )
  }

  const rawBody = await req.text()
  if (!isValidPaddleSignature(req.headers.get('paddle-signature'), rawBody)) {
    logEvent('warn', 'paddle.webhook.invalid_signature')
    return NextResponse.json({ error: 'Invalid signature' }, { status: 401 })
  }

  let event: PaddleEvent
  try {
    event = JSON.parse(rawBody) as PaddleEvent
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  try {
    if (event.event_type === 'transaction.completed') {
      return await handleTransactionCompleted(event.data, event.event_id)
    }
    if (event.event_type === 'subscription.canceled') {
      return await handleSubscriptionCanceled(event.data)
    }
    if (event.event_type === 'adjustment.created') {
      return await handleAdjustment(event.data)
    }
    return NextResponse.json({ received: true, ignored: event.event_type || 'unknown' })
  } catch (error: unknown) {
    return apiError('paddle.webhook', error, 500, 'Could not process the webhook')
  }
}

async function handleTransactionCompleted(data: unknown, eventId?: string) {
  const transaction = parseTransactionEvent(data)
  if (!transaction) {
    return NextResponse.json({ error: 'Missing transaction' }, { status: 400 })
  }
  if (transaction.status !== 'completed') {
    return NextResponse.json({ received: true, ignored: 'not_completed' })
  }

  const target = await resolveTarget(transaction)
  if (!target) {
    logEvent('warn', 'paddle.webhook.unresolved_transaction', {
      transactionId: transaction.transactionId,
      subscriptionId: transaction.subscriptionId,
    })
    return NextResponse.json({ received: true, ignored: 'unresolved_transaction' })
  }

  // The price id is what proves the customer paid for this plan. A missing id is
  // tolerated (older payloads), a mismatched one is not.
  const expectedPrice = priceIdFor(target.planId, transaction.interval)
  if (expectedPrice && transaction.priceId && transaction.priceId !== expectedPrice) {
    logEvent('warn', 'paddle.webhook.price_mismatch', {
      transactionId: transaction.transactionId,
      planId: target.planId,
      interval: transaction.interval,
      priceId: transaction.priceId,
    })
    return NextResponse.json({ received: true, ignored: 'price_mismatch' })
  }

  const currency = paddleCurrency()
  if (transaction.currency && transaction.currency.toUpperCase() !== currency) {
    logEvent('warn', 'paddle.webhook.currency_mismatch', {
      transactionId: transaction.transactionId,
      currency: transaction.currency,
    })
    return NextResponse.json({ received: true, ignored: 'currency_mismatch' })
  }

  // The catalogue price for the cadence bought, not `totalCents`: Paddle collects
  // tax on top. A missing price means this deployment never configured that
  // combination, so the payment is acknowledged and left for a human instead of
  // being applied with a guessed period length.
  const amount = priceForPlan(target.planId, transaction.interval)
  if (!amount) {
    logEvent('error', 'paddle.webhook.missing_price', {
      transactionId: transaction.transactionId,
      planId: target.planId,
      interval: transaction.interval,
    })
    return NextResponse.json({ received: true, ignored: 'missing_price' })
  }

  const result = await applyPaidOrder({
    userId: target.userId,
    planId: target.planId,
    amount,
    interval: transaction.interval,
    provider: 'paddle',
    providerEventId: `paddle:transaction:${transaction.transactionId}`,
  })

  logEvent('info', 'paddle.webhook.transaction', {
    transactionId: transaction.transactionId,
    eventId,
    userId: target.userId,
    planId: target.planId,
    interval: transaction.interval,
    result: result.reason,
  })

  if (result.applied || result.reason === 'duplicate') {
    await recordSubscription({
      userId: target.userId,
      email: transaction.customerEmail,
      subscriptionId: transaction.subscriptionId,
    })
  }

  return NextResponse.json({ received: true, ...result })
}

/**
 * Finds the account and plan behind a transaction.
 *
 * `custom_data` is authoritative and is copied onto the subscription, so a
 * renewal carries it too. The fallbacks exist for the case Paddle omits it: the
 * subscription row we recorded on the first payment, then the tier the account
 * is already on.
 */
async function resolveTarget(transaction: {
  userId: string | null
  planId: string | null
  subscriptionId: string | null
}): Promise<{ userId: string; planId: string } | null> {
  const admin = getAdminClient()
  let userId = transaction.userId
  let planId = transaction.planId && PAID_PLANS.includes(transaction.planId)
    ? transaction.planId
    : null

  if (!userId && transaction.subscriptionId) {
    const { data } = await admin
      .from('billing_subscriptions')
      .select('user_id')
      .eq('provider', 'paddle')
      .eq('remote_plan_id', transaction.subscriptionId)
      .maybeSingle()
    if (data?.user_id) userId = String(data.user_id)
  }

  if (userId && !planId) {
    const { data } = await admin
      .from('users')
      .select('subscription_tier')
      .eq('id', userId)
      .maybeSingle()
    if (typeof data?.subscription_tier === 'string' && PAID_PLANS.includes(data.subscription_tier)) {
      planId = data.subscription_tier
    }
  }

  if (!userId || !planId) return null
  return { userId, planId }
}

/** Remembers which account owns a Paddle subscription, so cancel can find it. */
async function recordSubscription(params: {
  userId: string
  email: string | null
  subscriptionId: string | null
}): Promise<void> {
  const admin = getAdminClient()
  const { error } = await admin.from('billing_subscriptions').upsert(
    {
      user_id: params.userId,
      provider: 'paddle',
      email: params.email,
      remote_plan_id: params.subscriptionId,
      status: 'active',
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,provider' }
  )
  if (error) {
    console.error('Could not record the Paddle subscription:', error.message)
  }
}

/**
 * Paddle already stopped billing. Access is not taken away here: the customer
 * paid for the days ahead, and `expire_lapsed_subscriptions` handles the rest.
 */
async function handleSubscriptionCanceled(data: unknown) {
  const record = data && typeof data === 'object' ? (data as Record<string, unknown>) : null
  const subscriptionId = typeof record?.id === 'string' ? record.id : null
  if (!subscriptionId) {
    return NextResponse.json({ received: true, ignored: 'missing_subscription' })
  }

  const admin = getAdminClient()
  const { data: row } = await admin
    .from('billing_subscriptions')
    .select('user_id')
    .eq('provider', 'paddle')
    .eq('remote_plan_id', subscriptionId)
    .maybeSingle()

  if (!row?.user_id) {
    return NextResponse.json({ received: true, ignored: 'unknown_subscription' })
  }

  await admin
    .from('users')
    .update({ cancel_at_period_end: true })
    .eq('id', row.user_id)

  await admin
    .from('billing_subscriptions')
    .update({ status: 'cancelled', updated_at: new Date().toISOString() })
    .eq('provider', 'paddle')
    .eq('remote_plan_id', subscriptionId)

  logEvent('info', 'paddle.webhook.cancelled', { userId: row.user_id })
  return NextResponse.json({ received: true, cancelled: true })
}

/**
 * A refund or chargeback revokes the paid period. The adjustment itself carries
 * no custom data, so the account is found through the transaction event id the
 * original payment was recorded under.
 */
async function handleAdjustment(data: unknown) {
  const adjustment = parseAdjustmentEvent(data)
  if (!adjustment) {
    return NextResponse.json({ received: true, ignored: 'missing_adjustment' })
  }
  if (adjustment.action !== 'refund') {
    return NextResponse.json({ received: true, ignored: 'not_a_refund' })
  }
  if (!adjustment.transactionId) {
    return NextResponse.json({ received: true, ignored: 'missing_transaction' })
  }

  const admin = getAdminClient()
  const { data: original } = await admin
    .from('payment_events')
    .select('user_id, plan_id, amount')
    .eq('provider', 'paddle')
    .eq('provider_event_id', `paddle:transaction:${adjustment.transactionId}`)
    .maybeSingle()

  if (!original?.user_id) {
    return NextResponse.json({ received: true, ignored: 'unresolved_refund' })
  }

  const revoked = await revokePaidOrder({
    userId: String(original.user_id),
    planId: String(original.plan_id),
    amount: Number(original.amount) || 0,
    provider: 'paddle',
    // Keyed on the adjustment, so a replayed refund is a no-op.
    providerEventId: `paddle:refund:${adjustment.adjustmentId}`,
  })

  logEvent('info', 'paddle.webhook.refund', {
    adjustmentId: adjustment.adjustmentId,
    userId: String(original.user_id),
    result: revoked,
  })

  return NextResponse.json({ received: true, revoked })
}
