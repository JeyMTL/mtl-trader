/**
 * Execution-coach insights: quantified comparisons the journal can prove.
 *
 * The point of this module is the sentence a trader cannot argue with —
 * "EURUSD · Late: -$2.10 per trade vs $0.80 overall (362% worse, 9 trades)" —
 * rather than a vague "watch your late-session trades". Every number is computed
 * here from the trades themselves; the model is only ever asked to narrate them.
 *
 * Deliberately conservative:
 *   - a bucket needs `MIN_INSIGHT_SAMPLE` trades before it is mentioned at all,
 *     because three unlucky trades make a dramatic percentage and a bad habit;
 *   - an expectancy bucket needs a 20% departure from the baseline, a win-rate
 *     bucket 8 percentage points, so noise is not dressed up as a pattern;
 *   - at most four insights are returned, worst two and best two, because a list
 *     of twenty "patterns" is a list nobody acts on.
 *
 * Pure and I/O-free.
 */

import { parseOpenDate, sessionOf, tradePnl } from './edge-stats'
import type { CoachInsight, EdgeStats, TradeRecord } from './types'

export const MIN_INSIGHT_SAMPLE = 6
export const MIN_DELTA_PCT = 20
/** Percentage points a win-rate bucket must move to be worth reporting. */
export const MIN_WIN_RATE_POINTS = 8
/** Below this per-trade expectancy, percentages of it are meaningless. */
const MEANINGFUL_EXPECTANCY = 0.5
export const MAX_INSIGHTS = 4

interface Bucket {
  label: string
  dimension: CoachInsight['dimension']
  trades: TradeRecord[]
}

function pad(value: number): string {
  return String(value).padStart(2, '0')
}

/** Four-hour window in UTC, so "after 20:00 UTC" is expressible. */
function hourWindow(date: Date): string {
  const start = Math.floor(date.getUTCHours() / 4) * 4
  return `${pad(start)}:00–${pad(start + 4)}:00 UTC`
}

function money(value: number): string {
  const sign = value < 0 ? '-' : ''
  return `${sign}$${Math.abs(value).toFixed(2)}`
}

export function buildCoachInsights(
  trades: TradeRecord[],
  stats: EdgeStats,
  minSample = MIN_INSIGHT_SAMPLE
): CoachInsight[] {
  if (trades.length < minSample) return []

  const buckets = new Map<string, Bucket>()
  const add = (dimension: CoachInsight['dimension'], label: string, trade: TradeRecord) => {
    const key = `${dimension}:${label}`
    const existing = buckets.get(key)
    if (existing) existing.trades.push(trade)
    else buckets.set(key, { label, dimension, trades: [trade] })
  }

  for (const trade of trades) {
    const open = parseOpenDate(trade)
    if (!open) continue
    const session = sessionOf(open)
    add('session', session, trade)
    add('hour', hourWindow(open), trade)
    if (trade.symbol) {
      add('symbol', trade.symbol, trade)
      add('symbol-session', `${trade.symbol} · ${session}`, trade)
    }
  }

  // A near-zero baseline turns every percentage into a division by almost
  // nothing, so those journals are compared on win rate instead.
  const baselineExpectancy = stats.expectancy
  const byWinRate = Math.abs(baselineExpectancy) < MEANINGFUL_EXPECTANCY
  const baselineWinRate = stats.winRate

  const candidates: CoachInsight[] = []
  for (const bucket of buckets.values()) {
    const count = bucket.trades.length
    if (count < minSample) continue

    const pnl = bucket.trades.reduce((sum, trade) => sum + tradePnl(trade), 0)
    const wins = bucket.trades.filter((trade) => tradePnl(trade) > 0).length
    const expectancy = pnl / count
    const winRate = (wins / count) * 100

    const value = byWinRate ? winRate : expectancy
    const baseline = byWinRate ? baselineWinRate : baselineExpectancy
    const delta = value - baseline
    // Expectancy delta is relative (percent of the baseline); win-rate delta is
    // already in percentage points.
    const deltaPct = byWinRate ? delta : (delta / Math.abs(baselineExpectancy)) * 100
    const threshold = byWinRate ? MIN_WIN_RATE_POINTS : MIN_DELTA_PCT
    if (Math.abs(deltaPct) < threshold) continue

    const tone: CoachInsight['tone'] = delta < 0 ? 'risk' : 'strength'
    const compare = tone === 'risk' ? 'worse' : 'better'
    const summary = byWinRate
      ? `${bucket.label}: ${value.toFixed(1)}% win rate vs ${baseline.toFixed(1)}% overall (${Math.abs(delta).toFixed(0)} points ${compare}, ${count} trades)`
      : `${bucket.label}: ${money(value)} per trade vs ${money(baseline)} overall (${Math.abs(deltaPct).toFixed(0)}% ${compare}, ${count} trades)`

    candidates.push({
      label: bucket.label,
      dimension: bucket.dimension,
      trades: count,
      metric: byWinRate ? 'winRate' : 'expectancy',
      value,
      baseline,
      deltaPct,
      tone,
      summary,
    })
  }

  // Most specific evidence first: a symbol in a session explains more than the
  // session alone, so the same story is not reported twice.
  const specificity: Record<CoachInsight['dimension'], number> = {
    'symbol-session': 4,
    symbol: 3,
    hour: 2,
    session: 1,
  }

  candidates.sort(
    (a, b) =>
      Math.abs(b.deltaPct) - Math.abs(a.deltaPct) ||
      specificity[b.dimension] - specificity[a.dimension]
  )

  const risks = candidates.filter((item) => item.tone === 'risk').slice(0, 2)
  const strengths = candidates.filter((item) => item.tone === 'strength').slice(0, 2)
  return [...risks, ...strengths].slice(0, MAX_INSIGHTS)
}
