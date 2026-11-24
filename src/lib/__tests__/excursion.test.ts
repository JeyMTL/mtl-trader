import { describe, expect, it } from 'vitest'
import {
  giveBack,
  intervalForDuration,
  measureExcursion,
  median,
  summariseExcursions,
  type MeasuredTrade,
} from '@/lib/excursion'
import type { Candle } from '@/lib/market-candles'

const BAR = 60_000

function candle(t: number, low: number, high: number): Candle {
  return { t, o: low, h: high, l: low, c: (low + high) / 2, v: 0 }
}

function trade(overrides: Partial<MeasuredTrade> = {}): MeasuredTrade {
  return {
    symbol: 'EURUSD',
    side: 'buy',
    setup: 'Breakout',
    mfe: 10,
    mae: 4,
    realised: 5,
    capture: 0.5,
    peakAtMs: 0,
    bars: 10,
    complete: true,
    ...overrides,
  }
}

describe('measureExcursion', () => {
  it('measures a long trade against the best and worst price while it was open', () => {
    const result = measureExcursion(
      { side: 'buy', entry: 100, exit: 105, openedAt: 0, closedAt: 3 * BAR },
      [candle(0, 98, 102), candle(BAR, 99, 110), candle(2 * BAR, 101, 106)],
      BAR
    )

    expect(result).not.toBeNull()
    expect(result?.mfe).toBe(10)
    expect(result?.mae).toBe(2)
    expect(result?.realised).toBe(5)
    expect(result?.capture).toBe(0.5)
    expect(result?.peakAtMs).toBe(BAR)
    expect(result?.complete).toBe(true)
  })

  it('inverts favourable and adverse for a short trade', () => {
    const result = measureExcursion(
      { side: 'sell', entry: 100, exit: 96, openedAt: 0, closedAt: 3 * BAR },
      [candle(0, 97, 103), candle(BAR, 90, 101), candle(2 * BAR, 95, 99)],
      BAR
    )

    expect(result?.mfe).toBe(10)
    expect(result?.mae).toBe(3)
    expect(result?.realised).toBe(4)
    expect(result?.capture).toBe(0.4)
    expect(result?.peakAtMs).toBe(BAR)
  })

  it('reports no capture when the trade never went the trader’s way', () => {
    const result = measureExcursion(
      { side: 'buy', entry: 100, exit: 97, openedAt: 0, closedAt: 2 * BAR },
      [candle(0, 98, 99), candle(BAR, 96, 99.5)],
      BAR
    )

    expect(result?.mfe).toBe(0)
    expect(result?.mae).toBe(4)
    expect(result?.capture).toBeNull()
    expect(giveBack(null)).toBeNull()
  })

  it('marks a series that starts after the fill as incomplete', () => {
    const result = measureExcursion(
      { side: 'buy', entry: 100, exit: 105, openedAt: 0, closedAt: 5 * BAR },
      [candle(3 * BAR, 99, 106), candle(4 * BAR, 101, 108)],
      BAR
    )

    expect(result).not.toBeNull()
    // The best price may well have happened before the first bar we have.
    expect(result?.complete).toBe(false)
  })

  it('ignores bars outside the trade and refuses a zero-length window', () => {
    const result = measureExcursion(
      { side: 'buy', entry: 100, exit: 101, openedAt: 0, closedAt: 2 * BAR },
      [candle(-10 * BAR, 1, 500), candle(0, 99, 101), candle(20 * BAR, 1, 500)],
      BAR
    )

    expect(result?.mfe).toBe(1)
    expect(result?.mae).toBe(1)
    expect(
      measureExcursion(
        { side: 'buy', entry: 100, exit: 100, openedAt: 0, closedAt: 0 },
        [candle(0, 99, 101)],
        BAR
      )
    ).toBeNull()
  })
})

describe('intervalForDuration', () => {
  it('scales the candle size with the holding time', () => {
    expect(intervalForDuration(30 * 60_000)).toBe('1m')
    expect(intervalForDuration(6 * 3_600_000)).toBe('5m')
    expect(intervalForDuration(2 * 86_400_000)).toBe('15m')
    expect(intervalForDuration(10 * 86_400_000)).toBe('1h')
    expect(intervalForDuration(30 * 86_400_000)).toBe('4h')
  })
})

describe('median', () => {
  it('averages the middle pair for an even count and ignores non-finite values', () => {
    expect(median([1, 3, 2])).toBe(2)
    expect(median([1, 2, 3, 4])).toBe(2.5)
    expect(median([1, Number.NaN, 5])).toBe(3)
    expect(median([])).toBeNull()
  })
})

describe('summariseExcursions', () => {
  it('uses medians and leaves trades without a capture out of the ratio', () => {
    const summary = summariseExcursions([
      trade({ capture: 0.2, mfe: 10, mae: 2, setup: 'Breakout' }),
      trade({ capture: 0.6, mfe: 20, mae: 4, setup: 'Breakout' }),
      trade({ capture: null, mfe: 0, mae: 8, setup: 'Reversal' }),
    ])

    expect(summary.measured).toBe(3)
    expect(summary.captureMedian).toBe(0.4)
    expect(summary.giveBackMedian).toBe(0.6)
    expect(summary.mfeMedian).toBe(10)
    expect(summary.maeMedian).toBe(4)
  })

  it('groups by setup and symbol, busiest first', () => {
    const summary = summariseExcursions([
      trade({ setup: 'Breakout', symbol: 'EURUSD' }),
      trade({ setup: 'Breakout', symbol: 'EURUSD' }),
      trade({ setup: 'Reversal', symbol: 'XAUUSD' }),
    ])

    expect(summary.bySetup[0]).toMatchObject({ key: 'Breakout', measured: 2 })
    expect(summary.bySymbol[0]).toMatchObject({ key: 'EURUSD', measured: 2 })
    expect(summary.bySetup.find((bucket) => bucket.key === 'Reversal')?.measured).toBe(1)
  })

  it('reports efficiency as mfe over the total move, and nothing for a flat trade', () => {
    const summary = summariseExcursions([trade({ mfe: 10, mae: 10 }), trade({ mfe: 0, mae: 0 })])

    expect(summary.efficiencyMedian).toBe(0.5)
  })
})
