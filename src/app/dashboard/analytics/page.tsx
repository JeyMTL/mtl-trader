import { createServerSupabase, requireServerUser } from '@/lib/supabase-server'
import { logEvent } from '@/lib/log'
import { AnalyticsView } from '@/components/analytics-view'
import {
  EMPTY_SUMMARY,
  EMPTY_TIME_STATS,
  type EquityPoint,
  type SessionWindowStat,
  type StrategyStat,
  type SymbolStat,
  type TagStat,
  type TimeStats,
  type TradeBreakdowns,
  type TradeSummary,
} from '@/types/journal'

/**
 * Analytics (server component).
 *
 * Same pattern as the dashboard: the database computes the summary, equity
 * curve, symbol and weekday/month breakdowns, so the browser receives a few
 * kilobytes instead of the entire trade history.
 */

export const dynamic = 'force-dynamic'

const EMPTY_BREAKDOWNS: TradeBreakdowns = { weekdays: [], months: [] }

export default async function AnalyticsPage() {
  const user = await requireServerUser()
  const supabase = await createServerSupabase()

  if (!supabase) {
    return (
      <div className="bg-danger/10 border border-danger/30 text-danger rounded-xl p-4">
        Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY.
      </div>
    )
  }

  const [summaryResult, equityResult, symbolsResult, tagsResult, breakdownsResult, depositsResult, timeResult, sessionResult, strategyResult] = await Promise.all([
    supabase.rpc('trade_summary'),
    supabase.rpc('equity_curve'),
    supabase.rpc('symbol_stats', { p_limit: 20 }),
    supabase.rpc('tag_stats', { p_limit: 12 }),
    supabase.rpc('trade_breakdowns'),
    supabase.rpc('deposits_total'),
    supabase.rpc('time_stats'),
    // The four UTC windows, the same buckets the journal filters by. A missing
    // migration logs here and leaves the card showing its empty state.
    supabase.rpc('session_stats'),
    // The free-text label typed on each journal trade, grouped in SQL so the
    // browser receives one row per strategy instead of every trade.
    supabase.rpc('strategy_stats', { p_limit: 20 }),
  ])

  for (const [event, result] of [
    ['analytics.summary', summaryResult],
    ['analytics.equity', equityResult],
    ['analytics.symbols', symbolsResult],
    ['analytics.tags', tagsResult],
    ['analytics.breakdowns', breakdownsResult],
    ['analytics.deposits', depositsResult],
    ['analytics.time_stats', timeResult],
    ['analytics.session_stats', sessionResult],
    ['analytics.strategy_stats', strategyResult],
  ] as const) {
    if (result.error) logEvent('error', event, { error: result.error, userId: user.id })
  }

  const summary = (summaryResult.data as unknown as TradeSummary) ?? EMPTY_SUMMARY
  const equity = (equityResult.data as unknown as EquityPoint[]) ?? []
  const symbols = (symbolsResult.data as unknown as SymbolStat[]) ?? []
  const tagStats = (tagsResult.data as unknown as TagStat[]) ?? []
  const breakdowns = (breakdownsResult.data as unknown as TradeBreakdowns) ?? EMPTY_BREAKDOWNS
  const depositsTotal = Number(depositsResult.data ?? 0)
  const timeStats = (timeResult.data as unknown as TimeStats) ?? EMPTY_TIME_STATS
  const sessionStats = (sessionResult.data as unknown as SessionWindowStat[]) ?? []
  const strategyStats = (strategyResult.data as unknown as StrategyStat[]) ?? []
  // Distinguishes "this database predates the migration" from "you have no timed
  // trades", which are the same empty array and very different advice.
  const sessionStatsMissing = Boolean(sessionResult.error)
  const strategyStatsMissing = Boolean(strategyResult.error)

  return (
    <AnalyticsView
      summary={summary}
      equity={equity}
      symbols={symbols}
      tagStats={tagStats}
      breakdowns={breakdowns}
      depositsTotal={Number.isFinite(depositsTotal) ? depositsTotal : 0}
      timeStats={timeStats}
      sessionStats={Array.isArray(sessionStats) ? sessionStats : []}
      sessionStatsMissing={sessionStatsMissing}
      strategyStats={Array.isArray(strategyStats) ? strategyStats : []}
      strategyStatsMissing={strategyStatsMissing}
    />
  )
}
