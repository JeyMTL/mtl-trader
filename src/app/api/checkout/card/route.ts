import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'
import { createCheckoutTransaction, paddleConfigured, priceIdFor } from '@/lib/paddle'
import {
  createCheckoutSession,
  ensurePaymentPlan,
  flutterwaveConfigured,
  isPaidPlanId,
} from '@/lib/flutterwave'
import { apiError, apiWarn, logEvent } from '@/lib/log'

/**
 * Card checkout, whichever processor this deployment actually has.
 *
 *   GET  -> which provider is live, and which plans it can sell
 *   POST -> create the checkout and hand back its hosted URL
 *
 * The phone app used to call `/api/flutterwave/checkout` directly, so a
 * deployment running Paddle answered 503 to every customer who tapped
 * "Subscribe with card" in the app — the one surface most of them use. The
 * processor is a deployment decision, not a client one, so the client asks here
 * and never needs to know which one is configured.
 *
 * Paddle is preferred when both are configured: it is the merchant of record, so
 * it handles sales tax and receipts, and it renews on its own.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const PAID_PLANS = PLANS.filter((plan) => plan.price > 0).map((plan) => plan.id)

type CardProvider = 'paddle' | 'flutterwave'

interface CardRouting {
  provider: CardProvider | null
  plans: string[]
}

/** One decision, used by both the GET and the POST, so they cannot disagree. */
function routeCard(): CardRouting {
  if (paddleConfigured()) {
    const plans = PAID_PLANS.filter((planId) => Boolean(priceIdFor(planId, 'month')))
    if (plans.length > 0) return { provider: 'paddle', plans }
  }
  if (flutterwaveConfigured()) {
    return { provider: 'flutterwave', plans: PAID_PLANS.filter(isPaidPlanId) }
  }
  return { provider: null, plans: [] }
}

export async function GET() {
  const { provider, plans } = routeCard()
  return NextResponse.json(
    { enabled: provider !== null, provider, plans },
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

    const { provider } = routeCard()
    if (!provider) {
      return NextResponse.json(
        { error: 'Card payments are not configured yet.' },
        { status: 503 }
      )
    }

    if (provider === 'paddle') {
      const priceId = priceIdFor(planId, 'month')
      if (!priceId) {
        logEvent('error', 'checkout.card.missing_price', { planId, provider })
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
        provider,
        transactionId: checkout.transactionId,
      })
      return NextResponse.json(
        { url: checkout.url, provider, transactionId: checkout.transactionId },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    // Flutterwave builds the charge from a plan in its own account, and needs a
    // URL to come back to.
    const appUrl = process.env.NEXT_PUBLIC_APP_URL
    if (!appUrl) {
      logEvent('error', 'checkout.card.missing_app_url', { provider })
      return NextResponse.json({ error: 'Payments are not configured yet.' }, { status: 503 })
    }
    const email = authUser.email
    if (!email) return NextResponse.json({ error: 'Account has no email' }, { status: 400 })

    const remotePlanId = await ensurePaymentPlan(planId)
    const session = await createCheckoutSession({
      userId: authUser.id,
      email,
      name:
        typeof authUser.user_metadata?.full_name === 'string'
          ? authUser.user_metadata.full_name
          : null,
      planId,
      remotePlanId,
      appUrl,
    })
    logEvent('info', 'checkout.card.created', {
      userId: authUser.id,
      planId,
      provider,
      txRef: session.txRef,
    })
    return NextResponse.json(
      { url: session.url, provider, txRef: session.txRef },
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
