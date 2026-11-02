'use client'

import { useCallback, useEffect, useId, useMemo, useState } from 'react'
import Link from 'next/link'
import { Target, DollarSign, AlertTriangle, Clock, Sparkles, Loader2, TrendingDown, TrendingUp } from 'lucide-react'
import { formatCurrency, formatDuration, formatPercent } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { authedFetch } from '@/lib/api'
import { SetupMatrix } from '@/components/setup-matrix'
import type { CoachInsight } from '@/lib/ai/types'
import { axisProps, gridProps, useChartPalette } from '@/lib/chart-theme'
import { hourlySeries, sessionPeriod, timeEdgeReport, type EdgePeriod } from '@/lib/edge-window'
import { matchStrategyByLabel } from '@/lib/backtest/strategies'
import {
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
  Cell,
} from 'recharts'
import type {
  EquityPoint,
  SessionWindowStat,
  StrategyStat,
  SymbolStat,
  TagStat,
  TimeStats,
  TradeBreakdowns,
  TradeSummary,
} from '@/types/journal'

interface Finding {
  title: string
  detail: string
  evidence?: string
}

interface SimilarSetup {
  note: string
  outcome: number
  when?: string | null
  score?: number
}

interface AiReview {
  headline: string
  confidence: 'low' | 'medium' | 'high'
  sampleSize: number
  strengths: Finding[]
  risks: Finding[]
  actions: Finding[]
  similarSetups: SimilarSetup[]
  disclaimer: string
}

interface AiReviewMeta {
  provider?: string
  model?: string
  cached: boolean
  skipped: boolean
  generatedAt: string
}

interface AiQuota {
  allowed: boolean
  quota: number
  used: number
  remaining: number
  resetsAt: string
}

export interface AnalyticsViewProps {
  summary: TradeSummary
  equity: EquityPoint[]
  symbols: SymbolStat[]
  tagStats: TagStat[]
  breakdowns: TradeBreakdowns
  depositsTotal: number
  timeStats: TimeStats
  sessionStats: SessionWindowStat[]
  /** True when `session_stats` is missing from the database. */
  sessionStatsMissing: boolean
  strategyStats: StrategyStat[]
  /** True when `strategy_stats` is missing from the database. */
  strategyStatsMissing: boolean
}

/** Display names for the four UTC windows the filter and the RPC share. */
const SESSION_LABELS: Record<string, string> = {
  asian: 'Asian',
  london: 'London',
  newyork: 'New York',
  sydney: 'Sydney',
}

function EdgeCard({
  title,
  period,
  tone,
  icon: Icon,
}: {
  title: string
  period: EdgePeriod | null
  tone: 'pos' | 'neg'
  icon: typeof TrendingUp
}) {
  return (
    <div className={cnEdge(tone)}>
      <div className="flex items-center justify-between gap-2">
        <p className="text-[11px] uppercase tracking-wide text-gray-500">{title}</p>
        <Icon className={`h-4 w-4 ${tone === 'pos' ? 'text-success' : 'text-danger'}`} />
      </div>
      <p className="mt-2 truncate text-sm font-semibold text-white">
        {period ? period.label : 'Not enough data'}
      </p>
      <p className={`num mt-1 text-lg font-semibold ${period ? (tone === 'pos' ? 'text-success' : 'text-danger') : 'text-gray-600'}`}>
        {period ? `${period.pnl >= 0 ? '+' : ''}${formatCurrency(period.pnl)}` : '—'}
      </p>
      <p className="mt-1 text-[10px] leading-relaxed text-gray-500">
        {period ? `${period.trades} trades · ${formatPercent(period.winRate)} win rate` : 'Needs 3+ trades in the same window'}
      </p>
    </div>
  )
}

function cnEdge(tone: 'pos' | 'neg'): string {
  return `rounded-lg border p-3 ${
    tone === 'pos' ? 'border-success/25 bg-success/5' : 'border-danger/25 bg-danger/5'
  }`
}

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ color: string; name: string; value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-surface-light border border-border rounded-lg p-3 shadow-lg">
      <p className="text-gray-400 text-xs mb-1">{label}</p>
      {payload.map((p, i) => (
        <p key={i} className="text-sm font-medium" style={{ color: p.color }}>
          {p.name}: {typeof p.value === 'number' ? formatCurrency(p.value) : p.value}
        </p>
      ))}
    </div>
  )
}

export function AnalyticsView({ summary, equity, symbols, tagStats, breakdowns, depositsTotal, timeStats, sessionStats, sessionStatsMissing, strategyStats, strategyStatsMissing }: AnalyticsViewProps) {
  const palette = useChartPalette()
  // Unique per instance, and identical across the server render and the
  // hydrating client. A fixed id collides whenever two of these charts are
  // mounted at once: `url(#eqFill)` in the second chart resolves to the first
  // chart's gradient, which silently paints it in the wrong direction or
  // colour. Colons are stripped because they are legal in an id but awkward
  // inside an SVG `url(#…)` reference.
  const eqFillId = `eqFill-${useId().replace(/:/g, '')}`
  const [aiReview, setAiReview] = useState<AiReview | null>(null)
  const [aiMeta, setAiMeta] = useState<AiReviewMeta | null>(null)
  const [aiLoading, setAiLoading] = useState(false)
  const [aiError, setAiError] = useState('')
  const [aiQuota, setAiQuota] = useState<AiQuota | null>(null)
  const [aiInsights, setAiInsights] = useState<CoachInsight[]>([])

  // The allowance is shown before it runs out, not discovered at the wall.
  // A failed fetch leaves the badge hidden; the review route still enforces.
  const loadAiQuota = useCallback(async () => {
    try {
      const response = await authedFetch('/api/ai/review/quota')
      if (!response.ok) return
      setAiQuota((await response.json()) as AiQuota)
    } catch {
      // Optional badge; nothing to show if it cannot be read.
    }
  }, [])

  useEffect(() => {
    let active = true
    authedFetch('/api/ai/review/quota')
      .then(async (response) => (response.ok ? ((await response.json()) as AiQuota) : null))
      .then((quota) => {
        if (active && quota) setAiQuota(quota)
      })
      .catch(() => {
        // Optional badge; the review route still enforces the limit.
      })
    return () => {
      active = false
    }
  }, [])

  const totalTrades = Number(summary.total_trades) || 0
  const wins = Number(summary.wins) || 0
  const losses = Number(summary.losses) || 0
  const winRate = totalTrades > 0 ? (wins / totalTrades) * 100 : 0
  const totalPnl = Number(summary.total_pnl) || 0
  const grossWins = Number(summary.gross_profit) || 0
  const grossLosses = Number(summary.gross_loss) || 0
  const profitFactor = grossLosses > 0 ? grossWins / grossLosses : 0
  const avgWin = wins > 0 ? grossWins / wins : 0
  const avgLoss = losses > 0 ? -grossLosses / losses : 0
  const largestWin = Number(summary.best_trade) || 0
  const largestLoss = Number(summary.worst_trade) || 0
  const expectancy = totalTrades > 0 ? totalPnl / totalTrades : 0

  const equityData = useMemo(
    () =>
      equity.map((point) => ({
        day: point.day,
        balance: parseFloat((depositsTotal + Number(point.cumulative || 0)).toFixed(2)),
      })),
    [equity, depositsTotal]
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

  const edge = useMemo(() => timeEdgeReport(timeStats, 3), [timeStats])
  const hourChart = useMemo(() => hourlySeries(timeStats), [timeStats])
  const sessionRows = useMemo(() => (timeStats.sessions ?? []).map(sessionPeriod), [timeStats.sessions])
  const hasTimeSamples = hourChart.some((row) => row.trades > 0)

  const symbolData = useMemo(
    () =>
      symbols.map((item) => ({
        symbol: item.symbol,
        trades: Number(item.trades) || 0,
        pnl: Number(item.pnl) || 0,
        winRate: Number(item.trades) > 0 ? (Number(item.wins) / Number(item.trades)) * 100 : 0,
      })),
    [symbols]
  )

  const tagData = useMemo(
    () =>
      tagStats.map((item) => ({
        tag: item.tag,
        trades: Number(item.trades) || 0,
        pnl: Number(item.pnl) || 0,
        winRate: Number(item.win_rate) || 0,
      })),
    [tagStats]
  )

  const strategyData = useMemo(
    () =>
      strategyStats.map((item) => {
        const strategy = item.strategy?.trim() || 'Untagged'
        // Only link a label the backtester can actually recognise; an unmatched
        // one stays plain text rather than opening a form with the wrong rules.
        const matched = matchStrategyByLabel(strategy)
        return {
          strategy,
          backtestHref: matched
            ? `/dashboard/backtest?strategy=${encodeURIComponent(strategy)}`
            : null,
          trades: Number(item.trades) || 0,
          pnl: Number(item.pnl) || 0,
          winRate:
            Number(item.trades) > 0
              ? (Number(item.wins) / Number(item.trades)) * 100
              : Number(item.win_rate) || 0,
        }
      }),
    [strategyStats]
  )

  const dayData = useMemo(() => {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    const byName = new Map(breakdowns.weekdays.map((row) => [names[row.dow], row]))
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'].map((day) => {
      const row = byName.get(day)
      return {
        day,
        wins: Number(row?.wins ?? 0),
        losses: Number(row?.losses ?? 0),
        pnl: parseFloat((Number(row?.pnl ?? 0)).toFixed(2)),
      }
    })
  }, [breakdowns.weekdays])

  const monthlyData = useMemo(
    () =>
      breakdowns.months
        .slice(-12)
        .map((row) => ({ month: row.month, pnl: parseFloat((Number(row.pnl) || 0).toFixed(2)) })),
    [breakdowns.months]
  )

  const handleAiReview = async () => {
    setAiLoading(true)
    setAiError('')
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) {
      setAiError('Please log in again to request an AI review.')
      setAiLoading(false)
      return
    }

    try {
      const response = await fetch('/api/ai/review', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          totalTrades,
          wins,
          losses,
          winRate: Number(winRate.toFixed(2)),
          totalPnl: Number(totalPnl.toFixed(2)),
          profitFactor: Number(profitFactor.toFixed(2)),
          maxDrawdown: Number(maxDrawdown.toFixed(2)),
          expectancy: Number(expectancy.toFixed(2)),
          avgWin: Number(avgWin.toFixed(2)),
          avgLoss: Number(avgLoss.toFixed(2)),
          symbols: symbolData.slice(0, 20),
          weekdays: dayData,
          months: monthlyData,
          // The route loads the note-bearing trades itself; sending the whole
          // journal from the browser was the largest request in the app.
        }),
      })
      const data = await response.json() as {
        review?: AiReview
        meta?: AiReviewMeta
        insights?: CoachInsight[]
        error?: string
      }
      if (!response.ok) {
        setAiError(data.error || 'Could not generate an AI review.')
      } else {
        setAiReview(data.review || null)
        setAiMeta(data.meta || null)
        setAiInsights(Array.isArray(data.insights) ? data.insights : [])
        void loadAiQuota()
      }
    } catch {
      setAiError('Could not generate an AI review.')
    }
    setAiLoading(false)
  }

  const renderFindings = (label: string, items: Finding[], color: string) =>
    items.length > 0 ? (
      <div>
        <p className={`text-xs font-semibold uppercase tracking-wide ${color}`}>{label}</p>
        <ul className="mt-2 space-y-2">
          {items.map((finding, index) => (
            <li key={index} className="text-sm">
              <span className="text-white font-medium">{finding.title}</span>
              <span className="text-gray-400"> — {finding.detail}</span>
              {finding.evidence && (
                <span className="block text-xs text-gray-500 mt-0.5">evidence: {finding.evidence}</span>
              )}
            </li>
          ))}
        </ul>
      </div>
    ) : null

  const confidenceClass = aiReview?.confidence === 'high'
    ? 'bg-success/20 text-success'
    : aiReview?.confidence === 'medium'
    ? 'bg-primary/20 text-primary'
    : 'bg-warning/20 text-warning'

  return (
    <div className="space-y-4 lg:space-y-6">
      <div>
        <h1 className="text-xl font-bold text-white lg:text-2xl">Analytics</h1>
        <p className="text-gray-400 text-sm mt-1">Your real trading performance</p>
      </div>

      <SetupMatrix tagStats={tagStats} strategyStats={strategyStats} />

      <div className="bg-surface border border-primary/40 rounded-xl p-4 sm:p-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <Sparkles className="w-5 h-5 text-primary" />
              <h2 className="text-lg font-semibold text-white">AI Trading Review</h2>
            </div>
            <p className="text-sm text-gray-400 mt-1">Get educational feedback based on your journal statistics.</p>
            {aiQuota && (
              <p
                className={`mt-2 inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${
                  aiQuota.allowed && aiQuota.remaining > 0
                    ? 'border-border bg-surface-light text-gray-300'
                    : 'border-warning/30 bg-warning/10 text-warning'
                }`}
              >
                {aiQuota.allowed
                  ? aiQuota.remaining > 0
                    ? `${aiQuota.remaining} of ${aiQuota.quota} AI reviews left this month`
                    : `No AI reviews left — resets ${new Date(aiQuota.resetsAt).toLocaleDateString()}`
                  : 'AI reviews are not included in your plan'}
              </p>
            )}
          </div>
          <button
            onClick={handleAiReview}
            disabled={
              aiLoading ||
              totalTrades === 0 ||
              (aiQuota ? !aiQuota.allowed || aiQuota.remaining <= 0 : false)
            }
            className="flex items-center justify-center gap-2 px-4 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors disabled:opacity-50"
          >
            {aiLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Sparkles className="w-4 h-4" />}
            {aiLoading ? 'Reviewing...' : 'Review My Journal'}
          </button>
        </div>
        {aiError && <p className="mt-4 text-sm text-warning bg-warning/10 border border-warning/30 rounded-lg p-3">{aiError}</p>}
        {aiReview && (
          <div className="mt-5 pt-5 border-t border-border space-y-4">
            <div className="flex items-center gap-2 flex-wrap">
              <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${confidenceClass}`}>
                {aiReview.confidence} confidence
              </span>
              <span className="text-xs text-gray-500">{aiReview.sampleSize} trades analysed</span>
              {aiMeta?.cached && aiMeta.generatedAt && (
                <span className="text-xs text-gray-500">saved {new Date(aiMeta.generatedAt).toLocaleDateString()}</span>
              )}
            </div>
            <p className="text-sm text-white font-medium">{aiReview.headline}</p>
            {aiInsights.length > 0 && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-primary">
                  Execution patterns
                </p>
                <ul className="mt-2 space-y-1.5">
                  {aiInsights.map((insight) => (
                    <li
                      key={`${insight.dimension}:${insight.label}`}
                      className="flex items-start gap-2 text-sm"
                    >
                      <span
                        className={`mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full ${
                          insight.tone === 'risk' ? 'bg-danger' : 'bg-success'
                        }`}
                      />
                      <span className="text-gray-300">{insight.summary}</span>
                    </li>
                  ))}
                </ul>
                <p className="mt-2 text-[11px] text-gray-500">
                  Measured from your own trades; each pattern needs at least six trades in the group.
                </p>
              </div>
            )}
            {renderFindings('Strengths', aiReview.strengths, 'text-success')}
            {renderFindings('Risks', aiReview.risks, 'text-warning')}
            {renderFindings('Actions', aiReview.actions, 'text-primary')}
            {aiReview.similarSetups.length > 0 && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">From your notes</p>
                <ul className="mt-2 space-y-2">
                  {aiReview.similarSetups.map((setup, index) => (
                    <li key={index} className="text-sm text-gray-400">
                      <span className={setup.outcome >= 0 ? 'text-success' : 'text-danger'}>
                        {setup.outcome >= 0 ? '+' : ''}{formatCurrency(setup.outcome)}
                      </span>{' '}
                      {setup.note}
                      {setup.when && <span className="text-xs text-gray-500"> ({setup.when.slice(0, 10)})</span>}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <p className="text-xs text-gray-500">{aiReview.disclaimer}</p>
          </div>
        )}
        <p className="text-xs text-gray-500 mt-4">AI feedback is educational and is not financial advice.</p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-6">
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <DollarSign className="w-4 h-4" />
            Total P&L
          </div>
          <div className={`text-2xl font-bold ${totalPnl >= 0 ? 'text-success' : 'text-danger'}`}>{formatCurrency(totalPnl)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <Target className="w-4 h-4" />
            Win Rate
          </div>
          <div className="text-2xl font-bold text-white">{formatPercent(winRate)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <DollarSign className="w-4 h-4" />
            Profit Factor
          </div>
          <div className="text-2xl font-bold text-white">{profitFactor.toFixed(2)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <AlertTriangle className="w-4 h-4" />
            Max Drawdown
          </div>
          <div className="text-2xl font-bold text-warning">{maxDrawdown.toFixed(1)}%</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <DollarSign className="w-4 h-4" />
            Expectancy
          </div>
          <div className={`text-2xl font-bold ${expectancy >= 0 ? 'text-success' : 'text-danger'}`}>{formatCurrency(expectancy)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <Clock className="w-4 h-4" />
            Total Trades
          </div>
          <div className="text-2xl font-bold text-white">{totalTrades}</div>
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold text-white">Time edge</h2>
            <p className="mt-1 text-sm text-gray-400">
              Which windows pay and which bleed — entry hours in {timeStats.timezone}, sessions in UTC market hours.
            </p>
          </div>
          <span className="chip">
            <Clock className="h-3.5 w-3.5" />
            Median hold {formatDuration(timeStats.hold.median_minutes)}
          </span>
        </div>

        {hasTimeSamples ? (
          <>
            <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
              <EdgeCard title="Most profitable hour" period={edge.bestHour} tone="pos" icon={TrendingUp} />
              <EdgeCard title="Most losses" period={edge.worstHour} tone="neg" icon={TrendingDown} />
              <EdgeCard title="Best session" period={edge.bestSession} tone="pos" icon={TrendingUp} />
              <EdgeCard title="Weakest session" period={edge.worstSession} tone="neg" icon={TrendingDown} />
            </div>

            <div className="mt-5 h-[220px] w-full">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={hourChart} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                  <CartesianGrid {...gridProps(palette)} />
                  <XAxis
                    {...axisProps(palette)}
                    dataKey="label"
                    interval={2}
                    tickFormatter={(value: string) => value.slice(0, 2)}
                  />
                  <YAxis
                    {...axisProps(palette)}
                    width={58}
                    tickFormatter={(value: number) => `$${Math.round(value).toLocaleString('en-US')}`}
                  />
                  <Tooltip content={<CustomTooltip />} cursor={{ fill: palette.grid }} />
                  <Bar dataKey="pnl" name="P&L" radius={[2, 2, 0, 0]} maxBarSize={22}>
                    {hourChart.map((row) => (
                      <Cell key={row.key} fill={row.pnl >= 0 ? palette.profit : palette.loss} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="mt-5 overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-border">
                    <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Session</th>
                    <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Trades</th>
                    <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Win rate</th>
                    <th className="px-3 py-2 text-right text-xs font-medium uppercase text-gray-400">Net P&amp;L</th>
                  </tr>
                </thead>
                <tbody>
                  {sessionRows.map((row) => {
                    const isBest = edge.bestSession?.key === row.key
                    const isWorst = edge.worstSession?.key === row.key
                    return (
                      <tr key={row.key} className="border-b border-border/60 last:border-0">
                        <td className="px-3 py-2.5 text-sm text-white">
                          <span className="inline-flex items-center gap-2">
                            {row.label}
                            {isBest && <span className="badge badge-buy">best</span>}
                            {isWorst && <span className="badge badge-sell">weakest</span>}
                          </span>
                        </td>
                        <td className="px-3 py-2.5 text-sm text-gray-300">{row.trades}</td>
                        <td className="px-3 py-2.5 text-sm text-gray-300">{formatPercent(row.winRate)}</td>
                        <td className={`px-3 py-2.5 text-right text-sm font-medium tabular-nums ${row.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                          {row.pnl >= 0 ? '+' : ''}{formatCurrency(row.pnl)}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>

            <p className="mt-3 text-[10px] leading-relaxed text-gray-500">
              Windows with fewer than {edge.minTrades} trades are left out of the best/worst calls. Hours are
              local entry time; session rows use UTC. The hold figure uses trades that carry both an open and a close time.
            </p>
          </>
        ) : (
          <p className="mt-4 rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-gray-500">
            Add the entry and exit time when you journal a trade. The hour-by-hour report builds itself from
            those fields.
          </p>
        )}
      </div>

      <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-lg font-semibold text-white">Sessions</h2>
          <p className="text-xs text-gray-500">UTC windows — the same buckets the journal filters by</p>
        </div>
        {sessionStats.length > 0 ? (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Session</th>
                  <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Trades</th>
                  <th className="px-3 py-2 text-left text-xs font-medium uppercase text-gray-400">Win rate</th>
                  <th className="px-3 py-2 text-right text-xs font-medium uppercase text-gray-400">Net P&amp;L</th>
                </tr>
              </thead>
              <tbody>
                {sessionStats.map((row) => (
                  <tr key={row.session} className="border-b border-border/60 last:border-0">
                    <td className="px-3 py-2.5 text-sm text-white">
                      <span className="inline-flex items-center gap-2">
                        {SESSION_LABELS[row.session] ?? row.session}
                        {row.pnl > 0 && <span className="badge badge-buy">best</span>}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 text-sm text-gray-300">{row.trades}</td>
                    <td className="px-3 py-2.5 text-sm text-gray-300">
                      {formatPercent(row.trades > 0 ? (row.wins / row.trades) * 100 : 0)}
                    </td>
                    <td className={`px-3 py-2.5 text-right text-sm font-medium tabular-nums ${row.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                      {row.pnl >= 0 ? '+' : ''}{formatCurrency(row.pnl)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="mt-3 text-[10px] leading-relaxed text-gray-500">
              A trade opened in the London/New York overlap is counted in both rows, exactly as it is when
              you filter by either session. Trades with no entry time cannot be placed and are left out.
            </p>
          </div>
        ) : (
          <p className="mt-4 rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-gray-500">
            {sessionStatsMissing
              ? 'Session totals are unavailable: this database is missing session_stats(). Apply supabase/migrations/20261105_session_stats.sql.'
              : 'No timed trades yet — sessions are built from the entry time on each trade.'}
          </p>
        )}
      </div>

      <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Equity Curve</h2>
        {equityData.length > 0 ? (
          <div className="h-[230px] w-full sm:h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={equityData}>
              <defs>
                <linearGradient id={eqFillId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={totalPnl >= 0 ? palette.profit : palette.loss} stopOpacity={0.3} />
                  <stop offset="95%" stopColor={totalPnl >= 0 ? palette.profit : palette.loss} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid {...gridProps(palette)} />
              <XAxis {...axisProps(palette)} dataKey="day" tickFormatter={(value: string) => value.slice(5)} />
              <YAxis {...axisProps(palette)} tickFormatter={(v) => `$${v}`} />
              <Tooltip content={<CustomTooltip />} cursor={{ fill: palette.grid }} />
              <Area type="monotone" dataKey="balance" stroke={totalPnl >= 0 ? palette.profit : palette.loss} fill={`url(#${eqFillId})`} strokeWidth={2} name="Balance" />
            </AreaChart>
          </ResponsiveContainer>
          </div>
        ) : (
          <p className="text-gray-500 text-sm">No trades to display.</p>
        )}
      </div>

      <div className="grid gap-4 lg:grid-cols-2 lg:gap-6">
        <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Performance Summary</h2>
          <div className="space-y-3">
            {[
              { label: 'Total Trades', value: totalTrades },
              { label: 'Wins / Losses', value: `${wins} / ${losses}` },
              { label: 'Avg Win', value: formatCurrency(avgWin), color: 'text-success' },
              { label: 'Avg Loss', value: formatCurrency(avgLoss), color: 'text-danger' },
              { label: 'Largest Win', value: formatCurrency(largestWin), color: 'text-success' },
              { label: 'Largest Loss', value: formatCurrency(largestLoss), color: 'text-danger' },
            ].map((item) => (
              <div key={item.label} className="flex justify-between py-2 border-b border-border last:border-0">
                <span className="text-gray-400">{item.label}</span>
                <span className={`font-medium ${item.color || 'text-white'}`}>{item.value}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
          <h2 className="text-lg font-semibold text-white mb-4">P&L by Day</h2>
          {dayData.some(d => d.wins + d.losses > 0) ? (
            <div className="h-[220px] w-full sm:h-[250px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={dayData}>
                <CartesianGrid {...gridProps(palette)} />
                <XAxis {...axisProps(palette)} dataKey="day" />
                <YAxis {...axisProps(palette)} tickFormatter={(v) => `$${v}`} />
                <Tooltip content={<CustomTooltip />} />
                <Bar dataKey="pnl" name="P&L" radius={[4, 4, 0, 0]}>
                  {dayData.map((entry, index) => (
                    <Cell key={index} fill={entry.pnl >= 0 ? palette.profit : palette.loss} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
            </div>
          ) : (
            <p className="text-gray-500 text-sm">No day-of-week data yet.</p>
          )}
        </div>
      </div>

      {monthlyData.length > 0 && (
        <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Monthly P&L</h2>
          <div className="h-[220px] w-full sm:h-[250px]">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={monthlyData}>
              <CartesianGrid {...gridProps(palette)} />
              <XAxis {...axisProps(palette)} dataKey="month" />
              <YAxis {...axisProps(palette)} tickFormatter={(v) => `$${v}`} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="pnl" name="P&L" radius={[4, 4, 0, 0]}>
                {monthlyData.map((entry, index) => (
                  <Cell key={index} fill={entry.pnl >= 0 ? palette.profit : palette.loss} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
          </div>
        </div>
      )}

      <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Performance by Symbol</h2>
        {symbolData.length > 0 ? (
          <>
          <div className="space-y-2 lg:hidden">
            {symbolData.map((item) => (
              <div key={item.symbol} className="flex items-center justify-between rounded-xl border border-border bg-surface-light/60 px-4 py-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-white">{item.symbol}</p>
                  <p className="text-xs text-gray-500">
                    {item.trades} trades · {formatPercent(item.winRate)} win rate
                  </p>
                </div>
                <span className={`shrink-0 pl-3 text-sm font-semibold tabular-nums ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                  {formatCurrency(item.pnl)}
                </span>
              </div>
            ))}
          </div>
          <div className="hidden overflow-x-auto lg:block">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Symbol</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Trades</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Win Rate</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">P&L</th>
                </tr>
              </thead>
              <tbody>
                {symbolData.map((item) => (
                  <tr key={item.symbol} className="border-b border-border last:border-0">
                    <td className="px-4 py-3 text-sm font-medium text-white">{item.symbol}</td>
                    <td className="px-4 py-3 text-sm text-gray-300">{item.trades}</td>
                    <td className="px-4 py-3 text-sm text-gray-300">{formatPercent(item.winRate)}</td>
                    <td className={`px-4 py-3 text-sm font-medium ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                      {formatCurrency(item.pnl)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          </>
        ) : (
          <p className="text-gray-500 text-sm">No trades imported yet.</p>
        )}
      </div>

      <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
        <div className="mb-4 flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-lg font-semibold text-white">Performance by Tag</h2>
          <p className="text-xs text-gray-500">Ranked by net P&amp;L</p>
        </div>
        {tagData.length > 0 ? (
          <>
          <div className="space-y-2 lg:hidden">
            {tagData.map((item) => (
              <div key={item.tag} className="flex items-center justify-between rounded-xl border border-border bg-surface-light/60 px-4 py-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-white">{item.tag}</p>
                  <p className="text-xs text-gray-500">
                    {item.trades} trades · {formatPercent(item.winRate)} win rate
                  </p>
                </div>
                <span className={`shrink-0 pl-3 text-sm font-semibold tabular-nums ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                  {formatCurrency(item.pnl)}
                </span>
              </div>
            ))}
          </div>
          <div className="hidden overflow-x-auto lg:block">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Tag</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Trades</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Win Rate</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">P&L</th>
                </tr>
              </thead>
              <tbody>
                {tagData.map((item) => (
                  <tr key={item.tag} className="border-b border-border last:border-0">
                    <td className="px-4 py-3">
                      <span className="chip">{item.tag}</span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-300">{item.trades}</td>
                    <td className="px-4 py-3 text-sm text-gray-300">{formatPercent(item.winRate)}</td>
                    <td className={`px-4 py-3 text-sm font-medium ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                      {formatCurrency(item.pnl)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          </>
        ) : (
          <p className="text-gray-500 text-sm">
            No tagged trades yet. Add tags when logging a trade — the review reads them, and this table shows
            which setups actually pay.
          </p>
        )}
      </div>

      <div className="bg-surface border border-border rounded-xl p-4 sm:p-6">
        <div className="mb-4 flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-lg font-semibold text-white">Performance by Strategy</h2>
          <p className="text-xs text-gray-500">The label you typed on each trade</p>
        </div>
        {strategyData.length > 0 ? (
          <>
          <div className="space-y-2 lg:hidden">
            {strategyData.map((item) => (
              <div key={item.strategy} className="flex items-center justify-between rounded-xl border border-border bg-surface-light/60 px-4 py-3">
                <div className="min-w-0">
                  {item.backtestHref ? (
                    <Link
                      href={item.backtestHref}
                      className="block truncate text-sm font-semibold text-white hover:text-primary hover:underline"
                    >
                      {item.strategy}
                    </Link>
                  ) : (
                    <p className="truncate text-sm font-semibold text-white">{item.strategy}</p>
                  )}
                  <p className="text-xs text-gray-500">
                    {item.trades} trades · {formatPercent(item.winRate)} win rate
                  </p>
                </div>
                <span className={`shrink-0 pl-3 text-sm font-semibold tabular-nums ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                  {formatCurrency(item.pnl)}
                </span>
              </div>
            ))}
          </div>
          <div className="hidden overflow-x-auto lg:block">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Strategy</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Trades</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Win Rate</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">P&amp;L</th>
                </tr>
              </thead>
              <tbody>
                {strategyData.map((item) => (
                  <tr key={item.strategy} className="border-b border-border last:border-0">
                    <td className="px-4 py-3 text-sm font-medium text-white">
                      {item.backtestHref ? (
                        <Link
                          href={item.backtestHref}
                          className="hover:text-primary hover:underline"
                        >
                          {item.strategy}
                        </Link>
                      ) : (
                        item.strategy
                      )}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-300">{item.trades}</td>
                    <td className="px-4 py-3 text-sm text-gray-300">{formatPercent(item.winRate)}</td>
                    <td className={`px-4 py-3 text-sm font-medium ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                      {formatCurrency(item.pnl)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-3 text-[10px] leading-relaxed text-gray-500">
            Rows match the label exactly (trimmed of spaces), so “SMA cross” and “sma cross” count as two
            strategies. Blank labels are grouped as Untagged. A name the backtester recognises opens it
            with its rules pre-selected; the rest stay plain text.
          </p>
          </>
        ) : (
          <p className="text-gray-500 text-sm">
            {strategyStatsMissing
              ? 'Strategy totals are unavailable: this database is missing strategy_stats(). Apply supabase/migrations/20261107_strategy_stats.sql.'
              : 'No trades yet — the strategy field on the journal form is what fills this table.'}
          </p>
        )}
      </div>
    </div>
  )
}
