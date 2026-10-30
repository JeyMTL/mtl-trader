import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import {
  FLW_CURRENCY,
  flutterwaveConfigured,
  recordSubscription,
  resolveChargeTarget,
  verifyTransaction,
} from '@/lib/flutterwave'
import { applyPaidOrder } from '@/lib/payments'
import { apiError, apiWarn, logEvent } from '@/lib/log'

/**
 * Applies the payment returned by Flutterwave's redirect. The webhook remains
 * the durable path, so a closed tab loses nothing: both use the same charge id
 * in `apply_paid_order`, and a replay is a no-op.
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
      transactionId?: unknown
    }
    const transactionId =
      typeof body.transactionId === 'string' ? body.transactionId.trim() : ''
    if (!transactionId) {
      return apiWarn('flutterwave.verify.missing_id', 'Missing transactionId')
    }

    const charge = await verifyTransaction(transactionId)
    if (charge.status !== 'successful') {
      return NextResponse.json(
        { error: 'That payment was not successful.' },
        { status: 400 }
      )
    }
    if (charge.currency !== FLW_CURRENCY) {
      logEvent('warn', 'flutterwave.verify.currency_mismatch', {
        transactionId: charge.id,
        currency: charge.currency,
      })
      return NextResponse.json(
        { error: 'That payment is not in the expected currency.' },
        { status: 400 }
      )
    }

    const target = await resolveChargeTarget(charge)
    if (!target) {
      return NextResponse.json(
        { error: 'We could not match that payment to your account.' },
        { status: 404 }
      )
    }
    if (target.userId !== authUser.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const result = await applyPaidOrder({
      userId: target.userId,
      planId: target.planId,
      amount: charge.amount,
      provider: 'flutterwave',
      providerEventId: `flutterwave:charge:${charge.id}`,
    })

    if (result.reason === 'amount_mismatch') {
      logEvent('warn', 'flutterwave.verify.amount_mismatch', {
        transactionId: charge.id,
        planId: target.planId,
        amount: charge.amount,
      })
      return NextResponse.json(
        { error: 'The amount does not match the plan.' },
        { status: 400 }
      )
    }
    if (result.reason === 'unknown_user' || result.reason === 'invalid_plan') {
      return NextResponse.json(
        { error: 'That payment could not be applied to an account.' },
        { status: 400 }
      )
    }

    await recordSubscription(target)

    return NextResponse.json({
      success: true,
      planId: target.planId,
      applied: result.applied,
      reason: result.reason,
    })
  } catch (error: unknown) {
    return apiError(
      'flutterwave.verify',
      error,
      500,
      'Could not confirm the payment. If you were charged, it will be applied automatically.'
    )
  }
}
