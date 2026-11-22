import { describe, expect, it } from 'vitest'
import {
  sessionWindows,
  shiftSessionWindow,
  wallClock,
  zoneOffsetMs,
  zonedTimeToUtc,
} from '../market-sessions'

const HOUR = 3_600_000

describe('market sessions', () => {
  it('reads the London wall clock behind UTC in winter and ahead in summer', () => {
    expect(zoneOffsetMs(Date.UTC(2026, 0, 15, 12), 'Europe/London')).toBe(0)
    expect(zoneOffsetMs(Date.UTC(2026, 6, 15, 12), 'Europe/London')).toBe(HOUR)
    expect(zoneOffsetMs(Date.UTC(2026, 0, 15, 12), 'America/New_York')).toBe(-5 * HOUR)
    expect(zoneOffsetMs(Date.UTC(2026, 6, 15, 12), 'America/New_York')).toBe(-4 * HOUR)
    expect(zoneOffsetMs(Date.UTC(2026, 0, 15, 12), 'Asia/Tokyo')).toBe(9 * HOUR)
  })

  it('places the Tokyo session at the same UTC hours all year', () => {
    const cases = [
      { month: 0, instant: Date.UTC(2026, 0, 15, 12) },
      { month: 6, instant: Date.UTC(2026, 6, 15, 12) },
    ]
    for (const { month, instant } of cases) {
      const asia = sessionWindows(instant).find((window) => window.name === 'Asia')!
      expect(asia.from).toBe(Date.UTC(2026, month, 15))
      expect(asia.to - asia.from).toBe(9 * HOUR)
    }
  })

  it('moves London and New York with daylight saving', () => {
    const summer = sessionWindows(Date.UTC(2026, 6, 15, 12))
    const londonSummer = summer.find((window) => window.name === 'London')!
    const newYorkSummer = summer.find((window) => window.name === 'New York')!
    // BST: 08:00–16:30 local is 07:00–15:30 UTC.
    expect(londonSummer.from).toBe(Date.UTC(2026, 6, 15, 7))
    expect(londonSummer.to).toBe(Date.UTC(2026, 6, 15, 15, 30))
    // EDT: 08:00–17:00 local is 12:00–21:00 UTC.
    expect(newYorkSummer.from).toBe(Date.UTC(2026, 6, 15, 12))
    expect(newYorkSummer.to).toBe(Date.UTC(2026, 6, 15, 21))

    // Mid-afternoon UTC keeps both sessions inside their own calendar day.
    const winter = sessionWindows(Date.UTC(2026, 0, 15, 18))
    const londonWinter = winter.find((window) => window.name === 'London')!
    const newYorkWinter = winter.find((window) => window.name === 'New York')!
    // GMT: 08:00–16:30 local is 08:00–16:30 UTC.
    expect(londonWinter.from).toBe(Date.UTC(2026, 0, 15, 8))
    expect(londonWinter.to).toBe(Date.UTC(2026, 0, 15, 16, 30))
    // EST: 08:00–17:00 local is 13:00–22:00 UTC.
    expect(newYorkWinter.from).toBe(Date.UTC(2026, 0, 15, 13))
    expect(newYorkWinter.to).toBe(Date.UTC(2026, 0, 15, 22))
  })

  it('does not report a session that has not opened yet as today', () => {
    // 00:30 UTC: London is still on the previous calendar day.
    const windows = sessionWindows(Date.UTC(2026, 6, 15, 0, 30))
    const london = windows.find((window) => window.name === 'London')!
    expect(london.from).toBe(Date.UTC(2026, 6, 14, 7))
    expect(london.to).toBe(Date.UTC(2026, 6, 14, 15, 30))
  })

  it('converts a wall time near a daylight-saving change without drifting', () => {
    // London springs forward on 2026-03-29; 08:00 local is then 07:00 UTC.
    expect(zonedTimeToUtc(2026, 3, 29, 8 * 60, 'Europe/London')).toBe(Date.UTC(2026, 2, 29, 7))
    // New York springs forward on 2026-03-08; 08:00 local is then 12:00 UTC.
    expect(zonedTimeToUtc(2026, 3, 8, 8 * 60, 'America/New_York')).toBe(Date.UTC(2026, 2, 8, 12))
    expect(wallClock(Date.UTC(2026, 2, 8, 12), 'America/New_York')).toMatchObject({
      year: 2026,
      month: 3,
      day: 8,
      hour: 8,
      minute: 0,
    })
  })

  it('shifts a window a day at a time and keeps local opening hours', () => {
    const london = sessionWindows(Date.UTC(2026, 6, 15, 12)).find(
      (window) => window.name === 'London'
    )!
    const previous = shiftSessionWindow(london, -1)
    expect(previous.from).toBe(Date.UTC(2026, 6, 14, 7))
    expect(previous.to).toBe(Date.UTC(2026, 6, 14, 15, 30))
  })
})
