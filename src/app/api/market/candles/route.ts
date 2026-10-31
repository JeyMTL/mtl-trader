import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import {
  CHART_RANGES,
  SOURCE_TTL_MS,
  candleProviderChain,
  normalizeOandaCandles,
  normalizeSymbol,
  normalizeTwelveDataCandles,
  normalizeYahooCandles,
  oandaDate,
  oandaErrorMessage,
  oandaInstrument,
  parseChartRange,
  parseWindow,
  twelveDataDate,
  twelveDataErrorMessage,
  twelveDataSymbol,
  yahooErrorMessage,
  type CandleSeries,
  type CandleSource,
  type CandleWindow,
  type ChartRangeKey,
} from '@/lib/market-candles'

/**
 * Candles for the mobile level-pinning chart.
 *
 * Provider keys never leave the server: the app sends its Supabase session and
 * this route fetches the candles. `candleProviderChain` decides the order —
 * Twelve Data when `TWELVE_DATA_API_KEY` is set, OANDA when only
 * `OANDA_API_TOKEN` is, and the delayed public feed behind both, so a vendor
 * quota or outage degrades to slower data instead of a blank chart.
 *
 * Without `from`/`to` the newest candles are served (live view). With both, the
 * route honours the window, which is what market replay uses to jump to a past
 * date or page further back.
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
const VALID_TICKER = /^[A-Za-z0-9.^=-]{1,20}$/
const TWELVE_DATA_BASE = 'https://api.twelvedata.com'
/** Twelve Data's per-request candle cap; larger windows are truncated by it. */
const TWELVE_DATA_MAX_OUTPUT = 5000

function oandaConfig(): OandaConfig | null {
  const token = process.env.OANDA_API_TOKEN
  if (!token) return null
  const base = (process.env.OANDA_API_BASE || 'https://api-fxpractice.oanda.com').replace(
    /\/+$/,
    ''
  )
  return { token, base }
}

/** `EURUSD` → `EURUSD=X`, matching the legacy feed's ticker convention. */
function fallbackTicker(symbol: string): string {
  return /^[A-Z]{6}$/.test(symbol) ? `${symbol}=X` : symbol
}

async function fetchTwelveData(
  apiKey: string,
  symbol: string,
  range: ChartRangeKey,
  window: CandleWindow | null
): Promise<CandleSeries | null> {
  const vendorSymbol = twelveDataSymbol(symbol)
  if (!vendorSymbol) return null
  const spec = CHART_RANGES[range]

  const bounds = window
    ? `&start_date=${encodeURIComponent(twelveDataDate(window.from))}` +
      `&end_date=${encodeURIComponent(twelveDataDate(window.to))}` +
      `&outputsize=${TWELVE_DATA_MAX_OUTPUT}`
    : `&outputsize=${spec.count}`

  const url =
    `${TWELVE_DATA_BASE}/time_series?symbol=${encodeURIComponent(vendorSymbol)}` +
    `&interval=${spec.twelveInterval}${bounds}` +
    '&timezone=UTC&order=ASC&format=JSON' +
    `&apikey=${encodeURIComponent(apiKey)}`

  const response = await fetch(url, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(8000),
    cache: 'no-store',
  })
  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    logEvent('warn', 'market.candles.twelvedata_failed', {
      symbol,
      vendorSymbol,
      status: response.status,
      reason: twelveDataErrorMessage(payload),
    })
    return null
  }

  const candles = normalizeTwelveDataCandles(payload)
  if (candles.length === 0) {
    // Twelve Data answers a quota or bad-symbol refusal with HTTP 200.
    logEvent('warn', 'market.candles.twelvedata_empty', {
      symbol,
      vendorSymbol,
      window: window ? { from: window.from, to: window.to } : null,
      reason: twelveDataErrorMessage(payload),
    })
    return null
  }
  return { symbol, range, interval: spec.interval, source: 'twelvedata', candles }
}

async function fetchOanda(
  config: OandaConfig,
  symbol: string,
  range: ChartRangeKey,
  window: CandleWindow | null
): Promise<CandleSeries | null> {
  const instrument = oandaInstrument(symbol)
  if (!instrument) return null
  const spec = CHART_RANGES[range]
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
      status: response.status,
      reason: oandaErrorMessage(payload),
    })
    return null
  }

  const candles = normalizeOandaCandles(payload)
  if (candles.length === 0) {
    logEvent('warn', 'market.candles.oanda_empty', { symbol, instrument })
    return null
  }
  return { symbol, range, interval: spec.interval, source: 'oanda', candles }
}

async function fetchLegacy(
  symbol: string,
  range: ChartRangeKey,
  ticker: string,
  window: CandleWindow | null
): Promise<CandleSeries | null> {
  const spec = CHART_RANGES[range]
  const bounds = window
    ? `&period1=${Math.floor(window.from / 1000)}&period2=${Math.ceil(window.to / 1000)}`
    : `&range=${range}`
  const url =
    'https://query1.finance.yahoo.com/v8/finance/chart/' +
    `${encodeURIComponent(ticker)}?interval=${spec.interval}${bounds}&includePrePost=false`

  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'Mozilla/5.0 (compatible; MTLTrader/1.0)',
    },
    signal: AbortSignal.timeout(10_000),
    cache: 'no-store',
  })
  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    logEvent('warn', 'market.candles.legacy_failed', {
      symbol,
      ticker,
      status: response.status,
      reason: yahooErrorMessage(payload),
    })
    return null
  }

  const candles = normalizeYahooCandles(payload)
  if (candles.length === 0) {
    logEvent('warn', 'market.candles.legacy_empty', {
      symbol,
      ticker,
      reason: yahooErrorMessage(payload),
    })
    return null
  }
  return { symbol, range, interval: spec.interval, source: 'yahoo', candles }
}

async function fetchFrom(
  provider: CandleSource,
  symbol: string,
  range: ChartRangeKey,
  ticker: string,
  window: CandleWindow | null
): Promise<CandleSeries | null> {
  try {
    if (provider === 'twelvedata') {
      const apiKey = process.env.TWELVE_DATA_API_KEY
      return apiKey ? await fetchTwelveData(apiKey, symbol, range, window) : null
    }
    if (provider === 'oanda') {
      const config = oandaConfig()
      return config ? await fetchOanda(config, symbol, range, window) : null
    }
    return await fetchLegacy(symbol, range, ticker, window)
  } catch (error) {
    // A provider hiccup should hand over to the next one, not 500 the chart.
    logEvent('warn', `market.candles.${provider}_error`, { symbol, error })
    return null
  }
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
  const range = parseChartRange(searchParams.get('range'))
  if (!range) {
    return apiWarn('market.candles.range', 'Unknown chart range')
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
  }

  // The ticker hint is only used by the fallback feed, so it is constrained to
  // something the public chart endpoint accepts.
  const hint = searchParams.get('ticker') ?? ''
  const ticker = VALID_TICKER.test(hint) ? hint : fallbackTicker(symbol)

  // One open chart screen polls about 60 times an hour; 300 leaves room for
  // range switches without letting a client hammer the provider on our key.
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
  const key = `${symbol}|${range}|${windowKey}`
  const cached = seriesCache.get(key)
  // A historical window never changes, so it can be kept far longer than the
  // live tail that keeps moving.
  const ttl = window
    ? 30 * 60 * 1000
    : cached
      ? SOURCE_TTL_MS[cached.series.source]
      : 0
  if (cached && Date.now() - cached.at < ttl) {
    return NextResponse.json(cached.series)
  }

  try {
    // Built explicitly: `process.env` is an index signature, and passing it
    // straight through hides a typo in a key name from the compiler.
    const chain = candleProviderChain({
      MARKET_DATA_PROVIDER: process.env.MARKET_DATA_PROVIDER,
      TWELVE_DATA_API_KEY: process.env.TWELVE_DATA_API_KEY,
      OANDA_API_TOKEN: process.env.OANDA_API_TOKEN,
    })

    let series: CandleSeries | null = null
    for (const provider of chain) {
      series = await fetchFrom(provider, symbol, range, ticker, window)
      if (series) break
    }

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
