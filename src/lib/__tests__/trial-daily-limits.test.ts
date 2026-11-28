import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * The trial samples the two per-call Pro tools: one AI review and one backtest
 * a day. These tests pin the refusal at the route, because a limit that only
 * lives in the copy is not a limit — the second request has to be turned away
 * before it costs a model call or a simulation.
 */

const state = vi.hoisted(() => ({
  reviewsToday: 0,
  backtestsToday: 0,
  completeCalls: 0,
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => ({ id: 'u1', email: 'trader@example.com' }),
  getAdminClient: () => ({
    from: () => {
      const chain: Record<string, unknown> = {
        select: () => chain,
        eq: () => chain,
        gte: () => chain,
        order: () => chain,
        limit: () => chain,
        insert: () => chain,
        maybeSingle: async () => ({ data: null, error: null }),
        single: async () => ({ data: { id: 'row-1' }, error: null }),
        then: (resolve: (value: unknown) => unknown) =>
          Promise.resolve({ data: null, error: null }).then(resolve),
      }
      return chain
    },
  }),
}))

vi.mock('@/lib/rate-limit', () => ({
  rateLimit: async () => ({ ok: true, remaining: 99, retryAfterMs: 0 }),
}))

vi.mock('@/lib/plan-guard', () => ({
  checkFeature: async () => ({
    allowed: true,
    status: 200,
    message: '',
    reason: 'trial',
    account: null,
    quota: 3,
    dailyQuota: 1,
  }),
  aiReviewsThisMonth: async () => 0,
  aiReviewsToday: async () => state.reviewsToday,
  backtestsToday: async () => state.backtestsToday,
  secondsUntilUtcDayEnd: () => 3600,
}))

vi.mock('@/lib/ai/providers', () => ({
  resolveProviderConfig: () => ({ provider: 'test' }),
  createProvider: () => ({
    name: 'test',
    model: 'test-model',
    async complete() {
      state.completeCalls += 1
      return '{}'
    },
    async *stream() {
      state.completeCalls += 1
      yield '{}'
    },
  }),
}))

beforeEach(() => {
  state.reviewsToday = 0
  state.backtestsToday = 0
  state.completeCalls = 0
})

describe('trial daily limits', () => {
  it('refuses a second AI review the same day without calling the model', async () => {
    state.reviewsToday = 1
    const { POST } = await import('@/app/api/ai/review/route')

    const res = await POST(
      new Request('http://localhost/api/ai/review', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ totalTrades: 12 }),
      })
    )

    expect(res.status).toBe(402)
    const body = (await res.json()) as { code: string; error: string }
    expect(body.code).toBe('daily_limit')
    expect(body.error).toContain('a day')
    expect(state.completeCalls).toBe(0)
  })

  it('refuses a second backtest the same day', async () => {
    state.backtestsToday = 1
    const { POST } = await import('@/app/api/backtest/route')

    const res = await POST(
      new Request('http://localhost/api/backtest', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ csv: 'x', strategyId: 'ict' }),
      })
    )

    expect(res.status).toBe(429)
    expect(res.headers.get('Retry-After')).toBe('3600')
    const body = (await res.json()) as { code: string; error: string }
    expect(body.code).toBe('daily_limit')
    expect(body.error).toContain('a day')
  })
})
