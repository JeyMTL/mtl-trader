import { describe, expect, it } from 'vitest'
import { barsPerYearFrom, computeMetrics, emptyMetrics } from '@/lib/backtest/metrics'
import type { EquityPoint, SimulationResult, Trade } from '@/lib/backtest/types'

const start = Date.UTC(2026, 9, 1)

function trade(pnl: number, rMultiple = pnl / 100): Trade {
  return {
    side: 'long',
    entryTime: start,
    exitTime: start + 60_000,
    entryPrice: 100,
    exitPrice: 100 + pnl / 100,
    stopPrice: 99,
    takeProfitPrice: 102,
    lots: 1,
    grossPnl: pnl,
    costs: 0,
    pnl,
    riskAmount: 100,
    rMultiple,
    barsHeld: 1,
    exitReason: 'target',
  }
}

function result(pnls: number[], equityValues: number[]): SimulationResult {
  const equity: EquityPoint[] = equityValues.map((equity, index) => ({
    time: start + index * 60_000,
    equity,
    balance: equity,
  }))
  return {
    trades: pnls.map((pnl) => trade(pnl)),
    equity,
    exposureBars: 10,
    barCount: equityValues.length,
    from: start,
    to: start + equityValues.length * 60_000,
    leverageCapped: false,
  }
}

describe('metrics', () => {
  it('computes profit factor, expectancy and win rate from the trades', () => {
    const metrics = computeMetrics(result([200, 100, -100, -50], [10_000, 10_200, 10_300, 10_150]), 10_000)

    expect(metrics.trades).toBe(4)
    expect(metrics.wins).toBe(2)
    expect(metrics.losses).toBe(2)
    expect(metrics.winRate).toBe(50)
    expect(metrics.grossProfit).toBe(300)
    expect(metrics.grossLoss).toBe(150)
    expect(metrics.profitFactor).toBeCloseTo(2, 6)
    expect(metrics.netPnl).toBe(150)
    expect(metrics.expectancy).toBeCloseTo(37.5, 6)
  })

  it('reports an undefined profit factor instead of infinity when nothing loses', () => {
    const metrics = computeMetrics(result([100, 50], [10_000, 10_100]), 10_000)
    expect(metrics.profitFactor).toBeNull()
  })

  it('measures drawdown from the equity peak, not from the start', () => {
    const metrics = computeMetrics(
      result([], [10_000, 12_000, 9_000, 11_000]),
      10_000
    )

    expect(metrics.maxDrawdown).toBe(3_000)
    expect(metrics.maxDrawdownPct).toBeCloseTo(25, 6)
    // Ends above the start even though it spent the middle in a deep hole.
    expect(metrics.returnPct).toBeCloseTo(10, 6)
  })

  it('handles a run with no trades at all', () => {
    const metrics = computeMetrics(result([], [10_000, 10_000]), 10_000)
    expect(metrics).toMatchObject({
      trades: 0,
      winRate: 0,
      netPnl: 0,
      profitFactor: 0,
      maxDrawdown: 0,
      returnPct: 0,
    })
    expect(metrics.sharpe).toBeNull()
    expect(emptyMetrics(10_000).trades).toBe(0)
  })

  it('annualises Sharpe only when the curve actually moves', () => {
    const flat = computeMetrics(result([], [10_000, 10_000, 10_000]), 10_000, 252)
    expect(flat.sharpe).toBeNull()

    const moving = computeMetrics(
      result([], [10_000, 10_100, 10_050, 10_200, 10_150]),
      10_000,
      252
    )
    expect(moving.sharpe).not.toBeNull()
    expect(Number.isFinite(moving.sharpe!)).toBe(true)
  })

  it('derives bars per year from the median spacing', () => {
    const hourly = Array.from({ length: 10 }, (_, index) => ({ time: start + index * 3_600_000 }))
    expect(barsPerYearFrom(hourly)).toBeCloseTo(365 * 24, 0)
    expect(barsPerYearFrom([{ time: start }])).toBeNull()
  })
})
