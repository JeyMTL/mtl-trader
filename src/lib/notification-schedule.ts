/**
 * Pure scheduling helpers for the notification cron. Kept free of I/O so the
 * window math and the "is this user due?" decisions can be unit tested without
 * a database or an email provider.
 *
 * Windows are anchored to local midnight in the user's timezone (defaulting to
 * UTC). Users store a short label like `PST` or a full IANA name; short labels
 * are mapped to a representative IANA zone so DST is handled correctly.
 */

import { tradeTime, type TradeLike } from './summaries'

export const DAY_MS = 24 * 60 * 60 * 1000

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

export interface Window {
  label: string
  since: Date
  until: Date
}

export interface SummaryPreferences {
  notifications_daily: boolean | null
  notifications_weekly: boolean | null
  notifications_monthly_email: boolean | null
}

export interface DashboardPreferences {
  notifications_journal_reminders: boolean | null
}

export function buildWindows(
  now: Date,
  timeZone: string | null = 'UTC'
): { daily: Window; weekly: Window; monthly: Window } {
  const tz = normalizeTimeZone(timeZone)
  const { year, month, day } = localParts(now, tz)
  const startOfToday = zonedStartOfDay(year, month, day, tz)
  return {
    daily: { label: 'Your daily summary', since: new Date(startOfToday.getTime() - DAY_MS), until: startOfToday },
    weekly: { label: 'Your weekly report', since: new Date(startOfToday.getTime() - 7 * DAY_MS), until: startOfToday },
    monthly: {
      label: 'Your monthly overview',
      since: zonedStartOfDay(year, month - 1, 1, tz),
      until: zonedStartOfDay(year, month, 1, tz),
    },
  }
}

/** 0 = Sunday … 6 = Saturday, as seen in the given timezone. */
function localWeekday(date: Date, timeZone: string): number {
  const parts = localParts(date, timeZone)
  return new Date(Date.UTC(parts.year, parts.month - 1, parts.day)).getUTCDay()
}

/** The summary windows this user is due for on `now` (Mondays weekly, 1st monthly). */
export function dueSummaryWindows(prefs: SummaryPreferences, now: Date, timeZone: string | null = 'UTC'): Window[] {
  const tz = normalizeTimeZone(timeZone)
  const windows = buildWindows(now, tz)
  const weekday = localWeekday(now, tz)
  const localDayOfMonth = localParts(now, tz).day
  const due: Window[] = []
  if (prefs.notifications_daily) due.push(windows.daily)
  if (prefs.notifications_weekly && weekday === 1) due.push(windows.weekly)
  if (prefs.notifications_monthly_email && localDayOfMonth === 1) due.push(windows.monthly)
  return due
}

/** Monday–Friday in the given timezone. */
export function isWorkingDay(date: Date, timeZone: string | null = 'UTC'): boolean {
  const weekday = localWeekday(date, normalizeTimeZone(timeZone))
  return weekday >= 1 && weekday <= 5
}

/** `YYYY-MM-DD` in UTC. */
export function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10)
}

/** `YYYY-MM-DD` as seen in the given timezone. */
export function zonedDayKey(date: Date, timeZone: string | null = 'UTC'): string {
  const { year, month, day } = localParts(date, normalizeTimeZone(timeZone))
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
}

/** Whether any trade is journaled on the same local day as `date`. */
export function hasJournaledOn(trades: TradeLike[], date: Date, timeZone: string | null = 'UTC'): boolean {
  const key = zonedDayKey(date, timeZone)
  return trades.some((trade) => {
    const time = tradeTime(trade)
    if (!time) return false
    const parsed = new Date(time)
    if (Number.isNaN(parsed.getTime())) return false
    return zonedDayKey(parsed, timeZone) === key
  })
}

/**
 * Whether to send this user a working-day journal reminder on `now`: they opted
 * in, it is a weekday in their timezone, and nothing has been journaled yet today.
 */
export function shouldSendJournalReminder(
  prefs: DashboardPreferences,
  trades: TradeLike[],
  now: Date,
  timeZone: string | null = 'UTC'
): boolean {
  if (!prefs.notifications_journal_reminders) return false
  const tz = normalizeTimeZone(timeZone)
  if (!isWorkingDay(now, tz)) return false
  return !hasJournaledOn(trades, now, tz)
}
