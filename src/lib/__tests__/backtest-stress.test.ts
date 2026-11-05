import { describe, expect, it } from 'vitest'
import { MIN_TRADES, stressTest } from '@/lib/backtest/stress'
import type { Trade } from '@/lib/backtest/types'

const start = Date.UTC(2026, 9, 1)

function trade(pnl: number): Trade {
  return {
    side: 'long',
    entryTime: start,
    exitTime: start + 60_000,
    entryPrice: 100,
    exitPrice: 100,
    stopPrice: 99,
    takeProfitPrice: 102,
    lots: 1,
    grossPnl: pnl,
    costs: 0,
    pnl,
    riskAmount: 100,
    rMultiple: pnl / 100,
    barsHeld: 1,
    exitReason: 'target',
  }
}

function trades(pnls: number[]): Trade[] {
  return pnls.map(trade)
}

describe('stress test', () => {
  it('is deterministic for the same trades', () => {
    const a = stressTest(trades([100, -50, 80, -20, 60, -40]), 10_000, 5)!
    const b = stressTest(trades([100, -50, 80, -20, 60, -40]), 10_000, 5)!

    expect(a).toEqual(b)
    expect(a.seed).toBe(b.seed)
  })

  it('reports certainty when every trade wins', () => {
    const result = stressTest(trades([50, 40, 30, 20, 10]), 10_000, 0)!

    expect(result.probabilityOfProfit).toBe(1)
    // Resampling changes how many times each win is drawn, so the total varies —
    // but every draw is positive, so no ordering can lose money.
    expect(result.returnPct.p05).toBeGreaterThan(0)
    expect(result.maxDrawdownPct.p95).toBeCloseTo(0, 6)
  })

  it('keeps the percentiles ordered and plausible', () => {
    const result = stressTest(
      trades([200, -150, 90, -80, 60, -40, 30, -20, 10, -5]),
      10_000,
      4
    )!

    expect(result.returnPct.p05).toBeLessThanOrEqual(result.returnPct.p50)
    expect(result.returnPct.p50).toBeLessThanOrEqual(result.returnPct.p95)
    expect(result.returnPct.p05).toBeGreaterThanOrEqual(-100)
    expect(result.simulations).toBe(1000)
    expect(result.trades).toBe(10)
  })

  it('counts reshuffles whose drawdown was deeper than the real run', () => {
    const result = stressTest(
      trades([300, -250, 200, -150, 100, -80, 60, -40, 20, -10]),
      10_000,
      1
    )!

    expect(result.worseDrawdownRate).toBeGreaterThan(0)
    expect(result.worseDrawdownRate).toBeLessThanOrEqual(1)
  })

  it('refuses to resample a handful of trades', () => {
    expect(stressTest(trades([100, -50]), 10_000, 0)).toBeNull()
    expect(MIN_TRADES).toBe(5)
  })
})
