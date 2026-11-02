import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { PAID_PLAN_PRICES } from '@/lib/payments'
import {
  createCheckoutTransaction,
  paddleConfigured,
  priceIdFor,
  sellablePlanIds,
} from '@/lib/paddle'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import type { BillingInterval } from '@/types'

/**
 * Starts a Paddle card subscription.
 *
 *   GET  -> which plans can be bought right now (drives the pricing buttons)
 *   POST -> create a transaction and hand back its hosted checkout link
 *
 * The GET is public and deliberately reveals only plan ids: a deployment with no
 * Paddle key, or with a missing price id, must hide the button rather than offer
 * a checkout that fails after the customer has decided to pay.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const PAID_PLANS = PLANS.filter((plan) => plan.price > 0).map((plan) => plan.id)

export async function GET() {
  return NextResponse.json(
    {
      enabled: paddleConfigured(),
      plans: sellablePlanIds(PAID_PLANS, 'month'),
      // Selling a yearly price is a separate catalogue entry in Paddle, so a
      // deployment can legitimately have one cadence and not the other.
      annual: sellablePlanIds(PAID_PLANS, 'year'),
    },
    { headers: { 'Cache-Control': 'no-store' } }
  )
}

export async function POST(req: Request) {
  if (!paddleConfigured()) {
    return NextResponse.json(
      { error: 'Card payments are not configured yet.' },
      { status: 503 }
    )
  }

  try {
    const authUser = await getAuthUser(req)
    if (!authUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = (await req.json().catch(() => ({}))) as {
      planId?: unknown
      userId?: unknown
      interval?: unknown
    }

    const planId = typeof body.planId === 'string' ? body.planId : ''
    // Anything unrecognised is treated as monthly rather than refused: the
    // cardinality is validated below by the amount and the price id anyway.
    const interval: BillingInterval = body.interval === 'year' ? 'year' : 'month'
    if (!PAID_PLANS.includes(planId) || !PAID_PLAN_PRICES[planId]) {
      return apiWarn('paddle.checkout.invalid_plan', 'Invalid plan')
    }

    // The authenticated user is the buyer. A caller-supplied id may confirm it,
    // but may never point the payment at someone else's account.
    if (typeof body.userId === 'string' && body.userId && body.userId !== authUser.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const priceId = priceIdFor(planId, interval)
    if (!priceId) {
      logEvent('error', 'paddle.checkout.missing_price', { planId, interval })
      return NextResponse.json(
        { error: 'That plan is not available for card payment right now.' },
        { status: 503 }
      )
    }

    const checkout = await createCheckoutTransaction({
      planId,
      priceId,
      userId: authUser.id,
      interval,
    })

    logEvent('info', 'paddle.checkout.created', {
      userId: authUser.id,
      planId,
      interval,
      transactionId: checkout.transactionId,
    })

    return NextResponse.json(
      { url: checkout.url, transactionId: checkout.transactionId },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError(
      'paddle.checkout',
      error,
      502,
      'Could not start the card checkout. Please try again.'
    )
  }
}
