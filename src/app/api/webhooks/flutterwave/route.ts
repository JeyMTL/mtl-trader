import { NextResponse } from 'next/server'
import { getAdminClient } from '@/lib/server-auth'
import {
  FLW_CURRENCY,
  isValidFlutterwaveSignature,
  recordSubscription,
  resolveChargeTarget,
  verifyTransaction,
  webhookSecretConfigured,
} from '@/lib/flutterwave'
import { applyPaidOrder } from '@/lib/payments'
import { apiError, logEvent } from '@/lib/log'

export const runtime = 'nodejs'

interface FlutterwaveEvent {
  event?: string
  data?: {
    id?: number | string
    status?: string
    amount?: number | string
    currency?: string
    tx_ref?: string
    customer?: { email?: string }
    plan?: { id?: number | string }
  }
}

export async function POST(req: Request) {
  if (!webhookSecretConfigured()) {
    return NextResponse.json(
      { error: 'Flutterwave webhook is not configured' },
      { status: 503 }
    )
  }

  const rawBody = await req.text()
  if (!isValidFlutterwaveSignature(req.headers.get('verif-hash'), rawBody)) {
    logEvent('warn', 'flutterwave.webhook.invalid_signature')
    return NextResponse.json({ error: 'Invalid signature' }, { status: 401 })
  }

  let event: FlutterwaveEvent
  try {
    event = JSON.parse(rawBody) as FlutterwaveEvent
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  try {
    if (event.event === 'charge.completed') {
      return await handleCharge(event)
    }

    if (event.event === 'subscription.cancelled') {
      return await handleCancellation(event)
    }

    return NextResponse.json({ received: true, ignored: event.event || 'unknown' })
  } catch (error: unknown) {
    // A 5xx tells Flutterwave to retry the event.
    return apiError(
      'flutterwave.webhook',
      error,
      500,
      'Could not process the webhook'
    )
  }
}

async function handleCharge(event: FlutterwaveEvent) {
  const data = event.data
  if (!data?.id) {
    return NextResponse.json({ error: 'Missing transaction id' }, { status: 400 })
  }
  if (String(data.status ?? '').toLowerCase() !== 'successful') {
    return NextResponse.json({ received: true, ignored: 'unsuccessful_charge' })
  }

  // Never trust the webhook body alone; confirm the charge with Flutterwave.
  const charge = await verifyTransaction(String(data.id))
  if (charge.status !== 'successful') {
    return NextResponse.json({ received: true, ignored: 'not_successful' })
  }
  if (charge.currency !== FLW_CURRENCY) {
    logEvent('warn', 'flutterwave.webhook.currency_mismatch', {
      transactionId: charge.id,
      currency: charge.currency,
    })
    return NextResponse.json({ received: true, ignored: 'currency_mismatch' })
  }

  const target = await resolveChargeTarget(charge)
  if (!target) {
    logEvent('warn', 'flutterwave.webhook.unresolved_charge', {
      transactionId: charge.id,
      email: charge.customerEmail,
    })
    return NextResponse.json({ received: true, ignored: 'unresolved_charge' })
  }

  const result = await applyPaidOrder({
    userId: target.userId,
    planId: target.planId,
    amount: charge.amount,
    provider: 'flutterwave',
    providerEventId: `flutterwave:charge:${charge.id}`,
  })

  logEvent('info', 'flutterwave.webhook.charge', {
    transactionId: charge.id,
    userId: target.userId,
    planId: target.planId,
    result: result.reason,
  })

  if (result.applied || result.reason === 'duplicate') {
    await recordSubscription(target)
  }

  return NextResponse.json({ received: true, ...result })
}

/**
 * A cancellation stops future charges. Access continues until the paid period
 * ends, which the existing daily expiry job handles.
 */
async function handleCancellation(event: FlutterwaveEvent) {
  const email = event.data?.customer?.email?.toLowerCase()
  if (!email) {
    return NextResponse.json({ received: true, ignored: 'missing_email' })
  }

  const admin = getAdminClient()
  // `eq`, not `ilike`: an address containing `_` or `%` must not act as a
  // wildcard here, or a cancellation could land on another account.
  const { data: user } = await admin
    .from('users')
    .select('id')
    .eq('email', email)
    .maybeSingle()

  if (!user?.id) {
    return NextResponse.json({ received: true, ignored: 'unknown_user' })
  }

  await admin
    .from('users')
    .update({ cancel_at_period_end: true })
    .eq('id', user.id)

  await admin
    .from('billing_subscriptions')
    .update({ status: 'cancelled', updated_at: new Date().toISOString() })
    .eq('user_id', user.id)
    .eq('provider', 'flutterwave')

  logEvent('info', 'flutterwave.webhook.cancelled', { userId: user.id })
  return NextResponse.json({ received: true, cancelled: true })
}
