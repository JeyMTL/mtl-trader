'use client'

import { Suspense, useCallback, useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import {
  AlertTriangle,
  FlaskConical,
  Info,
  Loader2,
  Play,
  Trash2,
  Upload,
} from 'lucide-react'
import { authedFetch } from '@/lib/api'
import { useToast } from '@/components/toast'
import BacktestJournal from '@/components/backtest-journal'
import BacktestSuggest, { type AppliedSuggestion } from '@/components/backtest-suggest'
import { STRATEGIES, matchStrategyByLabel } from '@/lib/backtest/strategies'
import type { Benchmark } from '@/lib/backtest/benchmark'
import type { Metrics } from '@/lib/backtest/metrics'
import type { StressSummary } from '@/lib/backtest/stress'
import type { Trade } from '@/lib/backtest/types'

/**
 * Backtest workbench.
 *
 * The form collects exactly what the engine needs and nothing else, and the
 * report prints the assumptions next to the numbers — a curve without its fill
 * rules is a number with no context. Runs are executed server-side, so the
 * numbers here come from one deterministic implementation.
 */

interface EquityPoint {
  time: number
  equity: number
  balance: number
}

interface Report {
  symbol: string
  timeframe: string
  strategy: { id: string; name: string; params: Record<string, number> }
  barCount: number
  from: number
  to: number
  metrics: Metrics
  split: { ratio: number; inSample: Metrics; outOfSample: Metrics } | null
  benchmark: Benchmark | null
  stress: StressSummary | null
  trades: Trade[]
  equityCurve: EquityPoint[]
  assumptions: string[]
  warnings: string[]
}

interface RunSummary {
  id: string
  name: string
  symbol: string
  timeframe: string
  strategy_id: string
  strategy_params: Record<string, number>
  metrics: Metrics
  bar_count: number
  period_start: string
  period_end: string
  created_at: string
}

interface SavedRunRow extends RunSummary {
  trades?: Trade[]
  equity_curve?: EquityPoint[]
  assumptions?: string[]
  warnings?: string[]
  split_metrics?: Report['split']
  benchmark?: Report['benchmark']
  stress?: Report['stress']
}

const defaultStrategy = STRATEGIES[0]!

function defaultsFor(id: string): Record<string, number> {
  const definition = STRATEGIES.find((strategy) => strategy.id === id) ?? defaultStrategy
  return Object.fromEntries(
    definition.params.map((spec) => [spec.key, spec.defaultValue])
  )
}

function money(value: number): string {
  const sign = value > 0 ? '+' : value < 0 ? '−' : ''
  return `${sign}$${Math.abs(value).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}

function pct(value: number, digits = 1): string {
  return `${value.toFixed(digits)}%`
}

function ratio(value: number | null): string {
  if (value === null) return '∞'
  return value.toFixed(2)
}

function day(iso: number | string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return '—'
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

/**
 * The page is statically rendered, and `useSearchParams` opts a subtree into
 * client rendering, so the workbench sits behind the boundary Next requires.
 * Kept here rather than in a second file because the fallback is the same shell.
 */
export default function BacktestPage() {
  return (
    <Suspense
      fallback={
        <div className="mx-auto max-w-6xl">
          <div className="h-8 w-40 animate-pulse rounded-lg bg-surface" />
        </div>
      }
    >
      <BacktestWorkbench />
    </Suspense>
  )
}

function BacktestWorkbench() {
  const { toast } = useToast()

  /**
   * A link from the analytics strategy table arrives as `?strategy=<label>`.
   * It is resolved through the same matcher that decided to render the link, so
   * an unrecognised label falls back to the default rules instead of guessing.
   * Read during the first render, not in an effect: the initial state should be
   * the linked strategy, not the default followed by a visible correction.
   */
  const searchParams = useSearchParams()
  const requestedStrategy = searchParams.get('strategy')
  const deepLinked = useMemo(() => {
    if (!requestedStrategy) return null
    const matched = matchStrategyByLabel(requestedStrategy)
    if (!matched) return null
    return {
      id: matched.id,
      params: defaultsFor(matched.id),
      name: requestedStrategy.slice(0, 60),
    }
  }, [requestedStrategy])

  const [strategyId, setStrategyId] = useState<string>(deepLinked?.id ?? defaultStrategy.id)
  const [params, setParams] = useState<Record<string, number>>(
    () => deepLinked?.params ?? defaultsFor(defaultStrategy.id)
  )
  const [symbol, setSymbol] = useState('EURUSD')
  const [timeframe, setTimeframe] = useState('M1')
  const [name, setName] = useState(deepLinked?.name ?? '')
  const [csv, setCsv] = useState('')
  const [fileName, setFileName] = useState('')
  const [initialBalance, setInitialBalance] = useState(10_000)
  const [riskPercent, setRiskPercent] = useState(1)
  const [contractSize, setContractSize] = useState(100_000)
  const [maxLeverage, setMaxLeverage] = useState(30)
  const [spread, setSpread] = useState(0.0002)
  const [slippage, setSlippage] = useState(0)
  const [commission, setCommission] = useState(7)
  const [splitRatio, setSplitRatio] = useState(0.7)
  const [timezoneOffsetMinutes, setTimezoneOffsetMinutes] = useState(0)

  const [report, setReport] = useState<Report | null>(null)
  const [runs, setRuns] = useState<RunSummary[]>([])
  const [busy, setBusy] = useState(false)
  const [loadingRuns, setLoadingRuns] = useState(true)

  const definition = useMemo(
    () => STRATEGIES.find((strategy) => strategy.id === strategyId) ?? defaultStrategy,
    [strategyId]
  )

  const loadRuns = useCallback(async () => {
    try {
      const res = await authedFetch('/api/backtest')
      const data = await res.json()
      if (res.ok) setRuns((data.runs ?? []) as RunSummary[])
    } catch {
      // The workbench still works without the archive.
    } finally {
      setLoadingRuns(false)
    }
  }, [])

  useEffect(() => {
    const timer = setTimeout(() => {
      void loadRuns()
    }, 0)
    return () => clearTimeout(timer)
  }, [loadRuns])

  const chooseStrategy = (id: string) => {
    setStrategyId(id)
    setParams(defaultsFor(id))
  }

  /**
   * Fills the form from a suggestion. The server already clamped every value, so
   * this only re-derives the full parameter set — a strategy added later cannot
   * be left with a missing input just because the model did not return it.
   */
  const applySuggestion = (suggestion: AppliedSuggestion) => {
    const target = STRATEGIES.find((entry) => entry.id === suggestion.strategyId)
    if (!target) return
    const next: Record<string, number> = {}
    for (const spec of target.params) {
      const value = suggestion.params[spec.key]
      next[spec.key] = Number.isFinite(value) ? value : spec.defaultValue
    }
    setStrategyId(target.id)
    setParams(next)
    if (suggestion.symbol) setSymbol(suggestion.symbol)
    if (suggestion.timeframe) setTimeframe(suggestion.timeframe)
    toast(`Filled ${target.name} from the journal entry. Check the rules, then run.`, {
      tone: 'success',
    })
  }

  const pickFile = async (file: File | undefined) => {
    if (!file) return
    if (file.size > 4_000_000) {
      toast('That file is over 4 MB. Export a shorter range.', { tone: 'error' })
      return
    }
    const text = await file.text()
    setCsv(text)
    setFileName(file.name)
    if (!name) setName(file.name.replace(/\.[^.]+$/, '').slice(0, 60))
  }

  const run = async () => {
    if (!csv.trim()) {
      toast('Upload or paste the bar data first.', { tone: 'error' })
      return
    }

    setBusy(true)
    try {
      const res = await authedFetch('/api/backtest', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name,
          symbol,
          timeframe,
          strategyId,
          params,
          initialBalance,
          riskPercent,
          contractSize,
          maxLeverage,
          spread,
          slippage,
          commission,
          splitRatio,
          timezoneOffsetMinutes,
          csv,
        }),
      })
      const data = await res.json()
      if (!res.ok) {
        toast(data.error || 'The run could not be completed.', { tone: 'error' })
        return
      }
      setReport(data.report as Report)
      toast(
        data.saved ? 'Run complete and saved.' : 'Run complete — the archive write failed.',
        { tone: data.saved ? 'success' : 'error' }
      )
      void loadRuns()
    } catch {
      toast('Could not reach the server. Try again.', { tone: 'error' })
    } finally {
      setBusy(false)
    }
  }

  const openRun = async (id: string) => {
    try {
      const res = await authedFetch(`/api/backtest?id=${encodeURIComponent(id)}`)
      const data = await res.json()
      if (!res.ok || !data.run) {
        toast(data.error || 'Could not load that run.', { tone: 'error' })
        return
      }
      const row = data.run as SavedRunRow
      setReport({
        symbol: row.symbol,
        timeframe: row.timeframe,
        strategy: { id: row.strategy_id, name: row.strategy_id, params: row.strategy_params },
        barCount: row.bar_count,
        from: new Date(row.period_start).getTime(),
        to: new Date(row.period_end).getTime(),
        metrics: row.metrics,
        split: row.split_metrics ?? null,
        benchmark: row.benchmark ?? null,
        stress: row.stress ?? null,
        trades: row.trades ?? [],
        equityCurve: row.equity_curve ?? [],
        assumptions: row.assumptions ?? [],
        warnings: row.warnings ?? [],
      })
    } catch {
      toast('Could not load that run.', { tone: 'error' })
    }
  }

  const deleteRun = async (id: string) => {
    if (!confirm('Delete this saved run?')) return
    try {
      const res = await authedFetch(`/api/backtest?id=${encodeURIComponent(id)}`, {
        method: 'DELETE',
      })
      if (res.ok) {
        setRuns((current) => current.filter((entry) => entry.id !== id))
        toast('Run deleted.', { tone: 'success' })
      }
    } catch {
      toast('Could not delete the run.', { tone: 'error' })
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold text-white">
          <FlaskConical className="h-6 w-6 text-primary" />
          Backtest
        </h1>
        <p className="mt-1 text-gray-400">
          Replay a rule-based strategy over your own MT5 bar data, with costs and the
          fill assumptions printed on the result.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,380px)_minmax(0,1fr)]">
        {/* ---------------------------------------------------------- form */}
        <div className="space-y-4">
          <section className="rounded-xl border border-border bg-surface p-5">
            <h2 className="mb-4 text-sm font-semibold text-white">1. Bar data</h2>

            <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="csv-file">
              MT5 history export
            </label>
            <label
              htmlFor="csv-file"
              className="flex cursor-pointer items-center gap-3 rounded-lg border border-dashed border-border bg-background px-4 py-3 text-sm text-gray-400 transition-colors hover:border-primary/50 hover:text-white"
            >
              <Upload className="h-4 w-4 flex-shrink-0" />
              <span className="truncate">{fileName || 'Choose a CSV or paste below'}</span>
            </label>
            <input
              id="csv-file"
              type="file"
              accept=".csv,.txt,text/csv,text/plain"
              className="hidden"
              onChange={(event) => void pickFile(event.target.files?.[0])}
            />

            <textarea
              value={csv}
              onChange={(event) => setCsv(event.target.value)}
              rows={5}
              spellCheck={false}
              placeholder={'<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\n2026.10.01\t10:00:00\t1.1050\t1.1060\t1.1040\t1.1055'}
              className="mt-3 w-full rounded-lg border border-border bg-background px-3 py-2 font-mono text-xs text-gray-200 placeholder-gray-600 focus:border-primary focus:outline-none"
            />
            <p className="mt-2 text-xs text-gray-500">
              Up to 60,000 bars. In MT5: select the chart with Ctrl+A, copy, paste into
              a text file.
            </p>
          </section>

          <section className="rounded-xl border border-border bg-surface p-5">
            <h2 className="mb-4 text-sm font-semibold text-white">2. Strategy</h2>

            <BacktestSuggest onApply={applySuggestion} />

            <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="run-name">
              Run name
            </label>
            <input
              id="run-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="e.g. EURUSD M1 SMA cross"
              className="mb-4 w-full rounded-lg border border-border bg-background px-4 py-2.5 text-white placeholder-gray-500 focus:border-primary focus:outline-none"
            />

            <div className="mb-4 grid grid-cols-2 gap-3">
              <div>
                <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="symbol">
                  Symbol
                </label>
                <input
                  id="symbol"
                  value={symbol}
                  onChange={(event) => setSymbol(event.target.value.toUpperCase())}
                  className="w-full rounded-lg border border-border bg-background px-4 py-2.5 text-white placeholder-gray-500 focus:border-primary focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="timeframe">
                  Timeframe
                </label>
                <input
                  id="timeframe"
                  value={timeframe}
                  onChange={(event) => setTimeframe(event.target.value.toUpperCase())}
                  className="w-full rounded-lg border border-border bg-background px-4 py-2.5 text-white placeholder-gray-500 focus:border-primary focus:outline-none"
                />
              </div>
            </div>

            <label className="mb-2 block text-sm font-medium text-gray-400" htmlFor="strategy">
              Rules
            </label>
            <select
              id="strategy"
              value={strategyId}
              onChange={(event) => chooseStrategy(event.target.value)}
              className="w-full rounded-lg border border-border bg-background px-4 py-2.5 text-white focus:border-primary focus:outline-none"
            >
              {STRATEGIES.map((strategy) => (
                <option key={strategy.id} value={strategy.id}>
                  {strategy.name}
                </option>
              ))}
            </select>
            <p className="mt-2 text-xs leading-relaxed text-gray-500">
              {definition.description}
            </p>

            <div className="mt-4 grid grid-cols-2 gap-3">
              {definition.params.map((spec) => (
                <div key={spec.key}>
                  <label
                    className="mb-1 block text-xs text-gray-500"
                    htmlFor={`param-${spec.key}`}
                  >
                    {spec.label}
                  </label>
                  <input
                    id={`param-${spec.key}`}
                    type="number"
                    min={spec.min}
                    max={spec.max}
                    step={spec.step}
                    value={params[spec.key] ?? spec.defaultValue}
                    onChange={(event) =>
                      setParams((current) => ({
                        ...current,
                        [spec.key]: Number(event.target.value),
                      }))
                    }
                    className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none"
                  />
                </div>
              ))}
            </div>
          </section>

          <section className="rounded-xl border border-border bg-surface p-5">
            <h2 className="mb-4 text-sm font-semibold text-white">3. Sizing and costs</h2>

            <div className="grid grid-cols-2 gap-3">
              {(
                [
                  ['Starting balance', initialBalance, setInitialBalance, 100, 1],
                  ['Risk per trade %', riskPercent, setRiskPercent, 0.1, 0.1],
                  ['Contract size', contractSize, setContractSize, 100, 1],
                  ['Max leverage', maxLeverage, setMaxLeverage, 1, 1],
                  ['Spread (price)', spread, setSpread, 0.00001, 0.00001],
                  ['Slippage (price)', slippage, setSlippage, 0.00001, 0.00001],
                  ['Commission / trade', commission, setCommission, 0.5, 0.5],
                ] as const
              ).map(([label, value, setter, step]) => (
                <div key={label}>
                  <label className="mb-1 block text-xs text-gray-500">{label}</label>
                  <input
                    type="number"
                    min={0}
                    step={step}
                    value={value}
                    onChange={(event) => setter(Number(event.target.value))}
                    className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none"
                  />
                </div>
              ))}

              <div>
                <label className="mb-1 block text-xs text-gray-500">
                  In-sample share
                </label>
                <input
                  type="number"
                  min={0.5}
                  max={0.9}
                  step={0.05}
                  value={splitRatio}
                  onChange={(event) => setSplitRatio(Number(event.target.value))}
                  className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs text-gray-500">
                  Server clock offset (min)
                </label>
                <input
                  type="number"
                  step={30}
                  value={timezoneOffsetMinutes}
                  onChange={(event) => setTimezoneOffsetMinutes(Number(event.target.value))}
                  className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none"
                />
              </div>
            </div>

            <button
              onClick={() => void run()}
              disabled={busy}
              className="mt-5 flex w-full items-center justify-center gap-2 rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-dark disabled:opacity-50"
            >
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Play className="h-4 w-4" />}
              {busy ? 'Simulating…' : 'Run backtest'}
            </button>
          </section>
        </div>

        {/* ------------------------------------------------------- results */}
        <div className="space-y-4">
          {!report ? (
            <div className="rounded-xl border border-border bg-surface p-10 text-center">
              <FlaskConical className="mx-auto h-8 w-8 text-gray-600" />
              <p className="mt-3 text-white">No run yet</p>
              <p className="mx-auto mt-1 max-w-sm text-sm text-gray-500">
                Upload a history export, choose the rules and the cost model, and the
                report appears here with its assumptions.
              </p>
            </div>
          ) : (
            <>
              <div className="rounded-xl border border-border bg-surface p-5">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <div>
                    <h2 className="text-lg font-semibold text-white">
                      {report.symbol} · {report.strategy.name}
                    </h2>
                    <p className="text-xs text-gray-500">
                      {report.barCount.toLocaleString('en-US')} bars ·{' '}
                      {day(report.from)} → {day(report.to)} · {report.timeframe}
                    </p>
                  </div>
                  <span
                    className={`rounded-md px-2 py-1 text-xs font-semibold ${
                      report.metrics.netPnl >= 0
                        ? 'bg-green-500/10 text-green-400'
                        : 'bg-red-500/10 text-red-400'
                    }`}
                  >
                    {money(report.metrics.netPnl)}
                  </span>
                </div>

                <MetricGrid metrics={report.metrics} />
              </div>

              <BacktestJournal
                symbol={report.symbol}
                from={report.from}
                to={report.to}
              />

              {report.warnings.length > 0 && (
                <div className="space-y-2 rounded-xl border border-yellow-500/20 bg-yellow-500/10 p-4">
                  {report.warnings.map((warning) => (
                    <div key={warning} className="flex items-start gap-2">
                      <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0 text-yellow-400" />
                      <p className="text-xs leading-relaxed text-yellow-200/90">{warning}</p>
                    </div>
                  ))}
                </div>
              )}

              {report.equityCurve.length > 1 && (
                <div className="rounded-xl border border-border bg-surface p-5">
                  <h2 className="mb-3 text-sm font-semibold text-white">Equity</h2>
                  <EquityChart points={report.equityCurve} />
                </div>
              )}

              {report.split && (
                <div className="rounded-xl border border-border bg-surface p-5">
                  <h2 className="text-sm font-semibold text-white">
                    In-sample vs out-of-sample
                  </h2>
                  <p className="mb-3 mt-1 text-xs text-gray-500">
                    Two independent runs from the same balance. The second window knows
                    nothing the first produced — the closest thing to an out-of-sample
                    test one file can give you.
                  </p>
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="text-left text-xs text-gray-500">
                          <th className="pb-2 font-medium">Window</th>
                          <th className="pb-2 font-medium">Trades</th>
                          <th className="pb-2 font-medium">Net</th>
                          <th className="pb-2 font-medium">Win rate</th>
                          <th className="pb-2 font-medium">Max DD</th>
                        </tr>
                      </thead>
                      <tbody className="text-gray-300">
                        {[
                          ['In-sample', report.split.inSample],
                          ['Out-of-sample', report.split.outOfSample],
                        ].map(([label, metrics]) => {
                          const value = metrics as Metrics
                          return (
                            <tr key={label as string} className="border-t border-border">
                              <td className="py-2">{label as string}</td>
                              <td className="py-2">{value.trades}</td>
                              <td
                                className={`py-2 ${
                                  value.netPnl >= 0 ? 'text-green-400' : 'text-red-400'
                                }`}
                              >
                                {money(value.netPnl)}
                              </td>
                              <td className="py-2">{pct(value.winRate)}</td>
                              <td className="py-2">{pct(value.maxDrawdownPct)}</td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}

              <RobustnessPanel
                benchmark={report.benchmark}
                stress={report.stress}
                metrics={report.metrics}
              />

              <div className="rounded-xl border border-border bg-surface p-5">
                <h2 className="mb-3 text-sm font-semibold text-white">Assumptions</h2>
                <ul className="space-y-2">
                  {report.assumptions.map((assumption) => (
                    <li key={assumption} className="flex items-start gap-2">
                      <Info className="mt-0.5 h-3.5 w-3.5 flex-shrink-0 text-gray-500" />
                      <span className="text-xs leading-relaxed text-gray-400">
                        {assumption}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>

              {report.trades.length > 0 && (
                <div className="rounded-xl border border-border bg-surface p-5">
                  <h2 className="mb-3 text-sm font-semibold text-white">
                    Trades ({report.trades.length})
                  </h2>
                  <div className="max-h-80 overflow-auto">
                    <table className="w-full text-xs">
                      <thead className="sticky top-0 bg-surface">
                        <tr className="text-left text-gray-500">
                          <th className="pb-2 font-medium">Side</th>
                          <th className="pb-2 font-medium">Entry</th>
                          <th className="pb-2 font-medium">Exit</th>
                          <th className="pb-2 font-medium">Lots</th>
                          <th className="pb-2 font-medium">P&amp;L</th>
                          <th className="pb-2 font-medium">Why</th>
                        </tr>
                      </thead>
                      <tbody className="font-mono text-gray-300">
                        {[...report.trades]
                          .reverse()
                          .slice(0, 100)
                          .map((trade, index) => (
                            <tr
                              key={`${trade.entryTime}-${index}`}
                              className="border-t border-border"
                            >
                              <td className="py-1.5">
                                {trade.side === 'long' ? 'LONG' : 'SHORT'}
                              </td>
                              <td className="py-1.5">{day(trade.entryTime)}</td>
                              <td className="py-1.5">{day(trade.exitTime)}</td>
                              <td className="py-1.5">{trade.lots.toFixed(2)}</td>
                              <td
                                className={`py-1.5 ${
                                  trade.pnl >= 0 ? 'text-green-400' : 'text-red-400'
                                }`}
                              >
                                {money(trade.pnl)}
                              </td>
                              <td className="py-1.5 text-gray-500">{trade.exitReason}</td>
                            </tr>
                          ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </>
          )}

          <div className="rounded-xl border border-border bg-surface p-5">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-white">Saved runs</h2>
              {loadingRuns && <Loader2 className="h-4 w-4 animate-spin text-gray-500" />}
            </div>

            {runs.length === 0 && !loadingRuns ? (
              <p className="text-sm text-gray-500">No saved runs yet.</p>
            ) : (
              <ul className="divide-y divide-border">
                {runs.map((entry) => (
                  <li key={entry.id} className="flex items-center gap-3 py-2.5">
                    <button
                      type="button"
                      onClick={() => void openRun(entry.id)}
                      className="min-w-0 flex-1 text-left"
                    >
                      <p className="truncate text-sm text-white">{entry.name}</p>
                      <p className="text-xs text-gray-500">
                        {entry.symbol} · {entry.strategy_id} · {day(entry.created_at)} ·{' '}
                        {entry.metrics?.trades ?? 0} trades
                      </p>
                    </button>
                    <span
                      className={`text-xs font-mono ${
                        (entry.metrics?.netPnl ?? 0) >= 0
                          ? 'text-green-400'
                          : 'text-red-400'
                      }`}
                    >
                      {money(entry.metrics?.netPnl ?? 0)}
                    </span>
                    <button
                      type="button"
                      onClick={() => void deleteRun(entry.id)}
                      aria-label={`Delete ${entry.name}`}
                      className="rounded-md p-1.5 text-gray-500 hover:bg-surface-light hover:text-red-400"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

/** Benchmark and reshuffle ranges: the two checks a positive curve cannot pass on its own. */
function RobustnessPanel({
  benchmark,
  stress,
  metrics,
}: {
  benchmark: Benchmark | null
  stress: StressSummary | null
  metrics: Metrics
}) {
  if (!benchmark && !stress) return null

  return (
    <div className="rounded-xl border border-border bg-surface p-5">
      <h2 className="text-sm font-semibold text-white">Is the edge real?</h2>
      <p className="mb-4 mt-1 text-xs text-gray-500">
        A rising curve is not proof. These checks ask whether the rules beat owning the
        instrument, and how much of the result depends on the order the trades arrived in.
      </p>

      {benchmark && (
        <div className="mb-5">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
            Versus buy and hold
          </h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-gray-500">
                  <th className="pb-2 font-medium">Window</th>
                  <th className="pb-2 font-medium">Return</th>
                  <th className="pb-2 font-medium">Max drawdown</th>
                </tr>
              </thead>
              <tbody className="text-gray-300">
                <tr className="border-t border-border">
                  <td className="py-2">These rules</td>
                  <td className="py-2">{pct(metrics.returnPct, 2)}</td>
                  <td className="py-2">{pct(metrics.maxDrawdownPct, 2)}</td>
                </tr>
                <tr className="border-t border-border">
                  <td className="py-2">Buy and hold</td>
                  <td className="py-2">{pct(benchmark.returnPct, 2)}</td>
                  <td className="py-2">{pct(benchmark.maxDrawdownPct, 2)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs leading-relaxed text-gray-500">
            {metrics.returnPct > benchmark.returnPct
              ? `The rules beat buying and holding by ${pct(metrics.returnPct - benchmark.returnPct, 2)} over ${benchmark.bars.toLocaleString('en-US')} bars.`
              : `Owning the instrument returned ${pct(benchmark.returnPct, 2)}; these rules did not beat it.`}
          </p>
        </div>
      )}

      {stress && (
        <div>
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
            Luck check · {stress.simulations.toLocaleString('en-US')} reshuffles
          </h3>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
            {[
              {
                label: 'Chance of profit',
                value: pct(stress.probabilityOfProfit * 100, 0),
              },
              { label: 'Median return', value: pct(stress.returnPct.p50, 2) },
              {
                label: 'Return 5–95%',
                value: `${pct(stress.returnPct.p05, 1)} to ${pct(stress.returnPct.p95, 1)}`,
              },
              {
                label: 'Drawdown 5–95%',
                value: `${pct(stress.maxDrawdownPct.p05, 1)} to ${pct(stress.maxDrawdownPct.p95, 1)}`,
              },
            ].map((item) => (
              <div key={item.label} className="rounded-lg border border-border bg-background p-3">
                <p className="text-[11px] font-medium uppercase tracking-wide text-gray-500">
                  {item.label}
                </p>
                <p className="mt-1 font-mono text-sm font-semibold text-white">{item.value}</p>
              </div>
            ))}
          </div>
          <p className="mt-2 text-xs leading-relaxed text-gray-500">
            The actual run drew down {pct(metrics.maxDrawdownPct, 2)};{' '}
            {pct(stress.worseDrawdownRate * 100, 0)} of reshuffles were deeper. Same trades,
            different order.
          </p>
        </div>
      )}
    </div>
  )
}

function MetricGrid({ metrics }: { metrics: Metrics }) {
  const items: { label: string; value: string; tone?: 'good' | 'bad' }[] = [
    { label: 'Net P&L', value: money(metrics.netPnl), tone: metrics.netPnl >= 0 ? 'good' : 'bad' },
    { label: 'Return', value: pct(metrics.returnPct, 2), tone: metrics.returnPct >= 0 ? 'good' : 'bad' },
    { label: 'Profit factor', value: ratio(metrics.profitFactor) },
    { label: 'Win rate', value: pct(metrics.winRate) },
    { label: 'Trades', value: String(metrics.trades) },
    { label: 'Expectancy', value: money(metrics.expectancy) },
    { label: 'Max drawdown', value: pct(metrics.maxDrawdownPct, 2), tone: 'bad' },
    { label: 'Sharpe', value: metrics.sharpe === null ? '—' : metrics.sharpe.toFixed(2) },
    { label: 'Exposure', value: pct(metrics.exposurePct, 0) },
    { label: 'Avg R', value: metrics.avgRMultiple === null ? '—' : metrics.avgRMultiple.toFixed(2) },
  ]

  return (
    <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
      {items.map((item) => (
        <div key={item.label} className="rounded-lg border border-border bg-background p-3">
          <p className="text-[11px] font-medium uppercase tracking-wide text-gray-500">
            {item.label}
          </p>
          <p
            className={`mt-1 font-mono text-sm font-semibold ${
              item.tone === 'good'
                ? 'text-green-400'
                : item.tone === 'bad'
                  ? 'text-red-400'
                  : 'text-white'
            }`}
          >
            {item.value}
          </p>
        </div>
      ))}
    </div>
  )
}

/** A dependency-free curve: min/max scaled line plus a soft fill. */
function EquityChart({ points }: { points: EquityPoint[] }) {
  const width = 640
  const height = 180
  const values = points.map((point) => point.equity)
  const min = Math.min(...values)
  const max = Math.max(...values)
  const span = max - min || 1

  const coordinates = points.map((point, index) => {
    const x = (index / Math.max(1, points.length - 1)) * width
    const y = height - ((point.equity - min) / span) * height
    return `${x.toFixed(1)},${y.toFixed(1)}`
  })
  const line = coordinates.join(' ')
  const area = `0,${height} ${line} ${width},${height}`
  const first = points[0]
  const last = points[points.length - 1]
  const rising = (last?.equity ?? 0) >= (first?.equity ?? 0)

  return (
    <div>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        className="h-44 w-full"
        preserveAspectRatio="none"
        role="img"
        aria-label={`Equity curve from ${money(first?.equity ?? 0)} to ${money(last?.equity ?? 0)}`}
      >
        <defs>
          <linearGradient id="equity-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={rising ? '#22C55E' : '#EF4444'} stopOpacity="0.28" />
            <stop offset="100%" stopColor={rising ? '#22C55E' : '#EF4444'} stopOpacity="0" />
          </linearGradient>
        </defs>
        <polygon points={area} fill="url(#equity-fill)" />
        <polyline
          points={line}
          fill="none"
          stroke={rising ? '#22C55E' : '#EF4444'}
          strokeWidth="1.6"
          vectorEffect="non-scaling-stroke"
        />
      </svg>
      <div className="mt-2 flex justify-between text-[11px] text-gray-500">
        <span>{day(first?.time ?? 0)}</span>
        <span>
          {money(min)} – {money(max)}
        </span>
        <span>{day(last?.time ?? 0)}</span>
      </div>
    </div>
  )
}
