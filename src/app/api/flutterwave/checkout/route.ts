import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import {
  createCheckoutSession,
  ensurePaymentPlan,
  flutterwaveConfigured,
  isPaidPlanId,
} from '@/lib/flutterwave'
import { apiError, apiWarn, logEvent } from '@/lib/log'

/**
 * Starts a Flutterwave card subscription.
 *
 * The remote payment plan is created once and cached, then the first charge
 * subscribes the customer's card. Flutterwave charges it every month after
 * that; each renewal arrives on the webhook and buys another 30-day period.
 */
export async function POST(req: Request) {
  if (!flutterwaveConfigured()) {
    return NextResponse.json(
      { error: 'Card payments are not configured yet.' },
      { status: 503 }
    )
  }

  try {
    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const body = (await req.json().catch(() => ({}))) as {
      planId?: unknown
      userId?: unknown
    }
    const planId = typeof body.planId === 'string' ? body.planId : ''
    if (!isPaidPlanId(planId)) {
      return apiWarn('flutterwave.checkout.invalid_plan', 'Invalid plan')
    }
    if (
      typeof body.userId === 'string' &&
      body.userId &&
      body.userId !== authUser.id
    ) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const appUrl = process.env.NEXT_PUBLIC_APP_URL
    if (!appUrl) {
      logEvent('error', 'flutterwave.checkout.missing_app_url')
      return NextResponse.json(
        { error: 'Payments are not configured yet.' },
        { status: 503 }
      )
    }
    const email = authUser.email
    if (!email) {
      return NextResponse.json({ error: 'Account has no email' }, { status: 400 })
    }

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

    return NextResponse.json({ url: session.url, txRef: session.txRef })
  } catch (error: unknown) {
    return apiError(
      'flutterwave.checkout',
      error,
      502,
      'Could not start the card checkout. Please try again.'
    )
  }
}
