import { describe, it, expect } from 'vitest'
import { computeEdgeStats, sessionOf } from '@/lib/ai/edge-stats'
import type { GroupStat, TradeRecord } from '@/lib/ai/types'

function trade(overrides: Partial<TradeRecord> = {}): TradeRecord {
  return {
    symbol: 'EURUSD',
    pnl: 0,
    open_time: '2026-06-01T08:00:00.000Z',
    close_time: '2026-06-01T09:00:00.000Z',
    ...overrides,
  }
}

function group(groups: GroupStat[], key: string): GroupStat | undefined {
  return groups.find((item) => item.key === key)
}

describe('sessionOf', () => {
  it('maps UTC hours to sessions', () => {
    expect(sessionOf(new Date('2026-06-01T02:00:00Z'))).toBe('Asian')
    expect(sessionOf(new Date('2026-06-01T08:00:00Z'))).toBe('London')
    expect(sessionOf(new Date('2026-06-01T14:00:00Z'))).toBe('New York')
    expect(sessionOf(new Date('2026-06-01T22:00:00Z'))).toBe('Late')
  })
})

describe('computeEdgeStats', () => {
  it('computes core metrics and streaks', () => {
    const stats = computeEdgeStats(
      [
        trade({ pnl: 100, close_time: '2026-06-01T09:00:00Z' }),
        trade({ pnl: -50, close_time: '2026-06-02T09:00:00Z' }),
        trade({ pnl: 30, close_time: '2026-06-03T09:00:00Z' }),
        trade({ pnl: -20, close_time: '2026-06-04T09:00:00Z' }),
      ],
      2
    )
    expect(stats.insufficient).toBe(false)
    expect(stats.trades).toBe(4)
    expect(stats.wins).toBe(2)
    expect(stats.losses).toBe(2)
    expect(stats.pnl).toBe(60)
    expect(stats.grossWins).toBe(130)
    expect(stats.grossLosses).toBe(70)
    expect(stats.profitFactor).toBeCloseTo(130 / 70, 6)
    expect(stats.expectancy).toBe(15)
    expect(stats.maxWinStreak).toBe(1)
    expect(stats.maxLossStreak).toBe(1)
    expect(stats.currentStreak).toBe(-1)
  })

  it('flags an insufficient sample', () => {
    const stats = computeEdgeStats([trade({ pnl: 10 })], 10)
    expect(stats.insufficient).toBe(true)
    expect(stats.minSample).toBe(10)
  })

  it('groups by symbol and sorts by P&L', () => {
    const stats = computeEdgeStats(
      [
        trade({ symbol: 'EURUSD', pnl: 100 }),
        trade({ symbol: 'EURUSD', pnl: -50 }),
        trade({ symbol: 'GBPUSD', pnl: 30 }),
        trade({ symbol: 'GBPUSD', pnl: -20 }),
      ],
      2
    )
    expect(stats.bySymbol[0].key).toBe('EURUSD')
    expect(group(stats.bySymbol, 'EURUSD')?.pnl).toBe(50)
    expect(group(stats.bySymbol, 'GBPUSD')?.winRate).toBe(50)
  })

  it('groups by session and hold time', () => {
    const stats = computeEdgeStats(
      [
        trade({ pnl: 5, open_time: '2026-06-01T08:00:00Z', close_time: '2026-06-01T08:10:00Z' }),
        trade({ pnl: 5, open_time: '2026-06-01T02:00:00Z', close_time: '2026-06-01T02:30:00Z' }),
        trade({ pnl: 5, open_time: '2026-06-01T14:00:00Z', close_time: '2026-06-01T16:00:00Z' }),
        trade({ pnl: 5, open_time: '2026-06-01T20:00:00Z', close_time: '2026-06-02T02:00:00Z' }),
      ],
      2
    )
    expect(group(stats.bySession, 'London')?.trades).toBe(1)
    expect(group(stats.bySession, 'Asian')?.trades).toBe(1)
    expect(group(stats.bySession, 'New York')?.trades).toBe(1)
    expect(group(stats.bySession, 'Late')?.trades).toBe(1)
    expect(group(stats.byHoldTime, '<15m')?.trades).toBe(1)
    expect(group(stats.byHoldTime, '15-60m')?.trades).toBe(1)
    expect(group(stats.byHoldTime, '1-4h')?.trades).toBe(1)
    expect(group(stats.byHoldTime, '>4h')?.trades).toBe(1)
  })

  it('counts notes and ignores trades without timestamps when grouping', () => {
    const stats = computeEdgeStats(
      [
        trade({ pnl: 1, notes: 'good setup' }),
        { pnl: 2 },
        trade({ pnl: 3, notes: '   ' }),
      ],
      2
    )
    expect(stats.noteCount).toBe(1)
    expect(stats.bySession.reduce((sum, g) => sum + g.trades, 0)).toBe(2)
  })

  it('handles an empty journal', () => {
    const stats = computeEdgeStats([], 10)
    expect(stats.trades).toBe(0)
    expect(stats.profitFactor).toBe(0)
    expect(stats.insufficient).toBe(true)
  })
})

describe('holdBucketFromTrades', () => {
  it('is exposed through grouping only for valid ranges', () => {
    // Reaches the same bucket logic via a single trade.
    const stats = computeEdgeStats([trade({ open_time: '2026-06-01T08:00:00Z', close_time: '2026-06-01T08:05:00Z' })], 1)
    expect(group(stats.byHoldTime, '<15m')?.trades).toBe(1)
  })
})
