import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { createCheckoutTransaction, paddleConfigured, priceIdFor } from '@/lib/paddle'
import { apiError, apiWarn, logEvent } from '@/lib/log'

/**
 * Card checkout through Paddle.
 *
 *   GET  -> which plans can be bought right now (drives the app's plan buttons)
 *   POST -> create a transaction and hand back its hosted checkout link
 *
 * The Flutter app calls this rather than a processor-specific route: the app is
 * the surface most customers use, and it must not need rebuilding every time the
 * server-side processor changes. Paddle is the merchant of record, so it handles
 * sales tax and receipts and renews the subscription itself.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const PAID_PLANS = PLANS.filter((plan) => plan.price > 0).map((plan) => plan.id)

/** One decision, used by both the GET and the POST, so they cannot disagree. */
function sellablePlans(): string[] {
  if (!paddleConfigured()) return []
  return PAID_PLANS.filter((planId) => Boolean(priceIdFor(planId, 'month')))
}

export async function GET() {
  const plans = sellablePlans()
  return NextResponse.json(
    { enabled: plans.length > 0, provider: plans.length > 0 ? 'paddle' : null, plans },
    { headers: { 'Cache-Control': 'no-store' } }
  )
}

export async function POST(req: Request) {
  try {
    const authUser = await getAuthUser(req)
    if (!authUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = (await req.json().catch(() => ({}))) as {
      planId?: unknown
      userId?: unknown
    }
    const planId = typeof body.planId === 'string' ? body.planId : ''
    if (!PAID_PLANS.includes(planId)) {
      return apiWarn('checkout.card.invalid_plan', 'Invalid plan')
    }

    // The authenticated user is the buyer. A caller-supplied id may confirm it,
    // but may never point the payment at someone else's account.
    if (typeof body.userId === 'string' && body.userId && body.userId !== authUser.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    if (!paddleConfigured()) {
      return NextResponse.json(
        { error: 'Card payments are not configured yet.' },
        { status: 503 }
      )
    }

    const priceId = priceIdFor(planId, 'month')
    if (!priceId) {
      logEvent('error', 'checkout.card.missing_price', { planId })
      return NextResponse.json(
        { error: 'That plan is not available for card payment right now.' },
        { status: 503 }
      )
    }

    const checkout = await createCheckoutTransaction({
      planId,
      priceId,
      userId: authUser.id,
      interval: 'month',
    })

    logEvent('info', 'checkout.card.created', {
      userId: authUser.id,
      planId,
      provider: 'paddle',
      transactionId: checkout.transactionId,
    })

    return NextResponse.json(
      { url: checkout.url, provider: 'paddle', transactionId: checkout.transactionId },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError(
      'checkout.card',
      error,
      502,
      'Could not start the card checkout. Please try again.'
    )
  }
}
