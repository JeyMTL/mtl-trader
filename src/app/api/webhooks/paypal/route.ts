import { NextResponse } from 'next/server'
import {
  applyPaidOrder,
  getPayPalAccessToken,
  parseCustomId,
  parseRefundEvent,
  revokePaidOrder,
  PAYPAL_BASE,
} from '@/lib/payments'
import { getAdminClient } from '@/lib/server-auth'
import { apiError, logEvent } from '@/lib/log'
import { readRawBody } from '@/lib/request'

/**
 * PayPal webhook — the durable upgrade path.
 *
 * The success-page capture call still exists for immediate feedback, but if a
 * user closes the tab before it completes the upgrade is applied here instead.
 * Every event is verified with PayPal's signature-verification API before any
 * account change is made, and `applyPaidOrder` makes replaying an event a no-op.
 *
 * Refunds, reversals and disputes revoke access through `revokePaidOrder`. A
 * partial refund also revokes: the product has no partial state, and continuing
 * to serve a refunded account is worse than ending access early.
 */

const REFUND_EVENTS = new Set([
  'PAYMENT.CAPTURE.REFUNDED',
  'PAYMENT.CAPTURE.REVERSED',
  'PAYMENT.CAPTURE.DENIED',
])

interface PayPalWebhookEvent {
  id?: string
  event_type?: string
  resource?: {
    id?: string
    custom_id?: string
    amount?: { value?: string; currency_code?: string }
    links?: Array<{ rel?: string; href?: string }>
  }
}

/** Finds the order behind a refund, falling back to the recorded capture event. */
async function resolveRefundTarget(event: PayPalWebhookEvent) {
  const details = parseRefundEvent(event)
  if (!details) return null

  const fromCustomId = parseCustomId(details.customId) ?? parseCustomId(event.resource?.custom_id)
  if (fromCustomId) {
    return {
      userId: fromCustomId.userId,
      planId: fromCustomId.planId,
      amount: details.amount,
      refundId: details.refundId,
    }
  }

  if (!details.captureId) return null

  const { data, error } = await getAdminClient()
    .from('payment_events')
    .select('user_id, plan_id, amount')
    .eq('provider', 'paypal')
    .eq('provider_event_id', `paypal:capture:${details.captureId}`)
    .maybeSingle()

  if (error) throw new Error(`Could not look up the refunded capture: ${error.message}`)
  if (!data || !data.user_id) return null

  return {
    userId: data.user_id as string,
    planId: (data.plan_id as string) ?? 'unknown',
    amount: details.amount !== '0' ? details.amount : String(data.amount ?? '0'),
    refundId: details.refundId,
  }
}

export async function POST(req: Request) {
  const webhookId = process.env.PAYPAL_WEBHOOK_ID
  if (!webhookId || !process.env.PAYPAL_CLIENT_ID || !process.env.PAYPAL_CLIENT_SECRET) {
    return NextResponse.json({ error: 'PayPal webhook is not configured' }, { status: 503 })
  }

  // The raw body must be verified exactly as received, and it should not be
  // allowed to grow past what a webhook can plausibly be.
  const parsedBody = await readRawBody(req, 1024 * 1024)
  if (!parsedBody.ok) return parsedBody.response
  const rawBody = parsedBody.value

  const transmissionId = req.headers.get('paypal-transmission-id')
  const transmissionTime = req.headers.get('paypal-transmission-time')
  const certUrl = req.headers.get('paypal-cert-url')
  const authAlgo = req.headers.get('paypal-auth-algo')
  const transmissionSig = req.headers.get('paypal-transmission-sig')

  if (!transmissionId || !transmissionTime || !certUrl || !authAlgo || !transmissionSig) {
    return NextResponse.json({ error: 'Missing PayPal signature headers' }, { status: 400 })
  }

  let event: PayPalWebhookEvent
  try {
    event = JSON.parse(rawBody) as PayPalWebhookEvent
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  try {
    const accessToken = await getPayPalAccessToken()
    const verifyRes = await fetch(`${PAYPAL_BASE}/v1/notifications/verify-webhook-signature`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        auth_algo: authAlgo,
        cert_url: certUrl,
        transmission_id: transmissionId,
        transmission_sig: transmissionSig,
        transmission_time: transmissionTime,
        webhook_id: webhookId,
        webhook_event: event,
      }),
    })
    const verification = await verifyRes.json() as { verification_status?: string }
    if (verification.verification_status !== 'SUCCESS') {
      logEvent('warn', 'paypal.webhook.invalid_signature', { eventType: event.event_type })
      return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
    }
  } catch (error: unknown) {
    // Returning non-2xx asks PayPal to retry, which is what we want here.
    return apiError('paypal.webhook.verify', error, 502, 'Signature verification failed')
  }

  if (REFUND_EVENTS.has(event.event_type || '')) {
    try {
      const target = await resolveRefundTarget(event)
      if (!target) {
        logEvent('warn', 'paypal.webhook.unresolved_refund', {
          eventType: event.event_type,
          resourceId: event.resource?.id,
        })
        return NextResponse.json({ received: true, ignored: 'unresolved_refund' })
      }

      const result = await revokePaidOrder({
        userId: target.userId,
        planId: target.planId,
        amount: target.amount,
        provider: 'paypal',
        providerEventId: `paypal:refund:${target.refundId}`,
      })

      logEvent('info', 'paypal.webhook.revoked', {
        eventType: event.event_type,
        userId: target.userId,
        result,
      })
      return NextResponse.json({ received: true, revoked: result })
    } catch (error: unknown) {
      return apiError('paypal.webhook.revoke', error, 500, 'Could not process the refund')
    }
  }

  // Acknowledge everything that is not a completed capture.
  if (event.event_type !== 'PAYMENT.CAPTURE.COMPLETED') {
    return NextResponse.json({ received: true, ignored: event.event_type || 'unknown' })
  }

  const parsed = parseCustomId(event.resource?.custom_id)
  const captureId = event.resource?.id
  if (!parsed || !captureId) {
    return NextResponse.json({ error: 'Invalid order metadata' }, { status: 400 })
  }

  try {
    const result = await applyPaidOrder({
      userId: parsed.userId,
      planId: parsed.planId,
      amount: event.resource?.amount?.value ?? '0',
      provider: 'paypal',
      providerEventId: `paypal:capture:${captureId}`,
    })
    return NextResponse.json({ received: true, ...result })
  } catch (error: unknown) {
    return apiError('paypal.webhook.apply', error, 500, 'Could not apply the payment')
  }
}
