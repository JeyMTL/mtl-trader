'use client'

import { useMemo, useState } from 'react'
import { CandlestickChart, Info } from 'lucide-react'
import {
  MARKET_VIEW_INSTRUMENTS,
  MARKET_VIEW_INTERVALS,
  marketViewUrl,
  tradingViewSymbol,
  type MarketInterval,
} from '@/lib/market-widget'
import { cn } from '@/lib/utils'

/**
 * Market view: prices by TradingView, in TradingView's own frame.
 *
 * It replaces the desk chart while the app has no feed it can legally draw, so
 * it is deliberately not a chart of *your* trades: there is no journal data on
 * this screen, no saved drawing and nothing to pin. Keeping the two apart is
 * what makes it honest — the prices a customer sees here may differ from their
 * broker's by spread and venue, and a chart that looked like the old one would
 * invite exactly the wrong reading.
 */
export function MarketView({ initialSymbol }: { initialSymbol?: string }) {
  const instruments = useMemo(() => {
    const list = MARKET_VIEW_INSTRUMENTS.map((code) => ({
      code,
      symbol: tradingViewSymbol(code) as string,
      label: code.length === 6 ? `${code.slice(0, 3)}/${code.slice(3)}` : code,
    }))
    return list
  }, [])

  const first = instruments[0]
  const [instrument, setInstrument] = useState<string>(() => {
    const wanted = initialSymbol ? tradingViewSymbol(initialSymbol) : null
    return instruments.find((item) => item.symbol === wanted)?.code ?? first.code
  })
  const [size, setSize] = useState<MarketInterval>('15m')
  const [theme, setTheme] = useState<'dark' | 'light'>('dark')

  const selected = instruments.find((item) => item.code === instrument) ?? first
  const url = marketViewUrl({ symbol: selected.symbol, interval: size, theme })

  return (
    <div className="mx-auto w-full max-w-6xl space-y-3 px-3 py-3 lg:px-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-lg font-bold tracking-tight text-white">
            <CandlestickChart className="h-4 w-4 text-primary" />
            Market view
          </h1>
          <p className="mt-0.5 max-w-2xl text-[11px] leading-relaxed text-gray-500">
            Live market prices from TradingView. This is not your journal and not
            your broker&apos;s feed — it is a free public chart to check a level
            against, while the journaled chart is offline.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <label className="sr-only" htmlFor="market-instrument">
            Instrument
          </label>
          <select
            id="market-instrument"
            value={instrument}
            onChange={(event) => setInstrument(event.target.value)}
            className="rounded-lg border border-border bg-surface px-2.5 py-1.5 text-xs text-gray-200"
          >
            {instruments.map((item) => (
              <option key={item.code} value={item.code}>
                {item.label}
              </option>
            ))}
          </select>

          <div className="flex overflow-hidden rounded-lg border border-border">
            {(Object.keys(MARKET_VIEW_INTERVALS) as MarketInterval[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => setSize(key)}
                aria-pressed={size === key}
                className={cn(
                  'px-2.5 py-1.5 text-[11px] font-medium transition-colors',
                  size === key
                    ? 'bg-primary/15 text-white'
                    : 'text-gray-400 hover:text-white'
                )}
              >
                {MARKET_VIEW_INTERVALS[key].label}
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={() => setTheme((current) => (current === 'dark' ? 'light' : 'dark'))}
            className="rounded-lg border border-border px-2.5 py-1.5 text-[11px] font-medium text-gray-300 transition-colors hover:text-white"
          >
            {theme === 'dark' ? 'Light' : 'Dark'}
          </button>
        </div>
      </div>

      {/* `key` on the URL: the embed reads its settings on load, so a new symbol
          or size is a new frame rather than a frame asked to change its mind. */}
      <iframe
        key={url}
        src={url}
        title={`${selected.label} market chart by TradingView`}
        className="h-[70vh] min-h-[420px] w-full rounded-xl border border-border bg-surface"
        allowFullScreen
        referrerPolicy="strict-origin-when-cross-origin"
      />

      <p className="flex items-start gap-1.5 text-[11px] leading-relaxed text-gray-500">
        <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
        Prices are supplied by TradingView and may be delayed or indicative
        depending on the venue. Your broker&apos;s executable price is the one in
        your terminal.
      </p>
    </div>
  )
}
