import { describe, expect, it } from 'vitest'
import { summarizeJournalTrades } from '@/lib/backtest/journal'

describe('journal comparison summary', () => {
  it('summarises net P&L, win rate and extremes', () => {
    const summary = summarizeJournalTrades([
      { strategy: 'Breakout', pnl: 120, close_time: '2026-10-01T10:00:00Z' },
      { strategy: 'Breakout', pnl: -40, close_time: '2026-10-02T10:00:00Z' },
      { strategy: 'Reversion', pnl: 60, close_time: '2026-10-03T10:00:00Z' },
    ])

    expect(summary.trades).toBe(3)
    expect(summary.netPnl).toBe(140)
    expect(summary.winRate).toBeCloseTo(66.666, 2)
    expect(summary.bestTrade).toBe(120)
    expect(summary.worstTrade).toBe(-40)
  })

  it('groups by strategy, most traded first, with untagged last', () => {
    const summary = summarizeJournalTrades([
      { strategy: 'Breakout', pnl: 10, close_time: '2026-10-01T10:00:00Z' },
      { strategy: 'Breakout', pnl: 5, close_time: '2026-10-01T11:00:00Z' },
      { strategy: null, pnl: -5, close_time: '2026-10-01T12:00:00Z' },
      { strategy: '  ', pnl: -5, close_time: '2026-10-01T13:00:00Z' },
    ])

    expect(summary.strategies[0]).toEqual({ name: 'Breakout', trades: 2, netPnl: 15 })
    expect(summary.strategies.find((entry) => entry.name === 'Untagged')).toEqual({
      name: 'Untagged',
      trades: 2,
      netPnl: -10,
    })
  })

  it('ignores trades that have not closed yet', () => {
    const summary = summarizeJournalTrades([
      { strategy: 'Breakout', pnl: 50, close_time: '2026-10-01T10:00:00Z' },
      { strategy: 'Breakout', pnl: 999, close_time: null },
    ])

    expect(summary.trades).toBe(1)
    expect(summary.netPnl).toBe(50)
  })

  it('handles an empty window without dividing by zero', () => {
    const summary = summarizeJournalTrades([])
    expect(summary).toMatchObject({ trades: 0, netPnl: 0, winRate: 0, strategies: [] })
  })
})
