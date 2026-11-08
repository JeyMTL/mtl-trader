import { beforeEach, describe, expect, it, vi } from 'vitest'

const rpc = vi.hoisted(() => ({ checkRateLimit: vi.fn() }))

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => ({ rpc: rpc.checkRateLimit }),
}))
vi.mock('@/lib/log', () => ({ logEvent: vi.fn() }))

import { rateLimit } from '@/lib/rate-limit'

// Each test gets its own minute: the degraded counter resets when the window
// rolls over, and sharing one would make these order-dependent.
const MINUTE = 60_000
const at = (minute: number) => Date.UTC(2026, 9, 1, 12, minute)

beforeEach(() => {
  rpc.checkRateLimit.mockReset()
})

describe('rateLimit', () => {
  it('uses the shared counter when the RPC answers', async () => {
    rpc.checkRateLimit.mockResolvedValue({
      data: [{ allowed: true, remaining: 4, retry_after_ms: 0 }],
      error: null,
    })

    const result = await rateLimit('ai:u1', 5, 600_000, at(0))
    expect(result).toEqual({ ok: true, remaining: 4, retryAfterMs: 0 })
    expect(rpc.checkRateLimit).toHaveBeenCalledWith('check_rate_limit', {
      p_key: 'ai:u1',
      p_limit: 5,
      p_window_ms: 600_000,
    })
  })

  it('keeps the per-key allowance when the database is down', async () => {
    rpc.checkRateLimit.mockRejectedValue(new Error('connection refused'))

    const now = at(1)
    expect((await rateLimit('pay:u1', 2, MINUTE, now)).ok).toBe(true)
    expect((await rateLimit('pay:u1', 2, MINUTE, now)).ok).toBe(true)

    const denied = await rateLimit('pay:u1', 2, MINUTE, now)
    expect(denied.ok).toBe(false)
    expect(denied.retryAfterMs).toBeGreaterThan(0)

    // A different caller is unaffected: the fallback is still per key.
    expect((await rateLimit('pay:u2', 2, MINUTE, now)).ok).toBe(true)
  })

  it('stops serving new keys once one process has absorbed an outage', async () => {
    rpc.checkRateLimit.mockRejectedValue(new Error('connection refused'))

    const now = at(2)
    // Per-key buckets alone would let one instance serve unlimited distinct keys.
    for (let index = 0; index < 3_000; index += 1) {
      await rateLimit(`flood:${index}`, 5, MINUTE, now)
    }

    const refused = await rateLimit('flood:fresh', 5, MINUTE, now)
    expect(refused.ok).toBe(false)
    expect(refused.remaining).toBe(0)

    // The ceiling is per minute, not permanent: the next window recovers.
    expect((await rateLimit('flood:next', 5, MINUTE, at(3))).ok).toBe(true)
  })
})
