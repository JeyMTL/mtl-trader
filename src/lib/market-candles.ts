/**
 * Provider mapping and payload normalisation for `/api/market/candles`.
 *
 * The mobile chart used to read Yahoo's public chart feed directly. That feed
 * serves composite spot quotes — a few pips off a broker, with bad intraday
 * prints — and is delayed for the exchange-traded classes, so candles come
 * from OANDA v20 instead: it quotes forex, metals, indices and energy as CFDs,
 * which is the market a broker actually fills against. OANDA is the only
 * vendor; a symbol it does not quote answers with an error rather than a second
 * feed, so the chart never shows prices from an unnamed source.
 */

export type ChartIntervalKey = '1m' | '5m' | '15m' | '30m' | '1h' | '4h' | '1d'

export type CandleSource = 'oanda'

/** How long a live series may be reused; the last candle keeps moving. */
export const LIVE_TTL_MS = 20_000

export interface Candle {
  /** Candle open time, epoch milliseconds. */
  t: number
  o: number
  h: number
  l: number
  c: number
  /** Tick volume reported by the vendor; 0 when the bar carries none. */
  v: number
}

export interface CandleSeries {
  symbol: string
  interval: ChartIntervalKey
  source: CandleSource
  candles: Candle[]
}

interface IntervalSpec {
  /** OANDA granularity code. */
  granularity: string
  /** Candles to ask for when the client did not send a window. */
  count: number
  /** Length of one candle in milliseconds. */
  ms: number
}

/**
 * Candle sizes the chart offers. `count` is sized so the live view covers a
 * useful span at each resolution without approaching the vendor's per-request
 * cap: 4 hours of minutes, a month of hours, or a year of daily bars.
 */
export const CANDLE_INTERVALS: Record<ChartIntervalKey, IntervalSpec> = {
  '1m': { granularity: 'M1', count: 240, ms: 60_000 },
  '5m': { granularity: 'M5', count: 288, ms: 300_000 },
  '15m': { granularity: 'M15', count: 480, ms: 900_000 },
  '30m': { granularity: 'M30', count: 336, ms: 1_800_000 },
  '1h': { granularity: 'H1', count: 744, ms: 3_600_000 },
  '4h': { granularity: 'H4', count: 180, ms: 14_400_000 },
  '1d': { granularity: 'D', count: 365, ms: 86_400_000 },
}

/** OANDA refuses a request for more candles than this. */
export const MAX_CANDLES_PER_REQUEST = 5000

export function parseChartInterval(value: string | null): ChartIntervalKey | null {
  if (!value) return null
  return Object.prototype.hasOwnProperty.call(CANDLE_INTERVALS, value)
    ? (value as ChartIntervalKey)
    : null
}

/**
 * Bars a window needs at the requested size, or null when the window asks for
 * more than the vendor will return. The chart uses the same rule before it
 * sends the request, so the two never disagree.
 */
export function candlesForWindow(
  window: CandleWindow,
  interval: ChartIntervalKey
): number | null {
  const bars = Math.ceil((window.to - window.from) / CANDLE_INTERVALS[interval].ms)
  return bars > MAX_CANDLES_PER_REQUEST ? null : bars
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

export function normalizeSymbol(value: string): string {
  return value.toUpperCase().replace(/[^A-Z0-9]/g, '')
}

/**
 * The OANDA name for a journal symbol. Hand-typed pairs outside the catalogue
 * still resolve (`EURGBP` → `EUR_GBP`); anything else returns null, which the
 * route reports as an instrument it cannot chart.
 */
export function oandaInstrument(symbol: string): string | null {
  const mapped = OANDA_INSTRUMENTS[symbol]
  if (mapped) return mapped
  return /^[A-Z]{6}$/.test(symbol) ? `${symbol.slice(0, 3)}_${symbol.slice(3)}` : null
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
    // OANDA sends `volume` beside `mid`; a missing value is a quiet bar, not an
    // error, so it becomes 0 rather than dropping the candle.
    candles.push({ t: time, o, h, l, c, v: numberAt(candle?.volume) ?? 0 })
  }
  return candles.sort((a, b) => a.t - b.t)
}

/** OANDA reports refusals as `{ errorMessage, errorCode }`. */
export function oandaErrorMessage(payload: unknown): string | null {
  const message = asRecord(payload)?.errorMessage
  return typeof message === 'string' && message.trim() ? message : null
}

/** A requested slice of history, in epoch milliseconds. */
export interface CandleWindow {
  from: number
  to: number
}

/**
 * Longest window the route will serve at all. Anything larger is a probe for
 * free history; the bar-count guard above is what actually protects the vendor
 * cap at fine resolutions.
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

/** OANDA wants RFC3339 and rejects the fractional seconds of `toISOString()`. */
export function oandaDate(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')
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

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function numberAt(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value !== 'string') return null
  // `Number('')` is 0, and the vendor sends empty strings for a bar that did not
  // print. Without this guard a missing price becomes a zero candle.
  const text = value.trim()
  if (!text) return null
  const parsed = Number(text)
  return Number.isFinite(parsed) ? parsed : null
}
