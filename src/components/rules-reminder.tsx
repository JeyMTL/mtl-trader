'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { BellRing, ChevronRight, X } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/components/toast'
import {
  formatCountdown,
  normalizePlaybook,
  reminderState,
  type Playbook,
} from '@/lib/playbook'

/**
 * The live reminder, wherever the trader is in the app.
 *
 * It reads the playbook directly under RLS — the checklist is the trader's own
 * data and there is nothing to compute on the server — and appears only inside
 * the review window they chose. The once-per-session guard is kept in
 * sessionStorage so a page change does not repeat the same toast, while a real
 * reload the next day can still fire the next session's reminder.
 */
export default function RulesReminder() {
  const { toast } = useToast()
  const [playbook, setPlaybook] = useState<Playbook | null>(null)
  const [timeZone, setTimeZone] = useState('UTC')
  const [now, setNow] = useState(() => new Date())
  const [dismissed, setDismissed] = useState('')
  const reminded = useRef('')

  useEffect(() => {
    async function load() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()
        if (!user) return

        const [playbookResult, profileResult] = await Promise.all([
          supabase.from('playbooks').select('*').eq('user_id', user.id).maybeSingle(),
          supabase.from('users').select('timezone').eq('id', user.id).maybeSingle(),
        ])
        if (playbookResult.error || !playbookResult.data) return

        setTimeZone(
          (profileResult.data?.timezone as string | null) ||
            Intl.DateTimeFormat().resolvedOptions().timeZone ||
            'UTC'
        )
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
      } catch {
        // The reminder is an extra; the dashboard must render without it.
      }
    }
    void load()
  }, [])

  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30_000)
    return () => clearInterval(timer)
  }, [])

  const reminder = useMemo(
    () => (playbook ? reminderState(playbook, now, timeZone) : null),
    [playbook, now, timeZone]
  )

  useEffect(() => {
    if (!reminder?.due || !playbook) return
    if (reminded.current === reminder.key) return
    reminded.current = reminder.key

    let alreadyShown = false
    try {
      alreadyShown = sessionStorage.getItem(`playbook-reminded:${userStorageKey()}`) === reminder.key
      sessionStorage.setItem(`playbook-reminded:${userStorageKey()}`, reminder.key)
    } catch {
      // Private mode: the in-page reminder still shows, only the toast repeats.
    }
    if (alreadyShown) return

    toast(
      `${reminder.occurrence.session.label} starts ${formatCountdown(reminder.minutesUntil)} — review your rules.`,
      { tone: 'info' }
    )
  }, [reminder, playbook, toast])

  if (!reminder?.due || dismissed === reminder.key) return null

  const rules = (playbook?.rules ?? []).filter(Boolean)

  return (
    <section className="rounded-xl border border-primary/40 bg-primary/10 p-4">
      <div className="flex items-start gap-3">
        <BellRing className="mt-0.5 h-5 w-5 shrink-0 text-primary" />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div>
              <p className="text-sm font-semibold text-white">
                {reminder.occurrence.session.label} starts{' '}
                {formatCountdown(reminder.minutesUntil)}
              </p>
              <p className="mt-0.5 text-xs text-gray-300">
                Read the rules before the first trade — not after it.
              </p>
            </div>
            <button
              type="button"
              onClick={() => setDismissed(reminder.key)}
              aria-label="Dismiss reminder"
              className="rounded-md p-1 text-gray-400 transition-colors hover:bg-primary/15 hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {rules.length > 0 && (
            <ol className="mt-2.5 grid gap-1 sm:grid-cols-2">
              {rules.slice(0, 4).map((rule, index) => (
                <li key={`${index}-${rule.slice(0, 10)}`} className="flex gap-1.5 text-[11px] leading-relaxed text-gray-200">
                  <span className="font-mono text-primary">{index + 1}.</span>
                  <span className="line-clamp-2">{rule}</span>
                </li>
              ))}
            </ol>
          )}

          <Link
            href="/dashboard/playbook"
            className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
          >
            {rules.length > 4 ? `All ${rules.length} rules` : 'Open the playbook'}
            <ChevronRight className="h-3.5 w-3.5" />
          </Link>
        </div>
      </div>
    </section>
  )
}

/** A stable bucket per signed-in session so two accounts on one browser differ. */
function userStorageKey(): string {
  return window.location.pathname === '/dashboard' ? 'dashboard' : 'app'
}
