/**
 * Declarative strategies, described by a trader in words and compiled by a model
 * into a rule spec this backtester can actually execute.
 *
 * Nothing user-supplied is ever run as code. A spec is data: a short list of
 * indicator comparisons, a stop placement and a target. `compileRuleStrategy`
 * interprets that data with the same deterministic engine the built-in
 * strategies use, so an AI-described strategy is auditable line by line and a
 * stored run stays reproducible from its spec alone.
 *
 * Every condition compares two operands. An operand is either a constant or one
 * of a fixed set of series — price, an average, RSI, ATR, MACD, Bollinger,
 * extremes. The set is deliberately small: a model cannot invent a new
 * indicator, and anything it names outside the list is rejected rather than
 * approximated.
 */

import { extractJsonObject } from '@/lib/ai/schema'
import type { PromptMessage } from '@/lib/ai/types'
import { atr, bollinger, ema, highestBefore, lowestBefore, macd, rsi, sma } from './indicators'
import type { Signal, StrategyDefinition } from './strategies'
import type { Bar } from './types'

export type RuleSeries =
  | 'close'
  | 'open'
  | 'high'
  | 'low'
  | 'hl2'
  | 'sma'
  | 'ema'
  | 'rsi'
  | 'atr'
  | 'highest'
  | 'lowest'
  | 'macd'
  | 'macd_signal'
  | 'macd_histogram'
  | 'bb_upper'
  | 'bb_middle'
  | 'bb_lower'

export type RuleComparison =
  | 'above'
  | 'below'
  | 'crosses_above'
  | 'crosses_below'

export type RuleTimeframe = 'primary' | 'higher'

export interface RuleOperand {
  series?: RuleSeries
  period?: number
  /** Standard-deviation multiple for Bollinger bands. */
  multiplier?: number
  /** Bars back from the decision bar, 0 = current. */
  offset?: number
  /** Which series this operand reads; defaults to the primary timeframe. */
  timeframe?: RuleTimeframe
  /** A constant, used instead of `series`. */
  value?: number
}

export interface RuleCondition {
  left: RuleOperand
  op: RuleComparison
  right: RuleOperand
}

export type RuleStopType = 'atr' | 'percent' | 'points' | 'swing'
export type RuleTargetType = 'r' | 'atr' | 'percent'

export interface RuleStop {
  type: RuleStopType
  /** ATR multiple, percent of price, price distance, or swing lookback bars. */
  value: number
  /** ATR / swing lookback length. Ignored by percent and points. */
  period?: number
}

export interface RuleTarget {
  type: RuleTargetType
  value: number
}

export type RuleSide = 'long' | 'short' | 'both'

export interface RuleSpec {
  name: string
  /** The trader's strategy in one or two plain sentences. */
  summary: string
  timeframe: string
  /** Confirmation timeframe, aggregated from the uploaded primary bars. */
  higherTimeframe: string | null
  side: RuleSide
  longEntry: RuleCondition[]
  shortEntry: RuleCondition[]
  /** Close an open position when all of these hold. */
  exit: RuleCondition[]
  stop: RuleStop
  target: RuleTarget
  /** Ambiguities the model had to resolve, shown to the trader. */
  notes: string[]
}

export const MAX_RULE_CONDITIONS = 4
export const MAX_COMPILE_DESCRIPTION = 4_000
export const MAX_COMPILE_IMAGES = 2
export const MAX_RULE_NOTES = 6
export const MAX_RULE_NAME = 60
export const MAX_RULE_SUMMARY = 400

export const RULE_SPEC_DISCLAIMER =
  'The model translated your description into these rules; it did not validate them. Run them, then check the out-of-sample window and the rolling-window table before risking anything.'

const SERIES_LABELS: Record<RuleSeries, string> = {
  close: 'close',
  open: 'open',
  high: 'high',
  low: 'low',
  hl2: 'midpoint',
  sma: 'SMA',
  ema: 'EMA',
  rsi: 'RSI',
  atr: 'ATR',
  highest: 'highest high',
  lowest: 'lowest low',
  macd: 'MACD line',
  macd_signal: 'MACD signal',
  macd_histogram: 'MACD histogram',
  bb_upper: 'upper band',
  bb_middle: 'middle band',
  bb_lower: 'lower band',
}

const SERIES_KEYS = Object.keys(SERIES_LABELS) as RuleSeries[]
const COMPARISONS: RuleComparison[] = ['above', 'below', 'crosses_above', 'crosses_below']
const STOP_TYPES: RuleStopType[] = ['atr', 'percent', 'points', 'swing']
const TARGET_TYPES: RuleTargetType[] = ['r', 'atr', 'percent']

/** Accepts `15m`, `m15`, `1h`, `4H`, `1d` and settles on the house label. */
export function normalizeTimeframe(label: string): string {
  const cleaned = label.trim().toUpperCase().replace(/\s+/g, '')
  const direct = /^(M|H|D|W)(\d{1,3})$/.exec(cleaned)
  if (direct) return `${direct[1]}${direct[2]}`
  const inverse = /^(\d{1,3})(M|H|D|W)$/.exec(cleaned)
  if (inverse) return `${inverse[2]}${inverse[1]}`
  return cleaned.slice(0, 8) || 'M15'
}

/** Minutes in one bar of a timeframe label, or null when it is unreadable. */
export function timeframeMinutes(label: string): number | null {
  const normalized = normalizeTimeframe(label)
  const match = /^(M|H|D|W)(\d{1,3})$/.exec(normalized)
  if (!match) return null
  const width = Number(match[2])
  if (!Number.isFinite(width) || width <= 0) return null
  switch (match[1]) {
    case 'M':
      return width
    case 'H':
      return width * 60
    case 'D':
      return width * 60 * 24
    case 'W':
      return width * 60 * 24 * 7
    default:
      return null
  }
}

/**
 * How many primary bars make one higher-timeframe bar, or null when unusable.
 *
 * The ratio must divide exactly. Rounding a request for M40 up from M15 bars
 * would silently build 45-minute bars and label them M40; a confirmation the
 * trader did not ask for is worse than saying that pair is unsupported.
 */
export function higherTimeframeRatio(
  primary: string,
  higher: string | null | undefined
): number | null {
  if (!higher) return null
  const fast = timeframeMinutes(primary)
  const slow = timeframeMinutes(higher)
  if (!fast || !slow || slow <= fast) return null
  const ratio = slow / fast
  if (!Number.isInteger(ratio) || ratio < 2 || ratio > 2_000) return null
  return ratio
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value))
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function asFinite(value: unknown): number | null {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function normalizeOperand(raw: unknown): RuleOperand | null {
  if (!raw || typeof raw !== 'object') return null
  const input = raw as Record<string, unknown>

  const constant = asFinite(input.value)
  if (constant !== null && input.value !== undefined) return { value: constant }

  const series = asString(input.series).toLowerCase() as RuleSeries
  if (!SERIES_KEYS.includes(series)) return null

  const operand: RuleOperand = { series }
  const period = asFinite(input.period)
  if (period !== null) operand.period = clamp(Math.round(period), 1, 500)
  const multiplier = asFinite(input.multiplier)
  if (multiplier !== null) operand.multiplier = clamp(multiplier, 0.1, 5)
  const offset = asFinite(input.offset)
  if (offset !== null) operand.offset = clamp(Math.round(offset), 0, 20)
  if (asString(input.timeframe) === 'higher') operand.timeframe = 'higher'
  return operand
}

function normalizeComparison(raw: unknown): RuleComparison | null {
  const value = asString(raw)
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/>/g, 'above')
    .replace(/</g, 'below')
    .replace(/^crossesabove$/, 'crosses_above')
    .replace(/^crossesbelow$/, 'crosses_below')
  if (COMPARISONS.includes(value as RuleComparison)) return value as RuleComparison
  // A few phrasings models reach for that mean the same thing.
  if (value === 'greater_than' || value === 'over' || value === 'above_or_equal') return 'above'
  if (value === 'less_than' || value === 'under' || value === 'below_or_equal') return 'below'
  if (value === 'cross_above') return 'crosses_above'
  if (value === 'cross_below') return 'crosses_below'
  return null
}

function normalizeCondition(raw: unknown): RuleCondition | null {
  if (!raw || typeof raw !== 'object') return null
  const input = raw as Record<string, unknown>
  const left = normalizeOperand(input.left)
  const right = normalizeOperand(input.right)
  const op = normalizeComparison(input.op ?? input.operator ?? input.comparison)
  if (!left || !right || !op) return null
  return { left, op, right }
}

function normalizeConditions(raw: unknown): RuleCondition[] {
  if (!Array.isArray(raw)) return []
  return raw
    .map((condition) => normalizeCondition(condition))
    .filter((condition): condition is RuleCondition => condition !== null)
    .slice(0, MAX_RULE_CONDITIONS)
}

function normalizeStop(raw: unknown): RuleStop {
  const input = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const requested = asString(input.type).toLowerCase()
  const type = STOP_TYPES.includes(requested as RuleStopType)
    ? (requested as RuleStopType)
    : 'atr'
  const rawValue = asFinite(input.value)
  const fallback = type === 'atr' ? 2 : type === 'swing' ? 20 : type === 'percent' ? 1 : 0.001
  const value = clamp(rawValue ?? fallback, type === 'percent' ? 0.05 : 0.00001, type === 'percent' ? 50 : 100_000)
  const period = asFinite(input.period)
  return {
    type,
    value,
    ...(period !== null ? { period: clamp(Math.round(period), 2, 200) } : {}),
  }
}

function normalizeTarget(raw: unknown): RuleTarget {
  const input = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const requested = asString(input.type).toLowerCase()
  const type = TARGET_TYPES.includes(requested as RuleTargetType)
    ? (requested as RuleTargetType)
    : 'r'
  const value = clamp(asFinite(input.value) ?? 2, 0.1, 100)
  return { type, value }
}

/**
 * Turns a model reply (or a stored spec) into something safe to simulate.
 *
 * Values are clamped rather than rejected, so a `period: 900` becomes the
 * longest allowed window instead of failing the whole compile and losing the
 * trader's work. A reply with no usable entry condition is refused: there would
 * be nothing to run, and silently substituting a built-in strategy would look
 * like the trader's own rules.
 */
export function normalizeRuleSpec(raw: unknown): RuleSpec {
  const parsed = typeof raw === 'string' ? parseSpecJson(raw) : raw
  if (!parsed || typeof parsed !== 'object') {
    throw new Error('The compiled strategy was not an object. Try describing it again.')
  }
  const input = parsed as Record<string, unknown>

  const name = (asString(input.name) || 'Custom rules').slice(0, MAX_RULE_NAME)
  const summary = asString(input.summary).slice(0, MAX_RULE_SUMMARY)
  const primary = normalizeTimeframe(asString(input.timeframe) || 'M15')
  const requestedHigher = asString(input.higherTimeframe ?? input.higher_timeframe)
  const higher = requestedHigher ? normalizeTimeframe(requestedHigher) : null
  const higherTimeframe =
    higher && higherTimeframeRatio(primary, higher) !== null ? higher : null

  let side = asString(input.side).toLowerCase() as RuleSide
  if (side !== 'long' && side !== 'short' && side !== 'both') side = 'both'

  const longEntry = normalizeConditions(input.longEntry ?? input.long_entry)
  const shortEntry = normalizeConditions(input.shortEntry ?? input.short_entry)
  const exit = normalizeConditions(input.exit)

  const resolvesLong = longEntry.length > 0
  const resolvesShort = shortEntry.length > 0
  if (side === 'long' && !resolvesLong) {
    throw new Error('The compiled rules had no usable long entry. Describe the entry more concretely and try again.')
  }
  if (side === 'short' && !resolvesShort) {
    throw new Error('The compiled rules had no usable short entry. Describe the entry more concretely and try again.')
  }
  if (!resolvesLong && !resolvesShort) {
    throw new Error('The compiled rules had no entry conditions this engine can run. Try naming indicators and levels.')
  }
  // A side the model asked for but did not describe is dropped rather than
  // invented; `both` with only one described side is simply one-directional.
  if (side === 'both' && !resolvesLong) side = 'short'
  if (side === 'both' && !resolvesShort) side = 'long'

  const notes = Array.isArray(input.notes)
    ? input.notes
        .map((note) => asString(note).slice(0, 200))
        .filter(Boolean)
        .slice(0, MAX_RULE_NOTES)
    : []

  return {
    name,
    summary,
    timeframe: primary,
    higherTimeframe,
    side,
    longEntry,
    shortEntry,
    exit,
    stop: normalizeStop(input.stop),
    target: normalizeTarget(input.target),
    notes,
  }
}

function parseSpecJson(text: string): unknown {
  const json = extractJsonObject(text)
  if (!json) throw new Error('The compiled strategy did not come back as JSON. Try again.')
  try {
    return JSON.parse(json) as unknown
  } catch {
    throw new Error('The compiled strategy contained invalid JSON. Try again.')
  }
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

function seriesValues(
  bars: Bar[],
  series: RuleSeries,
  period: number,
  multiplier: number
): (number | null)[] {
  const closes = bars.map((bar) => bar.close)
  switch (series) {
    case 'close':
      return bars.map((bar) => bar.close)
    case 'open':
      return bars.map((bar) => bar.open)
    case 'high':
      return bars.map((bar) => bar.high)
    case 'low':
      return bars.map((bar) => bar.low)
    case 'hl2':
      return bars.map((bar) => (bar.high + bar.low) / 2)
    case 'sma':
      return sma(closes, period)
    case 'ema':
      return ema(closes, period)
    case 'rsi':
      return rsi(closes, period)
    case 'atr':
      return atr(bars, period)
    case 'highest':
      return highestBefore(
        bars.map((bar) => bar.high),
        period
      )
    case 'lowest':
      return lowestBefore(
        bars.map((bar) => bar.low),
        period
      )
    case 'macd':
      return macd(closes, period).macd
    case 'macd_signal':
      return macd(closes, period).signal
    case 'macd_histogram':
      return macd(closes, period).histogram
    case 'bb_upper':
      return bollinger(closes, period, multiplier).upper
    case 'bb_middle':
      return bollinger(closes, period, multiplier).middle
    case 'bb_lower':
      return bollinger(closes, period, multiplier).lower
    default:
      return bars.map(() => null)
  }
}

/** Folds primary bars into higher-timeframe bars in fixed blocks from bar one. */
function aggregateBars(bars: Bar[], ratio: number): Bar[] {
  const out: Bar[] = []
  for (let start = 0; start < bars.length; start += ratio) {
    const chunk = bars.slice(start, start + ratio)
    const first = chunk[0]
    const last = chunk[chunk.length - 1]
    if (!first || !last) continue
    let high = first.high
    let low = first.low
    for (const bar of chunk) {
      if (bar.high > high) high = bar.high
      if (bar.low < low) low = bar.low
    }
    out.push({ time: last.time, open: first.open, high, low, close: last.close })
  }
  return out
}

interface PreparedFrame {
  bars: Bar[]
  /** Primary index -> usable index in this frame, or -1 when not yet formed. */
  indexFor: (primaryIndex: number) => number
  cache: Map<string, (number | null)[]>
}

function prepareFrame(bars: Bar[], ratio: number | null): PreparedFrame {
  if (!ratio) {
    return {
      bars,
      indexFor: (index) => index,
      cache: new Map(),
    }
  }
  return {
    bars: aggregateBars(bars, ratio),
    // Bar i belongs to block floor(i / ratio); only blocks that have fully
    // closed are visible, which is the previous block.
    indexFor: (index) => Math.floor(index / ratio) - 1,
    cache: new Map(),
  }
}

function frameFor(operand: RuleOperand, primary: PreparedFrame, higher: PreparedFrame | null): PreparedFrame | null {
  if (operand.timeframe === 'higher') return higher
  return primary
}

/** The periods the prompt tells the model are conventional defaults. */
function defaultPeriodFor(series: RuleSeries | undefined): number {
  if (series === 'macd' || series === 'macd_signal' || series === 'macd_histogram') return 26
  if (series === 'bb_upper' || series === 'bb_middle' || series === 'bb_lower') return 20
  return 14
}

function valueOf(
  operand: RuleOperand,
  primary: PreparedFrame,
  higher: PreparedFrame | null,
  index: number
): number | null {
  if (typeof operand.value === 'number' && Number.isFinite(operand.value)) {
    return operand.value
  }
  if (!operand.series) return null
  const frame = frameFor(operand, primary, higher)
  if (!frame) return null

  const mapped = frame.indexFor(index - (operand.offset ?? 0))
  if (mapped < 0 || mapped >= frame.bars.length) return null

  const period = operand.period ?? defaultPeriodFor(operand.series)
  const multiplier = operand.multiplier ?? 2
  const key = `${operand.series}:${period}:${multiplier}`
  let series = frame.cache.get(key)
  if (!series) {
    series = seriesValues(frame.bars, operand.series, period, multiplier)
    frame.cache.set(key, series)
  }
  return series[mapped] ?? null
}

function evaluate(
  condition: RuleCondition,
  primary: PreparedFrame,
  higher: PreparedFrame | null,
  index: number
): boolean {
  const left = valueOf(condition.left, primary, higher, index)
  const right = valueOf(condition.right, primary, higher, index)
  if (left === null || right === null) return false

  switch (condition.op) {
    case 'above':
      return left > right
    case 'below':
      return left < right
    case 'crosses_above': {
      if (index < 1) return false
      const previousLeft = valueOf(condition.left, primary, higher, index - 1)
      const previousRight = valueOf(condition.right, primary, higher, index - 1)
      if (previousLeft === null || previousRight === null) return false
      return previousLeft <= previousRight && left > right
    }
    case 'crosses_below': {
      if (index < 1) return false
      const previousLeft = valueOf(condition.left, primary, higher, index - 1)
      const previousRight = valueOf(condition.right, primary, higher, index - 1)
      if (previousLeft === null || previousRight === null) return false
      return previousLeft >= previousRight && left < right
    }
    default:
      return false
  }
}

/**
 * The engine-facing strategy for a spec.
 *
 * Stops are placed relative to the signal bar's close, exactly like the built-in
 * strategies, so position sizing from risk behaves identically. A condition
 * whose value does not exist yet (indicator warmup, or a higher-timeframe bar
 * still forming) evaluates false, which keeps the rules from trading on data
 * that would not have been available at the time.
 */
export function compileRuleStrategy(spec: RuleSpec): StrategyDefinition {
  const ratio = higherTimeframeRatio(spec.timeframe, spec.higherTimeframe)

  return {
    id: 'custom',
    name: spec.name,
    description: spec.summary || describeRuleSpec(spec).join(' '),
    params: [],
    signals(bars) {
      const primary = prepareFrame(bars, null)
      const higher = ratio ? prepareFrame(bars, ratio) : null
      const atrSeries = atr(bars, spec.stop.period ?? 14)
      const highs = bars.map((bar) => bar.high)
      const lows = bars.map((bar) => bar.low)
      const swing = spec.stop.period ?? 20
      const swingHigh = highestBefore(highs, swing)
      const swingLow = lowestBefore(lows, swing)

      return bars.map((bar, index) => {
        if (spec.exit.length > 0 && spec.exit.every((condition) => evaluate(condition, primary, higher, index))) {
          return { action: 'close' as const }
        }

        const wantsLong =
          (spec.side === 'long' || spec.side === 'both') &&
          spec.longEntry.length > 0 &&
          spec.longEntry.every((condition) => evaluate(condition, primary, higher, index))
        const wantsShort =
          (spec.side === 'short' || spec.side === 'both') &&
          spec.shortEntry.length > 0 &&
          spec.shortEntry.every((condition) => evaluate(condition, primary, higher, index))

        if (!wantsLong && !wantsShort) return null
        // Both matching at once is contradictory; the cleaner of the two is not
        // knowable, so this bar is skipped rather than guessed.
        if (wantsLong && wantsShort) return null

        const side: 'long' | 'short' = wantsLong ? 'long' : 'short'
        const direction = side === 'long' ? 1 : -1
        const volatility = atrSeries[index]

        let stopDistance: number | null = null
        switch (spec.stop.type) {
          case 'atr':
            stopDistance = volatility == null ? null : volatility * spec.stop.value
            break
          case 'percent':
            stopDistance = (bar.close * spec.stop.value) / 100
            break
          case 'points':
            stopDistance = spec.stop.value
            break
          case 'swing': {
            const level = side === 'long' ? swingLow[index] : swingHigh[index]
            stopDistance = level == null ? null : Math.abs(bar.close - level)
            break
          }
        }
        if (stopDistance === null || !(stopDistance > 0)) return null

        let targetDistance: number
        switch (spec.target.type) {
          case 'r':
            targetDistance = stopDistance * spec.target.value
            break
          case 'atr':
            targetDistance = volatility == null ? 0 : volatility * spec.target.value
            break
          case 'percent':
            targetDistance = (bar.close * spec.target.value) / 100
            break
          default:
            targetDistance = stopDistance * 2
        }
        if (!(targetDistance > 0)) return null

        return {
          action: side,
          stopPrice: bar.close - direction * stopDistance,
          takeProfitPrice: bar.close + direction * targetDistance,
        } satisfies Signal
      })
    },
  }
}

// ---------------------------------------------------------------------------
// Human-readable rules
// ---------------------------------------------------------------------------

function operandLabel(operand: RuleOperand): string {
  if (typeof operand.value === 'number' && Number.isFinite(operand.value)) {
    return String(operand.value)
  }
  const base = operand.series ? SERIES_LABELS[operand.series] : '?'
  const parts: string[] = []
  if (operand.period) parts.push(String(operand.period))
  if (operand.multiplier && operand.series?.startsWith('bb_')) parts.push(String(operand.multiplier))
  const withPeriod = parts.length > 0 ? `(${parts.join(', ')})` : ''
  const offset = operand.offset ? ` ${operand.offset} bar${operand.offset === 1 ? '' : 's'} ago` : ''
  const frame = operand.timeframe === 'higher' ? ' (higher TF)' : ''
  return `${base}${withPeriod}${offset}${frame}`
}

const OP_LABELS: Record<RuleComparison, string> = {
  above: 'is above',
  below: 'is below',
  crosses_above: 'crosses above',
  crosses_below: 'crosses below',
}

function conditionLabel(condition: RuleCondition): string {
  return `${operandLabel(condition.left)} ${OP_LABELS[condition.op]} ${operandLabel(condition.right)}`
}

function stopLabel(stop: RuleStop): string {
  switch (stop.type) {
    case 'atr':
      return `${stop.value} × ATR(${stop.period ?? 14})`
    case 'percent':
      return `${stop.value}% of price`
    case 'points':
      return `${stop.value} price points`
    case 'swing':
      return `beyond the ${stop.period ?? 20}-bar swing`
    default:
      return 'unknown'
  }
}

function targetLabel(target: RuleTarget): string {
  switch (target.type) {
    case 'r':
      return `${target.value}R`
    case 'atr':
      return `${target.value} × ATR`
    case 'percent':
      return `${target.value}% of price`
    default:
      return 'unknown'
  }
}

/** The spec as plain instructions a trader can check against their intent. */
export function describeRuleSpec(spec: RuleSpec): string[] {
  const ratio = higherTimeframeRatio(spec.timeframe, spec.higherTimeframe)
  const lines: string[] = []

  lines.push(
    ratio && spec.higherTimeframe
      ? `Decides on ${spec.timeframe} closes; the higher-timeframe conditions read ${spec.higherTimeframe} (${ratio} ${spec.timeframe} bars per ${spec.higherTimeframe} bar, in fixed blocks from the first uploaded bar).`
      : `Decides on ${spec.timeframe} closes.`
  )

  if (spec.longEntry.length > 0) {
    lines.push(`Long when ${spec.longEntry.map(conditionLabel).join(' and ')}.`)
  }
  if (spec.shortEntry.length > 0) {
    lines.push(`Short when ${spec.shortEntry.map(conditionLabel).join(' and ')}.`)
  }
  if (spec.exit.length > 0) {
    lines.push(`Close the position when ${spec.exit.map(conditionLabel).join(' and ')}.`)
  }
  lines.push(`Stop at ${stopLabel(spec.stop)}; target ${targetLabel(spec.target)}.`)
  lines.push(`Directions traded: ${spec.side === 'both' ? 'long and short' : spec.side}.`)
  return lines
}

/**
 * The prompt side of the compile step.
 *
 * The model is told the exact closed set of series and operators, the JSON shape
 * and the fact that its answer will be simulated rather than trusted. Charts are
 * passed only as evidence for what the trader means — the engine never sees them.
 */
export function buildCompileMessages(
  input: {
    description: string
    timeframe: string
    higherTimeframe?: string | null
    stopLoss?: string | null
    symbol?: string | null
  },
  images: string[] = []
): PromptMessage[] {
  const seriesCatalog = SERIES_KEYS.map((key) => {
    if (key === 'macd' || key === 'macd_signal' || key === 'macd_histogram') {
      return `${key} (period = slow length, default 26)`
    }
    if (key.startsWith('bb_')) return `${key} (period, multiplier)`
    if (['close', 'open', 'high', 'low', 'hl2'].includes(key)) return `${key} (no period)`
    return `${key} (period)`
  }).join(', ')

  const system = [
    'You convert a trader’s written strategy into a machine-runnable rule specification for a backtester.',
    'You never execute anything and you never invent an indicator outside the fixed list below.',
    `Available series: ${seriesCatalog}.`,
    'Available comparisons: above, below, crosses_above, crosses_below.',
    'An operand is either {"series": "<name>", "period": <number>, "offset": <number>, "timeframe": "primary"|"higher"} or {"value": <number>}.',
    'A condition is {"left": operand, "op": comparison, "right": operand}.',
    `Use at most ${MAX_RULE_CONDITIONS} conditions per entry side, and only as many as the description actually requires.`,
    'Stops: {"type": "atr"|"percent"|"points"|"swing", "value": number, "period": number}. Use "swing" for a stop beyond the recent low/high. Targets: {"type": "r"|"atr"|"percent", "value": number}.',
    'The higher timeframe is optional. Only set it when the trader describes confirmation on a slower timeframe; mark those operands with "timeframe": "higher".',
    'Everything is decided on the close of a bar and filled at the next open. Do not describe intrabar or news-event behaviour.',
    'If part of the description is discretionary (feel, news, "wait for confirmation"), say so in notes and encode the closest mechanical rule.',
    'Reply with a single JSON object and nothing else, shaped exactly like this:',
    JSON.stringify({
      name: 'short strategy name',
      summary: 'one or two plain sentences',
      timeframe: 'M15',
      higherTimeframe: null,
      side: 'both',
      longEntry: [{ left: { series: 'ema', period: 20 }, op: 'crosses_above', right: { series: 'ema', period: 50 } }],
      shortEntry: [{ left: { series: 'ema', period: 20 }, op: 'crosses_below', right: { series: 'ema', period: 50 } }],
      exit: [],
      stop: { type: 'atr', value: 2, period: 14 },
      target: { type: 'r', value: 2 },
      notes: ['anything you had to interpret'],
    }),
    'Confidence may not exceed what the description supports. Never claim the strategy is profitable.',
    images.length > 0
      ? `${images.length} chart screenshot(s) are attached. Read the visible structure, indicator names and marked levels to resolve the description; say in notes if the image is not a chart or is unclear.`
      : 'No screenshot is attached; work from the text alone.',
  ].join('\n')

  const user = [
    `Symbol: ${input.symbol?.trim() || 'not specified'}`,
    `Primary timeframe: ${normalizeTimeframe(input.timeframe)}`,
    `Higher timeframe requested: ${input.higherTimeframe ? normalizeTimeframe(input.higherTimeframe) : 'none'}`,
    `Stop loss instructions: ${input.stopLoss?.trim() || 'not specified — infer one from the description'}`,
    '',
    'The trader’s description of the strategy:',
    input.description.slice(0, MAX_COMPILE_DESCRIPTION),
    '',
    'Return the JSON object now.',
  ].join('\n')

  if (images.length > 0) {
    return [
      { role: 'system', content: system },
      {
        role: 'user',
        content: [
          { type: 'text', text: user },
          ...images.map((dataUrl) => ({ type: 'image' as const, dataUrl })),
        ],
      },
    ]
  }

  return [
    { role: 'system', content: system },
    { role: 'user', content: user },
  ]
}
