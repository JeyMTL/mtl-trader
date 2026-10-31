/**
 * Provider mapping and payload normalisation for `/api/market/candles`.
 *
 * The mobile chart used to read Yahoo's public chart feed directly. That feed
 * serves composite spot quotes — a few pips off a broker, with bad intraday
 * prints — so candles come from a broker-grade vendor instead. Twelve Data is
 * the primary provider (instant self-serve key, real aggregated FX quotes),
 * OANDA stays available behind `MARKET_DATA_PROVIDER=oanda` for accounts that
 * prefer it, and the delayed public feed is the last resort so the chart never
 * goes blank. Everything provider-specific lives here, and the route always
 * answers with one shape, so the app parses a single format.
 */

export type ChartRangeKey = '1d' | '5d' | '1mo'

export type CandleSource = 'twelvedata' | 'oanda' | 'yahoo'

export interface Candle {
  /** Candle open time, epoch milliseconds. */
  t: number
  o: number
  h: number
  l: number
  c: number
}

export interface CandleSeries {
  symbol: string
  range: ChartRangeKey
  /** Interval label, e.g. `5m`. */
  interval: string
  source: CandleSource
  candles: Candle[]
}

interface RangeSpec {
  /** OANDA granularity code. */
  granularity: string
  /** Twelve Data interval code. */
  twelveInterval: string
  /** Candles to request: enough to fill the window, no more. */
  count: number
  /** Interval label, also accepted by the legacy feed. */
  interval: string
}

export const CHART_RANGES: Record<ChartRangeKey, RangeSpec> = {
  '1d': { granularity: 'M5', twelveInterval: '5min', count: 288, interval: '5m' },
  '5d': { granularity: 'M15', twelveInterval: '15min', count: 480, interval: '15m' },
  '1mo': { granularity: 'H1', twelveInterval: '1h', count: 744, interval: '1h' },
}

/**
 * How long a series may be reused. Real-time vendors get a short window because
 * the last candle keeps moving; the delayed feed is stale anyway, and the free
 * Twelve Data plan has a daily call budget that a longer window protects.
 */
export const SOURCE_TTL_MS: Record<CandleSource, number> = {
  twelvedata: 60_000,
  oanda: 20_000,
  yahoo: 300_000,
}

/**
 * Journal symbol → OANDA instrument. OANDA spells names with an underscore and
 * carries CFDs for the exchange-traded classes, so these resolve to the same
 * market a broker quotes instead of a futures or cash-index proxy.
 */
const OANDA_INSTRUMENTS: Record<string, string> = {
  // Forex majors
  EURUSD: 'EUR_USD',
  GBPUSD: 'GBP_USD',
  USDJPY: 'USD_JPY',
  USDCHF: 'USD_CHF',
  USDCAD: 'USD_CAD',
  AUDUSD: 'AUD_USD',
  NZDUSD: 'NZD_USD',
  // Forex crosses
  EURGBP: 'EUR_GBP',
  EURJPY: 'EUR_JPY',
  EURCHF: 'EUR_CHF',
  EURAUD: 'EUR_AUD',
  EURCAD: 'EUR_CAD',
  EURNZD: 'EUR_NZD',
  GBPJPY: 'GBP_JPY',
  GBPCHF: 'GBP_CHF',
  GBPAUD: 'GBP_AUD',
  GBPCAD: 'GBP_CAD',
  GBPNZD: 'GBP_NZD',
  AUDJPY: 'AUD_JPY',
  AUDCAD: 'AUD_CAD',
  AUDCHF: 'AUD_CHF',
  AUDNZD: 'AUD_NZD',
  CADJPY: 'CAD_JPY',
  CADCHF: 'CAD_CHF',
  CHFJPY: 'CHF_JPY',
  NZDJPY: 'NZD_JPY',
  NZDCAD: 'NZD_CAD',
  NZDCHF: 'NZD_CHF',
  // Forex exotics
  USDMXN: 'USD_MXN',
  USDZAR: 'USD_ZAR',
  USDTRY: 'USD_TRY',
  USDSEK: 'USD_SEK',
  USDNOK: 'USD_NOK',
  USDSGD: 'USD_SGD',
  USDHKD: 'USD_HKD',
  USDCNH: 'USD_CNH',
  // Metals
  XAUUSD: 'XAU_USD',
  XAGUSD: 'XAG_USD',
  XPTUSD: 'XPT_USD',
  XPDUSD: 'XPD_USD',
  // Indices
  NAS100: 'NAS100_USD',
  US30: 'US30_USD',
  SPX500: 'SPX500_USD',
  US2000: 'US2000_USD',
  GER40: 'DE30_EUR',
  UK100: 'UK100_GBP',
  FRA40: 'FR40_EUR',
  EU50: 'EU50_EUR',
  JP225: 'JP225_USD',
  AUS200: 'AU200_AUD',
  HK50: 'HK33_HKD',
  // Energy
  USOIL: 'WTICO_USD',
  UKOIL: 'BCO_USD',
  NATGAS: 'NATGAS_USD',
}

/**
 * Journal symbol → Twelve Data symbol. Forex pairs use a slash, which the
 * generic rule below covers. Indices are the vendor's cash-index tickers, so a
 * NAS100 chart shows the same 100-name basket a broker's CFD tracks rather than
 * a futures contract. Anything not listed returns null and is served by the
 * next provider in the chain.
 */
const TWELVE_DATA_SYMBOLS: Record<string, string> = {
  // Metals
  XAUUSD: 'XAU/USD',
  XAGUSD: 'XAG/USD',
  XPTUSD: 'XPT/USD',
  XPDUSD: 'XPD/USD',
  // Indices (cash indices, not futures). These two tickers are real, but Twelve
  // Data gates index data behind its Grow/Venture plans — on the free plan the
  // call is refused and the route falls through to the next provider. Anything
  // not mapped here (DAX, FTSE, Nikkei, energy) has no vendor symbol we could
  // confirm, so it goes straight to the fallback instead of burning a call.
  NAS100: 'NDX',
  SPX500: 'SPX',
}

export function parseChartRange(value: string | null): ChartRangeKey | null {
  if (!value) return null
  return Object.prototype.hasOwnProperty.call(CHART_RANGES, value)
    ? (value as ChartRangeKey)
    : null
}

/** `eur/usd` and `EUR USD` both become `EURUSD`. */
export function normalizeSymbol(value: string): string {
  return value.toUpperCase().replace(/[^A-Z0-9]/g, '')
}

/**
 * The OANDA name for a journal symbol. Hand-typed pairs outside the catalogue
 * still resolve (`EURGBP` → `EUR_GBP`); anything else returns null so the route
 * can serve it from the next provider.
 */
export function oandaInstrument(symbol: string): string | null {
  const mapped = OANDA_INSTRUMENTS[symbol]
  if (mapped) return mapped
  return /^[A-Z]{6}$/.test(symbol) ? `${symbol.slice(0, 3)}_${symbol.slice(3)}` : null
}

/**
 * The Twelve Data name for a journal symbol. Hand-typed pairs resolve through
 * the same `XXXYYY` → `XXX/YYY` rule, which also covers crypto quotes.
 */
export function twelveDataSymbol(symbol: string): string | null {
  const mapped = TWELVE_DATA_SYMBOLS[symbol]
  if (mapped) return mapped
  return /^[A-Z]{6}$/.test(symbol) ? `${symbol.slice(0, 3)}/${symbol.slice(3)}` : null
}

/** OANDA `price=M` candles, strings included, sorted oldest → newest. */
export function normalizeOandaCandles(payload: unknown): Candle[] {
  const rows = asRecord(payload)?.candles
  if (!Array.isArray(rows)) return []

  const candles: Candle[] = []
  for (const row of rows) {
    const candle = asRecord(row)
    const mid = asRecord(candle?.mid)
    const time = typeof candle?.time === 'string' ? Date.parse(candle.time) : NaN
    const o = numberAt(mid?.o)
    const h = numberAt(mid?.h)
    const l = numberAt(mid?.l)
    const c = numberAt(mid?.c)
    if (!Number.isFinite(time) || o === null || h === null || l === null || c === null) continue
    candles.push({ t: time, o, h, l, c })
  }
  return candles.sort((a, b) => a.t - b.t)
}

/**
 * Twelve Data `time_series` rows, oldest → newest. `datetime` arrives in UTC as
 * `2026-10-30 10:05:00` (or `2026-10-30` on daily intervals), and the numbers
 * arrive as strings.
 */
export function normalizeTwelveDataCandles(payload: unknown): Candle[] {
  const rows = asRecord(payload)?.values
  if (!Array.isArray(rows)) return []

  const candles: Candle[] = []
  for (const row of rows) {
    const candle = asRecord(row)
    const t = parseTimestamp(candle?.datetime)
    const o = numberAt(candle?.open)
    const h = numberAt(candle?.high)
    const l = numberAt(candle?.low)
    const c = numberAt(candle?.close)
    if (t === null || o === null || h === null || l === null || c === null) continue
    candles.push({ t, o, h, l, c })
  }
  return candles.sort((a, b) => a.t - b.t)
}

/** Legacy feed candles, sorted oldest → newest, empty quotes dropped. */
export function normalizeYahooCandles(payload: unknown): Candle[] {
  const results = asRecord(asRecord(payload)?.chart)?.result
  const first = Array.isArray(results) ? asRecord(results[0]) : null
  const timestamps = first?.timestamp
  const quotes = asRecord(first?.indicators)?.quote
  const quote = Array.isArray(quotes) ? asRecord(quotes[0]) : null
  if (!Array.isArray(timestamps) || !quote) return []

  const candles: Candle[] = []
  for (let i = 0; i < timestamps.length; i += 1) {
    const seconds = numberAt(timestamps[i])
    const o = numberAt(valueAt(quote.open, i))
    const h = numberAt(valueAt(quote.high, i))
    const l = numberAt(valueAt(quote.low, i))
    const c = numberAt(valueAt(quote.close, i))
    if (seconds === null || o === null || h === null || l === null || c === null) continue
    candles.push({ t: Math.round(seconds * 1000), o, h, l, c })
  }
  return candles.sort((a, b) => a.t - b.t)
}

/** Twelve Data reports refusals as `{ status: 'error', code, message }`. */
export function twelveDataErrorMessage(payload: unknown): string | null {
  const record = asRecord(payload)
  if (!record || record.status !== 'error') return null
  const message = record.message
  return typeof message === 'string' && message.trim() ? message : null
}

/** OANDA reports refusals as `{ errorMessage, errorCode }`. */
export function oandaErrorMessage(payload: unknown): string | null {
  const message = asRecord(payload)?.errorMessage
  return typeof message === 'string' && message.trim() ? message : null
}

/** The legacy feed reports refusals as `chart.error.description`. */
export function yahooErrorMessage(payload: unknown): string | null {
  const description = asRecord(asRecord(asRecord(payload)?.chart)?.error)?.description
  return typeof description === 'string' && description.trim() ? description : null
}

/** A requested slice of history, in epoch milliseconds. */
export interface CandleWindow {
  from: number
  to: number
}

/**
 * Longest window the route will ask a vendor for. The chart only jumps by one
 * range at a time (a day, five days or a month), so anything larger is a probe
 * for free history and would burn the vendor's per-request candle cap.
 */
export const MAX_WINDOW_SPAN_MS = 62 * 24 * 60 * 60 * 1000

/**
 * Parses the `from`/`to` query pair. Accepts epoch milliseconds or any ISO 8601
 * string; returns null when either bound is missing, unreadable, backwards or
 * wider than the cap, so the route can answer with one clear message.
 */
export function parseWindow(
  fromRaw: string | null,
  toRaw: string | null
): CandleWindow | null {
  const from = parseInstant(fromRaw)
  const to = parseInstant(toRaw)
  if (from === null || to === null) return null
  if (to <= from) return null
  if (to - from > MAX_WINDOW_SPAN_MS) return null
  return { from, to }
}

/** Twelve Data wants `YYYY-MM-DD HH:mm:ss` in the requested timezone (UTC). */
export function twelveDataDate(ms: number): string {
  const date = new Date(ms)
  const pad = (value: number) => String(value).padStart(2, '0')
  return (
    `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ` +
    `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`
  )
}

/** OANDA wants RFC3339 and rejects the fractional seconds of `toISOString()`. */
export function oandaDate(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')
}

export interface ProviderEnv {
  MARKET_DATA_PROVIDER?: string
  TWELVE_DATA_API_KEY?: string
  OANDA_API_TOKEN?: string
}

/**
 * Providers to try, best first.
 *
 * `MARKET_DATA_PROVIDER` pins one (with the delayed feed still behind it, so a
 * vendor outage never blanks a chart). Unset means "use whatever is configured",
 * preferring Twelve Data over OANDA — switching back is one env var, not a
 * deploy.
 */
export function candleProviderChain(env: ProviderEnv): CandleSource[] {
  const forced = (env.MARKET_DATA_PROVIDER ?? '').trim().toLowerCase()
  const pinned =
    forced === 'twelvedata' || forced === 'oanda' || forced === 'yahoo' ? forced : null

  const available: CandleSource[] = []
  if (env.TWELVE_DATA_API_KEY) available.push('twelvedata')
  if (env.OANDA_API_TOKEN) available.push('oanda')

  const chain: CandleSource[] = []
  // A pinned provider wins, but only if its key exists — asking for OANDA
  // without a token should not turn the chart off.
  if (pinned && pinned !== 'yahoo' && available.includes(pinned)) chain.push(pinned)
  for (const provider of available) {
    if (!chain.includes(provider)) chain.push(provider)
  }
  if (!chain.includes('yahoo')) chain.push('yahoo')
  return chain
}

function parseInstant(value: string | null): number | null {
  if (!value) return null
  const text = value.trim()
  if (!text) return null
  // Epoch milliseconds are all digits and far longer than any ISO year.
  const numeric = Number(text)
  if (text.length > 6 && Number.isFinite(numeric)) return numeric
  const parsed = Date.parse(text)
  return Number.isFinite(parsed) ? parsed : null
}

function parseTimestamp(value: unknown): number | null {
  if (typeof value !== 'string') return null
  const text = value.trim()
  if (!text) return null

  const normalized = /^\d{4}-\d{2}-\d{2}$/.test(text)
    ? `${text}T00:00:00Z`
    : /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(text)
      ? `${text.replace(' ', 'T')}Z`
      : text

  const parsed = Date.parse(normalized)
  return Number.isFinite(parsed) ? parsed : null
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function valueAt(list: unknown, index: number): unknown {
  return Array.isArray(list) ? list[index] : undefined
}

function numberAt(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value !== 'string') return null
  // `Number('')` is 0, and every vendor here sends empty strings for a bar that
  // did not print. Without this guard a missing price becomes a zero candle.
  const text = value.trim()
  if (!text) return null
  const parsed = Number(text)
  return Number.isFinite(parsed) ? parsed : null
}
