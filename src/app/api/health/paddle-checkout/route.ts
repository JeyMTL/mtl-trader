import { NextResponse } from 'next/server'
import { hasValidBearer } from '@/lib/auth-guards'
import { logEvent } from '@/lib/log'
import {
  paddleConfigured,
  paddleEnvironment,
  priceIdFor,
  probePaddleCheckout,
} from '@/lib/paddle'
import type { BillingInterval } from '@/types'

/**
 * Checkout health check.
 *
 * Creates one draft transaction for a price this deployment actually sells and
 * cancels it in the same request. That catches the half-swapped states a
 * presence check cannot: a price id copied from another Paddle account, a live
 * key pointed at the sandbox API, or a key without Transactions write. It never
 * charges and never touches a customer.
 *
 * Gated by `CRON_SECRET` and deliberately not part of `/api/health`: every call
 * leaves a canceled transaction in Paddle's records, so this is for the deploy
 * gate or an operator, not a 15-minute uptime poll.
 *
 * It cannot prove the client-side token belongs to the same seller. Paddle
 * validates that token only when Paddle.js opens a checkout; the failure looks
 * like a successfully created transaction followed by
 * `Transaction checkout creation is blocked for this vendor`. Use a real
 * checkout or Paddle's simulation tool for that half.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/** The first sellable cadence is enough; a mismatch affects every price id. */
const CANDIDATES: Array<{ planId: string; interval: BillingInterval }> = [
  { planId: 'basic', interval: 'month' },
  { planId: 'pro', interval: 'month' },
  { planId: 'basic', interval: 'year' },
  { planId: 'pro', interval: 'year' },
]

export async function GET(req: Request) {
  if (!hasValidBearer(req, process.env.CRON_SECRET)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  if (!paddleConfigured()) {
    return NextResponse.json(
      {
        status: 'not_configured',
        detail: 'PADDLE_API_KEY is not set on this deployment.',
      },
      { status: 503, headers: { 'Cache-Control': 'no-store' } }
    )
  }

  const target = CANDIDATES.map((candidate) => ({
    ...candidate,
    priceId: priceIdFor(candidate.planId, candidate.interval),
  })).find((candidate) => Boolean(candidate.priceId))

  if (!target?.priceId) {
    return NextResponse.json(
      {
        status: 'not_configured',
        detail: 'No Paddle price id is configured for any paid plan.',
      },
      { status: 503, headers: { 'Cache-Control': 'no-store' } }
    )
  }

  const started = Date.now()
  const result = await probePaddleCheckout({
    priceId: target.priceId,
    // Visible in the Paddle dashboard, so a canceled probe is identifiable and
    // is never mistaken for a customer's abandoned checkout.
    reference: `health-${new Date().toISOString()}`,
  })

  if (!result.ok) {
    logEvent('warn', 'paddle.checkout_probe.failed', {
      planId: target.planId,
      interval: target.interval,
      created: result.created,
      discarded: result.discarded,
      detail: result.detail,
    })
  }

  return NextResponse.json(
    {
      status: result.ok ? 'ok' : 'failed',
      environment: paddleEnvironment(),
      plan: target.planId,
      interval: target.interval,
      transactionCreated: result.created,
      discarded: result.discarded,
      transactionId: result.transactionId,
      detail: result.detail,
      durationMs: Date.now() - started,
      checkedAt: new Date().toISOString(),
    },
    {
      status: result.ok ? 200 : 503,
      headers: { 'Cache-Control': 'no-store' },
    }
  )
}
