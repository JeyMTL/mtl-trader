import { describe, expect, it } from 'vitest'
import { buildCoachInsights } from '@/lib/ai/coach'
import { computeEdgeStats } from '@/lib/ai/edge-stats'
import type { TradeRecord } from '@/lib/ai/types'

function trade(overrides: Partial<TradeRecord>): TradeRecord {
  return {
    symbol: 'GBPUSD',
    pnl: 50,
    open_time: '2026-06-01T09:00:00.000Z',
    close_time: '2026-06-01T10:00:00.000Z',
    ...overrides,
  }
}

function series(count: number, overrides: Partial<TradeRecord>): TradeRecord[] {
  return Array.from({ length: count }, () => trade(overrides))
}

describe('buildCoachInsights', () => {
  it('reports a symbol in a session that loses far more than the baseline', () => {
    const trades = [
      ...series(12, { symbol: 'GBPUSD', pnl: 50 }),
      ...series(8, { symbol: 'EURUSD', pnl: -40, open_time: '2026-06-01T22:00:00.000Z' }),
    ]
    const stats = computeEdgeStats(trades)
    const insights = buildCoachInsights(trades, stats)

    const risk = insights.find((insight) => insight.label === 'EURUSD · Late')
    expect(risk).toBeDefined()
    expect(risk?.tone).toBe('risk')
    expect(risk?.trades).toBe(8)
    expect(risk?.metric).toBe('expectancy')
    // The sentence carries the measured comparison rather than a vague claim.
    expect(risk?.summary).toContain('worse')
    expect(risk?.deltaPct).toBeLessThan(-20)
  })

  it('ignores a bucket with too few trades, however dramatic it looks', () => {
    const trades = [
      ...series(12, { symbol: 'GBPUSD', pnl: 50 }),
      ...series(3, { symbol: 'USDJPY', pnl: -400, open_time: '2026-06-01T22:00:00.000Z' }),
    ]
    const insights = buildCoachInsights(trades, computeEdgeStats(trades))
    expect(insights.some((insight) => insight.label.includes('USDJPY'))).toBe(false)
  })

  it('does not dress a small difference up as a pattern', () => {
    const trades = [
      ...series(12, { symbol: 'GBPUSD', pnl: 50 }),
      ...series(8, { symbol: 'EURUSD', pnl: 42, open_time: '2026-06-01T22:00:00.000Z' }),
    ]
    const insights = buildCoachInsights(trades, computeEdgeStats(trades))
    expect(insights.some((insight) => insight.label.includes('EURUSD'))).toBe(false)
  })

  it('falls back to win rate when the baseline expectancy is near zero', () => {
    const trades = [
      ...series(10, { symbol: 'GBPUSD', pnl: 20 }),
      ...series(10, { symbol: 'EURUSD', pnl: -20, open_time: '2026-06-01T22:00:00.000Z' }),
    ]
    const stats = computeEdgeStats(trades)
    const insights = buildCoachInsights(trades, stats)

    expect(stats.expectancy).toBe(0)
    const risk = insights.find((insight) => insight.tone === 'risk')
    expect(risk?.metric).toBe('winRate')
    expect(risk?.summary).toContain('win rate')
  })

  it('returns nothing for a journal that cannot support a comparison', () => {
    const trades = series(4, { pnl: 10 })
    expect(buildCoachInsights(trades, computeEdgeStats(trades))).toEqual([])
  })
})
