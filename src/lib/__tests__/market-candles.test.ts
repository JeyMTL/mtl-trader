import { describe, expect, it } from 'vitest'
import {
  CHART_RANGES,
  SOURCE_TTL_MS,
  candleProviderChain,
  oandaDate,
  parseWindow,
  twelveDataDate,
  normalizeOandaCandles,
  normalizeSymbol,
  normalizeTwelveDataCandles,
  normalizeYahooCandles,
  oandaInstrument,
  parseChartRange,
  twelveDataErrorMessage,
  twelveDataSymbol,
  yahooErrorMessage,
} from '@/lib/market-candles'

describe('chart ranges', () => {
  it('accepts exactly the ranges the mobile chart sends', () => {
    expect(parseChartRange('1d')).toBe('1d')
    expect(parseChartRange('5d')).toBe('5d')
    expect(parseChartRange('1mo')).toBe('1mo')
    expect(parseChartRange('1m')).toBeNull()
    expect(parseChartRange('')).toBeNull()
  })

  it('fills each window with candles from the matching granularity', () => {
    expect(CHART_RANGES['1d']).toMatchObject({ granularity: 'M5', count: 288, twelveInterval: '5min' })
    expect(CHART_RANGES['5d']).toMatchObject({ granularity: 'M15', count: 480, twelveInterval: '15min' })
    expect(CHART_RANGES['1mo']).toMatchObject({ granularity: 'H1', count: 744, twelveInterval: '1h' })
  })
})

describe('provider chain', () => {
  it('prefers Twelve Data over OANDA when both keys are present', () => {
    expect(candleProviderChain({ TWELVE_DATA_API_KEY: 'k', OANDA_API_TOKEN: 't' })).toEqual([
      'twelvedata',
      'oanda',
      'yahoo',
    ])
  })

  it('uses OANDA when it is the only key configured', () => {
    expect(candleProviderChain({ OANDA_API_TOKEN: 't' })).toEqual(['oanda', 'yahoo'])
  })

  it('still serves the delayed feed with no keys at all', () => {
    expect(candleProviderChain({})).toEqual(['yahoo'])
  })

  it('honours an explicit provider without dropping the fallback', () => {
    expect(
      candleProviderChain({ MARKET_DATA_PROVIDER: 'oanda', OANDA_API_TOKEN: 't' })
    ).toEqual(['oanda', 'yahoo'])
    expect(
      candleProviderChain({
        MARKET_DATA_PROVIDER: 'twelvedata',
        TWELVE_DATA_API_KEY: 'k',
        OANDA_API_TOKEN: 't',
      })
    ).toEqual(['twelvedata', 'oanda', 'yahoo'])
  })

  it('ignores a provider whose key is missing and an unknown value', () => {
    expect(candleProviderChain({ MARKET_DATA_PROVIDER: 'twelvedata' })).toEqual(['yahoo'])
    expect(candleProviderChain({ MARKET_DATA_PROVIDER: 'nonsense' })).toEqual(['yahoo'])
  })

  it('keeps the free Twelve Data budget alive with a longer cache window', () => {
    expect(SOURCE_TTL_MS.twelvedata).toBeGreaterThan(SOURCE_TTL_MS.oanda)
    expect(SOURCE_TTL_MS.yahoo).toBeGreaterThan(SOURCE_TTL_MS.twelvedata)
  })
})

describe('date windows', () => {
  it('accepts epoch milliseconds and ISO bounds', () => {
    const epochs = parseWindow('1793354400000', '1793440800000')
    expect(epochs).toEqual({ from: 1793354400000, to: 1793440800000 })

    const iso = parseWindow('2026-10-30T00:00:00.000Z', '2026-10-31T00:00:00.000Z')
    expect(iso).toEqual({
      from: Date.parse('2026-10-30T00:00:00.000Z'),
      to: Date.parse('2026-10-31T00:00:00.000Z'),
    })
  })

  it('rejects a half-sent, backwards or oversized window', () => {
    expect(parseWindow(null, '1793440800000')).toBeNull()
    expect(parseWindow('1793354400000', null)).toBeNull()
    expect(parseWindow('1793354400000', '1793354400000')).toBeNull()
    expect(parseWindow('1793440800000', '1793354400000')).toBeNull()
    expect(parseWindow('not-a-date', '1793354400000')).toBeNull()
    // 334 days is far past the 62-day cap.
    expect(parseWindow('2026-01-01T00:00:00Z', '2026-12-01T00:00:00Z')).toBeNull()
  })

  it('formats each vendor date without fractional seconds', () => {
    const ms = Date.UTC(2026, 9, 30, 13, 5, 9)
    expect(twelveDataDate(ms)).toBe('2026-10-30 13:05:09')
    expect(oandaDate(ms)).toBe('2026-10-30T13:05:09Z')
  })
})

describe('oandaInstrument', () => {
  it('translates journal tickers to OANDA names', () => {
    expect(oandaInstrument('EURUSD')).toBe('EUR_USD')
    expect(oandaInstrument('XAUUSD')).toBe('XAU_USD')
    expect(oandaInstrument('NAS100')).toBe('NAS100_USD')
    expect(oandaInstrument('GER40')).toBe('DE30_EUR')
    expect(oandaInstrument('USOIL')).toBe('WTICO_USD')
  })

  it('resolves a hand-typed pair that is not in the catalogue', () => {
    expect(oandaInstrument('EURRUB')).toBe('EUR_RUB')
  })

  it('declines symbols OANDA cannot quote', () => {
    expect(oandaInstrument('GOLD')).toBeNull()
    expect(oandaInstrument('XYZ')).toBeNull()
  })

  it('normalises separators and case before lookup', () => {
    expect(normalizeSymbol(' eur/usd ')).toBe('EURUSD')
    expect(normalizeSymbol('nas-100')).toBe('NAS100')
  })
})

describe('twelveDataSymbol', () => {
  it('translates journal tickers to Twelve Data names', () => {
    expect(twelveDataSymbol('EURUSD')).toBe('EUR/USD')
    expect(twelveDataSymbol('XAUUSD')).toBe('XAU/USD')
    expect(twelveDataSymbol('NAS100')).toBe('NDX')
    expect(twelveDataSymbol('SPX500')).toBe('SPX')
  })

  it('resolves pairs and crypto outside the catalogue', () => {
    expect(twelveDataSymbol('USDTRY')).toBe('USD/TRY')
    expect(twelveDataSymbol('BTCUSD')).toBe('BTC/USD')
  })

  it('declines symbols the vendor cannot quote', () => {
    expect(twelveDataSymbol('USOIL')).toBeNull()
    expect(twelveDataSymbol('GER40')).toBeNull()
    expect(twelveDataSymbol('XYZ')).toBeNull()
  })
})

describe('normalizeOandaCandles', () => {
  const payload = {
    instrument: 'EUR_USD',
    granularity: 'M5',
    candles: [
      {
        complete: true,
        volume: 120,
        time: '2026-10-30T10:05:00.000000000Z',
        mid: { o: '1.08420', h: '1.08465', l: '1.08401', c: '1.08450' },
      },
      {
        complete: true,
        volume: 98,
        time: '2026-10-30T10:00:00.000000000Z',
        mid: { o: '1.08400', h: '1.08430', l: '1.08390', c: '1.08420' },
      },
      {
        complete: false,
        time: '2026-10-30T10:10:00.000000000Z',
        mid: { o: '1.08450', h: null, l: '1.08440', c: '1.08460' },
      },
    ],
  }

  it('parses mid prices oldest first', () => {
    const candles = normalizeOandaCandles(payload)
    expect(candles).toHaveLength(2)
    expect(candles[0].c).toBe(1.0842)
    expect(candles[1].c).toBe(1.0845)
    expect(candles[0].t).toBeLessThan(candles[1].t)
    expect(candles[0].t).toBe(Date.parse('2026-10-30T10:00:00.000000000Z'))
  })

  it('returns nothing rather than throwing on a refusal', () => {
    expect(normalizeOandaCandles({ errorMessage: 'Instrument not found' })).toEqual([])
    expect(normalizeOandaCandles(null)).toEqual([])
  })
})

describe('normalizeTwelveDataCandles', () => {
  const payload = {
    meta: { symbol: 'EUR/USD', interval: '5min', timezone: 'UTC' },
    values: [
      { datetime: '2026-10-30 10:05:00', open: '1.0842', high: '1.0847', low: '1.0840', close: '1.0845' },
      { datetime: '2026-10-30 10:00:00', open: '1.0840', high: '1.0843', low: '1.0839', close: '1.0842' },
      { datetime: '2026-10-30 10:10:00', open: '', high: '1.0850', low: '1.0844', close: '1.0851' },
    ],
    status: 'ok',
  }

  it('parses string numbers as UTC, oldest first', () => {
    const candles = normalizeTwelveDataCandles(payload)
    expect(candles).toHaveLength(2)
    expect(candles[0].t).toBe(Date.parse('2026-10-30T10:00:00Z'))
    expect(candles[1].t).toBe(Date.parse('2026-10-30T10:05:00Z'))
    expect(candles[0]).toEqual({ t: Date.parse('2026-10-30T10:00:00Z'), o: 1.084, h: 1.0843, l: 1.0839, c: 1.0842 })
  })

  it('reads the date-only form used by daily intervals', () => {
    const candles = normalizeTwelveDataCandles({
      values: [{ datetime: '2026-10-30', open: '1.1', high: '1.2', low: '1.0', close: '1.15' }],
      status: 'ok',
    })
    expect(candles).toHaveLength(1)
    expect(candles[0].t).toBe(Date.parse('2026-10-30T00:00:00Z'))
  })

  it('returns nothing for a quota or symbol refusal served as HTTP 200', () => {
    expect(
      normalizeTwelveDataCandles({
        code: 429,
        message: 'API limit reached',
        status: 'error',
      })
    ).toEqual([])
    expect(normalizeTwelveDataCandles(null)).toEqual([])
  })

  it('reads the refusal message', () => {
    expect(
      twelveDataErrorMessage({ code: 404, message: 'symbol not found', status: 'error' })
    ).toBe('symbol not found')
    expect(twelveDataErrorMessage({ status: 'ok', values: [] })).toBeNull()
    expect(twelveDataErrorMessage(null)).toBeNull()
  })
})

describe('normalizeYahooCandles', () => {
  it('parses quotes and drops null rows', () => {
    const candles = normalizeYahooCandles({
      chart: {
        result: [
          {
            timestamp: [1793369400, 1793369100, 1793369700],
            indicators: {
              quote: [
                {
                  open: [1.1, 1.2, null],
                  high: [1.15, 1.25, null],
                  low: [1.05, 1.15, null],
                  close: [1.12, 1.18, null],
                },
              ],
            },
          },
        ],
        error: null,
      },
    })

    expect(candles).toHaveLength(2)
    expect(candles[0].o).toBe(1.2)
    expect(candles[0].t).toBe(1793369100000)
    expect(candles[1].c).toBe(1.12)
  })

  it('reads the feed error description', () => {
    expect(
      yahooErrorMessage({
        chart: { result: null, error: { description: 'No data found, symbol may be delisted' } },
      })
    ).toBe('No data found, symbol may be delisted')
    expect(yahooErrorMessage({ chart: { result: [], error: null } })).toBeNull()
  })
})
