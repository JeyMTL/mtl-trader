import { beforeEach, describe, expect, it, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  serverTrades: [] as Row[],
  reviews: [] as Row[],
  completeCalls: 0,
  pendingInsert: null as Row | null,
  queryHash: '',
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
        eq: (column: string, value: unknown) => {
          if (column === 'summary_hash') state.queryHash = String(value)
          return chain
        },
        gte: () => chain,
        order: () => chain,
        limit: () => chain,
        insert: (row: Row) => {
          state.pendingInsert = row
          return chain
        },
        maybeSingle: async () => {
          if (table !== 'ai_reviews') return { data: null, error: null }
          const found = state.reviews.find((row) => row.summary_hash === state.queryHash)
          return { data: found ?? null, error: null }
        },
        single: async () => {
          if (table === 'ai_reviews' && state.pendingInsert) {
            const row = {
              ...state.pendingInsert,
              id: `review-${state.reviews.length + 1}`,
              created_at: new Date().toISOString(),
            }
            state.reviews.push(row)
            state.pendingInsert = null
            return { data: { id: row.id }, error: null }
          }
          return { data: { id: 'review-1' }, error: null }
        },
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
    async complete() {
      state.completeCalls += 1
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

async function review(chartImage?: string) {
  const { POST } = await import('@/app/api/ai/review/route')
  const res = await POST(
    new Request('http://localhost/api/ai/review', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ trades: [], ...(chartImage ? { chartImage } : {}) }),
    })
  )
  expect(res.status).toBe(200)
  return (await res.json()) as { meta: { cached: boolean } }
}

beforeEach(() => {
  state.serverTrades = journalTrades(12)
  state.reviews = []
  state.completeCalls = 0
  state.pendingInsert = null
  state.queryHash = ''
})

describe('AI review cache', () => {
  it('reuses the review for identical journal and image input', async () => {
    const image = 'data:image/png;base64,AAAA'

    expect((await review(image)).meta.cached).toBe(false)
    expect((await review(image)).meta.cached).toBe(true)
    expect(state.completeCalls).toBe(1)
  })

  it('does not reuse the review for a different chart image', async () => {
    expect((await review('data:image/png;base64,AAAA')).meta.cached).toBe(false)
    expect((await review('data:image/png;base64,BBBB')).meta.cached).toBe(false)
    expect(state.completeCalls).toBe(2)
  })
})
