import { describe, it, expect } from 'vitest'
import {
  buildWindows,
  dueSummaryWindows,
  hasJournaledOn,
  isWorkingDay,
  shouldSendJournalReminder,
  normalizeTimeZone,
  zonedDayKey,
  dayKey,
} from '@/lib/notification-schedule'

const MONDAY = new Date('2026-06-01T07:00:00.000Z') // a Monday, and the 1st
const TUESDAY = new Date('2026-06-02T07:00:00.000Z')
const SATURDAY = new Date('2026-06-06T07:00:00.000Z')

describe('buildWindows', () => {
  it('anchors the daily window to the previous UTC day', () => {
    const { daily } = buildWindows(TUESDAY)
    expect(daily.since.toISOString()).toBe('2026-06-01T00:00:00.000Z')
    expect(daily.until.toISOString()).toBe('2026-06-02T00:00:00.000Z')
  })

  it('spans the previous 7 days for the weekly window', () => {
    const { weekly } = buildWindows(TUESDAY)
    expect(weekly.since.toISOString()).toBe('2026-05-26T00:00:00.000Z')
    expect(weekly.until.toISOString()).toBe('2026-06-02T00:00:00.000Z')
  })

  it('covers the previous calendar month for the monthly window', () => {
    const { monthly } = buildWindows(MONDAY)
    expect(monthly.since.toISOString()).toBe('2026-05-01T00:00:00.000Z')
    expect(monthly.until.toISOString()).toBe('2026-06-01T00:00:00.000Z')
  })
})

describe('dueSummaryWindows', () => {
  const all = { notifications_daily: true, notifications_weekly: true, notifications_monthly_email: true }

  it('sends daily, weekly and monthly on the 1st if it is a Monday', () => {
    const due = dueSummaryWindows(all, MONDAY)
    expect(due.map((w) => w.label)).toEqual([
      'Your daily summary',
      'Your weekly report',
      'Your monthly overview',
    ])
  })

  it('omits weekly and monthly on a mid-week, mid-month day', () => {
    const due = dueSummaryWindows(all, new Date('2026-06-16T07:00:00.000Z'))
    expect(due.map((w) => w.label)).toEqual(['Your daily summary'])
  })

  it('respects each toggle independently', () => {
    const due = dueSummaryWindows({ ...all, notifications_weekly: false }, MONDAY)
    expect(due.map((w) => w.label)).toEqual(['Your daily summary', 'Your monthly overview'])
  })

  it('returns nothing when every preference is off', () => {
    const due = dueSummaryWindows(
      { notifications_daily: false, notifications_weekly: false, notifications_monthly_email: false },
      MONDAY
    )
    expect(due).toEqual([])
  })
})

describe('isWorkingDay', () => {
  it('is true Monday–Friday and false at the weekend', () => {
    expect(isWorkingDay(MONDAY)).toBe(true)
    expect(isWorkingDay(TUESDAY)).toBe(true)
    expect(isWorkingDay(SATURDAY)).toBe(false)
  })
})

describe('hasJournaledOn', () => {
  it('matches on the UTC day of the trade timestamp', () => {
    expect(hasJournaledOn([{ pnl: 1, close_time: '2026-06-02T09:30:00.000Z' }], TUESDAY)).toBe(true)
    expect(hasJournaledOn([{ pnl: 1, close_time: '2026-06-01T09:30:00.000Z' }], TUESDAY)).toBe(false)
    expect(hasJournaledOn([{ pnl: 1 }], TUESDAY)).toBe(false)
  })

  it('falls back open_time then created_at', () => {
    expect(hasJournaledOn([{ pnl: 1, open_time: '2026-06-02T01:00:00.000Z' }], TUESDAY)).toBe(true)
    expect(hasJournaledOn([{ pnl: 1, created_at: '2026-06-02T01:00:00.000Z' }], TUESDAY)).toBe(true)
  })
})

describe('shouldSendJournalReminder', () => {
  const on = { notifications_journal_reminders: true }

  it('sends on a weekday with no journal entry yet', () => {
    expect(shouldSendJournalReminder(on, [], TUESDAY)).toBe(true)
  })

  it('does not send once something is journaled today', () => {
    const trades = [{ pnl: 1, close_time: '2026-06-02T09:30:00.000Z' }]
    expect(shouldSendJournalReminder(on, trades, TUESDAY)).toBe(false)
  })

  it('does not send when opted out or at the weekend', () => {
    expect(shouldSendJournalReminder({ notifications_journal_reminders: false }, [], TUESDAY)).toBe(false)
    expect(shouldSendJournalReminder(on, [], SATURDAY)).toBe(false)
  })
})

describe('dayKey', () => {
  it('formats the UTC date', () => {
    expect(dayKey(TUESDAY)).toBe('2026-06-02')
  })
})

describe('normalizeTimeZone', () => {
  it('maps dropdown labels to DST-aware IANA zones', () => {
    expect(normalizeTimeZone('PST')).toBe('America/Los_Angeles')
    expect(normalizeTimeZone('est')).toBe('America/New_York')
    expect(normalizeTimeZone('GMT')).toBe('UTC')
  })

  it('keeps valid IANA names and falls back to UTC for junk', () => {
    expect(normalizeTimeZone('Asia/Tokyo')).toBe('Asia/Tokyo')
    expect(normalizeTimeZone('Mars/Olympus')).toBe('UTC')
    expect(normalizeTimeZone(null)).toBe('UTC')
    expect(normalizeTimeZone('')).toBe('UTC')
  })
})

describe('timezone-aware scheduling', () => {
  it('anchors the daily window to local midnight', () => {
    const { daily } = buildWindows(TUESDAY, 'America/New_York')
    expect(daily.since.toISOString()).toBe('2026-06-01T04:00:00.000Z')
    expect(daily.until.toISOString()).toBe('2026-06-02T04:00:00.000Z')
  })

  it('uses the local day to decide which summaries are due', () => {
    // 2026-06-01T02:00Z is Monday June 1 in UTC but Sunday May 31 in New York.
    const instant = new Date('2026-06-01T02:00:00.000Z')
    const all = { notifications_daily: true, notifications_weekly: true, notifications_monthly_email: true }
    expect(dueSummaryWindows(all, instant, 'UTC')).toHaveLength(3)
    expect(dueSummaryWindows(all, instant, 'America/New_York').map((w) => w.label)).toEqual(['Your daily summary'])
  })

  it('uses the local weekday for journal reminders', () => {
    // 2026-06-06T02:00Z is Saturday in UTC but Friday 22:00 in New York.
    const instant = new Date('2026-06-06T02:00:00.000Z')
    expect(isWorkingDay(instant)).toBe(false)
    expect(isWorkingDay(instant, 'America/New_York')).toBe(true)
  })

  it('compares journal days in the user\u2019s timezone', () => {
    const instant = new Date('2026-06-02T02:00:00.000Z') // 2026-06-01 22:00 in New York
    expect(zonedDayKey(instant, 'America/New_York')).toBe('2026-06-01')
    const trade = [{ pnl: 1, close_time: '2026-06-01T23:00:00.000Z' }]
    expect(hasJournaledOn(trade, instant, 'America/New_York')).toBe(true)
    expect(hasJournaledOn(trade, instant, 'UTC')).toBe(false)
  })

  it('ignores trades with unparseable timestamps', () => {
    expect(hasJournaledOn([{ pnl: 1, close_time: 'not a date' }], TUESDAY)).toBe(false)
  })
})
