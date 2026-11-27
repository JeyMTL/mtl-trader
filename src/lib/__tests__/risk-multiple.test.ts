import { describe, expect, it } from 'vitest'
import {
  rDistribution,
  rSummary,
  riskMultipleOf,
  riskMultiples,
  sessionDayHeat,
  utcWeekday,
} from '@/lib/risk-multiple'

describe('riskMultipleOf', () => {
  it('measures a long against the distance to its stop', () => {
    // 1.1000 → 1.1050 is +50 pips, with a 25-pip stop: 2R.
    expect(
      riskMultipleOf({ type: 'BUY', entry_price: 1.1, exit_price: 1.105, stop_loss: 1.0975 })
    ).toBeCloseTo(2)
  })

  it('negates the move for a short', () => {
    // Price fell 50 pips with a 25-pip stop: still +2R.
    expect(
      riskMultipleOf({ type: 'SELL', entry_price: 1.1, exit_price: 1.095, stop_loss: 1.1025 })
    ).toBeCloseTo(2)
  })

  it('returns a negative multiple for a stopped-out trade', () => {
    expect(
      riskMultipleOf({ type: 'BUY', entry_price: 1.1, exit_price: 1.0975, stop_loss: 1.0975 })
    ).toBeCloseTo(-1)
  })

  it('refuses a trade with no risk defined', () => {
    expect(riskMultipleOf({ type: 'BUY', entry_price: 1.1, exit_price: 1.105, stop_loss: null })).toBeNull()
    expect(riskMultipleOf({ type: 'BUY', entry_price: 1.1, exit_price: 1.105, stop_loss: 1.1 })).toBeNull()
    expect(riskMultipleOf({ type: 'BUY', entry_price: 1.1, exit_price: null, stop_loss: 1.09 })).toBeNull()
  })

  it('refuses a stop stored as zero, which is how an older sync wrote "none"', () => {
    // Dividing by the whole entry price gave every stopless trade a fake R of
    // about 0.005 instead of leaving it out of the distribution.
    expect(
      riskMultipleOf({ type: 'BUY', entry_price: 3600, exit_price: 3610, stop_loss: 0 })
    ).toBeNull()
  })
})

describe('riskMultiples', () => {
  it('keeps only the measurable rows', () => {
    const values = riskMultiples([
      { type: 'BUY', entry_price: 100, exit_price: 110, stop_loss: 95 },
      { type: 'BUY', entry_price: 100, exit_price: 110, stop_loss: null },
      { type: 'BUY', entry_price: 100, exit_price: 95, stop_loss: 95 },
    ])
    expect(values).toEqual([2, -1])
  })
})

describe('rDistribution', () => {
  it('puts a value on the right side of each edge', () => {
    const buckets = rDistribution([-3, -2, -1.5, -0.5, 0.5, 1.5, 2.5, 9])
    expect(buckets.map((bucket) => bucket.count)).toEqual([1, 2, 1, 1, 1, 1, 1])
    expect(buckets[0].label).toBe('<-2R')
    expect(buckets[6].label).toBe('+3R')
  })

  it('tints losses and gains apart', () => {
    const buckets = rDistribution([])
    expect(buckets.map((bucket) => bucket.tone)).toEqual([
      'loss',
      'loss',
      'loss',
      'flat',
      'gain',
      'gain',
      'gain',
    ])
  })
})

describe('rSummary', () => {
  it('reports average, median and hit rate', () => {
    const summary = rSummary([-1, 1, 2, 4])
    expect(summary.count).toBe(4)
    expect(summary.average).toBeCloseTo(1.5)
    expect(summary.median).toBeCloseTo(1.5)
    expect(summary.hitRate).toBe(75)
    expect(summary.best).toBe(4)
    expect(summary.worst).toBe(-1)
  })

  it('is all zeros for an empty set', () => {
    expect(rSummary([])).toEqual({
      count: 0,
      average: 0,
      median: 0,
      best: 0,
      worst: 0,
      hitRate: 0,
    })
  })
})

describe('sessionDayHeat', () => {
  it('counts a trade in every window it overlaps', () => {
    // 13:00 UTC sits inside London (07–16) and New York (12–21).
    const cells = sessionDayHeat([{ open_time: '2026-11-24T13:00:00Z', pnl: 100 }])
    expect(cells.map((cell) => cell.session).sort()).toEqual(['london', 'newyork'])
    expect(cells.every((cell) => cell.weekday === 2)).toBe(true)
  })

  it('handles the Sydney window that wraps midnight', () => {
    // 22:00 UTC Tuesday is inside Sydney's 21–06 window.
    const cells = sessionDayHeat([{ open_time: '2026-11-24T22:00:00Z', pnl: 50 }])
    expect(cells).toHaveLength(1)
    expect(cells[0].session).toBe('sydney')
    expect(cells[0].weekday).toBe(2)
    expect(cells[0].pnl).toBe(50)
  })

  it('leaves out trades with no time and weekend trades', () => {
    expect(sessionDayHeat([{ open_time: null, pnl: 10 }])).toEqual([])
    // 2026-11-28 is a Saturday.
    expect(sessionDayHeat([{ open_time: '2026-11-28T10:00:00Z', pnl: 10 }])).toEqual([])
  })

  it('reports Monday as 1 and Sunday as 7', () => {
    expect(utcWeekday('2026-11-23T10:00:00Z')).toBe(1)
    expect(utcWeekday('2026-11-29T10:00:00Z')).toBe(7)
    expect(utcWeekday('not a date')).toBeNull()
  })
})
