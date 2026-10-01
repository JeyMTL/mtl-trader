/**
 * Minimal in-memory fixed-window rate limiter.
 *
 * Caveat: on serverless or multi-instance deployments this state is per-instance,
 * so it is an abuse/cost speed bump rather than a hard global limit. Back it with
 * a shared store (e.g. Redis) if a strict limit is ever required.
 */

interface Bucket {
  count: number
  resetAt: number
}

const buckets = new Map<string, Bucket>()

export interface RateLimitResult {
  ok: boolean
  remaining: number
  retryAfterMs: number
}


export function rateLimit(key: string, limit: number, windowMs: number, now: number = Date.now()): RateLimitResult {
  const bucket = buckets.get(key)
  if (!bucket || bucket.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs })
    return { ok: true, remaining: limit - 1, retryAfterMs: 0 }
  }
  if (bucket.count >= limit) {
    return { ok: false, remaining: 0, retryAfterMs: bucket.resetAt - now }
  }
  bucket.count += 1
  return { ok: true, remaining: limit - bucket.count, retryAfterMs: 0 }
}

/** Best-effort client identity for unauthenticated routes. */
export function clientKey(req: Request, scope: string): string {
  const forwarded = req.headers.get('x-forwarded-for') || ''
  const ip = forwarded.split(',')[0].trim() || req.headers.get('x-real-ip') || 'unknown'
  return `${scope}:${ip}`
}

/** Drop expired buckets so a long-lived process does not grow unbounded. */
export function sweepExpired(now: number = Date.now()): void {
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key)
  }
}
