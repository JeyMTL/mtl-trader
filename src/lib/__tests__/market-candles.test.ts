import { describe, expect, it } from 'vitest'
import {
  CANDLE_INTERVALS,
  MAX_CANDLES_PER_REQUEST,
  candlesForWindow,
  normalizeOandaCandles,
  normalizeSymbol,
  oandaDate,
  oandaInstrument,
  parseChartInterval,
  parseWindow,
} from '@/lib/market-candles'

describe('candle intervals', () => {
  it('accepts exactly the sizes the mobile chart offers', () => {
    for (const key of ['1m', '5m', '15m', '30m', '1h', '4h', '1d'] as const) {
      expect(parseChartInterval(key)).toBe(key)
    }
    expect(parseChartInterval('3m')).toBeNull()
    expect(parseChartInterval('1D')).toBeNull()
    expect(parseChartInterval('')).toBeNull()
    expect(parseChartInterval(null)).toBeNull()
  })

  it('maps each size onto an OANDA granularity', () => {
    expect(CANDLE_INTERVALS['1m'].granularity).toBe('M1')
    expect(CANDLE_INTERVALS['5m'].granularity).toBe('M5')
    expect(CANDLE_INTERVALS['15m'].granularity).toBe('M15')
    expect(CANDLE_INTERVALS['30m'].granularity).toBe('M30')
    expect(CANDLE_INTERVALS['1h'].granularity).toBe('H1')
    expect(CANDLE_INTERVALS['4h'].granularity).toBe('H4')
    expect(CANDLE_INTERVALS['1d'].granularity).toBe('D')
  })

  it('counts the bars a window needs and refuses past the vendor cap', () => {
    const day = { from: 0, to: 24 * 60 * 60 * 1000 }
    expect(candlesForWindow(day, '1m')).toBe(1440)
    expect(candlesForWindow(day, '5m')).toBe(288)
    expect(candlesForWindow(day, '1d')).toBe(1)

    const month = { from: 0, to: 30 * 24 * 60 * 60 * 1000 }
    expect(candlesForWindow(month, '1m')).toBeNull()
    expect(candlesForWindow(month, '1h')).toBe(720)
    expect(MAX_CANDLES_PER_REQUEST).toBe(5000)
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

  it('formats the vendor date without fractional seconds', () => {
    const ms = Date.UTC(2026, 9, 30, 13, 5, 9)
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

  it('declines symbols OANDA cannot be asked for', () => {
    expect(oandaInstrument('GOLD')).toBeNull()
    expect(oandaInstrument('DOGEUSD')).toBeNull()
    expect(oandaInstrument('XYZ')).toBeNull()
  })

  it('normalises separators and case before lookup', () => {
    expect(normalizeSymbol(' eur/usd ')).toBe('EURUSD')
    expect(normalizeSymbol('nas-100')).toBe('NAS100')
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
    // OANDA reports tick volume beside the mid prices.
    expect(candles[1].v).toBe(120)
    expect(candles[0].v).toBe(98)
    expect(candles[0].t).toBeLessThan(candles[1].t)
    expect(candles[0].t).toBe(Date.parse('2026-10-30T10:00:00.000000000Z'))
  })

  it('returns nothing rather than throwing on a refusal', () => {
    expect(normalizeOandaCandles({ errorMessage: 'Instrument not found' })).toEqual([])
    expect(normalizeOandaCandles(null)).toEqual([])
  })
})
