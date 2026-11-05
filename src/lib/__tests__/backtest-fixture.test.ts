import { describe, expect, it } from 'vitest'

import fixture from '../../../fixtures/backtest/report.json'
import { getStrategy } from '../backtest/strategies'

/**
 * The same file is parsed by `mobile_flutter/test/backtest_fixture_test.dart`.
 * These lists are the contract: when a report field is added, removed or
 * renamed, this test and the Dart one fail together, instead of the phone
 * silently ignoring the new value.
 */

const REPORT_KEYS = [
  'assumptions',
  'barCount',
  'benchmark',
  'config',
  'equityCurve',
  'from',
  'metrics',
  'split',
  'strategy',
  'stress',
  'symbol',
  'timeframe',
  'to',
  'trades',
  'warnings',
]

const METRIC_KEYS = [
  'avgRMultiple',
  'expectancy',
  'exposurePct',
  'maxDrawdownPct',
  'netPnl',
  'profitFactor',
  'returnPct',
  'sharpe',
  'trades',
  'winRate',
]

const TRADE_KEYS = [
  'barsHeld',
  'costs',
  'entryPrice',
  'entryTime',
  'exitPrice',
  'exitReason',
  'exitTime',
  'grossPnl',
  'lots',
  'pnl',
  'rMultiple',
  'riskAmount',
  'side',
  'stopPrice',
  'takeProfitPrice',
]

const EQUITY_KEYS = ['balance', 'equity', 'time']

const BENCHMARK_KEYS = [
  'bars',
  'finalEquity',
  'initialBalance',
  'maxDrawdownPct',
  'netPnl',
  'returnPct',
]

const STRESS_KEYS = [
  'maxDrawdownPct',
  'probabilityOfProfit',
  'returnPct',
  'seed',
  'simulations',
  'trades',
  'worseDrawdownRate',
]

const keys = (value: object) => Object.keys(value).sort()

describe('the shared backtest fixture', () => {
  it('covers every top-level field of a report', () => {
    expect(keys(fixture)).toEqual(REPORT_KEYS)
  })

  it('names a strategy the engine still ships', () => {
    const strategy = getStrategy(fixture.strategy.id)
    expect(strategy).toBeDefined()
    expect(fixture.strategy.name).toBe(strategy?.name)
    expect(keys(fixture.strategy.params)).toEqual(
      Object.keys(fixture.strategy.params).sort()
    )
  })

  it('uses the real metric, trade and curve field names', () => {
    expect(keys(fixture.metrics)).toEqual(METRIC_KEYS)
    expect(keys(fixture.split.inSample)).toEqual(METRIC_KEYS)
    expect(keys(fixture.split.outOfSample)).toEqual(METRIC_KEYS)
    expect(keys(fixture.trades[0] ?? {})).toEqual(TRADE_KEYS)
    expect(keys(fixture.equityCurve[0] ?? {})).toEqual(EQUITY_KEYS)
    expect(keys(fixture.config)).toEqual([
      'contractSize',
      'costs',
      'initialBalance',
      'maxLeverage',
      'riskPercent',
      'symbol',
    ])
    expect(keys(fixture.config.costs)).toEqual([
      'commission',
      'slippage',
      'spread',
    ])
  })

  it('carries the robustness results, so the phone sees them in the fixture', () => {
    expect(keys(fixture.benchmark)).toEqual(BENCHMARK_KEYS)
    expect(keys(fixture.stress)).toEqual(STRESS_KEYS)
    expect(keys(fixture.stress.returnPct)).toEqual(['p05', 'p50', 'p95'])
    expect(keys(fixture.stress.maxDrawdownPct)).toEqual(['p05', 'p50', 'p95'])
    // A percentile range that is not ordered is not a range.
    expect(fixture.stress.returnPct.p05).toBeLessThanOrEqual(
      fixture.stress.returnPct.p50
    )
    expect(fixture.stress.returnPct.p50).toBeLessThanOrEqual(
      fixture.stress.returnPct.p95
    )
  })

  it('keeps the split consistent with the reported totals', () => {
    expect(fixture.split.inSample.trades + fixture.split.outOfSample.trades).toBe(
      fixture.metrics.trades
    )
    expect(fixture.split.ratio).toBeGreaterThan(0.5)
    expect(fixture.split.ratio).toBeLessThan(0.9)
  })
})
