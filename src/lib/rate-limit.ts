import { getAdminClient } from '@/lib/server-auth'
import { logEvent } from '@/lib/log'

/**
 * Shared fixed-window rate limiter.
 *
 * The counter lives in the `rate_limits` table and is incremented atomically by
 * `check_rate_limit`, so the limit holds across every serverless instance. The
 * previous in-memory implementation gave each lambda its own counter, which
 * meant the AI and payment-request budgets effectively did not exist in
 * production.
 *
 * If the RPC is unavailable (migration not applied yet, or the database is
 * briefly unreachable) we fall back to per-instance buckets rather than failing
 * the request, because locking every customer out of a working app over a
 * database blip is worse than a weaker limit.
 *
 * The fallback is bounded rather than trusted. Per-key buckets are per process,
 * so on their own they let one instance serve unlimited distinct keys — the
 * aggregate ceiling below is what stops an outage from becoming an open door,
 * and the distinct log event is what stops an outage from being invisible.
 */

export interface RateLimitResult {
  ok: boolean
  remaining: number
  retryAfterMs: number
}

interface Bucket {
  count: number
  resetAt: number
}

const fallbackBuckets = new Map<string, Bucket>()
/**
 * Total fallback decisions one process may make per minute while the RPC is down.
 * High enough that a real outage still serves normal traffic, low enough that a
 * single instance cannot become an unmetered proxy for the whole app.
 */
const DEGRADED_CEILING = 3_000
let degradedWindow = -1
let degradedCount = 0

function fallbackRateLimit(key: string, limit: number, windowMs: number, now: number): RateLimitResult {
  // The fallback map is process-global. Without this, a long-lived instance
  // serving many spoofed IPs while the database is unavailable would grow it
  // forever; sweep only when it is large, so the normal path stays O(1).
  if (fallbackBuckets.size > 1_000) sweepExpired(now)

  const bucket = fallbackBuckets.get(key)
  if (!bucket || bucket.resetAt <= now) {
    fallbackBuckets.set(key, { count: 1, resetAt: now + windowMs })
    return { ok: true, remaining: limit - 1, retryAfterMs: 0 }
  }
  if (bucket.count >= limit) {
    return { ok: false, remaining: 0, retryAfterMs: bucket.resetAt - now }
  }
  bucket.count += 1
  return { ok: true, remaining: limit - bucket.count, retryAfterMs: 0 }
}

export async function rateLimit(
  key: string,
  limit: number,
  windowMs: number,
  now: number = Date.now()
): Promise<RateLimitResult> {
  try {
    const { data, error } = await getAdminClient().rpc('check_rate_limit', {
      p_key: key,
      p_limit: limit,
      p_window_ms: windowMs,
    })

    if (error) throw new Error(error.message)

    const row = (Array.isArray(data) ? data[0] : data) as
      | { allowed?: boolean; remaining?: number; retry_after_ms?: number }
      | null

    if (!row || typeof row.allowed !== 'boolean') {
      throw new Error('check_rate_limit returned an unexpected shape')
    }

    return {
      ok: row.allowed,
      remaining: Math.max(0, Number(row.remaining ?? 0)),
      retryAfterMs: Math.max(0, Number(row.retry_after_ms ?? 0)),
    }
  } catch (error: unknown) {
    const window = Math.floor(now / 60_000)
    if (window !== degradedWindow) {
      degradedWindow = window
      degradedCount = 0
    }
    if (degradedCount >= DEGRADED_CEILING) {
      return { ok: false, remaining: 0, retryAfterMs: 60_000 - (now % 60_000) }
    }
    degradedCount += 1
    logEvent('warn', 'rate_limit.degraded', { error, key })
    return fallbackRateLimit(key, limit, windowMs, now)
  }
}

/**
 * Client identity for unauthenticated routes.
 *
 * `x-forwarded-for` is caller-controlled: the edge appends to whatever was sent,
 * so its *first* entry can be a value the client chose, and keying on it lets
 * anyone mint unlimited buckets by rotating a fake IP. Vercel's own header and
 * `x-real-ip` are written at the edge and cannot be spoofed, so they win; only
 * if both are missing is the last forwarded hop used, which is the one the edge
 * added rather than the one the caller invented.
 */
export function clientKey(req: Request, scope: string): string {
  const platform = req.headers.get('x-vercel-forwarded-for')
  const real = req.headers.get('x-real-ip')
  const forwarded = (req.headers.get('x-forwarded-for') ?? '')
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean)

  const ip =
    platform?.split(',')[0]?.trim() || real?.trim() || forwarded[forwarded.length - 1] || 'unknown'
  return `${scope}:${ip}`
}

/** Drops expired fallback buckets so a long-lived process does not grow unbounded. */
export function sweepExpired(now: number = Date.now()): void {
  for (const [key, bucket] of fallbackBuckets) {
    if (bucket.resetAt <= now) fallbackBuckets.delete(key)
  }
}
