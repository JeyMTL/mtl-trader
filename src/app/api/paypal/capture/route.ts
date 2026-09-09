import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { getAuthUser } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'

const PAYPAL_CLIENT_ID = process.env.PAYPAL_CLIENT_ID!
const PAYPAL_CLIENT_SECRET = process.env.PAYPAL_CLIENT_SECRET!
const PAYPAL_BASE = 'https://api-m.paypal.com'

// Derived from PLANS so captured amounts must match the displayed prices.
const PLAN_MAP: Record<string, { amount: string; name: string }> = Object.fromEntries(
  PLANS.filter(p => p.price > 0).map(p => [p.id, { amount: p.price.toFixed(2), name: `${p.name} Plan` }])
)

async function getAccessToken(): Promise<string> {
  const auth = Buffer.from(`${PAYPAL_CLIENT_ID}:${PAYPAL_CLIENT_SECRET}`).toString('base64')
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
    const customId = purchaseUnit?.custom_id
    if (!customId) {
      return NextResponse.json({ error: 'No metadata found' }, { status: 400 })
    }

    let userId: string
    let planId: string
    try {
      const parsed = JSON.parse(customId)
      userId = parsed.userId
      planId = parsed.planId
    } catch {
      return NextResponse.json({ error: 'Invalid order metadata' }, { status: 400 })
    }

    // Only the account owner may capture their own order
    if (authUser.id !== userId) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    // Verify the paid amount matches the plan price
    const expectedAmount = PLAN_MAP[planId]?.amount
    const paidAmount = purchaseUnit?.amount?.value
    if (!expectedAmount || !paidAmount || Number(paidAmount) !== Number(expectedAmount)) {
      return NextResponse.json({ error: 'Amount mismatch, payment not applied' }, { status: 400 })
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )

    const maxTrades = planId === 'pro' ? -1 : planId === 'basic' ? 50 : 10

    const { error } = await supabase
      .from('users')
      .update({
        subscription_tier: planId,
        subscription_status: 'active',
        max_trades: maxTrades,
        trades_remaining: maxTrades === -1 ? -1 : maxTrades,
      })
      .eq('id', userId)

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ success: true })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
