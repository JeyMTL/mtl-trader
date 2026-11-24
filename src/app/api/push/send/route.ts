import { NextResponse } from 'next/server'
import { hasValidBearer } from '@/lib/auth-guards'
import { apiError, apiWarn } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import { sendPushToUser } from '@/lib/push'

/**
 * Notification sender for the sync supervisor.
 *
 * When a broker connection stops working there is nobody at the keyboard: the
 * row is marked `failed` on the host and the customer finds out the next time
 * they open the app, which for a phone-only user can be days. This is how the
 * host reaches them instead.
 *
 * Server-to-server only, with the same shared secret `/api/sync` accepts. A
 * browser session is deliberately not enough: this can push to any user.
 */

export const runtime = 'nodejs'

export async function POST(req: Request) {
  try {
    if (!hasValidBearer(req, process.env.SYNC_SUPERVISOR_TOKEN)) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const parsed = await readJsonBody<Record<string, unknown>>(req, { maxBytes: 8 * 1024 })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    const userId = typeof body.userId === 'string' ? body.userId.trim() : ''
    if (!userId) return apiWarn('push.send.missing_user', 'A userId is required.', 400)

    const title = typeof body.title === 'string' ? body.title.trim().slice(0, 80) : ''
    const text = typeof body.body === 'string' ? body.body.trim().slice(0, 240) : ''
    if (!title || !text) {
      return apiWarn('push.send.missing_content', 'A title and body are required.', 400)
    }

    const result = await sendPushToUser(userId, { title, body: text })
    return NextResponse.json(result)
  } catch (error: unknown) {
    return apiError('push.send', error, 500, 'Could not send the notification.')
  }
}
