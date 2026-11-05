/**
 * The public entry point: CSV in, a complete, reproducible report out.
 *
 * A run is split into two consecutive windows by default (70/30). The second
 * window is simulated independently from the same starting balance, which is the
 * only honest way to answer "does this hold up on data the rules were not tuned
 * on?" — reusing the first window's open position or equity would leak the
 * result forward.
 */

import { buyAndHold, type Benchmark } from './benchmark'
import { parseBarsCsv, type ParseOptions } from './csv'
import { simulate } from './engine'
import { barsPerYearFrom, computeMetrics, emptyMetrics, type Metrics } from './metrics'
import { stressTest, type StressSummary } from './stress'
import { getStrategy, normalizeParams, type StrategyId } from './strategies'
import type { Bar, BacktestConfig, EquityPoint, Trade } from './types'

export interface BacktestRequest {
  csv: string
  symbol: string
  timeframe?: string
  strategyId: string
  params?: Record<string, unknown>
  initialBalance?: number
  riskPercent?: number
  contractSize?: number
  maxLeverage?: number
  spread?: number
  slippage?: number
  commission?: number
  /** Share of the bars used as the in-sample window, 0.5–0.9. */
  splitRatio?: number
  timezoneOffsetMinutes?: number
}

export interface BacktestReport {
  symbol: string
  timeframe: string
  strategy: { id: StrategyId; name: string; params: Record<string, number> }
  config: BacktestConfig
  barCount: number
  from: number
  to: number
  metrics: Metrics
  split: { ratio: number; inSample: Metrics; outOfSample: Metrics } | null
  /** Owning the instrument over the same bars, with the same costs. */
  benchmark: Benchmark | null
  /** The same trades reshuffled, to separate an edge from a lucky order. */
  stress: StressSummary | null
  trades: Trade[]
  equityCurve: EquityPoint[]
  assumptions: string[]
  warnings: string[]
}

const DEFAULTS = {
  initialBalance: 10_000,
  riskPercent: 1,
  contractSize: 100_000,
  maxLeverage: 30,
  spread: 0,
  slippage: 0,
  commission: 0,
}

function positive(value: number | undefined, fallback: number, name: string): number {
  if (value === undefined || !Number.isFinite(value)) return fallback
  if (value < 0) throw new Error(`${name} cannot be negative.`)
  return value
}

/** Keeps the curve readable in a chart and inside a jsonb column. */
function downsample(points: EquityPoint[], maxPoints = 400): EquityPoint[] {
  if (points.length <= maxPoints) return points
  const step = (points.length - 1) / (maxPoints - 1)
  const out: EquityPoint[] = []
  for (let index = 0; index < maxPoints; index += 1) {
    const point = points[Math.round(index * step)]
    if (point) out.push(point)
  }
  return out
}

function assumptionsFor(
  config: BacktestConfig,
  offsetMinutes: number,
  leverageCapped: boolean
): string[] {
  const list = [
    'Signals are decided on a bar close and filled at the next bar’s open — a bar cannot trade its own close.',
    'Spread is charged as a fixed half-spread on entry and exit; slippage always goes against the position.',
    `Commission of ${config.costs.commission} per round-turn trade is charged on every trade.`,
    'When a bar’s range touches both the stop and the target, the stop is assumed to fill first.',
    'A position still open on the final bar is closed at that bar’s close, so reported P&L is realised.',
    'Values are in the data’s quote currency; no FX conversion is applied.',
    'Sizing risks a fixed percent of equity to the stop, then caps notional at the leverage limit.',
    'Buy and hold is one fully invested unit of notional equal to the starting balance, no leverage, entered at the first open and sold at the last close with the same costs.',
  ]

  if (offsetMinutes === 0) {
    list.push('Bar timestamps are read as UTC. If your broker’s server clock is offset, set it — session-based strategies depend on it.')
  } else {
    list.push(
      `Bar timestamps were shifted by ${offsetMinutes} minutes from the values in the file.`
    )
  }
  if (leverageCapped) {
    list.push('The leverage cap reduced the size of at least one position, so some trades risked less than the configured percentage.')
  }

  return list
}

export function runBacktest(request: BacktestRequest): BacktestReport {
  const definition = getStrategy(request.strategyId)
  if (!definition) {
    throw new Error(`Unknown strategy: ${request.strategyId}`)
  }

  const params = normalizeParams(definition, request.params)
  const initialBalance = positive(request.initialBalance, DEFAULTS.initialBalance, 'Starting balance')
  if (!(initialBalance > 0)) throw new Error('Starting balance must be greater than zero.')

  const riskPercent = positive(request.riskPercent, DEFAULTS.riskPercent, 'Risk per trade')
  if (riskPercent <= 0 || riskPercent > 100) {
    throw new Error('Risk per trade must be between 0 and 100 percent.')
  }

  const config: BacktestConfig = {
    symbol: request.symbol.trim() || 'UNKNOWN',
    initialBalance,
    riskPercent,
    contractSize: positive(request.contractSize, DEFAULTS.contractSize, 'Contract size') || DEFAULTS.contractSize,
    maxLeverage: positive(request.maxLeverage, DEFAULTS.maxLeverage, 'Leverage cap') || DEFAULTS.maxLeverage,
    costs: {
      spread: positive(request.spread, DEFAULTS.spread, 'Spread'),
      slippage: positive(request.slippage, DEFAULTS.slippage, 'Slippage'),
      commission: positive(request.commission, DEFAULTS.commission, 'Commission'),
    },
  }

  const parseOptions: ParseOptions = {
    maxBars: 60_000,
    ...(request.timezoneOffsetMinutes !== undefined
      ? { timezoneOffsetMinutes: request.timezoneOffsetMinutes }
      : {}),
  }
  const bars: Bar[] = parseBarsCsv(request.csv, parseOptions)
  const barsPerYear = barsPerYearFrom(bars)

  const full = simulate(bars, definition, params, config)
  const metrics = computeMetrics(full, initialBalance, barsPerYear)

  // Two questions a positive curve cannot answer: would owning the instrument
  // have paid better, and is the result an artefact of the order the trades
  // happened to arrive in?
  const benchmark = buyAndHold(bars, initialBalance, config.costs)
  const stress = stressTest(full.trades, initialBalance, metrics.maxDrawdownPct)

  const ratio = Math.min(0.9, Math.max(0.5, request.splitRatio ?? 0.7))
  const splitIndex = Math.floor(bars.length * ratio)
  let split: BacktestReport['split'] = null

  // Both windows need enough bars to warm the strategy up and still trade.
  if (splitIndex >= 100 && bars.length - splitIndex >= 100) {
    const inSampleBars = bars.slice(0, splitIndex)
    const outOfSampleBars = bars.slice(splitIndex)
    const inSample = simulate(inSampleBars, definition, params, config)
    const outOfSample = simulate(outOfSampleBars, definition, params, config)

    split = {
      ratio,
      inSample: computeMetrics(inSample, initialBalance, barsPerYearFrom(inSampleBars)),
      outOfSample: computeMetrics(
        outOfSample,
        initialBalance,
        barsPerYearFrom(outOfSampleBars)
      ),
    }
  }

  const warnings: string[] = []
  if (metrics.trades < 30) {
    warnings.push(
      `Only ${metrics.trades} trades. Below about 30, a win rate or profit factor is noise rather than evidence.`
    )
  }
  if (!split) {
    warnings.push('The range is too short to split into in-sample and out-of-sample windows.')
  }
  if (metrics.exposurePct > 90) {
    warnings.push('Positions were open for over 90% of the range — most of this result is one long exposure, not many independent bets.')
  }
  if (benchmark && metrics.trades > 0 && metrics.returnPct < benchmark.returnPct) {
    warnings.push(
      `Buy and hold returned ${benchmark.returnPct.toFixed(2)}% over the same bars; these rules returned ${metrics.returnPct.toFixed(2)}%.`
    )
  }
  if (stress && stress.probabilityOfProfit < 0.5) {
    warnings.push(
      `More than half of ${stress.simulations.toLocaleString('en-US')} reshuffles of these trades lost money — the result depends heavily on the order they arrived in.`
    )
  }

  return {
    symbol: config.symbol,
    timeframe: request.timeframe?.trim() || 'M1',
    strategy: { id: definition.id, name: definition.name, params },
    config,
    barCount: bars.length,
    from: full.from,
    to: full.to,
    metrics,
    split,
    benchmark,
    stress,
    trades: full.trades,
    equityCurve: downsample(full.equity),
    assumptions: assumptionsFor(config, request.timezoneOffsetMinutes ?? 0, full.leverageCapped),
    warnings,
  }
}

export { emptyMetrics }
export type { Metrics }
