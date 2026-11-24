import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { apiError, apiWarn } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

/**
 * Registers a device for server-sent notifications.
 *
 * The app calls this on every launch and on every FCM token refresh. `token` is
 * the primary key, so a repeat is an upsert that only touches `updated_at`; the
 * same phone re-registering on each launch costs one row write and nothing else.
 *
 * The token is never returned and never logged: it is a capability to wake the
 * device, and a support screenshot is not the place for it.
 */

export const runtime = 'nodejs'

const PLATFORMS = new Set(['android', 'ios'])

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const parsed = await readJsonBody<Record<string, unknown>>(req, { maxBytes: 4 * 1024 })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    const token = typeof body.token === 'string' ? body.token.trim() : ''
    // An FCM registration token is long and opaque. Anything short is a client
    // bug or a probe, not a device.
    if (token.length < 20 || token.length > 4096) {
      return apiWarn('push.register.invalid_token', 'Invalid device token.', 400)
    }

    const platform = typeof body.platform === 'string' ? body.platform.toLowerCase() : ''
    if (!PLATFORMS.has(platform)) {
      return apiWarn('push.register.invalid_platform', 'Unknown platform.', 400)
    }

    const { error } = await getAdminClient()
      .from('push_tokens')
      .upsert(
        {
          token,
          user_id: user.id,
          platform,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'token' }
      )

    if (error) return apiError('push.register', error, 500, 'Could not register this device.')

    return NextResponse.json({ ok: true })
  } catch (error: unknown) {
    return apiError('push.register', error, 500, 'Could not register this device.')
  }
}
