/**
 * Bootstrap stress test: the same trades in a different order.
 *
 * A backtest reports one sequence. That sequence produced the P&L, the streaks
 * and the drawdown — and if the result only works in that order, it is luck
 * rather than an edge. Resampling the trades with replacement keeps the set of
 * outcomes but throws away their order, which is exactly the assumption a
 * fixed-rule strategy should not need.
 *
 * Seeded from the trades themselves, so a saved run always reproduces the same
 * range. No network, no randomness that changes between reads.
 */

import type { Trade } from './types'

export interface Percentiles {
  p05: number
  p50: number
  p95: number
}

export interface StressSummary {
  simulations: number
  /** Derived from the trades, so the same run reports the same numbers. */
  seed: number
  returnPct: Percentiles
  maxDrawdownPct: Percentiles
  /** Share of reshuffles that end above the starting balance. */
  probabilityOfProfit: number
  /** Share of reshuffles whose worst drawdown was deeper than the real run. */
  worseDrawdownRate: number
  trades: number
}

export const DEFAULT_SIMULATIONS = 1000
export const MIN_TRADES = 5

/** Small, fast, deterministic PRNG. */
function mulberry32(seed: number): () => number {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let value = state
    value = Math.imul(value ^ (value >>> 15), value | 1)
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61)
    return ((value ^ (value >>> 14)) >>> 0) / 4_294_967_296
  }
}

/** FNV-1a over the trade P&L sequence, so order-independent inputs agree. */
function seedFor(trades: Trade[], simulations: number): number {
  let hash = (2166136261 ^ simulations) >>> 0
  for (const trade of trades) {
    hash ^= Math.round(trade.pnl * 100) >>> 0
    hash = Math.imul(hash, 16777619) >>> 0
  }
  return hash || 1
}

function percentile(sorted: number[], fraction: number): number {
  if (sorted.length === 0) return 0
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.round(fraction * (sorted.length - 1)))
  )
  return sorted[index] ?? 0
}

function summarize(values: number[]): Percentiles {
  const sorted = [...values].sort((a, b) => a - b)
  return {
    p05: percentile(sorted, 0.05),
    p50: percentile(sorted, 0.5),
    p95: percentile(sorted, 0.95),
  }
}

export function stressTest(
  trades: Trade[],
  initialBalance: number,
  actualMaxDrawdownPct = 0,
  simulations = DEFAULT_SIMULATIONS
): StressSummary | null {
  if (trades.length < MIN_TRADES || !(initialBalance > 0)) return null
  if (!Number.isFinite(simulations) || simulations < 1) return null

  const pnls = trades.map((trade) => trade.pnl).filter((value) => Number.isFinite(value))
  if (pnls.length < MIN_TRADES) return null

  const count = Math.floor(simulations)
  const random = mulberry32(seedFor(trades, count))
  const returns: number[] = []
  const drawdowns: number[] = []
  let profitable = 0
  let worse = 0

  for (let simulation = 0; simulation < count; simulation += 1) {
    let equity = initialBalance
    let peak = initialBalance
    let maxDrawdown = 0

    for (let index = 0; index < pnls.length; index += 1) {
      const pick = pnls[Math.floor(random() * pnls.length)]
      equity += pick ?? 0
      if (equity > peak) peak = equity
      const drawdown = peak > 0 ? ((peak - equity) / peak) * 100 : 0
      if (drawdown > maxDrawdown) maxDrawdown = drawdown
    }

    returns.push(((equity - initialBalance) / initialBalance) * 100)
    drawdowns.push(maxDrawdown)
    if (equity > initialBalance) profitable += 1
    if (maxDrawdown > actualMaxDrawdownPct) worse += 1
  }

  return {
    simulations: count,
    seed: seedFor(trades, count),
    returnPct: summarize(returns),
    maxDrawdownPct: summarize(drawdowns),
    probabilityOfProfit: profitable / count,
    worseDrawdownRate: worse / count,
    trades: trades.length,
  }
}
