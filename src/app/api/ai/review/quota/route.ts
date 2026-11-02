import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { aiReviewsThisMonth, checkFeature } from '@/lib/plan-guard'
import { apiError } from '@/lib/log'

/**
 * How many AI reviews the caller has left this month.
 *
 * Deliberately answers 200 even when the plan does not include the feature: the
 * card renders this as "not included in your plan", and a 402 here would make a
 * badge fail silently instead of explaining itself. The generation route is
 * still the thing that refuses.
 */

export const dynamic = 'force-dynamic'

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const now = new Date()
    const gate = await checkFeature(user.id, 'ai_review', now)
    // An unentitled account has no allowance to spend, so skip the count and
    // avoid a second query on every page load.
    const used = gate.allowed ? await aiReviewsThisMonth(user.id, now) : 0

    // The allowance resets with the UTC month, matching the count.
    const resetsAt = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)
    ).toISOString()

    return NextResponse.json(
      {
        allowed: gate.allowed,
        reason: gate.reason,
        quota: gate.quota,
        used,
        remaining: Math.max(0, gate.quota - used),
        resetsAt,
      },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('ai.review.quota', error, 500, 'Could not load your review allowance.')
  }
}
