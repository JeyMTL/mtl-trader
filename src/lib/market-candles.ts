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

export type ChartIntervalKey =
  | '5s'
  | '10s'
  | '15s'
  | '30s'
  | '45s'
  | '1m'
  | '5m'
  | '15m'
  | '30m'
  | '1h'
  | '4h'
  | '1d'

export type CandleSource = 'oanda'

/** How long a live series may be reused; the last candle keeps moving. */
export const LIVE_TTL_MS = 10_000

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
  /**
   * Vendor bars per output bar, for a size OANDA does not quote itself.
   *
   * OANDA offers 5, 10, 15 and 30 seconds but not 45, so a 45-second bar is
   * three 15-second bars bucketed on the same clock grid. The data is the
   * vendor's; only the grouping is ours.
   */
  aggregate?: number
}

/**
 * Candle sizes the chart offers. `count` is sized so the live view covers a
 * useful span at each resolution without approaching the vendor's per-request
 * cap: 4 hours of minutes, a month of hours, or a year of daily bars.
 */
export const CANDLE_INTERVALS: Record<ChartIntervalKey, IntervalSpec> = {
  // Seconds. OANDA keeps a few thousand bars at these sizes, so the counts
  // cover a session or two rather than a week.
  '5s': { granularity: 'S5', count: 600, ms: 5_000 },
  '10s': { granularity: 'S10', count: 600, ms: 10_000 },
  '15s': { granularity: 'S15', count: 720, ms: 15_000 },
  '30s': { granularity: 'S30', count: 720, ms: 30_000 },
  '45s': {
    granularity: 'S15',
    count: 720,
    ms: 45_000,
    aggregate: 3,
  },
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

/**
 * How long a live series may be reused.
 *
 * Half a bar, so the newest candle is never more than half-formed when it is
 * drawn — a 20-second rule on a 5-second chart would show a bar three bars old
 * and call it live. Bounded to ten seconds so a one-minute or hourly chart is
 * never ten seconds behind the broker for no reason.
 */
export function liveTtlMs(interval: ChartIntervalKey): number {
  return Math.max(1_500, Math.min(LIVE_TTL_MS, CANDLE_INTERVALS[interval].ms / 2))
}

/**
 * How often a live chart should ask again.
 *
 * Slightly faster than the server's cache for sub-minute sizes so the moving
 * bar is seen within a fraction of its own length, and slower for the long
 * sizes, where a new tick barely changes the shape of the candle and a request
 * every few seconds would only spend the vendor's quota.
 */
export function livePollMs(interval: ChartIntervalKey): number {
  const bar = CANDLE_INTERVALS[interval].ms
  if (bar >= 86_400_000) return 60_000
  if (bar >= 14_400_000) return 30_000
  if (bar >= 900_000) return 20_000
  if (bar >= 60_000) return 10_000
  return Math.max(2_000, Math.round(bar / 2))
}

/**
 * How often to ask for just the moving bars.
 *
 * The tail endpoint sends three candles instead of the whole series, so it can
 * be asked once a second without moving the chart's weight over the wire. Long
 * sizes gain nothing from a second-by-second close, so they slow down.
 */
export function tailPollMs(interval: ChartIntervalKey): number {
  const bar = CANDLE_INTERVALS[interval].ms
  if (bar >= 86_400_000) return 5_000
  if (bar >= 14_400_000) return 5_000
  if (bar >= 900_000) return 2_000
  return 1_000
}

/**
 * Replaces the overlapping tail of a live series by open time.
 *
 * A poll returns the newest `count` bars, so it overlaps the old series and
 * drops the oldest bars off the front. Merging, rather than replacing, keeps the
 * history the trader has scrolled back to and lets the newest candle change
 * without the rest of the chart shifting under the pointer.
 */
export function mergeCandleTail(existing: Candle[], incoming: Candle[]): Candle[] {
  if (incoming.length === 0) return existing
  if (existing.length === 0) return incoming
  const byTime = new Map<number, Candle>()
  for (const candle of existing) byTime.set(candle.t, candle)
  for (const candle of incoming) byTime.set(candle.t, candle)
  return [...byTime.values()].sort((a, b) => a.t - b.t)
}

/**
 * Groups vendor candles into a larger size, on the fixed clock grid.
 *
 * A bucket that is still filling is dropped instead of being drawn as a short
 * candle: the chart is meant to show completed bars, and the in-progress one is
 * what the live poll is for.
 */
export function aggregateCandles(
  candles: Candle[],
  ms: number,
  barsPerCandle: number
): Candle[] {
  if (candles.length === 0 || barsPerCandle < 2) return candles
  const out: Candle[] = []
  const counts: number[] = []
  for (const candle of candles) {
    const bucket = Math.floor(candle.t / ms) * ms
    const index = out.length - 1
    if (index < 0 || out[index].t !== bucket) {
      out.push({ ...candle, t: bucket })
      counts.push(1)
      continue
    }
    const bar = out[index]
    bar.h = Math.max(bar.h, candle.h)
    bar.l = Math.min(bar.l, candle.l)
    bar.c = candle.c
    bar.v += candle.v
    counts[index] += 1
  }
  if (counts.length > 0 && counts[counts.length - 1] < barsPerCandle) {
    out.pop()
  }
  return out
}

/**
 * True when the vendor answered with its own trouble rather than with a verdict
 * on our request.
 *
 * OANDA fronts its API with Cloudflare, which reports an origin failure as a
 * non-standard 520 — that is why the check is a range and not a list of the
 * codes a server normally sends. A 429 belongs here too: the vendor refusing to
 * talk right now is not evidence that the symbol has no candles.
 */
export function isVendorOutage(status: number): boolean {
  return status === 429 || status >= 500
}

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
  if (/^[A-Z]{6}$/.test(symbol)) return `${symbol.slice(0, 3)}_${symbol.slice(3)}`
  // A broker's own symbol usually carries a suffix: XAUUSDM, NAS100CASH,
  // EURUSDA. Peel characters off the end and take the first name the catalogue
  // knows. Nothing is guessed out of a near match, so a symbol that genuinely
  // cannot be charted still answers null and the route says so.
  for (let end = symbol.length - 1; end >= 3; end -= 1) {
    const known = OANDA_INSTRUMENTS[symbol.slice(0, end)]
    if (known) return known
  }
  return null
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
