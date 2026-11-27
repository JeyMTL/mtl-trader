import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, apiWarn, logEvent } from '@/lib/log'
import { mayReadMarketData } from '@/lib/solo'
import { MARKET_CHARTS_ENABLED } from '@/lib/features'
import {
  CANDLE_INTERVALS,
  aggregateCandles,
  candlesForWindow,
  isVendorOutage,
  liveTtlMs,
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

/**
 * The vendor itself is failing: an outage, not a symbol with nothing to show.
 *
 * The two used to be the same answer, so a trader looking at an empty chart on
 * a Saturday could not tell "this instrument has no bars" from "OANDA is down",
 * and neither could the app. They are different promises and get different
 * statuses.
 */
class FeedOutage extends Error {
  constructor(readonly status: number) {
    super(`OANDA answered ${status}`)
  }
}

async function fetchOanda(
  config: OandaConfig,
  symbol: string,
  interval: ChartIntervalKey,
  window: CandleWindow | null,
  tail = false
): Promise<CandleSeries | null> {
  const instrument = oandaInstrument(symbol)
  if (!instrument) return null
  const spec = CANDLE_INTERVALS[interval]
  // A re-bucketed size needs its own count of vendor bars: 45 seconds is three
  // 15-second bars, so asking for 720 of them would return a third of the chart.
  // A tail request only needs the moving bars, not the whole series.
  const wanted = tail
    ? (spec.aggregate ?? 1) * 3
    : spec.aggregate
      ? spec.count * spec.aggregate
      : spec.count
  const bounds = window
    ? `&from=${encodeURIComponent(oandaDate(window.from))}` +
      `&to=${encodeURIComponent(oandaDate(window.to))}`
    : `&count=${wanted}`
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
    // A 5xx or a throttle is the vendor's own trouble. Saying "no chart data"
    // for it blames the symbol, so it is raised and answered as an outage.
    if (isVendorOutage(response.status)) throw new FeedOutage(response.status)
    return null
  }

  const raw = normalizeOandaCandles(payload)
  if (raw.length === 0) {
    logEvent('warn', 'market.candles.oanda_empty', { symbol, instrument, interval })
    return null
  }
  const candles = spec.aggregate
    ? aggregateCandles(raw, spec.ms, spec.aggregate)
    : raw
  if (candles.length === 0) {
    logEvent('warn', 'market.candles.oanda_empty', { symbol, instrument, interval })
    return null
  }
  return { symbol, interval, source: 'oanda', candles }
}

export async function GET(req: Request) {
  // Charting is off until a feed licenses redistribution (see features.ts).
  // Answered before auth so a switched-off deployment spends no vendor credit
  // and no database round trip on a route nobody is offered.
  if (!MARKET_CHARTS_ENABLED) {
    return NextResponse.json(
      { error: 'Charting is turned off on this deployment.' },
      { status: 503 }
    )
  }
  const user = await getAuthUser(req)
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  // A solo deployment bought these prices for one person. Anyone else gets an
  // honest refusal instead of a chart, because that is the whole licence.
  if (!mayReadMarketData(user.id)) {
    return NextResponse.json(
      { error: 'The chart feed is private to the account that owns it.' },
      { status: 403 }
    )
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
  // `tail=1` is the live loop's request: the three newest bars, nothing else,
  // served from a one-second cache so the moving candle updates without
  // resending the whole series on every tick.
  const tail = searchParams.get('tail') === '1'

  // A half-sent window is a client bug, not "serve the latest": say so instead
  // of silently answering with the wrong slice of history.
  const fromRaw = searchParams.get('from')
  const toRaw = searchParams.get('to')
  let window: CandleWindow | null = null
  if (!tail && (fromRaw || toRaw)) {
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

  // The desk polls the live tail: every ten seconds on a minute chart, every
  // 2.5 seconds on a five-second one, and the compare overlay doubles that. The
  // ceiling clears two charts at the finest size (~2,900 an hour) and still
  // stops a script. Size switches are cheap: they come from the series cache.
  // A live tail now asks once a second, and a compare overlay doubles that.
  const limit = await rateLimit(`market:${user.id}`, 12_000, 60 * 60 * 1000)
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
  const key = `${symbol}|${interval}|${tail ? 'tail' : windowKey}`
  const cached = seriesCache.get(key)
  // A historical window never changes, so it can be kept far longer than the
  // live tail that keeps moving. The tail cache is a quarter of the client's
  // one-second cadence, which coalesces simultaneous charts without adding lag.
  const ttl = tail ? 1_000 : window ? 30 * 60 * 1000 : cached ? liveTtlMs(interval) : 0
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
    const series = await fetchOanda(config, symbol, interval, window, tail)

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
    if (error instanceof FeedOutage) {
      logEvent('error', 'market.candles.outage', {
        symbol,
        interval,
        status: error.status,
      })
      return NextResponse.json(
        {
          error:
            'The chart feed is down at the broker right now — this is not your connection. The chart retries on its own.',
          outage: true,
        },
        {
          status: 503,
          // An outage answer must not be cached as if it were a series.
          headers: { 'Cache-Control': 'no-store' },
        }
      )
    }
    return apiError(
      'market.candles.failed',
      error,
      502,
      'The chart feed is unavailable right now. Try again in a minute.'
    )
  }
}
