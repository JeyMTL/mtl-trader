/**
 * Deterministic analytics over trades. The LLM only *narrates* these numbers —
 * it never computes them — which keeps the review grounded and auditable.
 *
 * Pure and I/O-free so it can be unit tested.
 */

import type { EdgeStats, GroupStat, TradeRecord } from './types'

export const DEFAULT_MIN_SAMPLE = 10

export function tradePnl(trade: TradeRecord): number {
  return Number(trade.pnl) || 0
}

/** The timestamp a trade is attributed to, matching the rest of the app. */
export function tradeTime(trade: TradeRecord): string | null {
  return trade.close_time || trade.open_time || trade.created_at || null
}

export function parseTradeDate(trade: TradeRecord): Date | null {
  const raw = tradeTime(trade)
  if (!raw) return null
  const date = new Date(raw)
  return Number.isNaN(date.getTime()) ? null : date
}

/** The time a trade was taken — used for session classification. */
export function parseOpenDate(trade: TradeRecord): Date | null {
  const raw = trade.open_time || tradeTime(trade)
  if (!raw) return null
  const date = new Date(raw)
  return Number.isNaN(date.getTime()) ? null : date
}

/** Coarse trading session from the open hour (UTC). */
export function sessionOf(date: Date): 'Asian' | 'London' | 'New York' | 'Late' {
  const hour = date.getUTCHours()
  if (hour < 7) return 'Asian'
  if (hour < 12) return 'London'
  if (hour < 20) return 'New York'
  return 'Late'
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

function holdBucket(trade: TradeRecord): string | null {
  if (!trade.open_time || !trade.close_time) return null
  const open = new Date(trade.open_time).getTime()
  const close = new Date(trade.close_time).getTime()
  if (!Number.isFinite(open) || !Number.isFinite(close) || close < open) return null
  const minutes = (close - open) / 60000
  if (minutes < 15) return '<15m'
  if (minutes < 60) return '15-60m'
  if (minutes < 240) return '1-4h'
  return '>4h'
}

function groupStats(map: Map<string, TradeRecord[]>): GroupStat[] {
  const rows: GroupStat[] = []
  for (const [key, group] of map) {
    let wins = 0
    let losses = 0
    let pnl = 0
    for (const trade of group) {
      const value = tradePnl(trade)
      pnl += value
      if (value > 0) wins++
      else if (value < 0) losses++
    }
    rows.push({
      key,
      trades: group.length,
      wins,
      losses,
      pnl,
      winRate: group.length ? (wins / group.length) * 100 : 0,
      expectancy: group.length ? pnl / group.length : 0,
    })
  }
  return rows.sort((a, b) => b.pnl - a.pnl)
}

function push(map: Map<string, TradeRecord[]>, key: string, trade: TradeRecord) {
  const list = map.get(key)
  if (list) list.push(trade)
  else map.set(key, [trade])
}

export function computeEdgeStats(
  trades: TradeRecord[],
  minSample = DEFAULT_MIN_SAMPLE
): EdgeStats {
  let wins = 0
  let losses = 0
  let pnl = 0
  let grossWins = 0
  let grossLosses = 0
  let best = 0
  let worst = 0
  let noteCount = 0

  const bySymbol = new Map<string, TradeRecord[]>()
  const bySession = new Map<string, TradeRecord[]>()
  const byWeekday = new Map<string, TradeRecord[]>()
  const byHoldTime = new Map<string, TradeRecord[]>()

  let maxWinStreak = 0
  let maxLossStreak = 0
  let currentStreak = 0

  const ordered = [...trades].sort((a, b) => {
    const at = parseTradeDate(a)?.getTime() ?? 0
    const bt = parseTradeDate(b)?.getTime() ?? 0
    return at - bt
  })

  for (const trade of ordered) {
    const value = tradePnl(trade)
    pnl += value
    if (value > 0) {
      wins++
      grossWins += value
      currentStreak = currentStreak >= 0 ? currentStreak + 1 : 1
      maxWinStreak = Math.max(maxWinStreak, currentStreak)
    } else if (value < 0) {
      losses++
      grossLosses += Math.abs(value)
      currentStreak = currentStreak <= 0 ? currentStreak - 1 : -1
      maxLossStreak = Math.max(maxLossStreak, Math.abs(currentStreak))
    }
    best = Math.max(best, value)
    worst = Math.min(worst, value)
    if (trade.notes && trade.notes.trim()) noteCount++

    if (trade.symbol) push(bySymbol, trade.symbol, trade)
    const date = parseTradeDate(trade)
    const openDate = parseOpenDate(trade)
    if (openDate) push(bySession, sessionOf(openDate), trade)
    if (date) push(byWeekday, WEEKDAYS[date.getUTCDay()], trade)
    const bucket = holdBucket(trade)
    if (bucket) push(byHoldTime, bucket, trade)
  }

  const count = ordered.length
  return {
    trades: count,
    wins,
    losses,
    winRate: count ? (wins / count) * 100 : 0,
    pnl,
    grossWins,
    grossLosses,
    profitFactor: grossLosses > 0 ? grossWins / grossLosses : grossWins > 0 ? Infinity : 0,
    expectancy: count ? pnl / count : 0,
    avgWin: wins ? grossWins / wins : 0,
    avgLoss: losses ? -grossLosses / losses : 0,
    best,
    worst,
    maxWinStreak,
    maxLossStreak,
    currentStreak,
    bySymbol: groupStats(bySymbol),
    bySession: groupStats(bySession),
    byWeekday: groupStats(byWeekday),
    byHoldTime: groupStats(byHoldTime),
    noteCount,
    insufficient: count < minSample,
    minSample,
  }
}
