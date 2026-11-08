import { NextResponse } from 'next/server'
import { getAdminClient } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { applyPaidOrder, priceForPlan, revokePaidOrder } from '@/lib/payments'
import {
  isValidPaddleSignature,
  paddleCurrency,
  parseAdjustmentEvent,
  parseTransactionEvent,
  planForPriceId,
  webhookSecretConfigured,
} from '@/lib/paddle'
import { apiError, logEvent } from '@/lib/log'
import { readRawBody } from '@/lib/request'

/**
 * Paddle notifications.
 *
 * Paddle retries any non-2xx response, so a failure here means "come back
 * later"; an event we cannot use is acknowledged with 200 and a reason, because
 * retrying it forever would only hide the next real one.
 *
 * Access is granted by `transaction.completed` only. The amount applied comes
 * from the plan catalogue, not the transaction total, since Paddle adds sales tax
 * on top. The plan itself is derived from the price id on the transaction, not
 * from the `custom_data` the checkout request asked for: the price id is what
 * Paddle actually charged, so a stale, swapped or missing plan id cannot buy a
 * different tier. A transaction whose price is not in this deployment's
 * catalogue is acknowledged and ignored for a human to review.
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

  const parsedBody = await readRawBody(req, 1024 * 1024)
  if (!parsedBody.ok) return parsedBody.response
  const rawBody = parsedBody.value

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

  // The price id decides the plan and cadence. A missing, unknown or ambiguous
  // price is acknowledged without granting anything: Paddle retries a non-2xx
  // forever, and a guessed plan would be worse than a payment support can see.
  const priceMatch = planForPriceId(transaction.priceId, PAID_PLANS, transaction.planId)
  if (!priceMatch) {
    logEvent('warn', 'paddle.webhook.unrecognised_price', {
      transactionId: transaction.transactionId,
      planId: transaction.planId,
      interval: transaction.interval,
      priceId: transaction.priceId,
    })
    return NextResponse.json({ received: true, ignored: 'unrecognised_price' })
  }
  if (transaction.currency && transaction.currency.toUpperCase() !== paddleCurrency()) {
    // Informational only: the price id already proves the configured price. It is
    // logged so a currency mismatch in the catalogue is visible, not used to
    // refuse a correctly priced payment.
    logEvent('warn', 'paddle.webhook.currency_mismatch', {
      transactionId: transaction.transactionId,
      currency: transaction.currency,
    })
  }

  const target = await resolveTarget(transaction, priceMatch.planId)
  if (!target) {
    logEvent('warn', 'paddle.webhook.unresolved_transaction', {
      transactionId: transaction.transactionId,
      subscriptionId: transaction.subscriptionId,
    })
    return NextResponse.json({ received: true, ignored: 'unresolved_transaction' })
  }

  // The catalogue price for the cadence bought, not `totalCents`: Paddle collects
  // tax on top. A missing price means this deployment never configured that
  // combination, so the payment is acknowledged and left for a human instead of
  // being applied with a guessed period length.
  const amount = priceForPlan(target.planId, priceMatch.interval)
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
    interval: priceMatch.interval,
    provider: 'paddle',
    providerEventId: `paddle:transaction:${transaction.transactionId}`,
  })

  logEvent('info', 'paddle.webhook.transaction', {
    transactionId: transaction.transactionId,
    eventId,
    userId: target.userId,
    planId: target.planId,
    interval: priceMatch.interval,
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
 * Finds the account behind a transaction.
 *
 * `custom_data` is copied onto the subscription by Paddle, so it is normally
 * present even on a renewal. If it is not, the subscription row we recorded on
 * the first payment identifies the account. The plan never comes from here: it
 * comes from the price id, so a missing custom plan cannot silently fall back to
 * whatever tier the account happened to hold.
 */
async function resolveTarget(
  transaction: {
    userId: string | null
    subscriptionId: string | null
  },
  planId: string
): Promise<{ userId: string; planId: string } | null> {
  let userId = transaction.userId

  if (!userId && transaction.subscriptionId) {
    const { data } = await getAdminClient()
      .from('billing_subscriptions')
      .select('user_id')
      .eq('provider', 'paddle')
      .eq('remote_plan_id', transaction.subscriptionId)
      .maybeSingle()
    if (data?.user_id) userId = String(data.user_id)
  }

  if (!userId) return null
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
