import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import {
  CANDLE_INTERVALS,
  LIVE_TTL_MS,
  candlesForWindow,
  normalizeOandaCandles,
  normalizeSymbol,
  oandaDate,
  oandaErrorMessage,
  oandaInstrument,
  parseChartInterval,
  parseWindow,
  type ChartIntervalKey,
  type CandleSeries,
  type CandleWindow,
} from '@/lib/market-candles'

/**
 * Candles for the mobile level-pinning chart.
 *
 * The OANDA token never leaves the server: the app sends its Supabase session
 * and this route fetches the candles. OANDA is the only vendor — there is no
 * delayed fallback — so a symbol it cannot quote answers 502 instead of showing
 * prices from an unnamed feed.
 *
 * `interval` picks the candle size (1m … 1d). Without `from`/`to` the newest
 * candles are served (live view); with both, the route honours that window,
 * which is what market replay and the chart's time-frame picker use. A window
 * that would need more than the vendor's 5,000-candle cap is refused up front
 * rather than returning a silently truncated series.
 */

interface OandaConfig {
  token: string
  base: string
}

interface CacheEntry {
  at: number
  series: CandleSeries
}

const seriesCache = new Map<string, CacheEntry>()
const MAX_CACHE_ENTRIES = 200

function oandaConfig(): OandaConfig | null {
  const token = process.env.OANDA_API_TOKEN
  if (!token) return null
  const base = (process.env.OANDA_API_BASE || 'https://api-fxpractice.oanda.com').replace(
    /\/+$/,
    ''
  )
  return { token, base }
}

async function fetchOanda(
  config: OandaConfig,
  symbol: string,
  interval: ChartIntervalKey,
  window: CandleWindow | null
): Promise<CandleSeries | null> {
  const instrument = oandaInstrument(symbol)
  if (!instrument) return null
  const spec = CANDLE_INTERVALS[interval]
  const bounds = window
    ? `&from=${encodeURIComponent(oandaDate(window.from))}` +
      `&to=${encodeURIComponent(oandaDate(window.to))}`
    : `&count=${spec.count}`
  const url =
    `${config.base}/v3/instruments/${encodeURIComponent(instrument)}/candles` +
    `?granularity=${spec.granularity}${bounds}&price=M`

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${config.token}`,
      'Accept-Datetime-Format': 'RFC3339',
    },
    signal: AbortSignal.timeout(8000),
    cache: 'no-store',
  })
  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    logEvent('warn', 'market.candles.oanda_failed', {
      symbol,
      instrument,
      interval,
      status: response.status,
      reason: oandaErrorMessage(payload),
    })
    return null
  }

  const candles = normalizeOandaCandles(payload)
  if (candles.length === 0) {
    logEvent('warn', 'market.candles.oanda_empty', { symbol, instrument, interval })
    return null
  }
  return { symbol, interval, source: 'oanda', candles }
}

export async function GET(req: Request) {
  const user = await getAuthUser(req)
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { searchParams } = new URL(req.url)
  const symbol = normalizeSymbol(searchParams.get('symbol') ?? '')
  if (!/^[A-Z0-9]{4,10}$/.test(symbol)) {
    return apiWarn('market.candles.symbol', 'Unknown symbol')
  }
  const interval = parseChartInterval(searchParams.get('interval'))
  if (!interval) {
    return apiWarn('market.candles.interval', 'Unknown candle interval')
  }

  // A half-sent window is a client bug, not "serve the latest": say so instead
  // of silently answering with the wrong slice of history.
  const fromRaw = searchParams.get('from')
  const toRaw = searchParams.get('to')
  let window: CandleWindow | null = null
  if (fromRaw || toRaw) {
    window = parseWindow(fromRaw, toRaw)
    if (!window) {
      return apiWarn(
        'market.candles.window',
        'Send both from and to as epoch milliseconds or ISO dates, in order and within 62 days.'
      )
    }
    if (candlesForWindow(window, interval) === null) {
      return apiWarn(
        'market.candles.window',
        'That window needs more than 5,000 candles. Pick a larger candle size or a shorter window.'
      )
    }
  }

  // One open chart screen polls about 60 times an hour; 300 leaves room for
  // size switches without letting a client hammer the vendor on our key.
  const limit = await rateLimit(`market:${user.id}`, 300, 60 * 60 * 1000)
  if (!limit.ok) {
    return NextResponse.json(
      { error: 'Too many chart requests. Try again shortly.' },
      {
        status: 429,
        headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) },
      }
    )
  }

  const windowKey = window ? `${window.from}-${window.to}` : 'latest'
  const key = `${symbol}|${interval}|${windowKey}`
  const cached = seriesCache.get(key)
  // A historical window never changes, so it can be kept far longer than the
  // live tail that keeps moving.
  const ttl = window
    ? 30 * 60 * 1000
    : cached
      ? LIVE_TTL_MS
      : 0
  if (cached && Date.now() - cached.at < ttl) {
    return NextResponse.json(cached.series)
  }

  const config = oandaConfig()
  if (!config) {
    logEvent('error', 'market.candles.unconfigured', { symbol })
    return NextResponse.json(
      { error: 'The chart feed is not configured on this server.' },
      { status: 503 }
    )
  }

  // A symbol OANDA cannot name is a bad request, not a feed outage.
  if (!oandaInstrument(symbol)) {
    return NextResponse.json(
      { error: `No chart data for ${symbol} right now.` },
      { status: 502 }
    )
  }

  try {
    const series = await fetchOanda(config, symbol, interval, window)

    if (!series) {
      return NextResponse.json(
        { error: `No chart data for ${symbol} right now.` },
        { status: 502 }
      )
    }

    seriesCache.set(key, { at: Date.now(), series })
    if (seriesCache.size > MAX_CACHE_ENTRIES) {
      const oldest = seriesCache.keys().next().value
      if (oldest !== undefined) seriesCache.delete(oldest)
    }
    return NextResponse.json(series)
  } catch (error) {
    return apiError(
      'market.candles.failed',
      error,
      502,
      'The chart feed is unavailable right now. Try again in a minute.'
    )
  }
}
