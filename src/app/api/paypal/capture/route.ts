import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { applyPaidOrder, getPayPalAccessToken, parseCustomId, PAYPAL_BASE } from '@/lib/payments'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

interface PayPalOrder {
  id?: string
  status?: string
  purchase_units?: Array<{
    custom_id?: string
    amount?: { value?: string; currency_code?: string }
    payments?: {
      captures?: Array<{
        id?: string
        status?: string
        amount?: { value?: string; currency_code?: string }
      }>
    }
  }>
}

export async function POST(req: Request) {
  try {
    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    // Capturing is a paid provider call and the success page retries on a
    // flaky connection, so allow a handful and stop the loop.
    const limit = await rateLimit(`capture:${authUser.id}`, 20, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many confirmation attempts. Try again shortly.' },
        {
          status: 429,
          headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) },
        }
      )
    }

    const parsedBody = await readJsonBody<{ orderId?: unknown }>(req, { maxBytes: 8 * 1024 })
    if (!parsedBody.ok) return parsedBody.response
    const orderId = typeof parsedBody.value.orderId === 'string' ? parsedBody.value.orderId : ''

    if (!orderId) {
      return NextResponse.json({ error: 'Missing orderId' }, { status: 400 })
    }

    const accessToken = await getPayPalAccessToken()

    // Read the order before capturing it. Capture actually charges the buyer, so
    // the order's owner must be established first: checking `custom_id` after a
    // capture meant an authenticated caller could charge someone else's order
    // before being told it was forbidden.
    const orderResponse = await fetch(
      `${PAYPAL_BASE}/v2/checkout/orders/${encodeURIComponent(orderId)}`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    )
    const order = (await orderResponse.json().catch(() => ({}))) as PayPalOrder

    if (!orderResponse.ok) {
      logEvent('warn', 'paypal.capture.order_lookup', {
        orderId,
        status: orderResponse.status,
        userId: authUser.id,
      })
      return NextResponse.json(
        { error: 'Could not load that order.' },
        { status: orderResponse.status === 404 ? 404 : 502 }
      )
    }

    const orderUnit = order.purchase_units?.[0]
    const parsed = parseCustomId(orderUnit?.custom_id)
    if (!parsed) {
      return NextResponse.json({ error: 'Invalid order metadata' }, { status: 400 })
    }

    // Only the account owner may capture their own order.
    if (authUser.id !== parsed.userId) {
      logEvent('warn', 'paypal.capture.foreign_order', {
        orderId,
        userId: authUser.id,
      })
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    // A retried success page may find the order already captured. Reuse that
    // result instead of calling capture again, which PayPal would reject.
    let completed = order
    if (order.status !== 'COMPLETED') {
      const response = await fetch(
        `${PAYPAL_BASE}/v2/checkout/orders/${encodeURIComponent(orderId)}/capture`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        }
      )

      completed = (await response.json().catch(() => ({}))) as PayPalOrder
      if (!response.ok || completed.status !== 'COMPLETED') {
        logEvent('warn', 'paypal.capture.incomplete', {
          orderId,
          status: completed.status,
          userId: authUser.id,
        })
        return NextResponse.json({ error: 'Payment not completed' }, { status: 400 })
      }
    }

    const purchaseUnit = completed.purchase_units?.[0] ?? orderUnit
    const capture = purchaseUnit?.payments?.captures?.[0]
    const currency = capture?.amount?.currency_code ?? purchaseUnit?.amount?.currency_code
    if (currency && currency.toUpperCase() !== 'USD') {
      logEvent('warn', 'paypal.capture.currency', { orderId, currency, userId: authUser.id })
      return NextResponse.json({ error: 'Unexpected currency' }, { status: 400 })
    }

    // The capture is the money that actually moved; the order amount is what was
    // requested. If PayPal reports both and they disagree, applying either one
    // would grant an entitlement the payment did not buy.
    const orderedAmount = purchaseUnit?.amount?.value ?? orderUnit?.amount?.value
    const capturedAmount = capture?.amount?.value
    if (capturedAmount && orderedAmount && Number(capturedAmount) !== Number(orderedAmount)) {
      logEvent('warn', 'paypal.capture.amount_mismatch', {
        orderId,
        orderedAmount,
        capturedAmount,
        userId: authUser.id,
      })
      return NextResponse.json({ error: 'Payment amount mismatch' }, { status: 400 })
    }

    const amount = capturedAmount ?? orderedAmount
    if (typeof amount !== 'string' || !amount) {
      return NextResponse.json({ error: 'Payment amount missing' }, { status: 400 })
    }

    // The capture id matches the id the webhook and reconciliation use, so all
    // three paths de-dupe against the same payment_events row.
    const captureId = capture?.id

    const result = await applyPaidOrder({
      userId: parsed.userId,
      planId: parsed.planId,
      amount,
      provider: 'paypal',
      providerEventId: `paypal:capture:${captureId || orderId}`,
    })

    if (result.applied || result.reason === 'duplicate') {
      return NextResponse.json({ success: true })
    }
    if (result.reason === 'would_downgrade') {
      return NextResponse.json({ success: true, note: 'Already on an equal or higher plan' })
    }
    if (result.reason === 'amount_mismatch') {
      return NextResponse.json({ error: 'Amount mismatch, payment not applied' }, { status: 400 })
    }
    if (result.reason === 'unknown_user') {
      return NextResponse.json({ error: 'Account not found' }, { status: 404 })
    }
    return NextResponse.json({ error: 'Payment could not be applied' }, { status: 400 })
  } catch (error: unknown) {
    return apiError('paypal.capture', error, 500, 'Could not confirm the payment. If you were charged, it will be applied automatically.')
  }
}
