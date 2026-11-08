/**
 * The strategies a run can use.
 *
 * They are rules, not code: an id plus a bag of numbers, so a stored run is
 * reproducible from its row and nothing user-supplied is ever executed. Each one
 * decides on the close of a bar and hands the engine absolute stop and target
 * levels, which are also what the engine sizes the position from.
 */

import { atr, highestBefore, lowestBefore, rsi, sma } from './indicators'
import type { Bar } from './types'

export type StrategyId = 'sma_cross' | 'donchian_breakout' | 'rsi_reversion' | 'custom'

export interface Signal {
  action: 'long' | 'short' | 'close'
  stopPrice?: number
  takeProfitPrice?: number
}

export interface ParamSpec {
  key: string
  label: string
  min: number
  max: number
  step: number
  defaultValue: number
  integer?: boolean
}

export interface StrategyDefinition {
  id: StrategyId
  name: string
  description: string
  params: ParamSpec[]
  signals(bars: Bar[], params: Record<string, number>): (Signal | null)[]
}

const atrStopParams: ParamSpec[] = [
  { key: 'atrPeriod', label: 'ATR period', min: 2, max: 100, step: 1, defaultValue: 14, integer: true },
  { key: 'stopAtr', label: 'Stop (× ATR)', min: 0.2, max: 10, step: 0.1, defaultValue: 2 },
  { key: 'targetAtr', label: 'Target (× ATR)', min: 0.2, max: 20, step: 0.1, defaultValue: 4 },
]

const smaCross: StrategyDefinition = {
  id: 'sma_cross',
  name: 'SMA cross',
  description:
    'Long when the fast average crosses above the slow one, short on the opposite cross. Stop and target are ATR multiples of the signal bar close.',
  params: [
    { key: 'fast', label: 'Fast SMA', min: 2, max: 100, step: 1, defaultValue: 20, integer: true },
    { key: 'slow', label: 'Slow SMA', min: 3, max: 300, step: 1, defaultValue: 50, integer: true },
    ...atrStopParams,
  ],
  signals(bars, params) {
    const closes = bars.map((bar) => bar.close)
    const fastSeries = sma(closes, params.fast)
    const slowSeries = sma(closes, params.slow)
    const atrSeries = atr(bars, params.atrPeriod)

    return bars.map((bar, index) => {
      if (index < 1) return null
      const fast = fastSeries[index]
      const slow = slowSeries[index]
      const previousFast = fastSeries[index - 1]
      const previousSlow = slowSeries[index - 1]
      const volatility = atrSeries[index]
      if (
        fast == null ||
        slow == null ||
        previousFast == null ||
        previousSlow == null ||
        volatility == null ||
        volatility <= 0
      ) {
        return null
      }

      const stop = volatility * params.stopAtr
      const target = volatility * params.targetAtr

      if (previousFast <= previousSlow && fast > slow) {
        return {
          action: 'long' as const,
          stopPrice: bar.close - stop,
          takeProfitPrice: bar.close + target,
        }
      }
      if (previousFast >= previousSlow && fast < slow) {
        return {
          action: 'short' as const,
          stopPrice: bar.close + stop,
          takeProfitPrice: bar.close - target,
        }
      }
      return null
    })
  },
}

const donchianBreakout: StrategyDefinition = {
  id: 'donchian_breakout',
  name: 'Donchian breakout',
  description:
    'Long on a close above the highest high of the lookback window, short on a close below the lowest low. ATR stop and target.',
  params: [
    { key: 'lookback', label: 'Lookback bars', min: 5, max: 500, step: 1, defaultValue: 55, integer: true },
    ...atrStopParams,
  ],
  signals(bars, params) {
    const highs = bars.map((bar) => bar.high)
    const lows = bars.map((bar) => bar.low)
    const upper = highestBefore(highs, params.lookback)
    const lower = lowestBefore(lows, params.lookback)
    const atrSeries = atr(bars, params.atrPeriod)

    return bars.map((bar, index) => {
      const ceiling = upper[index]
      const floor = lower[index]
      const volatility = atrSeries[index]
      if (ceiling == null || floor == null || volatility == null || volatility <= 0) {
        return null
      }

      const stop = volatility * params.stopAtr
      const target = volatility * params.targetAtr

      if (bar.close > ceiling) {
        return {
          action: 'long' as const,
          stopPrice: bar.close - stop,
          takeProfitPrice: bar.close + target,
        }
      }
      if (bar.close < floor) {
        return {
          action: 'short' as const,
          stopPrice: bar.close + stop,
          takeProfitPrice: bar.close - target,
        }
      }
      return null
    })
  },
}

const rsiReversion: StrategyDefinition = {
  id: 'rsi_reversion',
  name: 'RSI reversion',
  description:
    'Long when RSI recovers back above the oversold line, short when it falls back below the overbought line — a mean-reversion entry, not a trend one.',
  params: [
    { key: 'period', label: 'RSI period', min: 2, max: 100, step: 1, defaultValue: 14, integer: true },
    { key: 'oversold', label: 'Oversold', min: 1, max: 49, step: 1, defaultValue: 30, integer: true },
    { key: 'overbought', label: 'Overbought', min: 51, max: 99, step: 1, defaultValue: 70, integer: true },
    ...atrStopParams,
  ],
  signals(bars, params) {
    const closes = bars.map((bar) => bar.close)
    const rsiSeries = rsi(closes, params.period)
    const atrSeries = atr(bars, params.atrPeriod)

    return bars.map((bar, index) => {
      if (index < 1) return null
      const current = rsiSeries[index]
      const previous = rsiSeries[index - 1]
      const volatility = atrSeries[index]
      if (
        current == null ||
        previous == null ||
        volatility == null ||
        volatility <= 0
      ) {
        return null
      }

      const stop = volatility * params.stopAtr
      const target = volatility * params.targetAtr

      if (previous < params.oversold && current >= params.oversold) {
        return {
          action: 'long' as const,
          stopPrice: bar.close - stop,
          takeProfitPrice: bar.close + target,
        }
      }
      if (previous > params.overbought && current <= params.overbought) {
        return {
          action: 'short' as const,
          stopPrice: bar.close + stop,
          takeProfitPrice: bar.close - target,
        }
      }
      return null
    })
  },
}

export const STRATEGIES: readonly StrategyDefinition[] = [
  smaCross,
  donchianBreakout,
  rsiReversion,
]

export function getStrategy(id: string): StrategyDefinition | null {
  return STRATEGIES.find((strategy) => strategy.id === id) ?? null
}

/** Lowercase letters and digits only, so "SMA cross" and "sma_cross" agree. */
function normalizeLabel(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '')
}

/**
 * Resolves the free-text strategy field a trader typed into a runnable strategy.
 *
 * Used only to build a deep link from the analytics table into the backtester,
 * and deliberately conservative: an exact id or name wins, then a containment
 * match on at least three characters. Anything less certain returns null and no
 * link is offered — guessing would quietly run rules the trader never asked for,
 * and a wrong result that looks deliberate is worse than no link.
 */
export function matchStrategyByLabel(label: string): StrategyDefinition | null {
  const needle = normalizeLabel(label)
  if (needle.length < 3) return null

  for (const strategy of STRATEGIES) {
    if (normalizeLabel(strategy.id) === needle || normalizeLabel(strategy.name) === needle) {
      return strategy
    }
  }

  let best: StrategyDefinition | null = null
  let bestLength = 0
  for (const strategy of STRATEGIES) {
    for (const candidate of [normalizeLabel(strategy.id), normalizeLabel(strategy.name)]) {
      if (candidate.length < 3) continue
      const overlaps =
        (candidate.includes(needle) || needle.includes(candidate)) && needle.length > bestLength
      if (overlaps) {
        best = strategy
        bestLength = needle.length
      }
    }
  }
  return best
}

/**
 * Clamps every parameter into its declared range, substituting the default for
 * anything missing or non-numeric. A run is never rejected for being one step
 * outside a slider; it is corrected, and the stored params are what actually ran.
 */
export function normalizeParams(
  definition: StrategyDefinition,
  raw: unknown
): Record<string, number> {
  const input =
    raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const params: Record<string, number> = {}

  for (const spec of definition.params) {
    const value = Number(input[spec.key])
    const chosen = Number.isFinite(value) ? value : spec.defaultValue
    const clamped = Math.min(spec.max, Math.max(spec.min, chosen))
    params[spec.key] = spec.integer ? Math.round(clamped) : clamped
  }
  return params
}
