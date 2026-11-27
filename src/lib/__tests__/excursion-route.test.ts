import { describe, expect, it, vi, beforeEach } from 'vitest'

const flags = vi.hoisted(() => ({ charts: true }))

// The route is off whenever a deployment has no licensed feed; the flag is read
// at call time, so a test can turn it on for the measuring cases.
vi.mock('@/lib/features', () => ({
  get MARKET_CHARTS_ENABLED() {
    return flags.charts
  },
}))

const state = vi.hoisted(() => ({
  trades: [] as Record<string, unknown>[],
  stored: [] as Record<string, unknown>[],
  upserts: [] as Record<string, unknown>[],
  storedTableMissing: false,
}))

vi.mock('@/lib/rate-limit', () => ({
  rateLimit: async () => ({ ok: true, retryAfterMs: 0 }),
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => ({ id: 'u1', email: 'trader@example.com' }),
  getAdminClient: () => ({
    from: (table: string) => {
      if (table === 'trade_excursions') {
        const chain = {
          select: () => chain,
          eq: () => chain,
          in: () =>
            state.storedTableMissing
              ? { data: null, error: { code: '42P01', message: 'missing' } }
              : { data: state.stored, error: null },
          upsert: async (rows: Record<string, unknown>[]) => {
            state.upserts.push(...rows)
            return { error: null }
          },
        }
        return chain
      }
      const chain = {
        select: () => chain,
        eq: () => chain,
        not: () => chain,
        gte: () => chain,
        order: () => chain,
        limit: async () => ({ data: state.trades, error: null }),
      }
      return chain
    },
  }),
}))

vi.mock('@/lib/excursion-feed', () => ({
  fetchExcursionSeries: async () => ({
    symbol: 'EURUSD',
    interval: '1m' as const,
    barMs: 60_000,
    candles: [
      { t: 0, o: 1.1, h: 1.102, l: 1.099, c: 1.1, v: 0 },
      { t: 60_000, o: 1.1, h: 1.106, l: 1.1, c: 1.104, v: 0 },
      { t: 120_000, o: 1.104, h: 1.105, l: 1.101, c: 1.103, v: 0 },
    ],
  }),
}))

const OPEN = new Date(Date.UTC(2026, 0, 5, 10, 0, 0)).toISOString()
const CLOSE = new Date(Date.UTC(2026, 0, 5, 10, 2, 0)).toISOString()

async function call(days = 90): Promise<Response> {
  const { GET } = await import('@/app/api/analytics/excursion/route')
  return GET(new Request(`http://localhost/api/analytics/excursion?days=${days}`))
}

beforeEach(() => {
  flags.charts = true
  state.trades = [
    {
      id: 't1',
      symbol: 'EURUSD',
      type: 'BUY',
      entry_price: 1.1,
      exit_price: 1.104,
      open_time: new Date(0).toISOString(),
      close_time: new Date(180_000).toISOString(),
      strategy: 'Breakout',
      created_at: OPEN,
    },
  ]
  state.stored = []
  state.upserts = []
  state.storedTableMissing = false
})

describe('GET /api/analytics/excursion', () => {
  it('answers 503 without touching a vendor when charting is off', async () => {
    flags.charts = false
    const { GET } = await import('@/app/api/analytics/excursion/route')

    const res = await GET(new Request('http://localhost/api/analytics/excursion?days=90'))

    expect(res.status).toBe(503)
    await expect(res.json()).resolves.toMatchObject({
      error: 'Charting is turned off on this deployment.',
    })
  })

  it('measures a trade, stores the row and returns the summary', async () => {
    const res = await call()
    expect(res.status).toBe(200)
    const body = await res.json()

    expect(body.summary.measured).toBe(1)
    // entry 1.100, best 1.106, exit 1.104 → kept 4 of 6 pips.
    expect(body.summary.captureMedian).toBeCloseTo(0.667, 2)
    expect(body.summary.bySetup[0].key).toBe('Breakout')
    expect(body.coverage.closed).toBe(1)
    expect(body.persisted).toBe(true)
    expect(state.upserts).toHaveLength(1)
    expect(state.upserts[0]).toMatchObject({ trade_id: 't1', user_id: 'u1', bar_interval: '1m' })
  })

  it('still answers when the measurements table has not been migrated', async () => {
    state.storedTableMissing = true
    const res = await call()
    const body = await res.json()

    expect(res.status).toBe(200)
    expect(body.persisted).toBe(false)
    expect(body.summary.measured).toBe(1)
  })

  it('uses stored measurements instead of measuring again', async () => {
    state.stored = [
      { trade_id: 't1', mfe: 10, mae: 2, realised: 5, capture: 0.5, peak_at: null, bars: 9, complete: true },
    ]
    const res = await call()
    const body = await res.json()

    expect(body.summary.captureMedian).toBe(0.5)
    expect(state.upserts).toHaveLength(0)
  })
})
