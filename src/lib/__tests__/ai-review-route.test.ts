import { beforeEach, describe, expect, it, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  serverTrades: [] as Row[],
  completeCalls: 0,
  lastMessages: [] as Array<{ role: string; content: unknown }>,
}))

const VALID_REVIEW = JSON.stringify({
  headline: 'Measured review.',
  confidence: 'medium',
  strengths: [{ title: 'Positive expectancy', detail: 'The journal has an edge.', evidence: 'expectancy: 20' }],
  risks: [],
  actions: [],
})

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => ({ id: 'u1', email: 'trader@example.com' }),
  getAdminClient: () => ({
    from: (table: string) => {
      const result =
        table === 'trades'
          ? { data: state.serverTrades, error: null }
          : { data: null, error: null }

      const chain: Record<string, unknown> = {
        select: () => chain,
        eq: () => chain,
        gte: () => chain,
        order: () => chain,
        limit: () => chain,
        insert: () => chain,
        maybeSingle: async () => ({ data: null, error: null }),
        single: async () => ({ data: { id: 'review-1' }, error: null }),
        then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve),
      }
      return chain
    },
  }),
}))

vi.mock('@/lib/rate-limit', () => ({
  rateLimit: async () => ({ ok: true, remaining: 99, retryAfterMs: 0 }),
}))

vi.mock('@/lib/plan-guard', () => ({
  checkFeature: async () => ({ allowed: true, status: 200, message: '', quota: 200, reason: '' }),
  aiReviewsThisMonth: async () => 0,
}))

vi.mock('@/lib/ai/providers', () => ({
  resolveProviderConfig: () => ({ provider: 'test' }),
  createProvider: () => ({
    name: 'test',
    model: 'test-model',
    compact: false,
    async complete(messages: Array<{ role: string; content: unknown }>) {
      state.completeCalls += 1
      state.lastMessages = messages
      return VALID_REVIEW
    },
    async *stream() {
      yield VALID_REVIEW
    },
  }),
}))

function journalTrades(count: number): Row[] {
  return Array.from({ length: count }, (_, index) => ({
    symbol: 'EURUSD',
    pnl: index % 3 === 0 ? -20 : 40,
    open_time: '2026-06-01T08:00:00.000Z',
    close_time: `2026-06-${String((index % 9) + 1).padStart(2, '0')}T09:00:00.000Z`,
    notes: 'stored journal note',
  }))
}

beforeEach(() => {
  state.serverTrades = journalTrades(12)
  state.completeCalls = 0
  state.lastMessages = []
})

describe('AI review route grounding', () => {
  it('ignores fabricated trades in the request body', async () => {
    const { POST } = await import('@/app/api/ai/review/route')

    const fabricated = Array.from({ length: 80 }, (_, index) => ({
      symbol: 'FAKE',
      pnl: 1_000 + index,
      notes: 'invented history',
    }))

    const res = await POST(
      new Request('http://localhost/api/ai/review', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          totalTrades: 80,
          trades: fabricated,
          totalPnl: 999_999,
          question: 'How good am I?',
        }),
      })
    )

    expect(res.status).toBe(200)
    expect(state.completeCalls).toBe(1)

    const body = (await res.json()) as { review: { sampleSize: number } }
    expect(body.review.sampleSize).toBe(12)

    const userPrompt = String(state.lastMessages[1]?.content ?? '')
    expect(userPrompt).toContain('"trades":12')
    expect(userPrompt).not.toContain('FAKE')
    expect(userPrompt).not.toContain('invented history')
  })
})
