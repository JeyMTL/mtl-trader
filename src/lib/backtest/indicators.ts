/**
 * Indicators, computed once over a whole series and aligned to bar indexes.
 *
 * `null` marks warmup: a value that does not exist yet. Strategies check it rather
 * than substituting zero, because a zero SMA silently invents a crossover on the
 * first bar and every metric downstream inherits the fake trade.
 */

import type { Bar } from './types'

/** Simple moving average; `null` until `period` values exist. */
export function sma(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  if (period < 1) return out

  let sum = 0
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index]
    if (value === undefined) continue
    sum += value
    if (index >= period) {
      const dropped = values[index - period]
      if (dropped !== undefined) sum -= dropped
    }
    if (index >= period - 1) out[index] = sum / period
  }
  return out
}

/** Wilder smoothing, the basis for ATR and RSI. */
function wilder(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  if (period < 1 || values.length < period) return out

  let sum = 0
  for (let index = 0; index < period; index += 1) {
    sum += values[index] ?? 0
  }
  out[period - 1] = sum / period

  for (let index = period; index < values.length; index += 1) {
    const previous = out[index - 1]
    const value = values[index]
    if (previous === null || previous === undefined || value === undefined) continue
    out[index] = (previous * (period - 1) + value) / period
  }
  return out
}

/** Average true range, Wilder smoothing. */
export function atr(bars: Bar[], period: number): (number | null)[] {
  const ranges: number[] = []
  for (let index = 0; index < bars.length; index += 1) {
    const bar = bars[index]
    if (!bar) continue
    const previous = index === 0 ? undefined : bars[index - 1]
    const trueRange =
      previous === undefined
        ? bar.high - bar.low
        : Math.max(
            bar.high - bar.low,
            Math.abs(bar.high - previous.close),
            Math.abs(bar.low - previous.close)
          )
    ranges.push(Math.max(0, trueRange))
  }
  return wilder(ranges, period)
}

/** Relative strength index, Wilder smoothing. */
export function rsi(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  if (period < 1 || values.length <= period) return out

  let gain = 0
  let loss = 0
  for (let index = 1; index <= period; index += 1) {
    const change = (values[index] ?? 0) - (values[index - 1] ?? 0)
    if (change >= 0) gain += change
    else loss -= change
  }

  let averageGain = gain / period
  let averageLoss = loss / period
  out[period] = averageLoss === 0 ? 100 : 100 - 100 / (1 + averageGain / averageLoss)

  for (let index = period + 1; index < values.length; index += 1) {
    const change = (values[index] ?? 0) - (values[index - 1] ?? 0)
    averageGain = (averageGain * (period - 1) + Math.max(0, change)) / period
    averageLoss = (averageLoss * (period - 1) + Math.max(0, -change)) / period
    out[index] =
      averageLoss === 0 ? 100 : 100 - 100 / (1 + averageGain / averageLoss)
  }
  return out
}

/**
 * Highest value over the `period` bars *before* the current one, so a breakout
 * signal at bar i is not compared against bar i itself.
 */
export function highestBefore(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  for (let index = period; index < values.length; index += 1) {
    let extreme = -Infinity
    for (let cursor = index - period; cursor < index; cursor += 1) {
      const value = values[cursor]
      if (value === undefined) continue
      if (value > extreme) extreme = value
    }
    out[index] = Number.isFinite(extreme) ? extreme : null
  }
  return out
}

/** Lowest value over the `period` bars before the current one. */
export function lowestBefore(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  for (let index = period; index < values.length; index += 1) {
    let extreme = Infinity
    for (let cursor = index - period; cursor < index; cursor += 1) {
      const value = values[cursor]
      if (value === undefined) continue
      if (value < extreme) extreme = value
    }
    out[index] = Number.isFinite(extreme) ? extreme : null
  }
  return out
}

/** Exponential moving average, seeded with the first value so it exists from bar one. */
export function ema(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  if (period < 1 || values.length === 0) return out
  const multiplier = 2 / (period + 1)
  let previous = values[0] ?? 0
  out[0] = previous
  for (let index = 1; index < values.length; index += 1) {
    const value = values[index]
    if (value === undefined) continue
    previous = (value - previous) * multiplier + previous
    out[index] = previous
  }
  return out
}

/** Rolling population standard deviation; `null` until `period` values exist. */
export function standardDeviation(values: number[], period: number): (number | null)[] {
  const out: (number | null)[] = new Array(values.length).fill(null)
  if (period < 1) return out
  for (let index = period - 1; index < values.length; index += 1) {
    let sum = 0
    for (let cursor = index - period + 1; cursor <= index; cursor += 1) {
      sum += values[cursor] ?? 0
    }
    const mean = sum / period
    let variance = 0
    for (let cursor = index - period + 1; cursor <= index; cursor += 1) {
      variance += ((values[cursor] ?? 0) - mean) ** 2
    }
    out[index] = Math.sqrt(variance / period)
  }
  return out
}

export interface BollingerBands {
  middle: (number | null)[]
  upper: (number | null)[]
  lower: (number | null)[]
}

/** Bollinger bands around an SMA, using the given standard-deviation multiple. */
export function bollinger(
  values: number[],
  period: number,
  multiplier = 2
): BollingerBands {
  const middle = sma(values, period)
  const deviation = standardDeviation(values, period)
  const upper: (number | null)[] = new Array(values.length).fill(null)
  const lower: (number | null)[] = new Array(values.length).fill(null)
  for (let index = 0; index < values.length; index += 1) {
    const mid = middle[index]
    const spread = deviation[index]
    if (mid == null || spread == null) continue
    upper[index] = mid + spread * multiplier
    lower[index] = mid - spread * multiplier
  }
  return { middle, upper, lower }
}

export interface MacdLines {
  macd: (number | null)[]
  signal: (number | null)[]
  histogram: (number | null)[]
}

/**
 * MACD from three EMAs. `period` is the slow length; the fast and signal lengths
 * keep the conventional 12:26:9 proportions, so the default of 26 is exactly
 * 12/26/9 rather than 13/26/9 from rounding half of 26.
 */
export function macd(values: number[], period = 26): MacdLines {
  const slow = Math.max(3, Math.round(period))
  const fast = Math.max(2, Math.round((slow * 12) / 26))
  const signalPeriod = Math.max(2, Math.round((slow * 9) / 26))
  const fastSeries = ema(values, fast)
  const slowSeries = ema(values, slow)
  const line: (number | null)[] = values.map((_, index) => {
    const f = fastSeries[index]
    const s = slowSeries[index]
    return f == null || s == null ? null : f - s
  })
  const definition = line.map((value) => value ?? 0)
  const signalSeries = ema(definition, signalPeriod)
  return {
    macd: line,
    signal: signalSeries,
    histogram: line.map((value, index) => {
      const sig = signalSeries[index]
      return value == null || sig == null ? null : value - sig
    }),
  }
}
