import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { apiError } from '@/lib/log'
import { mayReadMarketData } from '@/lib/solo'
import { MARKET_CHARTS_ENABLED } from '@/lib/features'
import { rateLimit } from '@/lib/rate-limit'
import { fetchExcursionSeries } from '@/lib/excursion-feed'
import {
  intervalForDuration,
  measureExcursion,
  summariseExcursions,
  type MeasuredTrade,
  type TradeSide,
} from '@/lib/excursion'

/**
 * Exit capture: how much of each trade's move the trader kept.
 *
 * Reads the closed trades in a range, measures the ones that have no stored
 * measurement yet, and returns the aggregate. Measurement is cached in
 * `trade_excursions` so the second visit is a single table read: a vendor call
 * per trade per page view would be both slow and rude to OANDA.
 *
 * One series is fetched per symbol and candle size, not per trade — the fetch is
 * grouped over the union of the trades' windows — which is what keeps a
 * 40-trade history inside a dozen vendor requests.
 *
 * Trades the feed cannot price are counted, not guessed. `coverage` says how
 * many closed trades were measurable, so the UI can say "measured on 62% of
 * trades" instead of pretending a partial sample is the whole story.
 */

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/** How many trades one request may measure. Bounds the vendor calls it can make. */
const MEASURE_PER_REQUEST = 40
/** How many closed trades the range is read for. */
const TRADE_LIMIT = 300

const TRADE_COLUMNS =
  'id, symbol, type, entry_price, exit_price, open_time, close_time, strategy, created_at'

interface TradeRow {
  id: string
  symbol: string
  type: string
  entry_price: number | string
  exit_price: number | string
  open_time: string | null
  close_time: string | null
  strategy: string | null
  created_at: string | null
}

interface StoredExcursion {
  trade_id: string
  mfe: number | string
  mae: number | string
  realised: number | string
  capture: number | string | null
  peak_at: string | null
  bars: number
  complete: boolean
}

function sideOf(raw: string): TradeSide | null {
  const value = raw.trim().toLowerCase()
  if (value === 'buy' || value === 'long') return 'buy'
  if (value === 'sell' || value === 'short') return 'sell'
  return null
}

function instant(value: string | null): number {
  if (!value) return NaN
  return Date.parse(value)
}

function num(value: number | string): number {
  return typeof value === 'number' ? value : Number(value)
}

export async function GET(req: Request) {
  try {
    // Exit capture is measured against candles, so it is off with the chart.
    if (!MARKET_CHARTS_ENABLED) {
      return NextResponse.json(
        { error: 'Charting is turned off on this deployment.' },
        { status: 503 }
      )
    }
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    // Same gate as the chart: this route spends vendor credit too.
    if (!mayReadMarketData(user.id)) {
      return NextResponse.json(
        { error: 'Market measurement is private to the account that owns the feed.' },
        { status: 403 }
      )
    }

    // A page view can trigger vendor calls, so it gets a budget. Re-visits after
    // the cache is warm cost one table read and still count against it, which is
    // the cheap thing to protect.
    const limit = await rateLimit(`excursion:${user.id}`, 60, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many requests. Try again shortly.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const { searchParams } = new URL(req.url)
    const requested = Number(searchParams.get('days') ?? 90)
    const days = Number.isFinite(requested)
      ? Math.min(365, Math.max(7, Math.round(requested)))
      : 90
    const since = new Date(Date.now() - days * 86_400_000).toISOString()

    const admin = getAdminClient()
    const { data, error } = await admin
      .from('trades')
      .select(TRADE_COLUMNS)
      .eq('user_id', user.id)
      .not('close_time', 'is', null)
      .gte('close_time', since)
      .order('close_time', { ascending: false })
      .limit(TRADE_LIMIT)

    if (error) return apiError('analytics.excursion.trades', error, 500, 'Could not read your trades.')

    const trades = (data ?? []) as TradeRow[]
    const byId = new Map(trades.map((trade) => [trade.id, trade]))

    // Stored measurements for this range. A missing table (migration not yet
    // applied) is not fatal: the request still measures and answers, it just
    // cannot cache, and says so with `persisted: false`.
    let persisted = true
    let stored: StoredExcursion[] = []
    if (trades.length > 0) {
      const { data: rows, error: readError } = await admin
        .from('trade_excursions')
        .select('trade_id, mfe, mae, realised, capture, peak_at, bars, complete')
        .eq('user_id', user.id)
        .in('trade_id', trades.map((trade) => trade.id))

      if (readError) {
        if (readError.code !== '42P01') {
          return apiError('analytics.excursion.read', readError, 500, 'Could not read your measurements.')
        }
        persisted = false
      } else {
        stored = (rows ?? []) as StoredExcursion[]
      }
    }

    const measured = new Map<string, MeasuredTrade>()
    const unsupported = new Set<string>()

    for (const row of stored) {
      const trade = byId.get(row.trade_id)
      const side = trade ? sideOf(trade.type) : null
      if (!trade || !side) continue
      measured.set(row.trade_id, {
        symbol: trade.symbol,
        side,
        setup: trade.strategy,
        mfe: num(row.mfe),
        mae: num(row.mae),
        realised: num(row.realised),
        capture: row.capture === null ? null : num(row.capture),
        peakAtMs: row.peak_at ? Date.parse(row.peak_at) : null,
        bars: row.bars,
        complete: row.complete,
      })
    }

    // Only trades without a measurement are fetched, newest first, and only so
    // many per request.
    const pending = trades
      .filter((trade) => !measured.has(trade.id))
      .map((trade) => ({
        trade,
        side: sideOf(trade.type),
        openedAt: instant(trade.open_time ?? trade.created_at),
        closedAt: instant(trade.close_time),
      }))
      .filter((entry) => entry.side !== null && Number.isFinite(entry.openedAt) && Number.isFinite(entry.closedAt))
      .slice(0, MEASURE_PER_REQUEST)

    // Group by symbol and candle size so one vendor call serves every trade in
    // the group, over the union of their windows.
    const groups = new Map<
      string,
      {
        symbol: string
        interval: ReturnType<typeof intervalForDuration>
        from: number
        to: number
        entries: typeof pending
      }
    >()

    for (const entry of pending) {
      const interval = intervalForDuration(entry.closedAt - entry.openedAt)
      const key = `${entry.trade.symbol}|${interval}`
      const group = groups.get(key)
      if (group) {
        group.from = Math.min(group.from, entry.openedAt)
        group.to = Math.max(group.to, entry.closedAt)
        group.entries.push(entry)
      } else {
        groups.set(key, {
          symbol: entry.trade.symbol,
          interval,
          from: entry.openedAt,
          to: entry.closedAt,
          entries: [entry],
        })
      }
    }

    const fresh: Record<string, unknown>[] = []
    for (const group of groups.values()) {
      const series = await fetchExcursionSeries(group.symbol, group.interval, group.from, group.to)
      if (!series) {
        unsupported.add(group.symbol)
        continue
      }
      for (const entry of group.entries) {
        const result = measureExcursion(
          {
            side: entry.side as TradeSide,
            entry: num(entry.trade.entry_price),
            exit: num(entry.trade.exit_price),
            openedAt: entry.openedAt,
            closedAt: entry.closedAt,
          },
          series.candles,
          series.barMs
        )
        // A partial series would flatter the exit, so it is not stored at all.
        if (!result || !result.complete) continue

        measured.set(entry.trade.id, {
          symbol: entry.trade.symbol,
          side: entry.side as TradeSide,
          setup: entry.trade.strategy,
          ...result,
        })

        if (persisted) {
          fresh.push({
            trade_id: entry.trade.id,
            user_id: user.id,
            mfe: result.mfe,
            mae: result.mae,
            realised: result.realised,
            capture: result.capture,
            peak_at: result.peakAtMs === null ? null : new Date(result.peakAtMs).toISOString(),
            bars: result.bars,
            bar_interval: group.interval,
            complete: result.complete,
            measured_at: new Date().toISOString(),
          })
        }
      }
    }

    if (fresh.length > 0) {
      const { error: writeError } = await admin
        .from('trade_excursions')
        .upsert(fresh, { onConflict: 'trade_id' })
      if (writeError) {
        // The numbers are still correct for this response; only the cache is
        // missing. Logged rather than failing the whole card.
        persisted = false
        if (writeError.code !== '42P01') {
          return apiError('analytics.excursion.write', writeError, 500, 'Could not save your measurements.')
        }
      }
    }

    const rows = [...measured.values()].filter((row) => row.complete)
    const summary = summariseExcursions(rows)

    return NextResponse.json(
      {
        days,
        persisted,
        coverage: {
          closed: trades.length,
          measured: rows.length,
          pending: Math.max(0, trades.length - measured.size),
          unsupportedSymbols: [...unsupported].slice(0, 12),
        },
        summary,
      },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('analytics.excursion', error, 500, 'Could not measure your trades.')
  }
}
