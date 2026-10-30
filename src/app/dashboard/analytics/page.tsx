import { createServerSupabase, requireServerUser } from '@/lib/supabase-server'
import { logEvent } from '@/lib/log'
import { AnalyticsView } from '@/components/analytics-view'
import {
  EMPTY_SUMMARY,
  EMPTY_TIME_STATS,
  type EquityPoint,
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

  const [summaryResult, equityResult, symbolsResult, tagsResult, breakdownsResult, depositsResult, timeResult] = await Promise.all([
    supabase.rpc('trade_summary'),
    supabase.rpc('equity_curve'),
    supabase.rpc('symbol_stats', { p_limit: 20 }),
    supabase.rpc('tag_stats', { p_limit: 12 }),
    supabase.rpc('trade_breakdowns'),
    supabase.rpc('deposits_total'),
    supabase.rpc('time_stats'),
  ])

  for (const [event, result] of [
    ['analytics.summary', summaryResult],
    ['analytics.equity', equityResult],
    ['analytics.symbols', symbolsResult],
    ['analytics.tags', tagsResult],
    ['analytics.breakdowns', breakdownsResult],
    ['analytics.deposits', depositsResult],
    ['analytics.time_stats', timeResult],
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

  return (
    <AnalyticsView
      summary={summary}
      equity={equity}
      symbols={symbols}
      tagStats={tagStats}
      breakdowns={breakdowns}
      depositsTotal={Number.isFinite(depositsTotal) ? depositsTotal : 0}
      timeStats={timeStats}
    />
  )
}
