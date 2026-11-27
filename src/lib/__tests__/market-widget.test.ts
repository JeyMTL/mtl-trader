import { describe, expect, it } from 'vitest'
import {
  MARKET_VIEW_INSTRUMENTS,
  MARKET_VIEW_INTERVALS,
  marketViewUrl,
  tradingViewSymbol,
} from '@/lib/market-widget'

describe('tradingViewSymbol', () => {
  it('maps every instrument the market view offers', () => {
    for (const code of MARKET_VIEW_INSTRUMENTS) {
      expect(tradingViewSymbol(code), code).toMatch(/^[A-Z]+:[A-Z0-9]+$/)
    }
  })

  it('sends plain pairs to the FX feed and pins the rest to their venue', () => {
    expect(tradingViewSymbol('EURUSD')).toBe('FX:EURUSD')
    expect(tradingViewSymbol('GBPJPY')).toBe('FX:GBPJPY')
    expect(tradingViewSymbol('XAUUSD')).toBe('OANDA:XAUUSD')
    expect(tradingViewSymbol('BTCUSD')).toBe('COINBASE:BTCUSD')
    expect(tradingViewSymbol('NAS100')).toBe('CAPITALCOM:US100')
    expect(tradingViewSymbol('US30')).toBe('CAPITALCOM:US30')
    // Capital.com spells the Nikkei J225: CAPITALCOM:JP225 is a 404 on TV.
    expect(tradingViewSymbol('JP225')).toBe('CAPITALCOM:J225')
  })

  it('reads the spellings brokers actually store', () => {
    // Separators.
    expect(tradingViewSymbol('EUR_USD')).toBe('FX:EURUSD')
    expect(tradingViewSymbol('eur/usd')).toBe('FX:EURUSD')
    expect(tradingViewSymbol(' eur usd ')).toBe('FX:EURUSD')
    // Exness and friends: account-type tails.
    expect(tradingViewSymbol('EURUSDM')).toBe('FX:EURUSD')
    expect(tradingViewSymbol('XAUUSDM')).toBe('OANDA:XAUUSD')
    expect(tradingViewSymbol('EURUSDRAW')).toBe('FX:EURUSD')
    expect(tradingViewSymbol('NAS100.cash')).toBe('CAPITALCOM:US100')
    // A venue someone else picked is not trusted over the mapping.
    expect(tradingViewSymbol('CAPITALCOM:XAUUSD')).toBe('OANDA:XAUUSD')
  })

  it('answers null rather than charting the wrong instrument', () => {
    expect(tradingViewSymbol('XPTUSD')).toBeNull()
    expect(tradingViewSymbol('AAPL')).toBeNull()
    expect(tradingViewSymbol('')).toBeNull()
    expect(tradingViewSymbol('   ')).toBeNull()
  })
})

describe('market view intervals', () => {
  it('offers no seconds, because TradingView does not render them for free', () => {
    expect(Object.keys(MARKET_VIEW_INTERVALS).filter((key) => key.endsWith('s'))).toEqual([])
  })

  it('sends TradingView its own interval codes in UTC', () => {
    const url = new URL(marketViewUrl({ symbol: 'FX:EURUSD', interval: '4h' }))

    expect(url.origin + url.pathname).toBe('https://s.tradingview.com/widgetembed/')
    expect(url.searchParams.get('symbol')).toBe('FX:EURUSD')
    expect(url.searchParams.get('interval')).toBe('240')
    expect(url.searchParams.get('timezone')).toBe('Etc/UTC')
    expect(url.searchParams.get('theme')).toBe('dark')
    // Attribution stays on: the widget is free on that condition.
    expect(url.searchParams.get('hidelogo')).toBeNull()
    expect(url.searchParams.get('saveimage')).toBe('0')
  })

  it('switches interval code and toolbar colour with the theme', () => {
    const daily = new URL(marketViewUrl({ symbol: 'CAPITALCOM:US30', interval: '1d' }))
    expect(daily.searchParams.get('interval')).toBe('D')

    const light = new URL(
      marketViewUrl({ symbol: 'FX:EURUSD', interval: '15m', theme: 'light' })
    )
    expect(light.searchParams.get('theme')).toBe('light')
    expect(light.searchParams.get('toolbarbg')).toBe('f1f3f6')
  })
})
