'use client'

import { useId, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import {
  ArrowUpRight,
  BarChart3,
  Bell,
  CalendarDays,
  ClipboardPenLine,
  Clock,
  Image as ImageIcon,
  Mic,
  Plus,
  Settings,
  TrendingDown,
  TrendingUp,
  Upload,
  Wallet,
} from 'lucide-react'
import { cn, formatCurrency, formatDuration, formatPercent } from '@/lib/utils'
import { ChartTooltip } from '@/components/chart-tooltip'
import { axisProps, gridProps, useChartPalette } from '@/lib/chart-theme'
import { Onboarding } from '@/components/onboarding'
import { hourlySeries, timeEdgeReport, type EdgePeriod } from '@/lib/edge-window'
import type {
  DailyPnlRow,
  EquityPoint,
  JournalFeedEntry,
  NotificationPreferences,
  SessionWindowStat,
  TimeStats,
  TradeSummary,
} from '@/types/journal'

export interface DashboardRecentTrade {
  id: string
  symbol: string
  type: string
  pnl: number
  created_at: string
}

interface DashboardViewProps {
  summary: TradeSummary
  equity: EquityPoint[]
  depositsTotal: number
  recentTrades: DashboardRecentTrade[]
  preferences: NotificationPreferences
  dailyPnl: DailyPnlRow[]
  timeStats: TimeStats
  journalFeed: JournalFeedEntry[]
  sessionStats: SessionWindowStat[]
  /** True when `session_stats` is missing from the database. */
  sessionStatsMissing: boolean
}

type ChartMode = 'equity' | 'daily'

/** Display names for the four UTC windows the filter and the RPC share. */
const SESSION_LABELS: Record<string, string> = {
  asian: 'Asian',
  london: 'London',
  newyork: 'New York',
  sydney: 'Sydney',
}

function Kpi({
  icon: Icon,
  label,
  value,
  foot,
  tone,
  href,
}: {
  icon: typeof Wallet
  label: string
  value: string
  foot: string
  tone?: 'pos' | 'neg'
  href?: string
}) {
  const body = (
    <>
      <div className="flex items-start justify-between gap-2">
        <p className="metric-label">{label}</p>
        <Icon className="h-4 w-4 shrink-0 text-gray-600" />
      </div>
      <p className={cn('num mt-2 text-[1.35rem] font-semibold leading-none tracking-tight lg:text-[1.6rem]', tone === 'pos' && 'pos', tone === 'neg' && 'neg', !tone && 'text-white')}>
        {value}
      </p>
      <p className="metric-foot mt-2 truncate">{foot}</p>
    </>
  )

  if (href) {
    return (
      <Link href={href} className="panel tap-card p-4 transition-colors hover:border-border-strong lg:p-5">
        {body}
      </Link>
    )
  }
  return <div className="panel p-4 lg:p-5">{body}</div>
}

function SmallStat({ label, value, tone }: { label: string; value: string; tone?: 'pos' | 'neg' }) {
  return (
    <div className="px-4 py-3">
      <p className="metric-label">{label}</p>
      <p className={cn('num mt-1.5 text-sm font-semibold text-white', tone === 'pos' && 'pos', tone === 'neg' && 'neg')}>{value}</p>
    </div>
  )
}

function timeOf(value: string | null): string {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
}

function EdgeRow({ label, period, tone }: { label: string; period: EdgePeriod | null; tone: 'pos' | 'neg' }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2.5">
      <div className="min-w-0">
        <p className="text-[11px] uppercase tracking-wide text-gray-500">{label}</p>
        <p className="truncate text-sm font-medium text-white">{period ? period.label : `Needs ${3}+ trades`}</p>
      </div>
      <div className="shrink-0 text-right">
        <p className={cn('num text-sm font-semibold', period ? (tone === 'pos' ? 'pos' : 'neg') : 'text-gray-600')}>
          {period ? `${period.pnl >= 0 ? '+' : ''}${formatCurrency(period.pnl)}` : '—'}
        </p>
        <p className="num text-[10px] text-gray-500">
          {period ? `${period.trades} trades · ${formatPercent(period.winRate)} win` : '—'}
        </p>
      </div>
    </div>
  )
}

function MonthHeatmap({ rows }: { rows: DailyPnlRow[] }) {
  const now = new Date()
  const year = now.getFullYear()
  const month = now.getMonth()
  const firstWeekday = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const byDay = useMemo(() => {
    const map = new Map<string, DailyPnlRow>()
    for (const row of rows) map.set(String(row.day).slice(0, 10), row)
    return map
  }, [rows])
  const maxAbs = Math.max(...rows.map((row) => Math.abs(Number(row.pnl) || 0)), 1)

  const cells: Array<number | null> = []
  for (let i = 0; i < firstWeekday; i++) cells.push(null)
  for (let day = 1; day <= daysInMonth; day++) cells.push(day)
  while (cells.length % 7 !== 0) cells.push(null)

  return (
    <div>
      <div className="grid grid-cols-7 gap-1">
        {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day, index) => (
          <div key={`${day}-${index}`} className="pb-1 text-center text-[10px] font-medium text-gray-600">
            {day}
          </div>
        ))}
        {cells.map((day, index) => {
          if (day === null) return <div key={`empty-${index}`} className="aspect-square rounded-[4px] bg-surface-light/25" />
          const key = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
          const row = byDay.get(key)
          const pnl = row ? Number(row.pnl) || 0 : 0
          const intensity = row ? 0.12 + Math.min(Math.abs(pnl) / maxAbs, 1) * 0.42 : 0
          return (
            <Link
              key={key}
              href="/dashboard/calendar"
              title={row ? `${key}: ${formatCurrency(pnl)} · ${row.trades} trades` : `${key}: no trades`}
              className={cn(
                'flex aspect-square flex-col items-center justify-center rounded-[4px] border text-[10px] transition-colors',
                row ? 'border-transparent text-white' : 'border-border/60 bg-surface-light/20 text-gray-600 hover:border-border'
              )}
              style={
                row
                  ? {
                      backgroundColor: pnl >= 0 ? `rgba(69, 210, 154, ${intensity})` : `rgba(242, 107, 120, ${intensity})`,
                    }
                  : undefined
              }
            >
              <span className={cn('num font-medium', row && pnl >= 0 && 'text-success', row && pnl < 0 && 'text-danger')}>{day}</span>
              {row && (
                <span className={cn('num hidden text-[8px] leading-none sm:block', pnl >= 0 ? 'text-success/80' : 'text-danger/80')}>
                  {pnl >= 0 ? '+' : ''}{Math.round(pnl)}
                </span>
              )}
            </Link>
          )
        })}
      </div>
      <div className="mt-3 flex items-center justify-between text-[10px] text-gray-500">
        <span className="num">{now.toLocaleString(undefined, { month: 'long', year: 'numeric' })}</span>
        <span className="flex items-center gap-1">
          Loss
          <span className="h-2.5 w-2.5 rounded-[2px] bg-danger/40" />
          <span className="h-2.5 w-2.5 rounded-[2px] bg-surface-light" />
          <span className="h-2.5 w-2.5 rounded-[2px] bg-success/40" />
          Profit
        </span>
      </div>
    </div>
  )
}

export function DashboardView({
  summary,
  equity,
  depositsTotal,
  recentTrades,
  preferences,
  dailyPnl,
  timeStats,
  journalFeed,
  sessionStats,
  sessionStatsMissing,
}: DashboardViewProps) {
  const palette = useChartPalette()
  // Per-instance gradient id: a fixed one collides as soon as two equity charts
  // are mounted together (dashboard plus preview, two dashboards side by side),
  // and `url(#equityFill)` in the second then paints with the first's stops.
  // useId is stable across the server render and hydration; colons are stripped
  // because they are legal in an id but awkward inside an SVG `url(#…)`.
  const equityFillId = `equityFill-${useId().replace(/:/g, '')}`
  const [chartMode, setChartMode] = useState<ChartMode>('equity')

  const totalPnl = Number(summary.total_pnl) || 0
  const wins = Number(summary.wins) || 0
  const losses = Number(summary.losses) || 0
  const totalTrades = Number(summary.total_trades) || 0
  const winRate = totalTrades > 0 ? (wins / totalTrades) * 100 : 0
  const grossWins = Number(summary.gross_profit) || 0
  const grossLosses = Number(summary.gross_loss) || 0
  const profitFactor = grossLosses > 0 ? grossWins / grossLosses : 0
  const balance = depositsTotal + totalPnl

  const equityData = useMemo(
    () =>
      equity.map((point) => ({
        day: point.day,
        balance: parseFloat((depositsTotal + Number(point.cumulative || 0)).toFixed(2)),
      })),
    [equity, depositsTotal]
  )

  const dailySeries = useMemo(
    () =>
      dailyPnl.map((row) => ({
        day: String(row.day).slice(0, 10),
        pnl: parseFloat((Number(row.pnl) || 0).toFixed(2)),
        trades: Number(row.trades) || 0,
      })),
    [dailyPnl]
  )

  const maxDrawdown = useMemo(() => {
    let peak = depositsTotal
    let worst = 0
    for (const point of equityData) {
      peak = Math.max(peak, point.balance)
      if (peak > 0) worst = Math.max(worst, ((peak - point.balance) / peak) * 100)
    }
    return worst
  }, [equityData, depositsTotal])

  const month = {
    trades: Number(summary.month_trades) || 0,
    wins: Number(summary.month_wins) || 0,
    winningDays: Number(summary.month_winning_days) || 0,
  }
  const monthWinRate = month.trades > 0 ? (month.wins / month.trades) * 100 : 0

  const monthTotals = useMemo(
    () =>
      dailySeries.reduce(
        (acc, row) => ({
          pnl: acc.pnl + row.pnl,
          trades: acc.trades + row.trades,
          winningDays: acc.winningDays + (row.pnl > 0 ? 1 : 0),
        }),
        { pnl: 0, trades: 0, winningDays: 0 }
      ),
    [dailySeries]
  )

  const edge = useMemo(() => timeEdgeReport(timeStats, 3), [timeStats])
  const hourSeries = useMemo(() => hourlySeries(timeStats), [timeStats])
  const hasTimeSamples = timeStats.hours.length > 0

  const today = new Date()
  const isWorkingDay = today.getDay() >= 1 && today.getDay() <= 5
  const showJournalReminder =
    preferences.notifications_journal_reminders !== false &&
    isWorkingDay &&
    !summary.has_trade_today

  const quickActions = [
    { href: '/dashboard/trades/new', label: 'Add trade', hint: 'Log a fill', icon: Plus },
    { href: '/dashboard/import', label: 'Import', hint: 'MT5 / CSV', icon: Upload },
    { href: '/dashboard/calendar', label: 'Calendar', hint: 'Daily P&L', icon: CalendarDays },
    { href: '/dashboard/settings', label: 'Settings', hint: 'Plan & desk', icon: Settings },
  ]

  return (
    <div className="space-y-4 lg:space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="eyebrow">MTL Trader</p>
          <h1 className="mt-1 text-xl font-semibold tracking-tight text-white lg:text-2xl">Desk</h1>
          <p className="mt-1 text-xs text-gray-500">
            {today.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link href="/dashboard/import" className="btn btn-secondary h-9 px-3 text-xs">
            <Upload className="h-3.5 w-3.5" />
            Import
          </Link>
          <Link href="/dashboard/trades/new" className="btn btn-primary h-9 px-3 text-xs">
            <ClipboardPenLine className="h-3.5 w-3.5" />
            Journal a trade
          </Link>
        </div>
      </header>

      <Onboarding hasTrades={totalTrades > 0} />

      {showJournalReminder && (
        <div className="panel flex flex-col gap-3 border-l-2 border-l-primary p-4 sm:flex-row sm:items-center">
          <Bell className="h-4 w-4 shrink-0 text-primary" />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium text-white">Today&apos;s journal is empty</p>
            <p className="mt-0.5 text-xs text-gray-500">Log the fills while the session is still fresh — the edge report is only as good as the times you record.</p>
          </div>
          <Link href="/dashboard/trades/new" className="btn btn-primary h-9 px-3 text-xs">
            <ClipboardPenLine className="h-3.5 w-3.5" />
            Journal a trade
          </Link>
        </div>
      )}

      {/* Headline metrics */}
      <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi
          icon={Wallet}
          label="Account balance"
          value={formatCurrency(balance)}
          foot={`${formatCurrency(depositsTotal)} deposited`}
        />
        <Kpi
          icon={totalPnl >= 0 ? TrendingUp : TrendingDown}
          label="Net P&L"
          value={formatCurrency(totalPnl)}
          foot={`${totalTrades} closed trades`}
          tone={totalPnl >= 0 ? 'pos' : 'neg'}
        />
        <Kpi
          icon={BarChart3}
          label="Win rate"
          value={formatPercent(winRate)}
          foot={`${wins}W / ${losses}L`}
        />
        <Kpi
          icon={Clock}
          label="Profit factor"
          value={profitFactor > 0 ? profitFactor.toFixed(2) : '—'}
          foot={`${formatCurrency(grossWins)} won / ${formatCurrency(grossLosses)} lost`}
        />
      </section>

      <section className="panel grid grid-cols-2 divide-x divide-border overflow-hidden border-border/80 lg:grid-cols-4">
        <SmallStat label="Max drawdown" value={`${maxDrawdown.toFixed(1)}%`} tone={maxDrawdown >= 10 ? 'neg' : undefined} />
        <SmallStat label="Best trade" value={formatCurrency(Number(summary.best_trade) || 0)} tone="pos" />
        <SmallStat label="Worst trade" value={formatCurrency(Number(summary.worst_trade) || 0)} tone="neg" />
        <SmallStat
          label="Avg / trade"
          value={totalTrades > 0 ? formatCurrency(totalPnl / totalTrades) : '—'}
        />
      </section>

      {/* Chart + time edge */}
      <div className="grid gap-4 lg:grid-cols-3 lg:gap-6">
        <section className="panel overflow-hidden lg:col-span-2">
          <div className="panel-head flex-wrap gap-2">
            <div className="min-w-0">
              <p className="eyebrow">Performance</p>
              <p className="num mt-1 text-lg font-semibold text-white">{formatCurrency(balance)}</p>
            </div>
            <div className="flex items-center gap-2">
              <span className={cn('badge', totalPnl >= 0 ? 'badge-buy' : 'badge-sell')}>
                {totalPnl >= 0 ? '+' : ''}{formatCurrency(totalPnl)}
              </span>
              <div className="segmented" role="tablist" aria-label="Chart range">
                {([
                  ['equity', 'Equity'],
                  ['daily', 'Daily'],
                ] as const).map(([mode, label]) => (
                  <button
                    key={mode}
                    type="button"
                    role="tab"
                    aria-selected={chartMode === mode}
                    data-active={chartMode === mode}
                    onClick={() => setChartMode(mode)}
                    className="segmented-option"
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="p-2 pb-3 sm:p-4">
            {chartMode === 'equity' ? (
              equityData.length > 0 ? (
                <div className="h-[230px] w-full sm:h-[280px]">
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={equityData} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                      <defs>
                        <linearGradient id={equityFillId} x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor={totalPnl >= 0 ? palette.profit : palette.loss} stopOpacity={0.22} />
                          <stop offset="100%" stopColor={totalPnl >= 0 ? palette.profit : palette.loss} stopOpacity={0} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid {...gridProps(palette)} />
                      <XAxis {...axisProps(palette)} dataKey="day" minTickGap={28} tickFormatter={(value: string) => value.slice(5)} />
                      <YAxis {...axisProps(palette)} width={62} tickFormatter={(value: number) => `$${Math.round(value).toLocaleString('en-US')}`} />
                      <Tooltip
                        content={<ChartTooltip format={(value) => formatCurrency(value)} />}
                        cursor={{ stroke: palette.axis, strokeDasharray: '3 3' }}
                      />
                      <Area
                        type="monotone"
                        dataKey="balance"
                        name="Equity"
                        stroke={totalPnl >= 0 ? palette.profit : palette.loss}
                        strokeWidth={1.8}
                        fill={`url(#${equityFillId})`}
                        dot={false}
                        activeDot={{ r: 3, strokeWidth: 0 }}
                      />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              ) : (
                <div className="flex h-[230px] flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border text-center sm:h-[280px]">
                  <p className="text-sm text-gray-400">No equity to plot yet</p>
                  <Link href="/dashboard/import" className="text-xs font-medium text-primary hover:text-primary-light">
                    Import your trade history →
                  </Link>
                </div>
              )
            ) : dailySeries.length > 0 ? (
              <div className="h-[230px] w-full sm:h-[280px]">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={dailySeries} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                    <CartesianGrid {...gridProps(palette)} />
                    <XAxis {...axisProps(palette)} dataKey="day" minTickGap={18} tickFormatter={(value: string) => value.slice(5)} />
                    <YAxis {...axisProps(palette)} width={62} tickFormatter={(value: number) => `$${Math.round(value).toLocaleString('en-US')}`} />
                    <Tooltip content={<ChartTooltip format={(value) => formatCurrency(value)} />} cursor={{ fill: palette.grid }} />
                    <Bar dataKey="pnl" name="Daily P&L" radius={[2, 2, 0, 0]} maxBarSize={26}>
                      {dailySeries.map((row) => (
                        <Cell key={row.day} fill={row.pnl >= 0 ? palette.profit : palette.loss} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            ) : (
              <div className="flex h-[230px] flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border text-center sm:h-[280px]">
                <p className="text-sm text-gray-400">No closed trades this month</p>
                <Link href="/dashboard/trades/new" className="text-xs font-medium text-primary hover:text-primary-light">
                  Journal a trade →
                </Link>
              </div>
            )}
          </div>

          {/* Honours the "Monthly trade overview" switch in settings, which
              previously changed nothing on this page. */}
          {preferences.notifications_monthly_overview && (
            <div className="border-t border-border">
              <div className="grid grid-cols-2 divide-x divide-border sm:grid-cols-4">
                <SmallStat label="This month" value={`${formatCurrency(monthTotals.pnl)}`} tone={monthTotals.pnl >= 0 ? 'pos' : 'neg'} />
                <SmallStat label="Trades" value={String(month.trades)} />
                <SmallStat label="Winning days" value={String(month.winningDays)} />
                <SmallStat label="Win rate" value={month.trades > 0 ? formatPercent(monthWinRate) : '—'} />
              </div>
              <div className="px-4 pb-3">
                <div className="h-1 w-full overflow-hidden rounded-full bg-surface-light">
                  <div
                    className={cn(
                      'h-1 rounded-full transition-all',
                      monthTotals.pnl >= 0 ? 'bg-success' : 'bg-danger'
                    )}
                    style={{ width: `${Math.max(0, Math.min(100, monthWinRate))}%` }}
                  />
                </div>
              </div>
            </div>
          )}
        </section>

        <section className="panel flex flex-col overflow-hidden">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Time edge</p>
              <p className="mt-1 text-sm font-medium text-white">When you win</p>
            </div>
            <Link href="/dashboard/analytics" className="flex items-center gap-1 text-xs font-medium text-primary hover:text-primary-light">
              Report <ArrowUpRight className="h-3 w-3" />
            </Link>
          </div>

          <div className="divide-y divide-border px-4">
            <EdgeRow label="Most profitable hour" period={edge.bestHour} tone="pos" />
            <EdgeRow label="Most losses" period={edge.worstHour} tone="neg" />
            <EdgeRow label="Best session" period={edge.bestSession} tone="pos" />
            <EdgeRow label="Weakest session" period={edge.worstSession} tone="neg" />
          </div>

          {/* The same four UTC buckets everywhere: chart shading, journal
              filter, analytics table and here. */}
          <div className="border-t border-border px-4 py-3">
            <p className="eyebrow">Sessions</p>
            {sessionStats.length > 0 ? (
              <div className="mt-2 space-y-1.5">
                {sessionStats.map((row) => (
                  <div key={row.session} className="flex items-center justify-between gap-2 text-xs">
                    <span className="text-gray-400">{SESSION_LABELS[row.session] ?? row.session}</span>
                    <span className="flex items-center gap-3 tabular-nums">
                      <span className="text-gray-500">{row.trades}</span>
                      <span className={row.pnl >= 0 ? 'text-success' : 'text-danger'}>
                        {row.pnl >= 0 ? '+' : ''}{formatCurrency(row.pnl)}
                      </span>
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <p className="mt-1 text-[10px] leading-relaxed text-gray-500">
                {sessionStatsMissing
                  ? 'Session totals need the 20261105_session_stats.sql migration.'
                  : 'No timed trades yet.'}
              </p>
            )}
          </div>

          <div className="mt-auto border-t border-border p-4">
            {hasTimeSamples ? (
              <div className="h-[92px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={hourSeries} margin={{ top: 2, right: 0, left: 0, bottom: 0 }}>
                    <XAxis dataKey="key" hide />
                    <YAxis hide domain={['auto', 'auto']} />
                    <Tooltip
                      content={<ChartTooltip format={(value) => formatCurrency(value)} />}
                      cursor={{ fill: palette.grid }}
                    />
                    <Bar dataKey="pnl" name="P&L" radius={[1, 1, 0, 0]}>
                      {hourSeries.map((row) => (
                        <Cell key={row.key} fill={row.pnl >= 0 ? palette.profit : palette.loss} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            ) : (
              <p className="text-xs text-gray-500">Add entry times to trades — the report needs them.</p>
            )}
            <p className="mt-2 text-[10px] leading-relaxed text-gray-500">
              {hasTimeSamples
                ? `By entry hour in ${timeStats.timezone}; session windows use UTC. Median hold ${formatDuration(timeStats.hold.median_minutes)} across ${timeStats.hold.trades} timed trades.`
                : 'Set the time window on each trade and this becomes your session report.'}
            </p>
          </div>
        </section>
      </div>

      {/* Calendar + recent fills */}
      <div className="grid gap-4 lg:grid-cols-3 lg:gap-6">
        <section className="panel overflow-hidden lg:col-span-2">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Trading calendar</p>
              <p className="mt-1 text-sm font-medium text-white">
                {monthTotals.pnl >= 0 ? '+' : ''}{formatCurrency(monthTotals.pnl)} this month
              </p>
            </div>
            <Link href="/dashboard/calendar" className="flex items-center gap-1 text-xs font-medium text-gray-400 hover:text-white">
              Open <ArrowUpRight className="h-3 w-3" />
            </Link>
          </div>
          <div className="p-4">
            <MonthHeatmap rows={dailyPnl} />
          </div>
        </section>

        <section className="panel overflow-hidden">
          <div className="panel-head">
            <p className="eyebrow">Recent fills</p>
            <Link href="/dashboard/trades" className="flex items-center gap-1 text-xs font-medium text-gray-400 hover:text-white">
              All <ArrowUpRight className="h-3 w-3" />
            </Link>
          </div>
          {recentTrades.length > 0 ? (
            <div className="divide-y divide-border">
              {recentTrades.map((trade) => {
                const pnl = Number(trade.pnl) || 0
                return (
                  <Link
                    key={trade.id}
                    href={`/dashboard/trades/${trade.id}/edit`}
                    className="tap-row flex items-center gap-3 px-4 py-3 active:bg-surface-light"
                  >
                    <span className={cn('badge w-6 justify-center px-0', trade.type === 'BUY' ? 'badge-buy' : 'badge-sell')}>
                      {trade.type === 'BUY' ? 'B' : 'S'}
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-white">{trade.symbol}</p>
                      <p className="num text-[11px] text-gray-500">
                        {new Date(trade.created_at).toLocaleDateString(undefined, { day: '2-digit', month: 'short' })}
                      </p>
                    </div>
                    <span className={cn('num text-sm font-semibold', pnl >= 0 ? 'pos' : 'neg')}>
                      {pnl >= 0 ? '+' : ''}{formatCurrency(pnl)}
                    </span>
                  </Link>
                )
              })}
            </div>
          ) : (
            <div className="p-6 text-center">
              <p className="text-sm text-gray-400">No fills recorded</p>
              <Link href="/dashboard/trades/new" className="mt-2 inline-block text-xs font-medium text-primary hover:text-primary-light">
                Add your first trade →
              </Link>
            </div>
          )}
        </section>
      </div>

      {/* Journal + quick actions */}
      <div className="grid gap-4 lg:grid-cols-3 lg:gap-6">
        <section className="panel overflow-hidden lg:col-span-2">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Journal</p>
              <p className="mt-1 text-sm font-medium text-white">Latest entries</p>
            </div>
            <Link href="/dashboard/trades" className="flex items-center gap-1 text-xs font-medium text-gray-400 hover:text-white">
              All trades <ArrowUpRight className="h-3 w-3" />
            </Link>
          </div>

          {journalFeed.length > 0 ? (
            <div className="divide-y divide-border">
              {journalFeed.map((entry) => {
                const pnl = Number(entry.pnl) || 0
                return (
                  <Link
                    key={entry.id}
                    href={`/dashboard/trades/${entry.id}/edit`}
                    className="block px-4 py-3 transition-colors hover:bg-surface-light/60"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex min-w-0 items-center gap-2">
                        <span className={cn('badge', entry.type === 'BUY' ? 'badge-buy' : 'badge-sell')}>
                          {entry.type}
                        </span>
                        <span className="truncate text-sm font-semibold text-white">{entry.symbol}</span>
                        <span className="num hidden text-[10px] text-gray-500 sm:inline">
                          {timeOf(entry.open_time)} → {timeOf(entry.close_time)}
                        </span>
                      </div>
                      <span className={cn('num shrink-0 text-sm font-semibold', pnl >= 0 ? 'pos' : 'neg')}>
                        {pnl >= 0 ? '+' : ''}{formatCurrency(pnl)}
                      </span>
                    </div>
                    {entry.notes && (
                      <p className="mt-1.5 line-clamp-2 text-xs leading-relaxed text-gray-500">{entry.notes}</p>
                    )}
                    <div className="mt-2 flex flex-wrap items-center gap-3 text-[10px] text-gray-500">
                      {entry.image_count > 0 && (
                        <span className="inline-flex items-center gap-1">
                          <ImageIcon className="h-3 w-3" /> {entry.image_count} photo{entry.image_count === 1 ? '' : 's'}
                        </span>
                      )}
                      {entry.audio_count > 0 && (
                        <span className="inline-flex items-center gap-1">
                          <Mic className="h-3 w-3" /> {entry.audio_count} recording{entry.audio_count === 1 ? '' : 's'}
                        </span>
                      )}
                      {entry.strategy && <span className="truncate">{entry.strategy}</span>}
                      {entry.tags && entry.tags.length > 0 && (
                        <span className="truncate">#{entry.tags.slice(0, 3).join(' #')}</span>
                      )}
                    </div>
                  </Link>
                )
              })}
            </div>
          ) : (
            <div className="p-6 text-center">
              <p className="text-sm text-gray-400">Nothing journaled yet</p>
              <p className="mt-1 text-xs text-gray-500">A note, a screenshot or a voice note turns a fill into a lesson.</p>
              <Link href="/dashboard/trades/new" className="mt-2 inline-block text-xs font-medium text-primary hover:text-primary-light">
                Journal a trade →
              </Link>
            </div>
          )}
        </section>

        <section className="grid grid-cols-2 gap-3 self-start lg:grid-cols-1">
          {quickActions.map((action) => (
            <Link
              key={action.href}
              href={action.href}
              className="panel tap-card group flex items-center gap-3 p-3.5 hover:border-border-strong"
            >
              <span className="icon-tile">
                <action.icon className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium text-white">{action.label}</span>
                <span className="block truncate text-[10px] text-gray-500">{action.hint}</span>
              </span>
              <ArrowUpRight className="h-3.5 w-3.5 shrink-0 text-gray-600 transition-colors group-hover:text-primary" />
            </Link>
          ))}
        </section>
      </div>
    </div>
  )
}
