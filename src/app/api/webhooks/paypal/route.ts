import { NextResponse } from 'next/server'
import { getPayPalAccessToken, parseCustomId, applyPaidOrder, PAYPAL_BASE } from '@/lib/payments'

/**
 * PayPal webhook — the durable upgrade path.
 *
 * The success-page capture call still exists for immediate feedback, but if a
 * user closes the tab before it completes the upgrade is applied here instead.
 * Every event is verified with PayPal's signature-verification API before any
 * account change is made, and `applyPaidOrder` makes replaying an event a no-op.
 */


interface PayPalWebhookEvent {
  id?: string
  event_type?: string
  resource?: {
    id?: string
    custom_id?: string
    amount?: { value?: string; currency_code?: string }
  }
}

export async function POST(req: Request) {
  const webhookId = process.env.PAYPAL_WEBHOOK_ID
  if (!webhookId || !process.env.PAYPAL_CLIENT_ID || !process.env.PAYPAL_CLIENT_SECRET) {
    return NextResponse.json({ error: 'PayPal webhook is not configured' }, { status: 503 })
  }

  // The raw body must be verified exactly as received.
  const rawBody = await req.text()

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
      return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
    }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: `Signature verification failed: ${message}` }, { status: 502 })
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
    // Returning non-2xx asks PayPal to retry.
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
