import { NextResponse } from 'next/server'
import { requireAdmin } from '@/lib/server-auth'
import { hasValidBearer } from '@/lib/auth-guards'
import { applyPaidOrder, expireLapsedSubscriptions, fetchRecentCompletedCaptures } from '@/lib/payments'
import { getAdminClient } from '@/lib/server-auth'
import { apiError, logEvent } from '@/lib/log'

/**
 * Payment reconciliation and the daily lifecycle sweep.
 *
 * Recovers payments that were captured at PayPal but never applied to an account
 * (for example because the user closed the success page and the webhook delivery
 * failed). Reads recent completed captures from PayPal and replays them through
 * `applyPaidOrder`, which is idempotent and refuses to downgrade an account.
 *
 * It also expires subscriptions whose paid period has ended, which is what stops
 * a one-time payment from behaving like a lifetime grant, and sweeps stale rate
 * limit buckets.
 *
 * Safe to run repeatedly. Trigger it either:
 *   - as an admin:  POST with a user bearer token (is_admin required), or
 *   - as a cron:    GET  with `Authorization: Bearer $CRON_SECRET`.
 */

async function runReconciliation() {
  if (!process.env.PAYPAL_WEBHOOK_ID) {
    return NextResponse.json(
      { error: 'Reconciliation requires PAYPAL_WEBHOOK_ID (PayPal stores webhook events per webhook)' },
      { status: 503 }
    )
  }

  try {
    let expired = 0
    let ratesSwept = 0

    try {
      expired = await expireLapsedSubscriptions()
    } catch (error: unknown) {
      logEvent('error', 'reconcile.expire', { error })
    }

    try {
      const { data } = await getAdminClient().rpc('sweep_rate_limits')
      ratesSwept = typeof data === 'number' ? data : Number(data ?? 0)
    } catch (error: unknown) {
      logEvent('error', 'reconcile.rate_sweep', { error })
    }

    const { orders, scanned } = await fetchRecentCompletedCaptures()
    const summary = {
      scannedEvents: scanned,
      captureCandidates: orders.length,
      applied: 0,
      duplicates: 0,
      skipped: 0,
      failed: 0,
      expired,
      ratesSwept,
    }

    for (const order of orders) {
      try {
        const result = await applyPaidOrder(order)
        if (result.applied) summary.applied++
        else if (result.reason === 'duplicate') summary.duplicates++
        else summary.skipped++
      } catch (error: unknown) {
        summary.failed++
        logEvent('error', 'reconcile.apply', { error, userId: order.userId, planId: order.planId })
      }
    }

    logEvent('info', 'reconcile.complete', summary)
    return NextResponse.json({ success: true, ...summary })
  } catch (error: unknown) {
    return apiError('reconcile.run', error, 502, 'Reconciliation failed')
  }
}

export async function GET(req: Request) {
  if (!hasValidBearer(req, process.env.CRON_SECRET)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  return runReconciliation()
}

export async function POST(req: Request) {
  const { user, error } = await requireAdmin(req)
  if (!user) {
    return NextResponse.json({ error }, { status: error === 'Unauthorized' ? 401 : 403 })
  }
  return runReconciliation()
}
