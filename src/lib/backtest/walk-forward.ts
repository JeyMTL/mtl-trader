/**
 * Rolling-window consistency check.
 *
 * The in-sample / out-of-sample split answers one question at one point in time.
 * This asks it repeatedly: cut the file into consecutive windows, run the exact
 * same rules on each from the same starting balance, and see whether the result
 * survives across them. A strategy that only works in one window is a strategy
 * fitted to that window, whichever half of the split it happened to land in.
 *
 * No parameter is refitted per window, on purpose — that would be a walk-forward
 * optimisation, and this module only claims what it measures: consistency.
 */

import { simulate } from './engine'
import { barsPerYearFrom, computeMetrics, type Metrics } from './metrics'
import type { StrategyDefinition } from './strategies'
import type { Bar, BacktestConfig } from './types'

export const DEFAULT_FOLDS = 4
/** Both a warmup and enough bars to trade: below this a fold says nothing. */
const MIN_BARS_PER_FOLD = 100

export interface WalkForwardFold {
  index: number
  from: number
  to: number
  bars: number
  metrics: Metrics
}

export interface WalkForwardSummary {
  folds: WalkForwardFold[]
  /** Folds that ended above the starting balance. */
  profitableFolds: number
  /** Share of folds that were profitable, 0–1. */
  consistency: number
  /** Median fold return, in percent. */
  medianReturnPct: number
  worstReturnPct: number
  bestReturnPct: number
  /** True when every fold was profitable — the strongest form of this check. */
  allProfitable: boolean
}

function median(values: number[]): number {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0
    ? ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2
    : (sorted[middle] ?? 0)
}

export function walkForward(
  bars: Bar[],
  definition: StrategyDefinition,
  params: Record<string, number>,
  config: BacktestConfig,
  requestedFolds = DEFAULT_FOLDS
): WalkForwardSummary | null {
  const folds = Math.max(2, Math.min(8, Math.round(requestedFolds)))
  if (bars.length < folds * MIN_BARS_PER_FOLD) return null

  const size = Math.floor(bars.length / folds)
  if (size < MIN_BARS_PER_FOLD) return null

  const results: WalkForwardFold[] = []
  for (let index = 0; index < folds; index += 1) {
    const start = index * size
    // The last fold takes the remainder, so no bars are silently dropped.
    const end = index === folds - 1 ? bars.length : start + size
    const window = bars.slice(start, end)
    if (window.length < MIN_BARS_PER_FOLD) continue

    const simulated = simulate(window, definition, params, config)
    results.push({
      index: index + 1,
      from: window[0]?.time ?? 0,
      to: window[window.length - 1]?.time ?? 0,
      bars: window.length,
      metrics: computeMetrics(simulated, config.initialBalance, barsPerYearFrom(window)),
    })
  }

  if (results.length < 2) return null

  const returns = results.map((fold) => fold.metrics.returnPct)
  const profitableFolds = results.filter((fold) => fold.metrics.netPnl > 0).length

  return {
    folds: results,
    profitableFolds,
    consistency: profitableFolds / results.length,
    medianReturnPct: median(returns),
    worstReturnPct: Math.min(...returns),
    bestReturnPct: Math.max(...returns),
    allProfitable: profitableFolds === results.length,
  }
}
