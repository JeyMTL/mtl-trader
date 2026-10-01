import { describe, it, expect } from 'vitest'
import { summarizeTrades, renderSummaryEmail, tradeTime, formatMoney, type TradeLike } from '@/lib/summaries'

const SINCE = new Date('2026-06-01T00:00:00.000Z')
const UNTIL = new Date('2026-06-02T00:00:00.000Z')

describe('tradeTime', () => {
  it('prefers close, then open, then created', () => {
    expect(tradeTime({ pnl: 0, close_time: 'c', open_time: 'o', created_at: 'k' })).toBe('c')
    expect(tradeTime({ pnl: 0, close_time: null, open_time: 'o', created_at: 'k' })).toBe('o')
    expect(tradeTime({ pnl: 0, close_time: null, open_time: null, created_at: 'k' })).toBe('k')
    expect(tradeTime({ pnl: 0 })).toBeNull()
  })
})

describe('summarizeTrades', () => {
  const trades: TradeLike[] = [
    { pnl: 100, close_time: '2026-06-01T10:00:00.000Z' },
    { pnl: -40, close_time: '2026-06-01T12:00:00.000Z' },
    { pnl: 10, close_time: '2026-06-01T23:59:59.000Z' },
    { pnl: 999, close_time: '2026-06-02T00:00:00.000Z' }, // outside (until is exclusive)
    { pnl: 500, close_time: '2026-05-31T23:59:59.000Z' }, // outside (before since)
    { pnl: 5, close_time: 'not a date' }, // ignored
    { pnl: 7 }, // no timestamp, ignored
  ]

  it('counts only trades inside the half-open window', () => {
    const summary = summarizeTrades(trades, SINCE, UNTIL)
    expect(summary.trades).toBe(3)
    expect(summary.wins).toBe(2)
    expect(summary.losses).toBe(1)
    expect(summary.pnl).toBe(70)
    expect(summary.winRate).toBeCloseTo((2 / 3) * 100, 6)
    expect(summary.best).toBe(100)
    expect(summary.worst).toBe(-40)
  })

  it('returns zeroes for an empty window', () => {
    const summary = summarizeTrades(trades, new Date('2026-01-01'), new Date('2026-01-02'))
    expect(summary).toEqual({ trades: 0, wins: 0, losses: 0, pnl: 0, winRate: 0, best: 0, worst: 0 })
  })

  it('treats a zero-P&L trade as neither a win nor a loss', () => {
    const summary = summarizeTrades([{ pnl: 0, close_time: '2026-06-01T10:00:00.000Z' }], SINCE, UNTIL)
    expect(summary.trades).toBe(1)
    expect(summary.wins).toBe(0)
    expect(summary.losses).toBe(0)
    expect(summary.winRate).toBe(0)
  })

  it('coerces string P&L values', () => {
    const summary = summarizeTrades([{ pnl: '12.5', close_time: '2026-06-01T10:00:00.000Z' }], SINCE, UNTIL)
    expect(summary.pnl).toBe(12.5)
  })
})

describe('formatMoney', () => {
  it('formats currency', () => {
    expect(formatMoney(1234.5)).toBe('$1,234.50')
    expect(formatMoney(-70)).toBe('-$70.00')
  })
})

describe('renderSummaryEmail', () => {
  const summary = summarizeTrades(
    [
      { pnl: 100, close_time: '2026-06-01T10:00:00.000Z' },
      { pnl: -40, close_time: '2026-06-01T12:00:00.000Z' },
    ],
    SINCE,
    UNTIL
  )

  it('builds a subject with the trade count and signed P&L', () => {
    const { subject } = renderSummaryEmail({ title: 'Your weekly report', summary })
    expect(subject).toBe('Your weekly report: 2 trades, +$60.00')
  })

  it('uses the singular for one trade', () => {
    const single = summarizeTrades([{ pnl: 5, close_time: '2026-06-01T10:00:00.000Z' }], SINCE, UNTIL)
    const { subject } = renderSummaryEmail({ title: 'Your daily summary', summary: single })
    expect(subject).toBe('Your daily summary: 1 trade, +$5.00')
  })

  it('escapes the name and includes the figures', () => {
    const { html } = renderSummaryEmail({ title: 'Your weekly report', summary, name: '<script>x</script>' })
    expect(html).not.toContain('<script>x</script>')
    expect(html).toContain('&lt;script&gt;')
    expect(html).toContain('+$60.00')
    expect(html).toContain('50.0%')
  })
})
