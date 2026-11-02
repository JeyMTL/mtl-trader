/**
 * Real trades from the journal, summarised for comparison with a backtest.
 *
 * This is deliberately *not* a simulation. A journal trade already happened, at
 * a price the broker filled; the useful question is "how did my own trading on
 * this symbol behave over the same window the rules were tested on?", and that
 * is answered by arithmetic, not by replaying bars.
 *
 * It cannot become more than that: a screenshot is pixels and a note is prose.
 * Neither carries a price series, so neither can drive the engine. They are
 * inputs to the AI review, which reads them qualitatively.
 */

export interface JournalTrade {
  strategy?: string | null
  pnl?: number | null
  close_time?: string | null
}

export interface StrategyBreakdown {
  name: string
  trades: number
  netPnl: number
}

export interface JournalSummary {
  trades: number
  netPnl: number
  winRate: number
  bestTrade: number
  worstTrade: number
  /** Most traded strategies first; untagged trades are grouped as "Untagged". */
  strategies: StrategyBreakdown[]
}

export function summarizeJournalTrades(trades: JournalTrade[]): JournalSummary {
  const closed = trades.filter((trade) => trade.close_time)
  const pnls = closed.map((trade) => Number(trade.pnl ?? 0)).filter((value) => Number.isFinite(value))
  const netPnl = pnls.reduce((total, value) => total + value, 0)
  const wins = pnls.filter((value) => value > 0).length

  const grouped = new Map<string, StrategyBreakdown>()
  for (const trade of closed) {
    const name = (trade.strategy ?? '').trim() || 'Untagged'
    const entry = grouped.get(name) ?? { name, trades: 0, netPnl: 0 }
    entry.trades += 1
    entry.netPnl += Number(trade.pnl ?? 0) || 0
    grouped.set(name, entry)
  }

  const strategies = [...grouped.values()].sort(
    (a, b) => b.trades - a.trades || b.netPnl - a.netPnl
  )

  return {
    trades: closed.length,
    netPnl,
    winRate: pnls.length > 0 ? (wins / pnls.length) * 100 : 0,
    bestTrade: pnls.length > 0 ? Math.max(...pnls) : 0,
    worstTrade: pnls.length > 0 ? Math.min(...pnls) : 0,
    strategies,
  }
}
