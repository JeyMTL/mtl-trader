/**
 * Report metrics.
 *
 * Everything is derived from the trade list and the marked-to-market equity
 * curve, so the summary can never disagree with the numbers on the trade table.
 * Where a metric is undefined — a profit factor with no losing trades, a Sharpe
 * from a flat curve — it is reported as `null` rather than as Infinity or a
 * plausible-looking zero.
 */

import type { SimulationResult, Trade } from './types'

export interface Metrics {
  trades: number
  wins: number
  losses: number
  breakeven: number
  winRate: number
  netPnl: number
  grossProfit: number
  grossLoss: number
  /** Null when there are no losing trades: the ratio is infinite. */
  profitFactor: number | null
  expectancy: number
  avgWin: number
  avgLoss: number
  bestTrade: number
  worstTrade: number
  avgRMultiple: number | null
  maxDrawdown: number
  maxDrawdownPct: number
  recoveryFactor: number | null
  returnPct: number
  finalEquity: number
  exposurePct: number
  avgBarsHeld: number
  /** Annualised from bar returns; null without enough bars or volatility. */
  sharpe: number | null
  /** Like Sharpe, but only downside returns count as risk. */
  sortino: number | null
  /** Annualised return divided by max drawdown; null without both. */
  calmar: number | null
  maxConsecutiveWins: number
  maxConsecutiveLosses: number
  barCount: number
}

const MS_PER_YEAR = 365 * 24 * 60 * 60 * 1000

/** How many bars of this series fit in a year, from its median spacing. */
export function barsPerYearFrom(bars: { time: number }[]): number | null {
  if (bars.length < 3) return null
  const gaps: number[] = []
  for (let index = 1; index < bars.length; index += 1) {
    const current = bars[index]
    const previous = bars[index - 1]
    if (!current || !previous) continue
    const gap = current.time - previous.time
    if (gap > 0) gaps.push(gap)
  }
  if (gaps.length === 0) return null
  gaps.sort((a, b) => a - b)
  const median = gaps[Math.floor(gaps.length / 2)]
  if (!median || median <= 0) return null
  return MS_PER_YEAR / median
}

function average(values: number[]): number {
  if (values.length === 0) return 0
  return values.reduce((total, value) => total + value, 0) / values.length
}

/**
 * Downside deviation for Sortino: the RMS of negative returns about the target
 * of zero, over every observation.
 *
 * The target is what makes this different from the standard deviation of the
 * losing returns. Subtracting the mean loss would measure how spread out the
 * losses are, not how far they fall below zero — a run with losses of -1% and
 * -3% would then report a *smaller* penalty than one with -2% and -2.1%,
 * inverting the ratio. Upside returns contribute zero, but still count in the
 * denominator, which is the convention this metric is normally quoted under.
 *
 * Deliberately simple — no risk-free rate, no autocorrelation correction. It is
 * there to compare runs of the same data, not to be quoted as a fund fact.
 */
function downsideDeviation(returns: number[]): number | null {
  if (returns.length === 0) return null
  let sumSquares = 0
  let losses = 0
  for (const value of returns) {
    if (value < 0) {
      sumSquares += value * value
      losses += 1
    }
  }
  if (losses === 0) return null
  const deviation = Math.sqrt(sumSquares / returns.length)
  return deviation > 0 ? deviation : null
}

function sharpeRatio(equity: number[], barsPerYear: number | null): number | null {
  if (!barsPerYear || equity.length < 3) return null
  const returns: number[] = []
  for (let index = 1; index < equity.length; index += 1) {
    const previous = equity[index - 1]
    const current = equity[index]
    if (previous === undefined || current === undefined || previous <= 0) continue
    returns.push(current / previous - 1)
  }
  if (returns.length < 2) return null
  const mean = average(returns)
  const variance =
    returns.reduce((total, value) => total + (value - mean) ** 2, 0) /
    (returns.length - 1)
  const deviation = Math.sqrt(variance)
  if (!(deviation > 0)) return null
  return (mean / deviation) * Math.sqrt(barsPerYear)
}

/** Longest run of trades on one side of zero, for both signs. */
function streaks(trades: Trade[]): { wins: number; losses: number } {
  let wins = 0
  let losses = 0
  let currentWins = 0
  let currentLosses = 0
  for (const trade of trades) {
    if (trade.pnl > 0) {
      currentWins += 1
      currentLosses = 0
    } else if (trade.pnl < 0) {
      currentLosses += 1
      currentWins = 0
    } else {
      currentWins = 0
      currentLosses = 0
    }
    if (currentWins > wins) wins = currentWins
    if (currentLosses > losses) losses = currentLosses
  }
  return { wins, losses }
}

export function computeMetrics(
  result: SimulationResult,
  initialBalance: number,
  barsPerYear: number | null = null
): Metrics {
  const trades = result.trades
  const wins = trades.filter((trade) => trade.pnl > 0)
  const losses = trades.filter((trade) => trade.pnl < 0)
  const breakeven = trades.length - wins.length - losses.length

  const grossProfit = wins.reduce((total, trade) => total + trade.pnl, 0)
  const grossLoss = Math.abs(losses.reduce((total, trade) => total + trade.pnl, 0))
  const netPnl = trades.reduce((total, trade) => total + trade.pnl, 0)

  const equityCurve = result.equity.map((point) => point.equity)
  const finalEquity =
    equityCurve.length > 0
      ? (equityCurve[equityCurve.length - 1] ?? initialBalance)
      : initialBalance + netPnl

  let peak = equityCurve[0] ?? initialBalance
  let maxDrawdown = 0
  let maxDrawdownPct = 0
  for (const value of equityCurve) {
    if (value > peak) peak = value
    const drawdown = peak - value
    if (drawdown > maxDrawdown) {
      maxDrawdown = drawdown
      maxDrawdownPct = peak > 0 ? (drawdown / peak) * 100 : 0
    }
  }

  const rMultiples = trades
    .map((trade) => trade.rMultiple)
    .filter((value) => Number.isFinite(value))

  const equityReturns: number[] = []
  for (let index = 1; index < equityCurve.length; index += 1) {
    const previous = equityCurve[index - 1]
    const current = equityCurve[index]
    if (previous === undefined || current === undefined || previous <= 0) continue
    equityReturns.push(current / previous - 1)
  }
  const sortinoDeviation = downsideDeviation(equityReturns)
  const sortino =
    barsPerYear && sortinoDeviation && equityReturns.length >= 2
      ? (average(equityReturns) / sortinoDeviation) * Math.sqrt(barsPerYear)
      : null

  const returnPct =
    initialBalance > 0 ? ((finalEquity - initialBalance) / initialBalance) * 100 : 0
  const maxDrawdownPctValue = maxDrawdownPct
  const years =
    barsPerYear && result.barCount > 0 ? result.barCount / barsPerYear : null
  const annualisedReturnPct =
    years && years > 0 && finalEquity > 0 && initialBalance > 0
      ? ((finalEquity / initialBalance) ** (1 / years) - 1) * 100
      : null
  const calmar =
    maxDrawdownPctValue > 0 && annualisedReturnPct !== null
      ? annualisedReturnPct / maxDrawdownPctValue
      : null
  const streaksResult = streaks(trades)
  const bestTrade = trades.length > 0
    ? trades.reduce((best, trade) => Math.max(best, trade.pnl), -Infinity)
    : 0
  const worstTrade = trades.length > 0
    ? trades.reduce((worst, trade) => Math.min(worst, trade.pnl), Infinity)
    : 0

  return {
    trades: trades.length,
    wins: wins.length,
    losses: losses.length,
    breakeven,
    winRate: trades.length > 0 ? (wins.length / trades.length) * 100 : 0,
    netPnl,
    grossProfit,
    grossLoss,
    profitFactor:
      grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? null : 0,
    expectancy: trades.length > 0 ? netPnl / trades.length : 0,
    avgWin: average(wins.map((trade) => trade.pnl)),
    avgLoss: average(losses.map((trade) => Math.abs(trade.pnl))),
    bestTrade,
    worstTrade,
    avgRMultiple: rMultiples.length > 0 ? average(rMultiples) : null,
    maxDrawdown,
    maxDrawdownPct,
    recoveryFactor: maxDrawdown > 0 ? netPnl / maxDrawdown : null,
    returnPct,
    finalEquity,
    exposurePct:
      result.barCount > 1
        ? (result.exposureBars / (result.barCount - 1)) * 100
        : 0,
    avgBarsHeld: average(trades.map((trade) => trade.barsHeld)),
    sharpe: sharpeRatio(equityCurve, barsPerYear),
    sortino,
    calmar,
    maxConsecutiveWins: streaksResult.wins,
    maxConsecutiveLosses: streaksResult.losses,
    barCount: result.barCount,
  }
}

/** Metrics for a run with no trades, so every report has the same shape. */
export function emptyMetrics(initialBalance: number, barCount = 0): Metrics {
  return {
    trades: 0,
    wins: 0,
    losses: 0,
    breakeven: 0,
    winRate: 0,
    netPnl: 0,
    grossProfit: 0,
    grossLoss: 0,
    profitFactor: 0,
    expectancy: 0,
    avgWin: 0,
    avgLoss: 0,
    bestTrade: 0,
    worstTrade: 0,
    avgRMultiple: null,
    maxDrawdown: 0,
    maxDrawdownPct: 0,
    recoveryFactor: null,
    returnPct: 0,
    finalEquity: initialBalance,
    exposurePct: 0,
    avgBarsHeld: 0,
    sharpe: null,
    sortino: null,
    calmar: null,
    maxConsecutiveWins: 0,
    maxConsecutiveLosses: 0,
    barCount,
  }
}

/** Trades whose entry falls inside a window, for subset reporting. */
export function tradesBetween(trades: Trade[], from: number, to: number): Trade[] {
  return trades.filter((trade) => trade.entryTime >= from && trade.entryTime <= to)
}
