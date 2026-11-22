/**
 * Trading-session windows in exchange time, not in the viewer's time.
 *
 * The chart used to derive Asia, London and New York from fixed UTC hours,
 * which is exact in winter and an hour wrong for most of the year once London
 * or New York move to daylight saving — and it was wrong for every viewer whose
 * clock was not UTC. Sessions are wall-clock opening hours in the city that
 * names them, so they are defined in that city's IANA zone here and converted
 * to UTC instants. A trader in Lusaka, London or New York then sees the same
 * levels for the same candles.
 */

export type SessionName = 'Asia' | 'London' | 'New York'

export interface SessionHours {
  name: SessionName
  /** IANA zone the opening hours belong to. */
  zone: string
  /** Opening time, minutes after local midnight. */
  openMinute: number
  /** Closing time, minutes after local midnight. */
  closeMinute: number
  colour: string
}

export interface SessionWindow {
  name: SessionName
  from: number
  to: number
  colour: string
}

export const SESSIONS: readonly SessionHours[] = [
  // Tokyo 09:00–18:00 JST — the Asian cash session, 00:00–09:00 UTC.
  { name: 'Asia', zone: 'Asia/Tokyo', openMinute: 9 * 60, closeMinute: 18 * 60, colour: '#a78bfa' },
  // London 08:00–16:30 local — the London cash session.
  { name: 'London', zone: 'Europe/London', openMinute: 8 * 60, closeMinute: 16 * 60 + 30, colour: '#38bdf8' },
  // New York 08:00–17:00 local — the New York cash session.
  { name: 'New York', zone: 'America/New_York', openMinute: 8 * 60, closeMinute: 17 * 60, colour: '#fb923c' },
]

const DAY_MS = 86_400_000

const PART_FORMATTERS = new Map<string, Intl.DateTimeFormat>()

function partsFormatter(zone: string): Intl.DateTimeFormat {
  let formatter = PART_FORMATTERS.get(zone)
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone: zone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
    PART_FORMATTERS.set(zone, formatter)
  }
  return formatter
}

interface WallClock {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
}

/** The wall clock in `zone` at the instant `instant`. */
export function wallClock(instant: number, zone: string): WallClock {
  const parts = partsFormatter(zone).formatToParts(new Date(instant))
  const value = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((part) => part.type === type)?.value ?? '0')
  return {
    year: value('year'),
    month: value('month'),
    day: value('day'),
    hour: value('hour'),
    minute: value('minute'),
    second: value('second'),
  }
}

/**
 * How far `zone` is ahead of UTC at `instant`, in milliseconds.
 *
 * Derived by reading the wall clock back and comparing it with the same fields
 * taken as UTC, so daylight saving is included without a timezone database.
 */
export function zoneOffsetMs(instant: number, zone: string): number {
  const wall = wallClock(instant, zone)
  const asUtc = Date.UTC(wall.year, wall.month - 1, wall.day, wall.hour, wall.minute, wall.second)
  return asUtc - Math.floor(instant / 1000) * 1000
}

/** The UTC instant of a wall-clock time in `zone`. */
export function zonedTimeToUtc(
  year: number,
  month: number,
  day: number,
  minuteOfDay: number,
  zone: string
): number {
  const naive = Date.UTC(year, month - 1, day) + minuteOfDay * 60_000
  // Two passes: the first lands within the right offset, the second settles a
  // timestamp that crossed a daylight-saving boundary in between.
  let guess = naive - zoneOffsetMs(naive, zone)
  guess = naive - zoneOffsetMs(guess, zone)
  return guess
}

function sessionWindowOn(
  session: SessionHours,
  year: number,
  month: number,
  day: number
): SessionWindow {
  return {
    name: session.name,
    from: zonedTimeToUtc(year, month, day, session.openMinute, session.zone),
    to: zonedTimeToUtc(year, month, day, session.closeMinute, session.zone),
    colour: session.colour,
  }
}

/**
 * The most recent occurrence of every session at `instant`.
 *
 * When a city has not opened yet on its own calendar date, the previous day's
 * window is returned, so a chart loaded early in the Tokyo morning still has an
 * Asian range to draw rather than a gap.
 */
export function sessionWindows(instant: number): SessionWindow[] {
  return SESSIONS.map((session) => {
    const wall = wallClock(instant, session.zone)
    let window = sessionWindowOn(session, wall.year, wall.month, wall.day)
    if (window.from > instant) {
      const previous = new Date(Date.UTC(wall.year, wall.month - 1, wall.day) - DAY_MS)
      window = sessionWindowOn(
        session,
        previous.getUTCFullYear(),
        previous.getUTCMonth() + 1,
        previous.getUTCDate()
      )
    }
    return window
  })
}

/** Shifts a window by whole days, keeping its local opening hours. */
export function shiftSessionWindow(window: SessionWindow, days: number): SessionWindow {
  const session = SESSIONS.find((entry) => entry.name === window.name)
  if (!session) return window
  const wall = wallClock(window.from, session.zone)
  const shifted = new Date(Date.UTC(wall.year, wall.month - 1, wall.day) + days * DAY_MS)
  return sessionWindowOn(
    session,
    shifted.getUTCFullYear(),
    shifted.getUTCMonth() + 1,
    shifted.getUTCDate()
  )
}
