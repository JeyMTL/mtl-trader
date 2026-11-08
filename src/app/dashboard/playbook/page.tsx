'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import {
  BellRing,
  BookOpenCheck,
  CalendarDays,
  Clock,
  Loader2,
  Plus,
  Save,
  Trash2,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/components/toast'
import {
  DAY_LABELS,
  DAY_SHORT,
  EMPTY_PLAYBOOK,
  MAX_RULES,
  MAX_SESSIONS,
  daysSummary,
  formatCountdown,
  normalizePlaybook,
  reminderState,
  sessionTimeRange,
  type Playbook,
  type TradingSession,
} from '@/lib/playbook'

/**
 * The Rules tab.
 *
 * A trader's edge is usually not the entry signal — it is the checklist they
 * follow before and after it. This page stores that checklist, the days and the
 * sessions it applies to, and opens the reminder window ahead of every session
 * so the rules get read before the first trade rather than after the first loss.
 */

const REMINDER_CHOICES = [15, 30, 45, 60, 90, 120]

function newSession(index: number): TradingSession {
  return {
    id: `session-${Date.now()}-${index}`,
    label: index === 0 ? 'London open' : 'New session',
    start: '09:00',
    end: '12:00',
  }
}

export default function PlaybookPage() {
  const { toast } = useToast()
  const [userId, setUserId] = useState<string | null>(null)
  const [timeZone, setTimeZone] = useState('UTC')
  const [playbook, setPlaybook] = useState<Playbook>({ ...EMPTY_PLAYBOOK })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [now, setNow] = useState(() => new Date())
  const remindedKey = useRef('')

  useEffect(() => {
    async function load() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()
        if (!user) return
        setUserId(user.id)

        const [playbookResult, profileResult] = await Promise.all([
          supabase.from('playbooks').select('*').eq('user_id', user.id).maybeSingle(),
          supabase.from('users').select('timezone').eq('id', user.id).maybeSingle(),
        ])

        const stored =
          (profileResult.data?.timezone as string | null) ||
          Intl.DateTimeFormat().resolvedOptions().timeZone ||
          'UTC'
        setTimeZone(stored)

        if (playbookResult.error) {
          toast('Could not load your playbook: ' + playbookResult.error.message, {
            tone: 'error',
          })
        } else if (playbookResult.data) {
          setPlaybook(
            normalizePlaybook({
              rules: playbookResult.data.rules,
              days: playbookResult.data.days,
              sessions: playbookResult.data.sessions,
              reminderMinutes: playbookResult.data.reminder_minutes,
              remindersEnabled: playbookResult.data.reminders_enabled,
              notes: playbookResult.data.notes,
            })
          )
        }
      } finally {
        setLoading(false)
      }
    }
    void load()
  }, [toast])

  // The countdown is the "live" part: it ticks while the page is open and the
  // reminder fires once per session, not on every tick.
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30_000)
    return () => clearInterval(timer)
  }, [])

  const reminder = useMemo(
    () => reminderState(playbook, now, timeZone),
    [playbook, now, timeZone]
  )

  useEffect(() => {
    if (!reminder?.due || remindedKey.current === reminder.key) return
    remindedKey.current = reminder.key
    toast(
      `${reminder.occurrence.session.label} starts ${formatCountdown(reminder.minutesUntil)}. Read your rules.`,
      { tone: 'info' }
    )
  }, [reminder, toast])

  const save = async () => {
    if (!userId) return
    setSaving(true)
    const cleaned = normalizePlaybook(playbook)
    const { error } = await supabase.from('playbooks').upsert(
      {
        user_id: userId,
        rules: cleaned.rules,
        days: cleaned.days,
        sessions: cleaned.sessions,
        reminder_minutes: cleaned.reminderMinutes,
        reminders_enabled: cleaned.remindersEnabled,
        notes: cleaned.notes,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'user_id' }
    )
    setSaving(false)
    if (error) {
      toast('Could not save your playbook: ' + error.message, { tone: 'error' })
      return
    }
    setPlaybook(cleaned)
    toast('Playbook saved.', { tone: 'success' })
  }

  const setRule = (index: number, value: string) => {
    setPlaybook((current) => ({
      ...current,
      rules: current.rules.map((rule, position) => (position === index ? value : rule)),
    }))
  }

  const addRule = () => {
    if (playbook.rules.length >= MAX_RULES) {
      toast(`A playbook holds ${MAX_RULES} rules. Fewer is easier to follow.`, { tone: 'error' })
      return
    }
    setPlaybook((current) => ({ ...current, rules: [...current.rules, ''] }))
  }

  const removeRule = (index: number) => {
    setPlaybook((current) => ({
      ...current,
      rules: current.rules.filter((_, position) => position !== index),
    }))
  }

  const toggleDay = (day: number) => {
    setPlaybook((current) => ({
      ...current,
      days: current.days.includes(day)
        ? current.days.filter((entry) => entry !== day)
        : [...current.days, day].sort((a, b) => a - b),
    }))
  }

  const setSession = (index: number, patch: Partial<TradingSession>) => {
    setPlaybook((current) => ({
      ...current,
      sessions: current.sessions.map((session, position) =>
        position === index ? { ...session, ...patch } : session
      ),
    }))
  }

  const addSession = () => {
    if (playbook.sessions.length >= MAX_SESSIONS) {
      toast(`Up to ${MAX_SESSIONS} sessions.`, { tone: 'error' })
      return
    }
    setPlaybook((current) => ({
      ...current,
      sessions: [...current.sessions, newSession(current.sessions.length)],
    }))
  }

  const removeSession = (index: number) => {
    setPlaybook((current) => ({
      ...current,
      sessions: current.sessions.filter((_, position) => position !== index),
    }))
  }

  return (
    <div className="mx-auto max-w-4xl space-y-5">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold text-white">
          <BookOpenCheck className="h-6 w-6 text-primary" />
          Rules
        </h1>
        <p className="mt-1 text-sm text-gray-400">
          The checklist you trade by, the days you trade and the sessions you trade in.
          The app reminds you to read it{' '}
          {playbook.reminderMinutes >= 60
            ? `${Math.round(playbook.reminderMinutes / 60)} hour${playbook.reminderMinutes === 60 ? '' : 's'}`
            : `${playbook.reminderMinutes} minutes`}{' '}
          before each session, in {timeZone.replace(/_/g, ' ')} time.
        </p>
      </div>

      {/* ----------------------------------------------- live reminder card */}
      <section
        className={`rounded-xl border p-4 ${
          reminder?.due
            ? 'border-primary/50 bg-primary/10'
            : 'border-border bg-surface'
        }`}
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-start gap-2.5">
            <BellRing
              className={`mt-0.5 h-4 w-4 shrink-0 ${
                reminder?.due ? 'text-primary' : 'text-gray-500'
              }`}
            />
            <div>
              {reminder ? (
                <>
                  <p className="text-sm font-semibold text-white">
                    {reminder.occurrence.session.label} · {sessionTimeRange(reminder.occurrence.session)}
                  </p>
                  <p className="text-xs text-gray-400">
                    Starts {formatCountdown(reminder.minutesUntil)}
                    {reminder.due
                      ? ' — your review window is open.'
                      : ` — the reminder opens ${playbook.reminderMinutes} min before.`}
                  </p>
                </>
              ) : (
                <>
                  <p className="text-sm font-semibold text-white">No reminder scheduled</p>
                  <p className="text-xs text-gray-400">
                    {playbook.sessions.length === 0
                      ? 'Add a trading session below to schedule reminders.'
                      : !playbook.remindersEnabled
                        ? 'Reminders are switched off.'
                        : playbook.rules.filter(Boolean).length === 0
                          ? 'Write at least one rule — there is nothing to review yet.'
                          : 'No upcoming session in the next week. Check your trading days.'}
                  </p>
                </>
              )}
            </div>
          </div>
          <span className="rounded-full border border-border bg-background px-2.5 py-1 text-[11px] text-gray-400">
            {daysSummary(playbook.days)}
          </span>
        </div>

        {reminder?.due && playbook.rules.filter(Boolean).length > 0 && (
          <ol className="mt-3 space-y-1.5 border-t border-primary/20 pt-3">
            {playbook.rules
              .filter(Boolean)
              .slice(0, 6)
              .map((rule, index) => (
                <li key={`${index}-${rule.slice(0, 12)}`} className="flex gap-2 text-xs leading-relaxed text-gray-200">
                  <span className="font-mono text-primary">{index + 1}.</span>
                  <span>{rule}</span>
                </li>
              ))}
          </ol>
        )}
      </section>

      {loading ? (
        <p className="flex items-center gap-2 text-sm text-gray-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading your playbook…
        </p>
      ) : (
        <>
          {/* ------------------------------------------------------- rules */}
          <section className="rounded-xl border border-border bg-surface p-5">
            <div className="mb-1 flex items-center justify-between gap-2">
              <h2 className="text-sm font-semibold text-white">Your rules</h2>
              <span className="text-xs text-gray-500">
                {playbook.rules.filter(Boolean).length}/{MAX_RULES}
              </span>
            </div>
            <p className="mb-4 text-xs leading-relaxed text-gray-500">
              Write them as instructions to yourself: what must be true before entry, what
              invalidates the trade, and what ends your session.
            </p>

            {playbook.rules.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border bg-background px-4 py-6 text-center text-sm text-gray-500">
                No rules yet. The first one is usually the hardest to keep.
              </p>
            ) : (
              <ol className="space-y-2">
                {playbook.rules.map((rule, index) => (
                  <li key={index} className="flex items-start gap-2">
                    <span className="mt-2.5 w-4 shrink-0 text-right font-mono text-xs text-gray-500">
                      {index + 1}
                    </span>
                    <textarea
                      value={rule}
                      onChange={(event) => setRule(index, event.target.value)}
                      rows={2}
                      placeholder="e.g. Only take the setup after a London open sweep of the Asian range."
                      className="min-h-[42px] w-full resize-y rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
                    />
                    <button
                      type="button"
                      onClick={() => removeRule(index)}
                      aria-label={`Remove rule ${index + 1}`}
                      className="mt-1 rounded-md p-1.5 text-gray-500 transition-colors hover:bg-surface-light hover:text-danger"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </li>
                ))}
              </ol>
            )}

            <button
              type="button"
              onClick={addRule}
              className="mt-3 flex items-center gap-1.5 rounded-lg border border-border px-3 py-2 text-xs font-medium text-gray-300 transition-colors hover:border-primary/50 hover:text-white"
            >
              <Plus className="h-3.5 w-3.5" /> Add rule
            </button>
          </section>

          {/* -------------------------------------------------------- days */}
          <section className="rounded-xl border border-border bg-surface p-5">
            <h2 className="mb-1 flex items-center gap-2 text-sm font-semibold text-white">
              <CalendarDays className="h-4 w-4 text-gray-500" /> Days you trade
            </h2>
            <p className="mb-4 text-xs text-gray-500">
              Reminders only fire on these days. Trading outside them is usually the leak.
            </p>
            <div className="flex flex-wrap gap-2">
              {DAY_LABELS.map((label, day) => {
                const active = playbook.days.includes(day)
                return (
                  <button
                    key={label}
                    type="button"
                    onClick={() => toggleDay(day)}
                    aria-pressed={active}
                    className={`rounded-lg border px-3 py-2 text-xs font-medium transition-colors ${
                      active
                        ? 'border-primary bg-primary/10 text-primary'
                        : 'border-border bg-background text-gray-400 hover:text-white'
                    }`}
                  >
                    {DAY_SHORT[day]}
                  </button>
                )
              })}
            </div>
          </section>

          {/* ---------------------------------------------------- sessions */}
          <section className="rounded-xl border border-border bg-surface p-5">
            <h2 className="mb-1 flex items-center gap-2 text-sm font-semibold text-white">
              <Clock className="h-4 w-4 text-gray-500" /> Trading sessions
            </h2>
            <p className="mb-4 text-xs text-gray-500">
              Times are local ({timeZone.replace(/_/g, ' ')}). A session that ends before it
              starts is treated as overnight.
            </p>

            {playbook.sessions.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border bg-background px-4 py-6 text-center text-sm text-gray-500">
                No sessions yet. Add the window you actually sit down for.
              </p>
            ) : (
              <ul className="space-y-2">
                {playbook.sessions.map((session, index) => (
                  <li
                    key={session.id}
                    className="grid grid-cols-[minmax(0,1fr)_auto_auto_auto] items-center gap-2"
                  >
                    <input
                      value={session.label}
                      onChange={(event) => setSession(index, { label: event.target.value })}
                      aria-label={`Session ${index + 1} name`}
                      placeholder="Session name"
                      className="w-full min-w-0 rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
                    />
                    <input
                      type="time"
                      value={session.start}
                      onChange={(event) => setSession(index, { start: event.target.value })}
                      aria-label={`Session ${index + 1} start`}
                      className="rounded-lg border border-border bg-background px-2 py-2 text-sm text-white focus:border-primary focus:outline-none"
                    />
                    <input
                      type="time"
                      value={session.end}
                      onChange={(event) => setSession(index, { end: event.target.value })}
                      aria-label={`Session ${index + 1} end`}
                      className="rounded-lg border border-border bg-background px-2 py-2 text-sm text-white focus:border-primary focus:outline-none"
                    />
                    <button
                      type="button"
                      onClick={() => removeSession(index)}
                      aria-label={`Remove ${session.label || `session ${index + 1}`}`}
                      className="rounded-md p-1.5 text-gray-500 transition-colors hover:bg-surface-light hover:text-danger"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </li>
                ))}
              </ul>
            )}

            <button
              type="button"
              onClick={addSession}
              className="mt-3 flex items-center gap-1.5 rounded-lg border border-border px-3 py-2 text-xs font-medium text-gray-300 transition-colors hover:border-primary/50 hover:text-white"
            >
              <Plus className="h-3.5 w-3.5" /> Add session
            </button>
          </section>

          {/* --------------------------------------------------- reminders */}
          <section className="rounded-xl border border-border bg-surface p-5">
            <div className="flex items-center justify-between gap-4">
              <div>
                <h2 className="text-sm font-semibold text-white">Remind me before a session</h2>
                <p className="mt-1 text-xs text-gray-500">
                  An in-app reminder while the app is open, with your rules in front of you.
                </p>
              </div>
              <label className="relative inline-flex cursor-pointer items-center">
                <input
                  type="checkbox"
                  checked={playbook.remindersEnabled}
                  onChange={(event) =>
                    setPlaybook((current) => ({
                      ...current,
                      remindersEnabled: event.target.checked,
                    }))
                  }
                  className="peer sr-only"
                />
                <span className="h-6 w-11 rounded-full bg-gray-600 after:absolute after:left-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:bg-white after:transition-all after:content-[''] peer-checked:bg-primary peer-checked:after:translate-x-full" />
              </label>
            </div>

            <div className="mt-4">
              <label className="mb-2 block text-xs text-gray-500" htmlFor="reminder-lead">
                How long before the session
              </label>
              <select
                id="reminder-lead"
                value={playbook.reminderMinutes}
                onChange={(event) =>
                  setPlaybook((current) => ({
                    ...current,
                    reminderMinutes: Number(event.target.value),
                  }))
                }
                className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white focus:border-primary focus:outline-none sm:w-56"
              >
                {REMINDER_CHOICES.map((minutes) => (
                  <option key={minutes} value={minutes}>
                    {minutes} minutes before
                  </option>
                ))}
              </select>
            </div>

            <div className="mt-4">
              <label className="mb-2 block text-xs text-gray-500" htmlFor="playbook-notes">
                Notes for yourself (optional)
              </label>
              <textarea
                id="playbook-notes"
                value={playbook.notes}
                onChange={(event) =>
                  setPlaybook((current) => ({ ...current, notes: event.target.value }))
                }
                rows={3}
                placeholder="What usually goes wrong, and what you do about it."
                className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-white placeholder-gray-600 focus:border-primary focus:outline-none"
              />
            </div>
          </section>

          <button
            type="button"
            onClick={() => void save()}
            disabled={saving}
            className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-dark disabled:opacity-50"
          >
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            {saving ? 'Saving…' : 'Save playbook'}
          </button>
        </>
      )}
    </div>
  )
}
