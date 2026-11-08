import { describe, expect, it } from 'vitest'
import {
  formatCountdown,
  nextSessionOccurrence,
  normalizePlaybook,
  reminderState,
  sessionTimeRange,
  zonedDateTime,
  type Playbook,
} from '@/lib/playbook'

const mondayMorning = new Date('2026-10-05T08:30:00.000Z') // Monday
const mondayEarly = new Date('2026-10-05T07:00:00.000Z')

const base: Playbook = {
  rules: ['Wait for the London open sweep', 'Risk 1% only'],
  days: [1, 2, 3, 4, 5],
  sessions: [{ id: 'london', label: 'London open', start: '09:00', end: '12:00' }],
  reminderMinutes: 60,
  remindersEnabled: true,
  notes: '',
}

describe('normalizePlaybook', () => {
  it('drops malformed sessions instead of moving them to midnight', () => {
    const playbook = normalizePlaybook({
      rules: ['  One rule  ', '', 'x'.repeat(500)],
      days: [1, 1, 9, -1, 5],
      sessions: [
        { id: 'a', label: 'Good', start: '09:30', end: '11:00' },
        { id: 'b', label: 'Bad', start: '25:00', end: '11:00' },
      ],
      reminderMinutes: 600,
      remindersEnabled: false,
    })

    expect(playbook.sessions).toHaveLength(1)
    expect(playbook.sessions[0]!.start).toBe('09:30')
    expect(playbook.days).toEqual([1, 5])
    expect(playbook.reminderMinutes).toBe(240)
    expect(playbook.rules).toHaveLength(2)
    expect(playbook.rules[1]!.length).toBe(280)
    expect(playbook.remindersEnabled).toBe(false)
  })
})

describe('session scheduling', () => {
  it('finds the next matching session in the trader’s timezone', () => {
    const occurrence = nextSessionOccurrence(base, mondayEarly, 'UTC')
    expect(occurrence?.session.label).toBe('London open')
    expect(occurrence?.startsAt.toISOString()).toBe('2026-10-05T09:00:00.000Z')
  })

  it('skips days the trader does not trade', () => {
    const weekend: Playbook = { ...base, days: [6] }
    const occurrence = nextSessionOccurrence(weekend, mondayMorning, 'UTC')
    expect(occurrence?.startsAt.toISOString()).toBe('2026-10-10T09:00:00.000Z')
  })

  it('opens the review window exactly one lead time before the session', () => {
    const due = reminderState(base, mondayMorning, 'UTC')
    expect(due?.due).toBe(true)
    expect(due?.minutesUntil).toBe(30)
    expect(due?.occurrence.session.id).toBe('london')

    const tooEarly = reminderState(base, new Date('2026-10-05T07:30:00.000Z'), 'UTC')
    expect(tooEarly?.due).toBe(false)
    expect(tooEarly?.minutesUntil).toBe(90)
  })

  it('never reminds when there is nothing to review', () => {
    expect(reminderState({ ...base, rules: [] }, mondayMorning, 'UTC')).toBeNull()
    expect(reminderState({ ...base, remindersEnabled: false }, mondayMorning, 'UTC')).toBeNull()
  })

  it('reads the local clock, not UTC', () => {
    // 09:00 in Paris in July is 07:00 UTC (CEST).
    expect(zonedDateTime(2026, 7, 1, 9, 0, 'Europe/Paris').toISOString()).toBe(
      '2026-07-01T07:00:00.000Z'
    )
  })
})

describe('presentation', () => {
  it('formats the countdown and overnight sessions', () => {
    expect(formatCountdown(30)).toBe('in 30 min')
    expect(formatCountdown(75)).toBe('in 1 h 15 min')
    expect(formatCountdown(0)).toBe('now')
    expect(sessionTimeRange({ id: 'x', label: 'Asian', start: '22:00', end: '02:00' })).toBe(
      '22:00–02:00 (+1d)'
    )
  })
})
