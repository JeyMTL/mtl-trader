import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { getPayPalAccessToken, PAYPAL_BASE } from '@/lib/payments'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

// Derived from PLANS so checkout can never drift from the displayed prices.
const PLAN_MAP: Record<string, { amount: string; name: string }> = Object.fromEntries(
  PLANS.filter(p => p.price > 0).map(p => [p.id, { amount: p.price.toFixed(2), name: `${p.name} Plan` }])
)

export async function POST(req: Request) {
  try {
    const parsed = await readJsonBody<{ planId?: unknown; userId?: unknown }>(req, {
      maxBytes: 8 * 1024,
    })
    if (!parsed.ok) return parsed.response

    const { planId, userId } = parsed.value
    if (typeof planId !== 'string' || !PLAN_MAP[planId]) {
      return NextResponse.json({ error: 'Invalid plan' }, { status: 400 })
    }

    if (typeof userId !== 'string' || !userId) {
      return NextResponse.json({ error: 'Missing userId' }, { status: 400 })
    }

    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    if (authUser.id !== userId) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }
    const buyerId = authUser.id

    // Creating an order is free but not free for PayPal or for us: an abandoned
    // checkout loop leaves a trail of live orders. Ten an hour is far more than
    // a person needs and far less than a script wants.
    const limit = await rateLimit(`checkout:${authUser.id}`, 10, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many checkout attempts. Try again later.' },
        {
          status: 429,
          headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) },
        }
      )
    }

    const accessToken = await getPayPalAccessToken()
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
          // Honest description: one payment buys one 30-day period. Access ends
          // unless it is renewed (see `expire_lapsed_subscriptions`).
          description: `MTL Trader - ${plan.name} Plan (30 days)`,
          custom_id: JSON.stringify({ userId: buyerId, planId }),
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
      logEvent('error', 'checkout.create_order_failed', {
        planId,
        userId,
        providerMessage: data.message,
        providerName: data.name,
      })
      return NextResponse.json({ error: 'Could not start the PayPal checkout. Please try again.' }, { status: 502 })
    }

    const approveUrl = data.links?.find((l: { rel: string; href: string }) => l.rel === 'approve')?.href

    return NextResponse.json({ orderId: data.id, url: approveUrl })
  } catch (error: unknown) {
    return apiError('checkout', error, 500, 'Could not start the checkout. Please try again.')
  }
}
