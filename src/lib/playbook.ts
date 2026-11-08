/**
 * The trading playbook: the rules a trader follows, the days they trade and the
 * sessions they trade them in.
 *
 * Reminder math lives here, free of I/O, so "is the trader due a reminder?"
 * can be unit tested without a browser, a database or a clock. Everything is
 * computed in the trader's own timezone: a session at 09:30 means 09:30 where
 * they are, not 09:30 UTC. That is what makes the reminder land an hour before
 * the market they actually sit in front of.
 */

import { normalizeTimeZone } from './notification-schedule'

export const DAY_LABELS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] as const
export const DAY_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const

export const DEFAULT_REMINDER_MINUTES = 60
export const MIN_REMINDER_MINUTES = 5
export const MAX_REMINDER_MINUTES = 240
/** A playbook is a checklist, not an essay; anything past this is ignored. */
export const MAX_RULES = 20
export const MAX_RULE_CHARS = 280
export const MAX_SESSIONS = 6
export const MAX_SESSION_LABEL = 40

export interface TradingSession {
  id: string
  label: string
  /** Local `HH:MM`, 24-hour. */
  start: string
  /** Local `HH:MM`. Before `start` means the session runs overnight. */
  end: string
}

export interface Playbook {
  rules: string[]
  /** 0 = Sunday … 6 = Saturday. */
  days: number[]
  sessions: TradingSession[]
  reminderMinutes: number
  remindersEnabled: boolean
  notes: string
}

export const EMPTY_PLAYBOOK: Playbook = {
  rules: [],
  days: [1, 2, 3, 4, 5],
  sessions: [],
  reminderMinutes: DEFAULT_REMINDER_MINUTES,
  remindersEnabled: true,
  notes: '',
}

const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/

export function isValidTime(value: string): boolean {
  return TIME_PATTERN.test(value.trim())
}

/** Minutes past local midnight, or null for a malformed value. */
export function minutesOfDay(value: string): number | null {
  const match = TIME_PATTERN.exec(value.trim())
  if (!match) return null
  return Number(match[1]) * 60 + Number(match[2])
}

export function formatClock(minutes: number): string {
  const normalized = ((Math.round(minutes) % 1440) + 1440) % 1440
  return `${String(Math.floor(normalized / 60)).padStart(2, '0')}:${String(normalized % 60).padStart(2, '0')}`
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function sessionId(seed: number): string {
  return `session-${seed}`
}

function normalizeSession(raw: unknown, index: number): TradingSession | null {
  if (!raw || typeof raw !== 'object') return null
  const input = raw as Record<string, unknown>
  const start = asString(input.start)
  const end = asString(input.end)
  if (!isValidTime(start) || !isValidTime(end)) return null
  const label = asString(input.label).slice(0, MAX_SESSION_LABEL) || `Session ${index + 1}`
  return {
    id: asString(input.id) || sessionId(index),
    label,
    start: formatClock(minutesOfDay(start) ?? 0),
    end: formatClock(minutesOfDay(end) ?? 0),
  }
}

/**
 * Turns whatever is stored (or typed) into a usable playbook.
 *
 * Anything malformed is dropped rather than repaired into a promise the trader
 * did not make: a session with a broken time is removed, not moved to midnight,
 * because a reminder at the wrong hour trains people to ignore reminders.
 */
export function normalizePlaybook(raw: unknown): Playbook {
  if (!raw || typeof raw !== 'object') return { ...EMPTY_PLAYBOOK }
  const input = raw as Record<string, unknown>

  const rules = Array.isArray(input.rules)
    ? input.rules
        .map((rule) => asString(rule).slice(0, MAX_RULE_CHARS))
        .filter((rule) => rule.length > 0)
        .slice(0, MAX_RULES)
    : []

  const days = Array.isArray(input.days)
    ? Array.from(
        new Set(
          input.days
            .map((day) => Number(day))
            .filter((day) => Number.isInteger(day) && day >= 0 && day <= 6)
        )
      ).sort((a, b) => a - b)
    : [...EMPTY_PLAYBOOK.days]

  const sessions = Array.isArray(input.sessions)
    ? input.sessions
        .map((session, index) => normalizeSession(session, index))
        .filter((session): session is TradingSession => session !== null)
        .slice(0, MAX_SESSIONS)
    : []

  const requestedReminder = Number(input.reminderMinutes)
  const reminderMinutes = Number.isFinite(requestedReminder)
    ? Math.min(MAX_REMINDER_MINUTES, Math.max(MIN_REMINDER_MINUTES, Math.round(requestedReminder)))
    : DEFAULT_REMINDER_MINUTES

  return {
    rules,
    days,
    sessions,
    reminderMinutes,
    remindersEnabled: input.remindersEnabled !== false,
    notes: asString(input.notes).slice(0, 2000),
  }
}

/** A playbook has something worth reminding about only when rules exist. */
export function hasRules(playbook: Playbook): boolean {
  return playbook.rules.length > 0
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

/**
 * The UTC instant of a wall-clock time in `timeZone`.
 *
 * Two passes, because the offset itself can change across a DST boundary: the
 * first pass gives an instant whose offset is then re-read and applied again.
 */
export function zonedDateTime(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  timeZone: string
): Date {
  const naive = Date.UTC(year, month - 1, day, hour, minute, 0)
  const offset = zoneOffsetMs(new Date(naive), timeZone)
  const candidate = new Date(naive - offset)
  const refined = zoneOffsetMs(candidate, timeZone)
  return refined === offset ? candidate : new Date(naive - refined)
}

/** Adds whole days to a calendar date without falling into local-time parsing. */
function addDays(year: number, month: number, day: number, days: number): { year: number; month: number; day: number } {
  const shifted = new Date(Date.UTC(year, month - 1, day + days))
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  }
}

function weekdayOf(year: number, month: number, day: number): number {
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay()
}

export interface SessionOccurrence {
  session: TradingSession
  /** UTC instant at which the session starts. */
  startsAt: Date
  /** Local calendar day the session starts on, `YYYY-MM-DD`. */
  localDay: string
}

/**
 * The next session start after `now`, looking up to eight days ahead so a
 * weekly schedule still resolves. Overnight sessions are keyed by their start
 * day, which is what the trader means by "I trade the 22:00 session".
 */
export function nextSessionOccurrence(
  playbook: Playbook,
  now: Date = new Date(),
  timeZone?: string | null
): SessionOccurrence | null {
  if (playbook.sessions.length === 0 || playbook.days.length === 0) return null
  const tz = normalizeTimeZone(timeZone)
  const local = localParts(now, tz)

  for (let offset = 0; offset <= 8; offset += 1) {
    const date = addDays(local.year, local.month, local.day, offset)
    if (!playbook.days.includes(weekdayOf(date.year, date.month, date.day))) continue

    const candidates = playbook.sessions
      .map((session) => {
        const startMinutes = minutesOfDay(session.start)
        if (startMinutes === null) return null
        const startsAt = zonedDateTime(
          date.year,
          date.month,
          date.day,
          Math.floor(startMinutes / 60),
          startMinutes % 60,
          tz
        )
        return {
          session,
          startsAt,
          localDay: `${date.year}-${String(date.month).padStart(2, '0')}-${String(date.day).padStart(2, '0')}`,
        }
      })
      .filter((entry): entry is SessionOccurrence => entry !== null)
      .filter((entry) => entry.startsAt.getTime() > now.getTime())
      .sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime())

    if (candidates[0]) return candidates[0]
  }

  return null
}

export interface ReminderState {
  occurrence: SessionOccurrence
  /** Whole minutes until the session starts; 0 once it has. */
  minutesUntil: number
  /** True inside the lead window, i.e. the rules should be read now. */
  due: boolean
  /** Stable key for \"already reminded about this one\". */
  key: string
}

/**
 * The reminder the trader is due on `now`, if any.
 *
 * The window opens `reminderMinutes` before the session and closes when it
 * starts. Given no rules there is nothing to review, so no reminder is due —
 * an empty checklist nudge would be noise.
 */
export function reminderState(
  playbook: Playbook,
  now: Date = new Date(),
  timeZone?: string | null
): ReminderState | null {
  if (!playbook.remindersEnabled || !hasRules(playbook)) return null
  const occurrence = nextSessionOccurrence(playbook, now, timeZone)
  if (!occurrence) return null

  const minutesUntil = Math.ceil(
    (occurrence.startsAt.getTime() - now.getTime()) / 60_000
  )
  const due = minutesUntil >= 0 && minutesUntil <= playbook.reminderMinutes

  return {
    occurrence,
    minutesUntil,
    due,
    key: `${occurrence.session.id}:${occurrence.startsAt.toISOString()}`,
  }
}

/** Human sentence for the countdown, e.g. "in 42 min" / "in 1 h 15 min". */
export function formatCountdown(minutes: number): string {
  if (minutes <= 0) return 'now'
  if (minutes < 60) return `in ${minutes} min`
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  return rest === 0 ? `in ${hours} h` : `in ${hours} h ${rest} min`
}

/** `09:30–12:00`, with an overnight flag when the end is on the next day. */
export function sessionTimeRange(session: TradingSession): string {
  const start = minutesOfDay(session.start)
  const end = minutesOfDay(session.end)
  const overnight = start !== null && end !== null && end <= start
  return `${session.start}–${session.end}${overnight ? ' (+1d)' : ''}`
}

export function daysSummary(days: number[]): string {
  if (days.length === 0) return 'No days selected'
  if (days.length === 7) return 'Every day'
  return [...days]
    .sort((a, b) => a - b)
    .map((day) => DAY_SHORT[day] ?? '')
    .join(', ')
}
