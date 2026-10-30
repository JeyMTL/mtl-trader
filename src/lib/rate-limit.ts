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
 * the request. That fallback is a speed bump, not a guarantee — the same caveat
 * the old implementation had.
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

function fallbackRateLimit(key: string, limit: number, windowMs: number, now: number): RateLimitResult {
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
    logEvent('warn', 'rate_limit.fallback', { error, key })
    return fallbackRateLimit(key, limit, windowMs, now)
  }
}

/** Best-effort client identity for unauthenticated routes. */
export function clientKey(req: Request, scope: string): string {
  const forwarded = req.headers.get('x-forwarded-for') || ''
  const ip = forwarded.split(',')[0].trim() || req.headers.get('x-real-ip') || 'unknown'
  return `${scope}:${ip}`
}

/** Drops expired fallback buckets so a long-lived process does not grow unbounded. */
export function sweepExpired(now: number = Date.now()): void {
  for (const [key, bucket] of fallbackBuckets) {
    if (bucket.resetAt <= now) fallbackBuckets.delete(key)
  }
}
