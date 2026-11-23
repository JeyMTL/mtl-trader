/**
 * Timezone helpers shared by the daily-stop lock, prop rules and the day-state
 * routes.
 *
 * Calendar days are anchored to local midnight in the user's timezone
 * (defaulting to UTC). Users store a short label like `PST` or a full IANA name;
 * short labels are mapped to a representative IANA zone so DST is handled
 * correctly.
 */

/** Common labels from the settings dropdown, mapped to DST-aware IANA zones. */
const TIME_ZONE_ALIASES: Record<string, string> = {
  UTC: 'UTC',
  GMT: 'UTC',
  Z: 'UTC',
  EST: 'America/New_York',
  EDT: 'America/New_York',
  CST: 'America/Chicago',
  CDT: 'America/Chicago',
  MST: 'America/Denver',
  MDT: 'America/Denver',
  PST: 'America/Los_Angeles',
  PDT: 'America/Los_Angeles',
  CET: 'Europe/Paris',
  CEST: 'Europe/Paris',
  JST: 'Asia/Tokyo',
  AEST: 'Australia/Sydney',
  AEDT: 'Australia/Sydney',
}

/** Resolve a stored timezone label to a valid IANA zone, falling back to UTC. */
export function normalizeTimeZone(timeZone?: string | null): string {
  if (!timeZone) return 'UTC'
  const trimmed = timeZone.trim()
  if (!trimmed) return 'UTC'
  const candidate = TIME_ZONE_ALIASES[trimmed.toUpperCase()] ?? trimmed
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: candidate })
    return candidate
  } catch {
    return 'UTC'
  }
}

interface LocalParts {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
}

function localParts(date: Date, timeZone: string): LocalParts {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(date)
  const get = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0)
  return {
    year: get('year'),
    month: get('month'),
    day: get('day'),
    hour: get('hour') % 24,
    minute: get('minute'),
    second: get('second'),
  }
}

function zoneOffsetMs(date: Date, timeZone: string): number {
  const parts = localParts(date, timeZone)
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second)
  return asUtc - date.getTime()
}

/** The UTC instant at which the local calendar day starts in `timeZone`. */
function zonedStartOfDay(year: number, month: number, day: number, timeZone: string): Date {
  const naiveUtc = Date.UTC(year, month - 1, day, 0, 0, 0)
  const offset = zoneOffsetMs(new Date(naiveUtc), timeZone)
  const candidate = new Date(naiveUtc - offset)
  // Re-derive once in case the offset shifts at a DST boundary.
  const refined = zoneOffsetMs(candidate, timeZone)
  return refined === offset ? candidate : new Date(naiveUtc - refined)
}

/**
 * The local calendar day containing `date`, with its UTC bounds.
 *
 * `end` is the start of the next local day, not `start + 24h`: a day around a
 * DST change is 23 or 25 hours long, and a daily loss window has to follow the
 * trader's clock rather than a fixed duration.
 */
export function zonedDayBounds(
  date: Date,
  timeZone: string | null = 'UTC'
): { key: string; start: Date; end: Date } {
  const tz = normalizeTimeZone(timeZone)
  const { year, month, day } = localParts(date, tz)
  const start = zonedStartOfDay(year, month, day, tz)
  // Add one calendar day before resolving its midnight: doing it in UTC first
  // keeps month-end and year-end rollovers correct.
  const next = new Date(Date.UTC(year, month - 1, day + 1))
  const end = zonedStartOfDay(
    next.getUTCFullYear(),
    next.getUTCMonth() + 1,
    next.getUTCDate(),
    tz
  )
  return {
    key: `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`,
    start,
    end,
  }
}
