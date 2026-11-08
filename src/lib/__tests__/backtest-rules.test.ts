import { describe, expect, it } from 'vitest'
import {
  compileRuleStrategy,
  describeRuleSpec,
  higherTimeframeRatio,
  normalizeRuleSpec,
  timeframeMinutes,
} from '@/lib/backtest/rules'
import { runBacktest } from '@/lib/backtest'
import type { Bar } from '@/lib/backtest/types'

const start = Date.UTC(2026, 9, 1)
const minute = 60_000

function trendBars(count: number): Bar[] {
  return Array.from({ length: count }, (_, index) => {
    const base = 100 + index * 0.1
    return {
      time: start + index * minute,
      open: base,
      high: base + 0.4,
      low: base - 0.4,
      close: base + 0.2,
    }
  })
}

const longOnly = {
  name: 'Trend follow',
  summary: 'Buy while price is above its five-bar average.',
  timeframe: 'M15',
  higherTimeframe: null,
  side: 'long',
  longEntry: [{ left: { series: 'close' }, op: 'above', right: { series: 'sma', period: 5 } }],
  shortEntry: [],
  exit: [],
  stop: { type: 'percent', value: 1 },
  target: { type: 'r', value: 2 },
  notes: [],
}

describe('timeframe labels', () => {
  it('normalises the common spellings', () => {
    expect(timeframeMinutes('15m')).toBe(15)
    expect(timeframeMinutes('H1')).toBe(60)
    expect(timeframeMinutes('4h')).toBe(240)
    expect(timeframeMinutes('1d')).toBe(1440)
  })

  it('only accepts a genuinely higher confirmation timeframe', () => {
    expect(higherTimeframeRatio('M15', 'H1')).toBe(4)
    expect(higherTimeframeRatio('H1', 'H4')).toBe(4)
    expect(higherTimeframeRatio('M15', 'M5')).toBeNull()
    expect(higherTimeframeRatio('M15', null)).toBeNull()
  })

  it('refuses a timeframe that does not divide into whole primary bars', () => {
    // 2.67 M15 bars per M40 bar: rounding would silently build 45-minute bars.
    expect(higherTimeframeRatio('M15', 'M40')).toBeNull()
    expect(higherTimeframeRatio('H1', 'H3')).toBe(3)
    // 10,080 M1 bars per W1 bar is exact, but beyond what the aggregator will
    // build; refusing is honest, whereas capping it would relabel 2,000 bars.
    expect(higherTimeframeRatio('M1', 'W1')).toBeNull()
    expect(higherTimeframeRatio('H1', 'D1')).toBe(24)
  })
})

describe('normalizeRuleSpec', () => {
  it('clamps values and drops a higher timeframe that is not higher', () => {
    const spec = normalizeRuleSpec({
      ...longOnly,
      higherTimeframe: 'M5',
      stop: { type: 'atr', value: 500 },
      target: { type: 'r', value: 1000 },
    })

    expect(spec.higherTimeframe).toBeNull()
    expect(spec.stop.type).toBe('atr')
    expect(spec.stop.value).toBeLessThanOrEqual(100_000)
    expect(spec.target.value).toBe(100)
  })

  it('drops an undescribed short side instead of inventing one', () => {
    const spec = normalizeRuleSpec({ ...longOnly, side: 'both' })
    expect(spec.side).toBe('long')
    expect(spec.shortEntry).toHaveLength(0)
  })

  it('refuses a reply with nothing runnable', () => {
    expect(() =>
      normalizeRuleSpec({
        ...longOnly,
        longEntry: [{ left: { series: 'moon_phase' }, op: 'above', right: { value: 1 } }],
      })
    ).toThrow(/no usable long entry/i)
  })

  it('rejects an unknown comparison rather than treating it as true', () => {
    expect(() =>
      normalizeRuleSpec({
        ...longOnly,
        longEntry: [{ left: { series: 'close' }, op: 'is_near', right: { value: 1 } }],
      })
    ).toThrow(/no usable long entry/i)
  })
})

describe('compiled rules', () => {
  it('places a percent stop and an R-multiple target around the signal close', () => {
    const spec = normalizeRuleSpec(longOnly)
    const bars = trendBars(40)
    const signals = compileRuleStrategy(spec).signals(bars, {})

    const index = signals.findIndex((signal) => signal?.action === 'long')
    expect(index).toBeGreaterThan(0)
    const signal = signals[index]!
    const close = bars[index]!.close

    expect(signal.stopPrice).toBeCloseTo(close - close * 0.01, 6)
    expect(signal.takeProfitPrice).toBeCloseTo(close + close * 0.01 * 2, 6)
  })

  it('cannot read a higher-timeframe bar before it has closed', () => {
    const spec = normalizeRuleSpec({
      ...longOnly,
      higherTimeframe: 'H1',
      longEntry: [
        { left: { series: 'close' }, op: 'above', right: { value: 1 } },
        {
          left: { series: 'close', timeframe: 'higher' },
          op: 'above',
          right: { value: 1 },
        },
      ],
    })

    const signals = compileRuleStrategy(spec).signals(trendBars(20), {})
    // The first completed H1 block is four M15 bars, so bar 4 is the first
    // decision that could legally see it.
    expect(signals.slice(0, 4).every((signal) => signal === null)).toBe(true)
    expect(signals[4]?.action).toBe('long')
  })

  it('closes on an exit condition', () => {
    const spec = normalizeRuleSpec({
      ...longOnly,
      exit: [{ left: { series: 'close' }, op: 'above', right: { series: 'sma', period: 2 } }],
    })
    const signals = compileRuleStrategy(spec).signals(trendBars(40), {})
    expect(signals.some((signal) => signal?.action === 'close')).toBe(true)
  })

  it('uses the promised default period when the model omits MACD length', () => {
    const closes = Array.from({ length: 90 }, (_, index) =>
      100 + Math.sin(index / 3) * 8
    )
    const bars: Bar[] = closes.map((close, index) => ({
      time: start + index * minute,
      open: close,
      high: close + 0.2,
      low: close - 0.2,
      close,
    }))
    const macdAboveZero = (period?: number) => ({
      ...longOnly,
      longEntry: [
        {
          left: { series: 'macd', ...(period ? { period } : {}) },
          op: 'above',
          right: { value: 0 },
        },
      ],
    })

    const omitted = compileRuleStrategy(normalizeRuleSpec(macdAboveZero())).signals(bars, {})
    const slow = compileRuleStrategy(normalizeRuleSpec(macdAboveZero(26))).signals(bars, {})
    const fast = compileRuleStrategy(normalizeRuleSpec(macdAboveZero(14))).signals(bars, {})

    expect(omitted).toEqual(slow)
    expect(omitted).not.toEqual(fast)
  })

  it('refuses to replay a custom spec against a different primary timeframe', () => {
    const spec = normalizeRuleSpec(longOnly)
    expect(() =>
      runBacktest({
        csv: 'unused',
        symbol: 'EURUSD',
        timeframe: 'M5',
        strategyId: 'custom',
        ruleSpec: spec,
      })
    ).toThrow(/compiled for M15/i)
  })

  it('describes itself in plain English for the trader', () => {
    const rules = describeRuleSpec(normalizeRuleSpec(longOnly))
    expect(rules.join(' ')).toContain('Long when close')
    expect(rules.join(' ')).toContain('Stop at 1% of price')
    expect(rules.join(' ')).toContain('target 2R')
  })
})
