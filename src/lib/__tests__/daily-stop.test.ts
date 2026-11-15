import { describe, expect, it } from 'vitest'
import {
  computeDayState,
  isAfterStopEntry,
  normalizeDailyStop,
  normalizeLockMode,
  tradeInstant,
  type DailyStopRules,
  type TradeForDay,
} from '@/lib/daily-stop'

const utcRules: DailyStopRules = { limit: 250, maxTrades: 0, timeZone: 'UTC' }

function trade(pnl: number, close: string): TradeForDay {
  return { pnl, close_time: close }
}

describe('computeDayState', () => {
  it('bounds the day in UTC and measures only that day', () => {
    const state = computeDayState({
      rules: utcRules,
      now: new Date('2026-11-13T12:00:00Z'),
      trades: [
        trade(-100, '2026-11-13T09:00:00Z'),
        trade(-999, '2026-11-12T23:59:59Z'), // previous day
      ],
    })

    expect(state.dayKey).toBe('2026-11-13')
    expect(state.dayStart).toBe('2026-11-13T00:00:00.000Z')
    expect(state.dayEnd).toBe('2026-11-14T00:00:00.000Z')
    expect(state.tradesCount).toBe(1)
    expect(state.realizedPnl).toBe(-100)
    expect(state.lossUsed).toBe(100)
    expect(state.headroom).toBe(150)
    expect(state.state).toBe('inside')
    expect(state.breached).toBe(false)
    expect(state.stopAt).toBeNull()
  })

  it('follows the trader clock, not UTC, for the day boundary', () => {
    const rules: DailyStopRules = { limit: 250, maxTrades: 0, timeZone: 'Africa/Johannesburg' }
    const state = computeDayState({
      rules,
      now: new Date('2026-11-13T10:00:00Z'), // 12:00 in Johannesburg
      trades: [
        trade(-100, '2026-11-12T23:00:00Z'), // 01:00 on the 13th locally
        trade(-50, '2026-11-12T21:00:00Z'), // 23:00 on the 12th locally
      ],
    })

    expect(state.dayKey).toBe('2026-11-13')
    expect(state.dayStart).toBe('2026-11-12T22:00:00.000Z')
    expect(state.dayEnd).toBe('2026-11-13T22:00:00.000Z')
    expect(state.tradesCount).toBe(1)
    expect(state.realizedPnl).toBe(-100)
  })

  it('treats the exact limit as breached and leaves no headroom', () => {
    const state = computeDayState({
      rules: utcRules,
      now: new Date('2026-11-13T12:00:00Z'),
      trades: [trade(-250, '2026-11-13T09:00:00Z')],
    })

    expect(state.breached).toBe(true)
    expect(state.state).toBe('breached')
    expect(state.headroom).toBe(0)
    expect(state.stopAt).toBe('2026-11-13T09:00:00.000Z')
  })

  it('separates the trades taken after the stop', () => {
    const state = computeDayState({
      rules: utcRules,
      now: new Date('2026-11-13T12:00:00Z'),
      trades: [
        trade(-200, '2026-11-13T08:00:00Z'),
        trade(-100, '2026-11-13T09:00:00Z'), // crosses the limit
        trade(40, '2026-11-13T10:00:00Z'), // after stop
        trade(-60, '2026-11-13T11:00:00Z'), // after stop
      ],
    })

    expect(state.realizedPnl).toBe(-320)
    expect(state.breached).toBe(true)
    expect(state.afterStopCount).toBe(2)
    expect(state.stopAt).toBe('2026-11-13T09:00:00.000Z')
    expect(state.afterStopPnl).toBe(-20)
  })

  it('ends the day when the trade cap is reached', () => {
    const state = computeDayState({
      rules: { limit: 0, maxTrades: 2, timeZone: 'UTC' },
      now: new Date('2026-11-13T12:00:00Z'),
      trades: [
        trade(50, '2026-11-13T08:00:00Z'),
        trade(20, '2026-11-13T09:00:00Z'),
        trade(10, '2026-11-13T10:00:00Z'),
      ],
    })

    expect(state.breached).toBe(true)
    expect(state.capReached).toBe(true)
    expect(state.tradesRemaining).toBe(0)
    expect(state.afterStopCount).toBe(1)
    expect(state.afterStopPnl).toBe(10)
  })

  it('stays off when neither rule is set', () => {
    const state = computeDayState({
      rules: { limit: 0, maxTrades: 0, timeZone: 'UTC' },
      now: new Date('2026-11-13T12:00:00Z'),
      trades: [trade(-900, '2026-11-13T09:00:00Z')],
    })

    expect(state.configured).toBe(false)
    expect(state.state).toBe('off')
    expect(state.breached).toBe(false)
  })

  it('warns inside 80% of the loss budget', () => {
    const state = computeDayState({
      rules: utcRules,
      now: new Date('2026-11-13T12:00:00Z'),
      trades: [trade(-201, '2026-11-13T09:00:00Z')],
    })

    expect(state.state).toBe('inside')
    expect(state.atLimit).toBe(true)
    expect(state.breached).toBe(false)
  })
})

describe('isAfterStopEntry', () => {
  const day = { dayStart: '2026-11-13T00:00:00.000Z', dayEnd: '2026-11-14T00:00:00.000Z' }

  it('tags an entry dated inside a breached day', () => {
    expect(isAfterStopEntry(trade(-10, '2026-11-13T15:00:00Z'), day, true)).toBe(true)
  })

  it('does not tag when the day is not breached', () => {
    expect(isAfterStopEntry(trade(-10, '2026-11-13T15:00:00Z'), day, false)).toBe(false)
  })

  it('does not tag a trade from another day', () => {
    expect(isAfterStopEntry(trade(-10, '2026-11-14T01:00:00Z'), day, true)).toBe(false)
  })
})

describe('tradeInstant', () => {
  it('prefers the close time and falls back to the open time', () => {
    expect(tradeInstant({ pnl: 0, close_time: '2026-11-13T10:00:00Z' })?.toISOString()).toBe(
      '2026-11-13T10:00:00.000Z'
    )
    expect(
      tradeInstant({ pnl: 0, close_time: null, open_time: '2026-11-13T09:00:00Z' })?.toISOString()
    ).toBe('2026-11-13T09:00:00.000Z')
  })

  it('returns null for an unreadable timestamp', () => {
    expect(tradeInstant({ pnl: 0, close_time: 'not a date' })).toBeNull()
  })
})

describe('normalizeLockMode', () => {
  it('keeps the two real modes and treats anything else as off', () => {
    expect(normalizeLockMode('soft')).toBe('soft')
    expect(normalizeLockMode('hard')).toBe('hard')
    expect(normalizeLockMode('off')).toBe('off')
    expect(normalizeLockMode('HARD')).toBe('off')
    expect(normalizeLockMode(null)).toBe('off')
    expect(normalizeLockMode(undefined)).toBe('off')
  })
})

describe('normalizeDailyStop', () => {
  it('clamps the limit and the cap and resolves the zone', () => {
    expect(normalizeDailyStop({ limit: -5, maxTrades: 0, timeZone: 'PST' })).toEqual({
      limit: 0,
      maxTrades: 0,
      timeZone: 'America/Los_Angeles',
    })
    expect(normalizeDailyStop({ limit: 250.456, maxTrades: 400 })).toMatchObject({
      limit: 250.46,
      maxTrades: 100,
    })
  })
})
