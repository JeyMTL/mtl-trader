/**
 * The candles behind the excursion measurement.
 *
 * `excursion.ts` is pure maths over bars; this is the only part that knows about
 * OANDA. It exists so the analytics route can fetch **one** series per symbol and
 * candle size and measure every trade in it, instead of making one vendor call
 * per trade: twenty trades on EUR/USD at the same size cost one request, not
 * twenty.
 *
 * A symbol the feed does not quote returns null. That is the normal case for a
 * broker's own names (`BTCUSDM`, `USTECM`), and the route reports it as coverage
 * rather than treating the trade as a failure — an unmeasurable trade is not a
 * bad trade.
 */

import { logEvent } from './log'
import {
  CANDLE_INTERVALS,
  candlesForWindow,
  normalizeOandaCandles,
  oandaDate,
  oandaInstrument,
  type Candle,
  type ChartIntervalKey,
} from './market-candles'

/** OANDA's own cap on an explicit `from`/`to` window. */
export const MAX_SERIES_SPAN_MS = 62 * 86_400_000

export interface ExcursionSeries {
  symbol: string
  interval: ChartIntervalKey
  candles: Candle[]
  barMs: number
}

interface CacheEntry {
  at: number
  series: ExcursionSeries | null
}

const seriesCache = new Map<string, CacheEntry>()
const CACHE_TTL_MS = 30 * 60_000
const MAX_CACHE_ENTRIES = 120
/** A window is rounded out to this grid before it is cached, so neighbouring
 *  trades on the same instrument share one fetch. */
const WINDOW_BUCKET_MS = 15 * 60_000

function oandaConfig(): { token: string; base: string } | null {
  const token = process.env.OANDA_API_TOKEN
  if (!token) return null
  const base = (process.env.OANDA_API_BASE || 'https://api-fxpractice.oanda.com').replace(
    /\/+$/,
    ''
  )
  return { token, base }
}

/**
 * An abort signal that also works where `AbortSignal.timeout` is missing.
 *
 * Production is Node and has it; the test environment is jsdom, whose
 * `AbortSignal` does not, and a `TypeError` there would read as "this symbol has
 * no candles" — the one failure mode that must never be silent.
 */
function timeoutSignal(ms: number): AbortSignal | undefined {
  if (typeof AbortSignal.timeout === 'function') return AbortSignal.timeout(ms)
  if (typeof AbortController !== 'function') return undefined
  const controller = new AbortController()
  setTimeout(() => controller.abort(), ms).unref?.()
  return controller.signal
}

function cacheKey(instrument: string, interval: ChartIntervalKey, from: number, to: number): string {
  const bucketFrom = Math.floor(from / WINDOW_BUCKET_MS)
  const bucketTo = Math.ceil(to / WINDOW_BUCKET_MS)
  return `${instrument}|${interval}|${bucketFrom}|${bucketTo}`
}

/**
 * The bars for a symbol between two instants, or null when it cannot be served.
 *
 * Null covers four different situations — no vendor token, a symbol OANDA does
 * not quote, a window past the vendor's bar cap, and a failed request — because
 * the caller treats all four the same way: this trade cannot be measured, and
 * the reason is logged here rather than shown to the trader.
 */
export async function fetchExcursionSeries(
  symbol: string,
  interval: ChartIntervalKey,
  fromMs: number,
  toMs: number
): Promise<ExcursionSeries | null> {
  const config = oandaConfig()
  if (!config) return null

  const instrument = oandaInstrument(symbol)
  if (!instrument) return null
  if (!(toMs > fromMs) || toMs - fromMs > MAX_SERIES_SPAN_MS) return null
  if (candlesForWindow({ from: fromMs, to: toMs }, interval) === null) return null

  const key = cacheKey(instrument, interval, fromMs, toMs)
  const cached = seriesCache.get(key)
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.series

  // The cached window is deliberately wider than the request so the next trade
  // in the same session does not miss the cache by a few minutes. It never runs
  // past now: OANDA rejects a `to` in the future with a bare 400, which would be
  // indistinguishable from a bad symbol here.
  const now = Date.now()
  const from = Math.floor(fromMs / WINDOW_BUCKET_MS) * WINDOW_BUCKET_MS
  const to = Math.min(now, Math.ceil(toMs / WINDOW_BUCKET_MS) * WINDOW_BUCKET_MS)
  const url =
    `${config.base}/v3/instruments/${encodeURIComponent(instrument)}/candles` +
    `?granularity=${CANDLE_INTERVALS[interval].granularity}` +
    `&from=${encodeURIComponent(oandaDate(from))}` +
    `&to=${encodeURIComponent(oandaDate(to))}&price=M`

  let series: ExcursionSeries | null = null
  try {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${config.token}`,
        'Accept-Datetime-Format': 'RFC3339',
      },
      signal: timeoutSignal(8000),
      cache: 'no-store',
    })
    if (!response.ok) {
      logEvent('warn', 'excursion.feed_failed', {
        symbol,
        instrument,
        interval,
        status: response.status,
      })
    } else {
      const payload = await response.json().catch(() => null)
      const candles = normalizeOandaCandles(payload)
      if (candles.length > 0) {
        series = {
          symbol,
          interval,
          candles,
          barMs: CANDLE_INTERVALS[interval].ms,
        }
      }
    }
  } catch (error: unknown) {
    logEvent('warn', 'excursion.feed_error', {
      symbol,
      instrument,
      interval,
      error: error instanceof Error ? error.message : String(error),
    })
  }

  if (seriesCache.size >= MAX_CACHE_ENTRIES) seriesCache.clear()
  seriesCache.set(key, { at: Date.now(), series })
  return series
}
