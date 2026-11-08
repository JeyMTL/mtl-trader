import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import { runBacktest } from '@/lib/backtest'
import { checkFeature } from '@/lib/plan-guard'

/**
 * Backtest runs.
 *
 *   POST   -> simulate a CSV over a strategy, persist the run, return the report
 *   GET    -> recent runs for the signed-in user
 *   DELETE -> remove one of the caller's runs
 *
 * Simulation happens here, never in the browser: the engine is deterministic, and
 * a result that the client could compute is a result the client could also forge.
 * The service role writes the row so a run cannot be saved without having been
 * executed by this route.
 */

export const runtime = 'nodejs'
export const maxDuration = 60

/** Vercel caps a function body at ~4.5 MB; fail with advice before that does. */
const MAX_CSV_CHARS = 4_000_000
const MAX_SAVED_RUNS = 50
const MAX_TRADES_STORED = 2_000
const MAX_TRADES_RETURNED = 300

interface SavedRunRow {
  id: string
  name: string
  symbol: string
  timeframe: string
  strategy_id: string
  strategy_params: Record<string, number>
  metrics: Record<string, unknown>
  bar_count: number
  period_start: string
  period_end: string
  created_at: string
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const limit = await rateLimit(`backtest:${user.id}`, 6, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many backtests this hour. Try again shortly.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    // Backtesting is a Pro feature. Reading and deleting saved runs is left
    // alone on purpose: your own results stay yours even if you downgrade.
    const gate = await checkFeature(user.id, 'backtest')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    const parsed = await readJsonBody<Record<string, unknown>>(req, {
      maxBytes: 5 * 1024 * 1024,
    })
    if (!parsed.ok) return parsed.response
    const body = parsed.value
    const csv = typeof body.csv === 'string' ? body.csv : ''
    if (!csv.trim()) {
      return apiWarn('backtest.invalid', 'Paste or upload the bar data first.', 400)
    }
    if (csv.length > MAX_CSV_CHARS) {
      return apiWarn(
        'backtest.too_large',
        'That file is over 4 MB. Export a shorter date range or use a larger timeframe.',
        413
      )
    }

    let report
    try {
      report = runBacktest({
        csv,
        symbol: typeof body.symbol === 'string' ? body.symbol : '',
        timeframe: typeof body.timeframe === 'string' ? body.timeframe : undefined,
        strategyId: typeof body.strategyId === 'string' ? body.strategyId : '',
        ruleSpec: body.ruleSpec,
        params:
          body.params && typeof body.params === 'object'
            ? (body.params as Record<string, unknown>)
            : {},
        initialBalance: numberOrUndefined(body.initialBalance),
        riskPercent: numberOrUndefined(body.riskPercent),
        contractSize: numberOrUndefined(body.contractSize),
        maxLeverage: numberOrUndefined(body.maxLeverage),
        spread: numberOrUndefined(body.spread),
        slippage: numberOrUndefined(body.slippage),
        commission: numberOrUndefined(body.commission),
        splitRatio: numberOrUndefined(body.splitRatio),
        timezoneOffsetMinutes: numberOrUndefined(body.timezoneOffsetMinutes),
      })
    } catch (error: unknown) {
      // Engine and parser errors are written for the customer; anything else is
      // still safe to show because it is validated input, but it is logged too.
      const message = error instanceof Error ? error.message : 'The run could not be completed.'
      return apiWarn('backtest.invalid', message, 400)
    }

    const admin = getAdminClient()
    const { count } = await admin
      .from('backtests')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)

    if ((count ?? 0) >= MAX_SAVED_RUNS) {
      return apiWarn(
        'backtest.quota',
        `You have ${MAX_SAVED_RUNS} saved runs. Delete one before starting another.`,
        429
      )
    }

    const name =
      typeof body.name === 'string' && body.name.trim()
        ? body.name.trim().slice(0, 80)
        : `${report.symbol} ${report.strategy.name}`

    const { data, error } = await admin
      .from('backtests')
      .insert({
        user_id: user.id,
        name,
        symbol: report.symbol,
        timeframe: report.timeframe,
        strategy_id: report.strategy.id,
        strategy_params: report.strategy.params,
        config: report.config,
        bar_count: report.barCount,
        period_start: new Date(report.from).toISOString(),
        period_end: new Date(report.to).toISOString(),
        metrics: report.metrics,
        split_metrics: report.split,
        benchmark: report.benchmark,
        stress: report.stress,
        walk_forward: report.walkForward,
        rule_spec: report.ruleSpec,
        equity_curve: report.equityCurve,
        trades: report.trades.slice(-MAX_TRADES_STORED),
        assumptions: report.assumptions,
        warnings: report.warnings,
      })
      .select('id, created_at')
      .single()

    if (error) {
      logEvent('warn', 'backtest.save_failed', { error, userId: user.id })
      // The run is still useful to the caller; only the archive failed.
      return NextResponse.json(
        { report: trimReport(report), saved: false },
        { status: 200 }
      )
    }

    logEvent('info', 'backtest.run', {
      userId: user.id,
      strategy: report.strategy.id,
      symbol: report.symbol,
      bars: report.barCount,
      trades: report.metrics.trades,
    })

    return NextResponse.json({
      saved: true,
      id: (data as { id: string }).id,
      createdAt: (data as { created_at: string }).created_at,
      report: trimReport(report),
    })
  } catch (error: unknown) {
    return apiError('backtest.run', error, 500, 'The backtest could not be completed.')
  }
}

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const admin = getAdminClient()
    const id = new URL(req.url).searchParams.get('id')

    // One run, for the report view: the full row, including the trades and the
    // curve, scoped to the caller.
    if (id) {
      const { data, error } = await admin
        .from('backtests')
        .select('*')
        .eq('id', id)
        .eq('user_id', user.id)
        .maybeSingle()

      if (error) return apiError('backtest.get', error, 500, 'Could not load that run.')
      if (!data) return NextResponse.json({ error: 'Run not found.' }, { status: 404 })

      return NextResponse.json(
        { run: data },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    const { data, error } = await admin
      .from('backtests')
      .select(
        'id, name, symbol, timeframe, strategy_id, strategy_params, metrics, bar_count, period_start, period_end, created_at'
      )
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(20)

    if (error) return apiError('backtest.list', error, 500, 'Could not load your saved runs.')

    return NextResponse.json(
      { runs: (data ?? []) as SavedRunRow[] },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('backtest.list', error, 500, 'Could not load your saved runs.')
  }
}

export async function DELETE(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const id = new URL(req.url).searchParams.get('id')
    if (!id) return NextResponse.json({ error: 'Missing run id.' }, { status: 400 })

    const { error } = await getAdminClient()
      .from('backtests')
      .delete()
      .eq('id', id)
      .eq('user_id', user.id)

    if (error) return apiError('backtest.delete', error, 500, 'Could not delete the run.')

    return NextResponse.json({ deleted: true })
  } catch (error: unknown) {
    return apiError('backtest.delete', error, 500, 'Could not delete the run.')
  }
}

function numberOrUndefined(value: unknown): number | undefined {
  const parsed = Number(value)
  return value === null || value === undefined || value === '' || !Number.isFinite(parsed)
    ? undefined
    : parsed
}

/** Trades and curve are capped on the way out, not stored truncated. */
function trimReport<T extends { trades: unknown[]; equityCurve: unknown[] }>(report: T): T {
  return {
    ...report,
    trades: report.trades.slice(-MAX_TRADES_RETURNED),
  }
}
