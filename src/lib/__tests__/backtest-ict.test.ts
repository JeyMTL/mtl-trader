import { describe, expect, it } from 'vitest'
import {
  MAX_RULE_CONDITIONS,
  compileRuleStrategy,
  describeRuleSpec,
  gapLevels,
  inSession,
  normalizeRuleSpec,
} from '@/lib/backtest/rules'
import type { Bar } from '@/lib/backtest/types'

const base = Date.UTC(2026, 9, 1, 6, 0)
const minute = 60_000

function bar(open: number, high: number, low: number, close: number, index: number): Bar {
  return { time: base + index * minute, open, high, low, close }
}

const NO_SESSIONS: never[] = []

function spec(overrides: Record<string, unknown>) {
  return normalizeRuleSpec({
    name: 'test',
    summary: '',
    timeframe: 'M15',
    higherTimeframe: null,
    side: 'long',
    // A valid entry by default: normalization refuses a spec with nothing to run,
    // so the tests below vary only the part they are about.
    longEntry: [{ left: { series: 'close' }, op: 'above', right: { value: 0 } }],
    shortEntry: [],
    exit: [],
    stop: { type: 'percent', value: 1 },
    target: { type: 'r', value: 2 },
    notes: [],
    ...overrides,
  })
}

describe('gapLevels', () => {
  it('keeps a bullish gap alive while price trades into it, and drops it on a fill', () => {
    const bars = [
      bar(1.0, 1.1, 1.0, 1.05, 0),
      bar(1.05, 1.2, 1.05, 1.15, 1),
      bar(1.15, 1.3, 1.2, 1.28, 2), // low 1.20 clears bar 0's high 1.10
      bar(1.28, 1.29, 1.14, 1.2, 3), // trades into the gap, above its 1.10 floor
      bar(1.2, 1.21, 1.09, 1.1, 4), // trades through the floor: filled
    ]
    const levels = gapLevels(bars, 20)

    expect(levels.fvg_bottom[2]).toBeCloseTo(1.1, 6)
    expect(levels.fvg_top[2]).toBeCloseTo(1.2, 6)
    expect(levels.fvg_mid[2]).toBeCloseTo(1.15, 6)
    // The retracement must not erase the level being traded from.
    expect(levels.fvg_mid[3]).toBeCloseTo(1.15, 6)
    expect(levels.fvg_mid[4]).toBeNull()
  })

  it('finds a bearish gap above the market', () => {
    const bars = [
      bar(10.2, 10.5, 10.0, 10.1, 0),
      bar(10.1, 10.2, 9.8, 9.9, 1),
      bar(9.9, 9.5, 9.0, 9.2, 2), // high 9.50 sits below bar 0's low 10.00
    ]
    const levels = gapLevels(bars, 20)
    expect(levels.ifvg_top[2]).toBeCloseTo(10.0, 6)
    expect(levels.ifvg_bottom[2]).toBeCloseTo(9.5, 6)
    expect(levels.ifvg_mid[2]).toBeCloseTo(9.75, 6)
  })

  it('forgets a gap older than the lookback, even while it is still unfilled', () => {
    // Filler bars stay above the gap's floor, so expiry is the only thing that
    // can remove it — otherwise this would pass for the wrong reason.
    const bars = Array.from({ length: 12 }, (_, index) => bar(1.3, 1.35, 1.25, 1.32, index))
    bars[0] = bar(1.0, 1.1, 1.0, 1.05, 0)
    bars[2] = bar(1.15, 1.3, 1.2, 1.28, 2)
    const levels = gapLevels(bars, 3)
    expect(levels.fvg_mid[4]).toBeCloseTo(1.15, 6)
    expect(levels.fvg_mid[8]).toBeNull()
  })
})

describe('sessions', () => {
  it('matches a daytime window and an overnight one', () => {
    const london = [{ start: 7 * 60, end: 10 * 60 }]
    expect(inSession(london, Date.UTC(2026, 0, 1, 7, 0))).toBe(true)
    expect(inSession(london, Date.UTC(2026, 0, 1, 6, 59))).toBe(false)
    expect(inSession(london, Date.UTC(2026, 0, 1, 10, 0))).toBe(false)

    const overnight = [{ start: 22 * 60, end: 2 * 60 }]
    expect(inSession(overnight, Date.UTC(2026, 0, 1, 23, 0))).toBe(true)
    expect(inSession(overnight, Date.UTC(2026, 0, 1, 1, 30))).toBe(true)
    expect(inSession(overnight, Date.UTC(2026, 0, 1, 12, 0))).toBe(false)
  })

  it('treats no windows as every hour', () => {
    expect(inSession([], Date.UTC(2026, 0, 1, 3, 17))).toBe(true)
  })

  it('drops a zero-length window instead of reading it as all day', () => {
    const normalized = spec({ sessions: [{ start: 300, end: 300 }] })
    expect(normalized.sessions).toEqual([])
  })

  it('only opens trades inside the window', () => {
    const bars = [
      bar(100, 101, 99, 100.5, 0), // 06:00 UTC, outside
      bar(100, 101, 99, 100.5, 1), // 06:01, outside
      bar(100, 101, 99, 100.5, 2), // 06:02, outside
      bar(100, 101, 99, 100.5, 3), // 06:03, outside
    ]
    const inside = spec({
      sessions: [{ start: 6 * 60, end: 6 * 60 + 3 }],
      longEntry: [{ left: { series: 'close' }, op: 'above', right: { value: 0 } }],
    })
    const signals = compileRuleStrategy(inside).signals(bars, {})
    // 06:00–06:02 are inside the window, 06:03 is the exclusive end.
    expect(signals[0]?.action).toBe('long')
    expect(signals[2]?.action).toBe('long')
    expect(signals[3]).toBeNull()
  })

  it('describes the window in clock time', () => {
    const lines = describeRuleSpec(spec({ sessions: [{ start: 420, end: 600 }] }))
    expect(lines.join(' ')).toContain('07:00–10:00 UTC')
  })
})

describe('arithmetic operands', () => {
  it('keeps a nested expression and reports it in plain English', () => {
    const normalized = spec({
      longEntry: [
        {
          left: { series: 'close' },
          op: 'above',
          right: {
            expr: {
              op: 'div',
              left: {
                expr: {
                  op: 'add',
                  left: { series: 'fvg_top' },
                  right: { series: 'fvg_bottom' },
                },
              },
              right: { value: 2 },
            },
          },
        },
      ],
    })
    expect(normalized.longEntry[0]?.right.expr?.op).toBe('div')
    expect(describeRuleSpec(normalized).join(' ')).toContain(
      '(unfilled bullish gap top + unfilled bullish gap bottom) ÷ 2'
    )
  })

  it('refuses an expression nested past the depth limit', () => {
    const depth = (levels: number): Record<string, unknown> =>
      levels === 0
        ? { series: 'close' }
        : { expr: { op: 'add', left: { series: 'close' }, right: depth(levels - 1) } }

    const tooDeep = spec({
      side: 'both',
      longEntry: [{ left: depth(6), op: 'above', right: { value: 1 } }],
      shortEntry: [{ left: { series: 'close' }, op: 'below', right: { value: 1_000_000 } }],
    })
    // The condition has no usable operand, so nothing is left to run.
    expect(tooDeep.longEntry).toHaveLength(0)
    expect(tooDeep.side).toBe('short')
  })

  it('treats division by zero as no value, so the condition cannot fire', () => {
    const divided = spec({
      longEntry: [
        {
          left: { series: 'close' },
          op: 'above',
          right: {
            expr: { op: 'div', left: { series: 'close' }, right: { value: 0 } },
          },
        },
      ],
    })
    const bars = Array.from({ length: 5 }, (_, index) => bar(1, 1.1, 0.9, 1, index))
    const signals = compileRuleStrategy(divided).signals(bars, {})
    expect(signals.every((signal) => signal === null)).toBe(true)
  })
})

describe('condition budget', () => {
  it('allows six conditions and drops the rest', () => {
    expect(MAX_RULE_CONDITIONS).toBe(6)
    const condition = { left: { series: 'close' }, op: 'above', right: { value: 0 } }
    const normalized = spec({ longEntry: Array.from({ length: 9 }, () => condition) })
    expect(normalized.longEntry).toHaveLength(6)
  })

  it('defaults sessions to empty so a stored spec from before gains them', () => {
    const normalized = spec({})
    expect(normalized.sessions).toEqual(NO_SESSIONS)
  })
})
