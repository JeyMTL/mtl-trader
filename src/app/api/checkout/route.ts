import { NextResponse } from 'next/server'

const PAYPAL_CLIENT_ID = process.env.PAYPAL_CLIENT_ID!
const PAYPAL_CLIENT_SECRET = process.env.PAYPAL_CLIENT_SECRET!
const PAYPAL_BASE = 'https://api-m.paypal.com'

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

const PLAN_MAP: Record<string, { amount: string; name: string }> = {
  basic: { amount: '9.99', name: 'Basic Plan' },
  pro: { amount: '29.99', name: 'Pro Plan' },
}

export async function POST(req: Request) {
  try {
    const { planId, userId, email } = await req.json()

    if (!planId || !PLAN_MAP[planId]) {
      return NextResponse.json({ error: 'Invalid plan' }, { status: 400 })
    }

    if (!userId || !email) {
      return NextResponse.json({ error: 'Missing userId or email' }, { status: 400 })
    }

    const accessToken = await getAccessToken()
    const plan = PLAN_MAP[planId]

    const response = await fetch(`${PAYPAL_BASE}/v2/checkout/orders`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        intent: 'CAPTURE',
        purchase_units: [{
          amount: {
            currency_code: 'USD',
            value: plan.amount,
          },
          description: `MTL Trader - ${plan.name} Monthly Subscription`,
          custom_id: JSON.stringify({ userId, planId }),
        }],
        application_context: {
          brand_name: 'MTL Trader',
          landing_page: 'BILLING',
          user_action: 'PAY_NOW',
          return_url: `${process.env.NEXT_PUBLIC_APP_URL}/paypal-success`,
          cancel_url: `${process.env.NEXT_PUBLIC_APP_URL}/dashboard/settings`,
        },
      }),
    })

    const data = await response.json()

    if (!data.id) {
      return NextResponse.json({ error: data.message || 'Failed to create PayPal order' }, { status: 400 })
    }

    const approveUrl = data.links?.find((l: { rel: string; href: string }) => l.rel === 'approve')?.href

    return NextResponse.json({ orderId: data.id, url: approveUrl })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
