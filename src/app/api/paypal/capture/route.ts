import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { applyPaidOrder, parseCustomId, PAYPAL_BASE } from '@/lib/payments'

async function getAccessToken(): Promise<string> {
  const auth = Buffer.from(`${process.env.PAYPAL_CLIENT_ID}:${process.env.PAYPAL_CLIENT_SECRET}`).toString('base64')
  const res = await fetch(`${PAYPAL_BASE}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  })
  const data = await res.json()
  return data.access_token
}

export async function POST(req: Request) {
  try {
    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { orderId } = await req.json()

    if (!orderId) {
      return NextResponse.json({ error: 'Missing orderId' }, { status: 400 })
    }

    const accessToken = await getAccessToken()

    const response = await fetch(`${PAYPAL_BASE}/v2/checkout/orders/${orderId}/capture`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    })

    const data = await response.json()

    if (data.status !== 'COMPLETED') {
      return NextResponse.json({ error: 'Payment not completed' }, { status: 400 })
    }

    const purchaseUnit = data.purchase_units?.[0]
    const parsed = parseCustomId(purchaseUnit?.custom_id)
    if (!parsed) {
      return NextResponse.json({ error: 'Invalid order metadata' }, { status: 400 })
    }

    // Only the account owner may capture their own order
    if (authUser.id !== parsed.userId) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    // The capture id matches the id the webhook and reconciliation use, so all
    // three paths de-dupe against the same payment_events row.
    const captureId = purchaseUnit?.payments?.captures?.[0]?.id

    const result = await applyPaidOrder({
      userId: parsed.userId,
      planId: parsed.planId,
      amount: purchaseUnit?.amount?.value ?? '0',
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
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
