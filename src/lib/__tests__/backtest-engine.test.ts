import { describe, expect, it } from 'vitest'
import { simulate } from '@/lib/backtest/engine'
import { computeMetrics } from '@/lib/backtest/metrics'
import { getStrategy, normalizeParams, STRATEGIES } from '@/lib/backtest/strategies'
import type { Bar, BacktestConfig } from '@/lib/backtest/types'

const start = Date.UTC(2026, 9, 1)
const minute = 60_000

function barAT(open: number, high: number, low: number, close: number, index: number): Bar {
  return { time: start + index * minute, open, high, low, close }
}

/** A definition that emits exactly the signals a test gives it. */
function scripted(signals: Record<number, { action: 'long' | 'short' | 'close'; stop: number; target: number }>) {
  return {
    id: 'sma_cross' as const,
    name: 'scripted',
    description: '',
    params: [],
    signals: (bars: Bar[]) =>
      bars.map((_, index) => {
        const entry = signals[index]
        if (!entry) return null
        return {
          action: entry.action,
          stopPrice: entry.stop,
          takeProfitPrice: entry.target,
        }
      }),
  }
}

// Contract size 1 keeps the arithmetic readable: one lot is one unit, so a
// 5-point stop on a $10,000 account risking 1% is 20 lots.
const config: BacktestConfig = {
  symbol: 'EURUSD',
  initialBalance: 10_000,
  riskPercent: 1,
  contractSize: 1,
  maxLeverage: 30,
  costs: { spread: 0, slippage: 0, commission: 0 },
}

describe('simulation', () => {
  it('fills a signal at the next bar open, not at the signal close', () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1),
      barAT(105, 106, 104, 105, 2),
      barAT(105, 106, 104, 105, 3),
    ]
    const result = simulate(bars, scripted({ 1: { action: 'long', stop: 90, target: 200 } }), {}, config)

    expect(result.trades).toHaveLength(1)
    expect(result.trades[0]!.entryTime).toBe(bars[2]!.time)
    expect(result.trades[0]!.entryPrice).toBe(105)
    expect(result.trades[0]!.exitReason).toBe('end')
  })

  it('charges spread, slippage and commission on every trade', () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1),
      barAT(100, 101, 99, 100, 2),
      barAT(100, 101, 99, 100, 3),
    ]
    const costs = { spread: 0.0002, slippage: 0.0001, commission: 7 }
    const result = simulate(
      bars,
      scripted({ 1: { action: 'long', stop: 95, target: 200 } }),
      {},
      { ...config, costs }
    )

    const trade = result.trades[0]!
    // Entry is 0.0002 worse (half spread + slippage) and so is the exit.
    expect(trade.entryPrice).toBeCloseTo(100.0002, 6)
    expect(trade.exitPrice).toBeCloseTo(99.9998, 6)
    expect(trade.costs).toBeGreaterThan(7)
    expect(trade.pnl).toBeLessThan(0)
  })

  it('assumes the stop fills first when a bar spans both levels', () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1),
      barAT(100, 106, 94, 100, 2),
      barAT(100, 101, 99, 100, 3),
    ]
    const result = simulate(
      bars,
      scripted({ 1: { action: 'long', stop: 95, target: 105 } }),
      {},
      config
    )

    expect(result.trades[0]!.exitReason).toBe('stop')
    expect(result.trades[0]!.exitPrice).toBe(95)
  })

  it('fills a gap through the stop at the open, not at the stop price', () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1), // signal, filled at the next open
      barAT(100, 101, 99, 100, 2), // entry at 100, stop 95
      barAT(90, 91, 89, 90, 3), // gaps straight through the stop
    ]
    const result = simulate(
      bars,
      scripted({ 1: { action: 'long', stop: 95, target: 120 } }),
      {},
      config
    )

    expect(result.trades[0]!.entryPrice).toBe(100)
    expect(result.trades[0]!.exitReason).toBe('stop')
    // Filled at the open, which is worse than the stop price.
    expect(result.trades[0]!.exitPrice).toBe(90)
    expect(result.trades[0]!.pnl).toBeLessThan(0)
  })

  it("sizes a position so a stop-out costs the configured risk", () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1),
      barAT(100, 100, 95, 95, 2),
    ]
    const result = simulate(
      bars,
      scripted({ 1: { action: 'long', stop: 95, target: 200 } }),
      {},
      { ...config, riskPercent: 1 }
    )

    const trade = result.trades[0]!
    // 1% of 10,000 over a 5-point stop, one unit per lot = 20 lots.
    expect(trade.lots).toBeCloseTo(20, 4)
    expect(trade.pnl).toBeCloseTo(-100, 2)
    expect(trade.rMultiple).toBeCloseTo(-1, 4)
  })

  it('caps size by the leverage limit and says so', () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1),
      barAT(100, 101, 99, 100, 2),
    ]
    const result = simulate(
      bars,
      scripted({ 1: { action: 'long', stop: 99.99, target: 200 } }),
      {},
      { ...config, riskPercent: 100, maxLeverage: 1 }
    )

    // Risk sizing would buy 1,000,000 lots; the 1x cap cuts that to 100.
    expect(result.leverageCapped).toBe(true)
    expect(result.trades[0]!.lots).toBeCloseTo(100, 2)
  })

  it('reverses on an opposite signal at the next open', () => {
    const bars = [
      barAT(100, 101, 99, 100, 0),
      barAT(100, 101, 99, 100, 1),
      barAT(100, 101, 99, 100, 2),
      barAT(110, 111, 109, 110, 3),
    ]
    const definition = scripted({
      1: { action: 'long', stop: 90, target: 300 },
      2: { action: 'short', stop: 200, target: 0.5 },
    })
    const result = simulate(bars, definition, {}, config)

    expect(result.trades).toHaveLength(2)
    expect(result.trades[0]!.side).toBe('long')
    expect(result.trades[0]!.exitReason).toBe('signal')
    expect(result.trades[1]!.side).toBe('short')
  })

  it('does not open a position when the stop is invalid', () => {
    const bars = [barAT(100, 101, 99, 100, 0), barAT(100, 101, 99, 100, 1)]
    const result = simulate(
      bars,
      scripted({ 0: { action: 'long', stop: 100, target: 120 } }),
      {},
      config
    )
    expect(result.trades).toHaveLength(0)
  })
})

describe('built-in strategies', () => {
  it('every strategy exposes clamped, documented parameters', () => {
    for (const strategy of STRATEGIES) {
      expect(strategy.params.length).toBeGreaterThan(0)
      const params = normalizeParams(strategy, {})
      for (const spec of strategy.params) {
        expect(params[spec.key]).toBe(spec.defaultValue)
      }
      const clamped = normalizeParams(strategy, { [strategy.params[0]!.key]: 1e9 })
      expect(clamped[strategy.params[0]!.key]).toBe(strategy.params[0]!.max)
    }
  })

  it('produces trades on a trending series', () => {
    const strategy = getStrategy('sma_cross')!
    const bars: Bar[] = []
    for (let index = 0; index < 400; index += 1) {
      const base = 100 + index * 0.1 + Math.sin(index / 8) * 2
      bars.push(barAT(base, base + 0.5, base - 0.5, base + 0.2, index))
    }
    const result = simulate(
      bars,
      strategy,
      normalizeParams(strategy, {}),
      { ...config, costs: { spread: 0.0002, slippage: 0, commission: 5 } }
    )

    expect(result.trades.length).toBeGreaterThan(0)
    const metrics = computeMetrics(result, config.initialBalance, 252)
    expect(metrics.trades).toBe(result.trades.length)
    expect(Number.isFinite(metrics.netPnl)).toBe(true)
  })
})
