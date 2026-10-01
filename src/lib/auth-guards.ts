import { timingSafeEqual } from 'node:crypto'

/**
 * Constant-time check that a request carries `Authorization: Bearer <secret>`.
 * Used by cron-triggered routes, which are called by Vercel with a shared secret.
 * Returns false when no secret is configured, so an unset env var fails closed.
 */
export function hasValidBearer(req: Request, secret: string | undefined | null): boolean {
  if (!secret) return false
  const header = req.headers.get('authorization') || ''
  const expected = `Bearer ${secret}`
  const provided = Buffer.from(header)
  const wanted = Buffer.from(expected)
  if (provided.length !== wanted.length) return false
  return timingSafeEqual(provided, wanted)
}
