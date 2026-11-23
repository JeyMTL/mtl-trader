import { describe, expect, it } from 'vitest'
import {
  CANDLE_INTERVALS,
  MAX_CANDLES_PER_REQUEST,
  aggregateCandles,
  candlesForWindow,
  isVendorOutage,
  livePollMs,
  liveTtlMs,
  mergeCandleTail,
  normalizeOandaCandles,
  normalizeSymbol,
  oandaDate,
  oandaInstrument,
  parseChartInterval,
  parseWindow,
} from '@/lib/market-candles'

describe('vendor outages', () => {
  it('treats a 5xx or a throttle as the vendor being down', () => {
    // Cloudflare reports an OANDA origin failure as a non-standard 520.
    expect(isVendorOutage(520)).toBe(true)
    expect(isVendorOutage(500)).toBe(true)
    expect(isVendorOutage(503)).toBe(true)
    expect(isVendorOutage(429)).toBe(true)
    // A refused request is our fault and must stay a plain "no data".
    expect(isVendorOutage(400)).toBe(false)
    expect(isVendorOutage(401)).toBe(false)
    expect(isVendorOutage(404)).toBe(false)
  })
})

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

  it('serves the second sizes from OANDA and buckets 45s from 15s', () => {
    expect(CANDLE_INTERVALS['5s'].granularity).toBe('S5')
    expect(CANDLE_INTERVALS['10s'].granularity).toBe('S10')
    expect(CANDLE_INTERVALS['15s'].granularity).toBe('S15')
    expect(CANDLE_INTERVALS['30s'].granularity).toBe('S30')
    // OANDA has no 45-second size: three 15-second bars make one.
    expect(CANDLE_INTERVALS['45s'].granularity).toBe('S15')
    expect(CANDLE_INTERVALS['45s'].aggregate).toBe(3)
  })

  it('keeps the live cache inside half a bar', () => {
    expect(liveTtlMs('5s')).toBe(2500)
    // Bounded at ten seconds, so a slow bar is not ten seconds stale for nothing.
    expect(liveTtlMs('30s')).toBe(10000)
    expect(liveTtlMs('1d')).toBe(10000)
  })

  it('polls faster than the cache on short bars and slower on long ones', () => {
    expect(livePollMs('5s')).toBe(2500)
    expect(livePollMs('15s')).toBe(7500)
    expect(livePollMs('1m')).toBe(10000)
    expect(livePollMs('5m')).toBe(10000)
    expect(livePollMs('15m')).toBe(20000)
    expect(livePollMs('1h')).toBe(20000)
    expect(livePollMs('4h')).toBe(30000)
    expect(livePollMs('1d')).toBe(60000)
  })

  it('merges a polled tail by open time and keeps older history', () => {
    const bar = (t: number, c: number) => ({ t, o: c, h: c, l: c, c, v: 1 })
    const existing = [bar(0, 1), bar(60_000, 2), bar(120_000, 3)]
    // The tail overlaps the last bar and adds a new one.
    const incoming = [bar(120_000, 9), bar(180_000, 4)]
    expect(mergeCandleTail(existing, incoming)).toEqual([
      bar(0, 1),
      bar(60_000, 2),
      bar(120_000, 9),
      bar(180_000, 4),
    ])
    // An empty poll never erases a chart.
    expect(mergeCandleTail(existing, [])).toBe(existing)
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

describe('aggregateCandles', () => {
  const bar = (t: number, o: number, h: number, l: number, c: number, v: number) => ({
    t,
    o,
    h,
    l,
    c,
    v,
  })

  it('merges three 15-second bars into one 45-second bar', () => {
    const bars = [
      bar(0, 1.0, 1.1, 0.9, 1.05, 3),
      bar(15_000, 1.05, 1.2, 1.0, 1.15, 4),
      bar(30_000, 1.15, 1.25, 1.1, 1.2, 5),
      bar(45_000, 1.2, 1.3, 1.15, 1.25, 6),
      bar(60_000, 1.25, 1.35, 1.2, 1.3, 7),
      bar(75_000, 1.3, 1.4, 1.25, 1.35, 8),
    ]
    const merged = aggregateCandles(bars, 45_000, 3)
    expect(merged).toHaveLength(2)
    expect(merged[0]).toEqual({ t: 0, o: 1.0, h: 1.25, l: 0.9, c: 1.2, v: 12 })
    expect(merged[1]).toEqual({ t: 45_000, o: 1.2, h: 1.4, l: 1.15, c: 1.35, v: 21 })
  })

  it('drops a group that is still filling', () => {
    const bars = [
      bar(0, 1.0, 1.1, 0.9, 1.05, 3),
      bar(15_000, 1.05, 1.2, 1.0, 1.15, 4),
      bar(30_000, 1.15, 1.25, 1.1, 1.2, 5),
      bar(45_000, 1.2, 1.3, 1.15, 1.25, 6),
    ]
    expect(aggregateCandles(bars, 45_000, 3)).toHaveLength(1)
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

  it('sees through a broker suffix on the symbol', () => {
    // MT5 accounts name the same feed instrument with a suffix; the level
    // picker has to chart what the journal actually holds.
    expect(oandaInstrument('XAUUSDM')).toBe('XAU_USD')
    expect(oandaInstrument('EURUSDM')).toBe('EUR_USD')
    expect(oandaInstrument('NAS100CASH')).toBe('NAS100_USD')
    expect(oandaInstrument('US30MINI')).toBe('US30_USD')
  })

  it('still refuses a symbol that only looks like a pair', () => {
    expect(oandaInstrument('ABCXYZQ')).toBeNull()
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
