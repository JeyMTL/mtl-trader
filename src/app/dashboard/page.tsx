import { createServerSupabase, requireServerUser } from '@/lib/supabase-server'
import { logEvent } from '@/lib/log'
import { DashboardView, type DashboardRecentTrade } from '@/components/dashboard-view'
import {
  EMPTY_SUMMARY,
  EMPTY_TIME_STATS,
  type DailyPnlRow,
  type EquityPoint,
  type JournalFeedEntry,
  type NotificationPreferences,
  type SessionWindowStat,
  type TimeStats,
  type TradeSummary,
} from '@/types/journal'

/**
 * Dashboard (server component).
 *
 * The old version pulled every trade into the browser and computed the stats
 * there. This renders from three aggregate RPCs (`trade_summary`,
 * `equity_curve`, `deposits_total`) plus the five most recent trades, so the
 * response size no longer grows with the user's history.
 */

export const dynamic = 'force-dynamic'

const DEFAULT_PREFERENCES: NotificationPreferences = {
  notifications_journal_reminders: true,
  notifications_monthly_overview: true,
}

/** Local calendar day as `YYYY-MM-DD` for the `daily_pnl` window. */
function isoDay(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

export default async function DashboardPage() {
  const user = await requireServerUser()
  const supabase = await createServerSupabase()

  if (!supabase) {
    return (
      <div className="bg-danger/10 border border-danger/30 text-danger rounded-xl p-4">
        Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY.
      </div>
    )
  }

  const now = new Date()
  const monthStart = isoDay(new Date(now.getFullYear(), now.getMonth(), 1))
  const monthEnd = isoDay(new Date(now.getFullYear(), now.getMonth() + 1, 0))

  const [summaryResult, equityResult, depositsResult, prefsResult, recentResult, dailyResult, timeResult, feedResult, sessionResult] = await Promise.all([
    supabase.rpc('trade_summary'),
    supabase.rpc('equity_curve'),
    supabase.rpc('deposits_total'),
    supabase
      .from('users')
      .select('notifications_journal_reminders, notifications_monthly_overview')
      .eq('id', user.id)
      .maybeSingle(),
    supabase
      .from('trades')
      .select('id, symbol, type, pnl, created_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(5),
    supabase.rpc('daily_pnl', { p_from: monthStart, p_to: monthEnd }),
    supabase.rpc('time_stats'),
    supabase.rpc('journal_feed', { p_limit: 4 }),
    // The four UTC windows the chart shades and the journal filters by.
    supabase.rpc('session_stats'),
  ])

  if (summaryResult.error) {
    logEvent('error', 'dashboard.summary', { error: summaryResult.error, userId: user.id })
  }
  if (equityResult.error) {
    logEvent('error', 'dashboard.equity', { error: equityResult.error, userId: user.id })
  }
  if (depositsResult.error) {
    logEvent('error', 'dashboard.deposits', { error: depositsResult.error, userId: user.id })
  }
  if (dailyResult.error) {
    logEvent('error', 'dashboard.daily', { error: dailyResult.error, userId: user.id })
  }
  if (timeResult.error) {
    logEvent('error', 'dashboard.time_stats', { error: timeResult.error, userId: user.id })
  }
  if (feedResult.error) {
    logEvent('error', 'dashboard.journal_feed', { error: feedResult.error, userId: user.id })
  }
  if (sessionResult.error) {
    logEvent('error', 'dashboard.session_stats', { error: sessionResult.error, userId: user.id })
  }

  const summary = (summaryResult.data as unknown as TradeSummary) ?? EMPTY_SUMMARY
  const equity = (equityResult.data as unknown as EquityPoint[]) ?? []
  const depositsTotal = Number(depositsResult.data ?? 0)
  const recentTrades = (recentResult.data ?? []) as DashboardRecentTrade[]
  const dailyPnl = (dailyResult.data as unknown as DailyPnlRow[]) ?? []
  const timeStats = (timeResult.data as unknown as TimeStats) ?? EMPTY_TIME_STATS
  const journalFeed = (feedResult.data as unknown as JournalFeedEntry[]) ?? []
  const sessionStats = (sessionResult.data as unknown as SessionWindowStat[]) ?? []
  // "This database predates the migration" and "you have no timed trades" are
  // the same empty array and very different advice.
  const sessionStatsMissing = Boolean(sessionResult.error)
  const preferences: NotificationPreferences = prefsResult.data
    ? {
        notifications_journal_reminders: prefsResult.data.notifications_journal_reminders !== false,
        notifications_monthly_overview: prefsResult.data.notifications_monthly_overview !== false,
      }
    : DEFAULT_PREFERENCES

  return (
    <DashboardView
      summary={summary}
      equity={equity}
      depositsTotal={Number.isFinite(depositsTotal) ? depositsTotal : 0}
      recentTrades={recentTrades}
      preferences={preferences}
      dailyPnl={dailyPnl}
      timeStats={timeStats}
      journalFeed={journalFeed}
      sessionStats={Array.isArray(sessionStats) ? sessionStats : []}
      sessionStatsMissing={sessionStatsMissing}
    />
  )
}
