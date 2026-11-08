/**
 * Buy and hold over the same bars.
 *
 * A positive equity curve answers "did the rules make money?". It does not
 * answer "would owning the instrument have paid more?" — and for a long-only
 * trend rule on a rising market, the honest answer is often yes. This module
 * computes that comparison with the same costs the strategy paid.
 *
 * One fully invested unit of notional equal to the starting balance, no
 * leverage, no swap or rollover, entered at the first bar's open and sold at the
 * last bar's close.
 */

import type { Bar, CostModel } from './types'

export interface Benchmark {
  initialBalance: number
  finalEquity: number
  netPnl: number
  returnPct: number
  maxDrawdownPct: number
  bars: number
}

export function buyAndHold(
  bars: Bar[],
  initialBalance: number,
  costs: CostModel
): Benchmark | null {
  if (bars.length < 2 || !(initialBalance > 0)) return null

  const first = bars[0]
  const last = bars[bars.length - 1]
  if (!first || !last) return null

  const half = Math.max(0, costs.spread) / 2
  const slip = Math.max(0, costs.slippage)
  const commission = Math.max(0, costs.commission)

  const entry = first.open + half + slip
  const exit = last.close - half - slip
  if (!(entry > 0) || !(exit > 0)) return null

  const units = initialBalance / entry
  const netPnl = units * (exit - entry) - commission

  // The path is marked at each close, with the round-turn cost applied at the
  // end so the peak and the trough are measured on the same basis as the final
  // number. Interim closes are not tradeable, so no cost is simulated there.
  let peak = initialBalance
  let maxDrawdownPct = 0
  for (let index = 0; index < bars.length; index += 1) {
    const bar = bars[index]
    if (!bar) continue
    // The last close is the exit, so its mark includes the exit half-spread,
    // slippage and commission. Without that point a flat market charged only
    // costs would report a perfect run with no drawdown.
    const value =
      index === bars.length - 1
        ? initialBalance + netPnl
        : initialBalance + units * (bar.close - entry)
    if (value > peak) peak = value
    const drawdown = peak > 0 ? ((peak - value) / peak) * 100 : 0
    if (drawdown > maxDrawdownPct) maxDrawdownPct = drawdown
  }

  return {
    initialBalance,
    finalEquity: initialBalance + netPnl,
    netPnl,
    returnPct: (netPnl / initialBalance) * 100,
    maxDrawdownPct,
    bars: bars.length,
  }
}
