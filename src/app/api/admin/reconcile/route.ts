import { NextResponse } from 'next/server'
import { requireAdmin } from '@/lib/server-auth'
import { hasValidBearer } from '@/lib/auth-guards'
import { applyPaidOrder, expireLapsedSubscriptions, fetchRecentCompletedCaptures } from '@/lib/payments'
import { syncStoredGoogleSubscriptions } from '@/lib/google-billing'
import { googlePlayConfigured } from '@/lib/google-play'
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

    // The expiry sweep and the rate-limit sweep are independent of PayPal: a
    // deployment that only sells card or bank must still let paid periods lapse.
    // PayPal event recovery is skipped, not fatal, when it is not configured.
    const paypalConfigured = Boolean(process.env.PAYPAL_WEBHOOK_ID)
    const { orders, scanned } = paypalConfigured
      ? await fetchRecentCompletedCaptures()
      : { orders: [], scanned: 0 }
    const summary = {
      paypal: paypalConfigured ? 'checked' : 'not_configured',
      scannedEvents: scanned,
      captureCandidates: orders.length,
      applied: 0,
      duplicates: 0,
      skipped: 0,
      failed: 0,
      expired,
      ratesSwept,
      google: 'not_configured' as
        | 'not_configured'
        | { checked: number; applied: number; failed: number },
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

    // Play subscriptions are re-checked here because Google cannot push to us
    // without a Pub/Sub topic: a renewal is only learned about by asking. It runs
    // before the response so a failed call is visible in the summary.
    let google: { checked: number; applied: number; failed: number } | 'not_configured' = 'not_configured'
    if (googlePlayConfigured()) {
      try {
        google = await syncStoredGoogleSubscriptions()
      } catch (error: unknown) {
        logEvent('error', 'reconcile.google', { error })
        google = { checked: 0, applied: 0, failed: 1 }
      }
    }

    summary.google = google

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
