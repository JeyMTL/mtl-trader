/**
 * Outcome tracking: compare performance before vs after a saved review so a
 * trader can see whether acting on the advice changed anything. This is the
 * feedback-loop scaffold for Tier 3.
 *
 * Pure and I/O-free.
 */

import type { TradeRecord } from './types'
import { parseTradeDate, tradePnl } from './edge-stats'

export interface OutcomeComparison {
  beforeTrades: number
  afterTrades: number
  beforePnl: number
  afterPnl: number
  beforeWinRate: number
  afterWinRate: number
  beforeExpectancy: number
  afterExpectancy: number
  pnlDelta: number
  winRateDelta: number
  improved: boolean
  enoughData: boolean
}

function summarize(trades: TradeRecord[]) {
  let pnl = 0
  let wins = 0
  for (const trade of trades) {
    const value = tradePnl(trade)
    pnl += value
    if (value > 0) wins++
  }
  const count = trades.length
  return {
    count,
    pnl,
    winRate: count ? (wins / count) * 100 : 0,
    expectancy: count ? pnl / count : 0,
  }
}

/**
 * Split trades into those closed before `reviewedAt` and those after.
 * Trades without a timestamp are attributed to `after` (they are recent).
 */
export function compareOutcome(trades: TradeRecord[], reviewedAt: Date): OutcomeComparison {
  const cutoff = reviewedAt.getTime()
  const before: TradeRecord[] = []
  const after: TradeRecord[] = []
  for (const trade of trades) {
    const date = parseTradeDate(trade)
    if (date && date.getTime() < cutoff) before.push(trade)
    else after.push(trade)
  }

  const b = summarize(before)
  const a = summarize(after)
  return {
    beforeTrades: b.count,
    afterTrades: a.count,
    beforePnl: b.pnl,
    afterPnl: a.pnl,
    beforeWinRate: b.winRate,
    afterWinRate: a.winRate,
    beforeExpectancy: b.expectancy,
    afterExpectancy: a.expectancy,
    pnlDelta: a.pnl - b.pnl,
    winRateDelta: a.winRate - b.winRate,
    improved: a.expectancy > b.expectancy,
    enoughData: a.count >= 5,
  }
}
