import { NextResponse } from 'next/server'
import { hasValidBearer } from '@/lib/auth-guards'
import { apiError } from '@/lib/log'
import { notifyTrialEnding, sweepPropBreaches } from '@/lib/push-events'

/**
 * The scheduled half of the notification work.
 *
 * Two jobs, both of which are states rather than events, so they need a sweep
 * instead of a hook:
 *
 *  - **Trial ending.** The trial is inside its last day for a whole day; this
 *    tells each trader once, keyed on the trial's end date.
 *  - **Prop breaches.** The real check runs from `/api/sync` the moment a trade
 *    lands, because a trader with a terminal attached has no app open. This
 *    sweep exists for the trades entered by hand, and for accounts whose broker
 *    stopped syncing.
 *
 * Safe to run repeatedly: `push_events` makes every send once-only. Authenticated
 * with `CRON_SECRET`, the same scheme `/api/admin/reconcile` accepts.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: Request) {
  try {
    if (!hasValidBearer(req, process.env.CRON_SECRET)) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const trials = await notifyTrialEnding()
    const breaches = await sweepPropBreaches()

    return NextResponse.json({ ok: true, trials, breaches })
  } catch (error: unknown) {
    return apiError('cron.notify', error, 500, 'The notification sweep failed.')
  }
}
