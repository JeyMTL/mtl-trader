/**
 * The TradingView market view.
 *
 * The app used to draw its own candles from an OANDA token, and a personal
 * token licensed those prices to one person — showing them to anyone else was
 * redistribution, so the chart went dark (see `MARKET_CHARTS_ENABLED` in
 * `features.ts`). This is the licensed-by-construction replacement: TradingView
 * serves the prices inside their own iframe under their own terms, we never
 * touch a quote, and nothing a customer does here costs a vendor credit.
 *
 * Consequences that are deliberate, not oversights: no seconds, no overlays
 * computed from our data, no saved drawings, and no relation to the journal.
 * The instrument list is ours because a broker's symbol (`XAUUSDM`, `EUR_USD`,
 * `NAS100.cash`) is not a TradingView symbol, and a wrong guess shows an error
 * inside the frame rather than a chart.
 */

/** Candle sizes TradingView renders for free. Seconds are simply not offered. */
export const MARKET_VIEW_INTERVALS = {
  '1m': { label: '1m', tv: '1' },
  '5m': { label: '5m', tv: '5' },
  '15m': { label: '15m', tv: '15' },
  '30m': { label: '30m', tv: '30' },
  '1h': { label: '1h', tv: '60' },
  '4h': { label: '4h', tv: '240' },
  '1d': { label: '1d', tv: 'D' },
  '1W': { label: '1W', tv: 'W' },
  '1M': { label: '1M', tv: 'M' },
} as const

export type MarketInterval = keyof typeof MARKET_VIEW_INTERVALS

/**
 * Instruments the view offers, named the way the terminal names them.
 *
 * Each is mapped through `tradingViewSymbol`, so the list and the mapping are
 * checked against each other by the tests rather than drifting apart.
 */
export const MARKET_VIEW_INSTRUMENTS = [
  'EURUSD',
  'GBPUSD',
  'USDJPY',
  'AUDUSD',
  'USDCAD',
  'USDCHF',
  'XAUUSD',
  'XAGUSD',
  'BTCUSD',
  'ETHUSD',
  'US30',
  'NAS100',
  'SPX500',
  'GER40',
] as const

export type MarketInstrument = (typeof MARKET_VIEW_INSTRUMENTS)[number]

/**
 * Symbols whose TradingView home is not the default FX feed.
 *
 * Metals and crypto on TradingView's FX page come from a different venue than
 * the one traders usually compare against, so they are pinned to the exchange
 * whose quote matches the broker's; indices are pinned to Capital.com, whose
 * cash-index symbols are the ones with a 24/5 session and a US-dollar quote.
 */
const PINNED: Record<string, string> = {
  XAUUSD: 'OANDA:XAUUSD',
  XAGUSD: 'OANDA:XAGUSD',
  BTCUSD: 'COINBASE:BTCUSD',
  ETHUSD: 'COINBASE:ETHUSD',
  US30: 'CAPITALCOM:US30',
  NAS100: 'CAPITALCOM:US100',
  US100: 'CAPITALCOM:US100',
  USTEC: 'CAPITALCOM:US100',
  SPX500: 'CAPITALCOM:US500',
  US500: 'CAPITALCOM:US500',
  GER40: 'CAPITALCOM:DE40',
  DE40: 'CAPITALCOM:DE40',
  UK100: 'CAPITALCOM:UK100',
  // Capital.com lists the Nikkei as J225, not JP225; the 225 alias is a 404.
  JP225: 'CAPITALCOM:J225',
}

const CURRENCIES = new Set([
  'USD', 'EUR', 'JPY', 'GBP', 'AUD', 'CHF', 'CAD', 'NZD',
  'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF', 'TRY', 'ZAR',
  'MXN', 'SGD', 'HKD', 'CNH',
])

/** `EUR_USD`, `eur/usd` and `EURUSD` all mean the same pair. */
function compact(raw: string): string {
  // A symbol already carrying an exchange (`OANDA:EURUSD`) keeps only its code:
  // the mapping decides the venue, not whatever the caller guessed.
  const bare = raw.includes(':') ? raw.slice(raw.indexOf(':') + 1) : raw
  return bare.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
}

/**
 * Account-type tails brokers stick on a symbol: XAUUSDM, EURUSDRAW, NAS100CASH.
 * Longest first, so `MICRO` is never mistaken for a bare `M`.
 */
const SUFFIXES = ['MICRO', 'MINI', 'CASH', 'SPOT', 'RAW', 'ECN', 'PRO', 'M']

/**
 * A broker symbol to the symbol TradingView knows, or null when it cannot be
 * mapped confidently.
 *
 * Returning null is the point: a market view that silently charts EUR/USD
 * because the customer asked for `XPTUSD` is worse than one that says it does
 * not carry that instrument.
 */
export function tradingViewSymbol(raw: string): string | null {
  const code = compact(raw)
  if (!code) return null

  const direct = lookup(code)
  if (direct) return direct

  for (const suffix of SUFFIXES) {
    if (code.length > suffix.length && code.endsWith(suffix)) {
      const trimmed = lookup(code.slice(0, code.length - suffix.length))
      if (trimmed) return trimmed
    }
  }

  return null
}

function lookup(code: string): string | null {
  return PINNED[code] ?? (isPair(code) ? `FX:${code}` : null)
}

function isPair(code: string): boolean {
  return (
    code.length === 6 &&
    CURRENCIES.has(code.slice(0, 3)) &&
    CURRENCIES.has(code.slice(3))
  )
}

/**
 * The iframe URL.
 *
 * A plain iframe rather than TradingView's injected script: the script would be
 * third-party code running in our document, and the CSP that keeps this app
 * locked to `'self'` exists for a reason. An iframe needs one `frame-src`
 * exception and touches nothing else.
 *
 * Branding is left on. The widget is free on the condition that its attribution
 * stays visible.
 */
export function marketViewUrl(options: {
  symbol: string
  interval: MarketInterval
  theme?: 'dark' | 'light'
}): string {
  const theme = options.theme ?? 'dark'
  const params = new URLSearchParams({
    symbol: options.symbol,
    interval: MARKET_VIEW_INTERVALS[options.interval].tv,
    theme,
    style: '1',
    timezone: 'Etc/UTC',
    locale: 'en',
    hidesidetoolbar: '0',
    symboledit: '1',
    saveimage: '0',
    withdateranges: '1',
    hideideas: '1',
    toolbarbg: theme === 'light' ? 'f1f3f6' : '131722',
  })
  return `https://s.tradingview.com/widgetembed/?${params.toString()}`
}
