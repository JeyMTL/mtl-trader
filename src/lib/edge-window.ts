import type { HourStat, SessionStat, TimeStats } from '@/types/journal'
import { formatDuration } from '@/lib/utils'

/**
 * The "when do I actually make money" report.
 *
 * Pure functions over the `time_stats` RPC so the dashboard, the analytics page
 * and the tests all agree on what a best or worst window is. Small samples are
 * ignored on purpose: one lucky trade at 03:00 is not an edge.
 */

export interface EdgePeriod {
  key: string
  label: string
  trades: number
  wins: number
  losses: number
  pnl: number
  winRate: number
}

export interface EdgeReport {
  best: EdgePeriod | null
  worst: EdgePeriod | null
  minTrades: number
}

function winRate(wins: number, trades: number): number {
  return trades > 0 ? (wins / trades) * 100 : 0
}

/** `14` → `14:00–15:00` (the hour bucket a trade was opened in). */
export function formatHourRange(hour: number): string {
  const start = Math.max(0, Math.min(23, Math.floor(hour)))
  const end = start === 23 ? 24 : start + 1
  return `${String(start).padStart(2, '0')}:00–${String(end).padStart(2, '0')}:00`
}

export function hourPeriod(row: HourStat): EdgePeriod {
  const trades = Number(row.trades) || 0
  const wins = Number(row.wins) || 0
  return {
    key: `hour-${row.hour}`,
    label: formatHourRange(Number(row.hour) || 0),
    trades,
    wins,
    losses: Number(row.losses) || 0,
    pnl: Number(row.pnl) || 0,
    winRate: winRate(wins, trades),
  }
}

export function sessionPeriod(row: SessionStat): EdgePeriod {
  const trades = Number(row.trades) || 0
  const wins = Number(row.wins) || 0
  const first = Number(row.first_hour)
  const last = Number(row.last_hour)
  const span = Number.isFinite(first) && Number.isFinite(last)
    ? ` (${String(first).padStart(2, '0')}:00–${String(last + 1).padStart(2, '0')}:00)`
    : ''
  return {
    key: `session-${row.session}`,
    label: `${row.session}${span}`,
    trades,
    wins,
    losses: Number(row.losses) || 0,
    pnl: Number(row.pnl) || 0,
    winRate: winRate(wins, trades),
  }
}

/** A full 24-hour series, so the chart keeps its shape on quiet days. */
export function hourlySeries(stats: TimeStats): EdgePeriod[] {
  const byHour = new Map<number, HourStat>()
  for (const row of stats.hours ?? []) byHour.set(Number(row.hour), row)
  return Array.from({ length: 24 }, (_, hour) => {
    const row = byHour.get(hour)
    return hourPeriod(
      row ?? { hour, trades: 0, wins: 0, losses: 0, pnl: 0 }
    )
  })
}

export function pickEdge(periods: EdgePeriod[], minTrades = 3): EdgeReport {
  const eligible = periods.filter((period) => period.trades >= minTrades)
  if (eligible.length === 0) return { best: null, worst: null, minTrades }

  const best = eligible.reduce((top, period) => (period.pnl > top.pnl ? period : top))
  const worst = eligible.reduce((bottom, period) => (period.pnl < bottom.pnl ? period : bottom))

  return {
    best: best.pnl > 0 ? best : null,
    worst: worst.pnl < 0 ? worst : null,
    minTrades,
  }
}

export function timeEdgeReport(stats: TimeStats, minTrades = 3): {
  bestHour: EdgePeriod | null
  worstHour: EdgePeriod | null
  bestSession: EdgePeriod | null
  worstSession: EdgePeriod | null
  minTrades: number
} {
  const hours = pickEdge(hourlySeries(stats), minTrades)
  const sessions = pickEdge((stats.sessions ?? []).map(sessionPeriod), minTrades)
  return {
    bestHour: hours.best,
    worstHour: hours.worst,
    bestSession: sessions.best,
    worstSession: sessions.worst,
    minTrades,
  }
}

/**
 * Minutes → `1h 24m`, used by the hold-time line.
 * Delegates to `formatDuration` so the same number never renders two ways.
 */
export const formatMinutes = formatDuration
