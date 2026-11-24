/**
 * How much of a trade's move the trader actually kept.
 *
 * Every journal can show P&L; almost none can say whether that P&L was the whole
 * move or the last third of it. This module computes that from the candles the
 * app already serves: for each closed trade, the best price reached while it was
 * open (MFE, maximum favourable excursion), the worst (MAE, maximum adverse
 * excursion), and the share of the favourable move the exit captured.
 *
 * The maths is pure and takes the candles as an argument, so the route, the card
 * and the tests cannot disagree about the same trade. Nothing here decides which
 * candles to fetch — that needs a clock and a vendor, and lives in
 * `excursion-feed.ts`.
 *
 * Two honesty rules are baked in:
 *
 *   * A trade is only measured when the bars cover its whole life. A partial
 *     series would understate the move and make the exit look better than it was,
 *     so `complete` is returned and the caller drops the row when it is false.
 *   * A trade that never moved in the trader's favour has no capture ratio.
 *     Reporting 0% there would drag every average down with trades that simply
 *     had nothing to capture; `capture` is null and the count is reported
 *     separately.
 */

import { CANDLE_INTERVALS, type Candle, type ChartIntervalKey } from './market-candles'

export type TradeSide = 'buy' | 'sell'

export interface ExcursionInput {
  side: TradeSide
  /** Entry price, in the instrument's quote currency. */
  entry: number
  exit: number
  /** Epoch milliseconds of the fill and the close. */
  openedAt: number
  closedAt: number
}

export interface ExcursionResult {
  /** Best favourable move, in price units. Never negative. */
  mfe: number
  /** Worst adverse move, in price units. Never negative. */
  mae: number
  /** Price move in the trade's direction: profit before costs and sizing. */
  realised: number
  /** `realised / mfe`, or null when the trade never went the trader's way. */
  capture: number | null
  /** Epoch ms of the candle that held the best favourable price. */
  peakAtMs: number | null
  /** Bars used in the measurement. */
  bars: number
  /** Whether the bars span the whole trade, not just the middle of it. */
  complete: boolean
}

/** How much of the move was given back: `1 - capture`. Null when no capture. */
export function giveBack(capture: number | null): number | null {
  return capture === null ? null : 1 - capture
}

/**
 * The candle size to measure a trade with.
 *
 * Small enough that a spike inside the trade is visible, large enough that a
 * week-long trade stays inside the vendor's 5,000-bar cap: a one-minute series
 * for a week is 10,080 bars and would be refused.
 */
export function intervalForDuration(durationMs: number): ChartIntervalKey {
  if (durationMs <= 2 * 3_600_000) return '1m'
  if (durationMs <= 12 * 3_600_000) return '5m'
  if (durationMs <= 3 * 86_400_000) return '15m'
  if (durationMs <= 14 * 86_400_000) return '1h'
  return '4h'
}

/**
 * Measures one trade against the candles that cover it.
 *
 * `barMs` is the width of one candle, which is what decides whether the series
 * really covers the trade: OANDA timestamps a candle at its open, so the last bar
 * of a trade closes one bar after its own timestamp. A series that starts after
 * the fill or ends before the exit is reported as incomplete rather than
 * guessed at.
 */
export function measureExcursion(
  input: ExcursionInput,
  candles: readonly Candle[],
  barMs: number
): ExcursionResult | null {
  if (!Number.isFinite(input.entry) || !Number.isFinite(input.exit)) return null
  if (!(input.closedAt > input.openedAt) || barMs <= 0) return null

  // A bar is relevant when any part of it overlaps the trade. The one bar of
  // grace at each end covers a fill that happened mid-bar.
  const used = candles.filter(
    (candle) =>
      Number.isFinite(candle.t) &&
      candle.t + barMs > input.openedAt &&
      candle.t < input.closedAt + barMs
  )
  if (used.length === 0) return null

  const buy = input.side === 'buy'
  let best = buy ? -Infinity : Infinity
  let worst = buy ? Infinity : -Infinity
  let peakAtMs: number | null = null

  for (const candle of used) {
    const favourable = buy ? candle.h : candle.l
    const adverse = buy ? candle.l : candle.h
    if (buy ? favourable > best : favourable < best) {
      best = favourable
      peakAtMs = candle.t
    }
    if (buy ? adverse < worst : adverse > worst) worst = adverse
  }

  const mfe = Math.max(0, buy ? best - input.entry : input.entry - best)
  const mae = Math.max(0, buy ? input.entry - worst : worst - input.entry)
  const realised = buy ? input.exit - input.entry : input.entry - input.exit

  const first = used[0].t
  const last = used[used.length - 1].t
  const complete =
    first <= input.openedAt + barMs && last + barMs >= input.closedAt - barMs

  return {
    mfe: round(mfe),
    mae: round(mae),
    realised: round(realised),
    capture: mfe > 0 ? round(realised / mfe) : null,
    peakAtMs,
    bars: used.length,
    complete,
  }
}

export interface MeasuredTrade extends ExcursionResult {
  symbol: string
  side: TradeSide
  /** `strategy` from the journal, when the trade carried one. */
  setup: string | null
}

export interface ExcursionBucket {
  key: string
  measured: number
  /** Median share of the move kept. Null when no trade had a move to capture. */
  captureMedian: number | null
  giveBackMedian: number | null
  /** Median favourable and adverse excursion, in price units. */
  mfeMedian: number
  maeMedian: number
}

export interface ExcursionSummary {
  measured: number
  captureMedian: number | null
  giveBackMedian: number | null
  mfeMedian: number
  maeMedian: number
  /** Median `mfe / (mfe + mae)`: how one-sided the trades were. */
  efficiencyMedian: number | null
  bySetup: ExcursionBucket[]
  bySymbol: ExcursionBucket[]
}

/** Median of a list, or null when it is empty. Even counts average the middle two. */
export function median(values: readonly number[]): number | null {
  const usable = values.filter((value) => Number.isFinite(value))
  if (usable.length === 0) return null
  const sorted = [...usable].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  const value =
    sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  return round(value)
}

/**
 * Aggregates a set of measured trades.
 *
 * Medians rather than means on purpose: one trade that gave back 400% of its move
 * (a stop taken on a spike) would otherwise describe the whole account. Buckets
 * with a single trade are kept — the count is shown beside them — because a new
 * journal has nothing else and an empty screen teaches less than a labelled one.
 */
export function summariseExcursions(rows: readonly MeasuredTrade[]): ExcursionSummary {
  const withCapture = rows.filter((row) => row.capture !== null)
  const captures = withCapture.map((row) => row.capture as number)
  const efficiencies = rows
    .map((row) => (row.mfe + row.mae > 0 ? row.mfe / (row.mfe + row.mae) : null))
    .filter((value): value is number => value !== null)

  const bucket = (key: string, group: readonly MeasuredTrade[]): ExcursionBucket => {
    const groupCaptures = group
      .map((row) => row.capture)
      .filter((value): value is number => value !== null)
    const captureMedian = median(groupCaptures)
    return {
      key,
      measured: group.length,
      captureMedian,
      giveBackMedian: giveBack(captureMedian),
      mfeMedian: median(group.map((row) => row.mfe)) ?? 0,
      maeMedian: median(group.map((row) => row.mae)) ?? 0,
    }
  }

  const groupBy = (keyOf: (row: MeasuredTrade) => string | null): ExcursionBucket[] => {
    const groups = new Map<string, MeasuredTrade[]>()
    for (const row of rows) {
      const key = keyOf(row)
      if (!key) continue
      const list = groups.get(key)
      if (list) list.push(row)
      else groups.set(key, [row])
    }
    return [...groups.entries()]
      .map(([key, group]) => bucket(key, group))
      .sort((a, b) => b.measured - a.measured)
  }

  const captureMedian = median(captures)
  return {
    measured: rows.length,
    captureMedian,
    giveBackMedian: giveBack(captureMedian),
    mfeMedian: median(rows.map((row) => row.mfe)) ?? 0,
    maeMedian: median(rows.map((row) => row.mae)) ?? 0,
    efficiencyMedian: median(efficiencies),
    bySetup: groupBy((row) => row.setup),
    bySymbol: groupBy((row) => row.symbol),
  }
}

/** The bar width for an interval, in milliseconds. */
export function barMsFor(interval: ChartIntervalKey): number {
  return CANDLE_INTERVALS[interval].ms
}

function round(value: number): number {
  return Math.round(value * 1e6) / 1e6
}
