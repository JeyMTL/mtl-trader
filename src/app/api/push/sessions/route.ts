import { NextResponse } from 'next/server'
import { hasValidBearer } from '@/lib/auth-guards'
import { apiError } from '@/lib/log'
import { notifySessionStarting } from '@/lib/push-events'

/**
 * "Is anyone's session about to start?"
 *
 * Called by the sync supervisor, which is the only process here that runs often
 * enough to land an arbitrary wall-clock time. Vercel's cron on this plan fires
 * once a day, so the same function is exposed there as a backstop for accounts
 * with no terminal attached — but it cannot be the primary trigger and still be
 * on time.
 *
 * Server-to-server only, with the supervisor's shared secret, because it can
 * notify every user at once. Deduped in `push_events` on the session's start
 * instant, so being called every minute costs nothing extra and sends nothing
 * twice.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: Request) {
  try {
    if (!hasValidBearer(req, process.env.SYNC_SUPERVISOR_TOKEN)) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    const sent = await notifySessionStarting()
    return NextResponse.json({ ok: true, sent })
  } catch (error: unknown) {
    return apiError('push.sessions', error, 500, 'The session reminder sweep failed.')
  }
}
