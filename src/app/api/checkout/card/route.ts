import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { loadAccount } from '@/lib/plan-guard'
import { isDuplicatePurchase } from '@/lib/subscription'
import { PLANS } from '@/lib/plans'
import { createCheckoutTransaction, paddleConfigured, priceIdFor, sellablePlanIds } from '@/lib/paddle'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { rateLimit } from '@/lib/rate-limit'
import { readJsonBody } from '@/lib/request'
import type { BillingInterval } from '@/types'

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

/**
 * The GET is public and reveals only plan ids: a deployment without a yearly
 * price must hide the yearly switch rather than offer a checkout that fails
 * after the customer has decided to pay.
 */
export async function GET() {
  const plans = sellablePlanIds(PAID_PLANS, 'month')
  return NextResponse.json(
    {
      enabled: plans.length > 0,
      provider: plans.length > 0 ? 'paddle' : null,
      plans,
      // Selling a year is a separate catalogue entry, so one cadence can exist
      // without the other.
      annual: sellablePlanIds(PAID_PLANS, 'year'),
    },
    { headers: { 'Cache-Control': 'no-store' } }
  )
}

export async function POST(req: Request) {
  try {
    const authUser = await getAuthUser(req)
    if (!authUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    // One shared budget with the PayPal route: a checkout attempt costs a live
    // processor call whichever provider it targets, and an abandoned loop should
    // not be able to create an unlimited trail of transactions.
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

    const parsed = await readJsonBody<{
      planId?: unknown
      userId?: unknown
      interval?: unknown
    }>(req, { maxBytes: 8 * 1024 })
    if (!parsed.ok) return parsed.response
    const body = parsed.value
    const planId = typeof body.planId === 'string' ? body.planId : ''
    // Anything unrecognised is monthly rather than refused: the price id and the
    // amount the webhook expects are what actually gate the cadence.
    const interval: BillingInterval = body.interval === 'year' ? 'year' : 'month'
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

    // Tapping the plan you already pay for should not charge you a second time
    // for days you own. Yearly is never blocked: that is how a monthly customer
    // upgrades, and `apply_annual_order` stacks the year onto what is left.
    const account = await loadAccount(authUser.id)
    if (account && isDuplicatePurchase(account, planId, interval)) {
      const planName = PLANS.find((plan) => plan.id === planId)?.name ?? planId
      return NextResponse.json(
        {
          error: `You are already on ${planName} monthly. Switch to annual to get two months free.`,
        },
        { status: 409 }
      )
    }

    const priceId = priceIdFor(planId, interval)
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
      interval,
    })

    logEvent('info', 'checkout.card.created', {
      userId: authUser.id,
      planId,
      interval,
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
