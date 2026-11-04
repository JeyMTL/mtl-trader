import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { clientKey, rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'

/**
 * First-party sink for crash and funnel events.
 *
 * Fire-and-forget from the app: it always answers 202 when the row was written
 * and never makes the client wait on a retry. A dropped telemetry event is not
 * worth a broken screen, so validation failures are quiet — the client is not
 * listening and a 400 would only produce noise in the logs.
 *
 * An event that cannot be stored is logged at warn level, which is where a
 * misconfigured deployment shows up before it silently loses a week of data.
 */

export const dynamic = 'force-dynamic'

const EVENT = /^[a-z][a-z0-9_.]{1,63}$/
const SESSION = /^[A-Za-z0-9_-]{6,64}$/
const PLATFORM = /^[a-z]{3,12}$/
const MAX_PROPERTIES_BYTES = 2048

interface Payload {
  event?: unknown
  sessionId?: unknown
  platform?: unknown
  appVersion?: unknown
  properties?: unknown
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (!trimmed || trimmed.length > max) return null
  return trimmed
}

export async function POST(req: Request) {
  try {
    const limit = await rateLimit(clientKey(req, 'telemetry'), 240, 60_000)
    if (!limit.ok) {
      // Silent drop: the client never sees this response anyway, and a 429 body
      // would just be logged as an error on the device.
      return new NextResponse(null, { status: 429 })
    }

    const body = (await req.json().catch(() => null)) as Payload | null
    if (!body || typeof body !== 'object') {
      return new NextResponse(null, { status: 400 })
    }

    const event = text(body.event, 64)
    const sessionId = text(body.sessionId, 64)
    const platform = text(body.platform, 12)
    const appVersion = text(body.appVersion, 32)

    if (!event || !EVENT.test(event)) return new NextResponse(null, { status: 400 })
    if (!sessionId || !SESSION.test(sessionId)) return new NextResponse(null, { status: 400 })
    if (!platform || !PLATFORM.test(platform)) return new NextResponse(null, { status: 400 })

    // Flatten to JSON and measure it, rather than trusting the declared shape:
    // a nested object of arbitrary depth would otherwise slip past a size check
    // on the outer object alone.
    let properties: Record<string, unknown> = {}
    if (body.properties && typeof body.properties === 'object' && !Array.isArray(body.properties)) {
      properties = body.properties as Record<string, unknown>
    }
    const serialised = JSON.stringify(properties)
    if (Buffer.byteLength(serialised, 'utf8') > MAX_PROPERTIES_BYTES) {
      return new NextResponse(null, { status: 413 })
    }

    // Anonymous events are the whole point (app_open happens before sign-in), so
    // a missing or expired token is not an error — it just means no user id.
    let userId: string | null = null
    try {
      const user = await getAuthUser(req)
      userId = user?.id ?? null
    } catch {
      userId = null
    }

    const { error } = await getAdminClient().from('telemetry_events').insert({
      user_id: userId,
      session_id: sessionId,
      platform,
      app_version: appVersion,
      event,
      properties,
    })

    if (error) {
      logEvent('warn', 'telemetry.store', { error, event })
      return new NextResponse(null, { status: 202 })
    }

    return new NextResponse(null, { status: 202 })
  } catch (error: unknown) {
    return apiError('telemetry', error, 500, 'Could not record the event.')
  }
}

export function GET() {
  return apiWarn('telemetry.method', 'Use POST to record an event.', 405)
}
