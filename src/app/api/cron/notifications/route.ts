import { NextResponse } from 'next/server'
import { getAdminClient } from '@/lib/server-auth'
import { hasValidBearer } from '@/lib/auth-guards'
import { isEmailConfigured, sendEmail } from '@/lib/email'
import {
  renderJournalReminderEmail,
  renderSummaryEmail,
  renderTrialReminderEmail,
  summarizeTrades,
  type TradeLike,
} from '@/lib/summaries'
import {
  dueSummaryWindows,
  isJournalReminderHour,
  shouldSendJournalReminder,
  trialReminder,
  zonedDayKey,
} from '@/lib/notification-schedule'
import { apiError, logEvent } from '@/lib/log'
import type { SupabaseClient } from '@supabase/supabase-js'

/**
 * Sends the notification emails users opted into. Triggered by Vercel Cron with
 * `Authorization: Bearer $CRON_SECRET`.
 *
 *   - daily summary    → every day, for the previous calendar day
 *   - weekly report    → on Mondays, for the previous 7 days
 *   - monthly overview → on the 1st, for the previous calendar month
 *   - journal reminder → weekdays, in the user's own evening (18:00–20:00 local),
 *                        when nothing has been journaled yet today
 *   - trial ending     → within 3 days of the end, then once when it passes
 *
 * The cron runs hourly so the journal reminder can follow each user's clock.
 * The digests and the trial notice still go out on the 07:00 UTC pass only, so
 * their timing is unchanged; the send ledger makes the extra passes harmless.
 *
 * The trial notice is an account email, not a digest: it goes to every trial
 * account with an address, whatever the digest toggles say, because it is the
 * one message that tells a customer what paying would actually get them.
 *
 * Design notes that matter at scale:
 *   - Users are read in pages, and each user's email work is isolated, so one
 *     failure cannot abort the run (the old version did exactly that).
 *   - Each send is claimed in `notification_sends` first, so running the cron
 *     twice in a day cannot email anyone twice. A failed send releases the claim
 *     so the next run retries it.
 *   - Only the trades inside the relevant windows are fetched, not the whole
 *     journal, and the run stops before the platform timeout instead of being
 *     killed halfway through.
 */

export const dynamic = 'force-dynamic'
export const maxDuration = 300

const PAGE_SIZE = 200
const CONCURRENCY = 5
const TIME_BUDGET_MS = 240_000
/** The UTC hour the daily/weekly/monthly digests and trial notices go out in. */
const SUMMARY_HOUR_UTC = 7

interface UserPrefs {
  id: string
  email: string | null
  full_name: string | null
  currency: string | null
  timezone: string | null
  notifications_daily: boolean | null
  notifications_weekly: boolean | null
  notifications_monthly_email: boolean | null
  notifications_journal_reminders: boolean | null
  notifications_email: boolean | null
  subscription_status: string | null
  subscription_tier: string | null
  trial_ends_at: string | null
}

interface RunOptions {
  /** Digests and the trial notice: the 07:00 UTC pass, or a manual `?job=summary`. */
  summaries: boolean
  /** Journal reminders: every pass, gated per user on their local evening. */
  journal: boolean
  /** A manual `?job=journal` run ignores the local-evening gate. */
  force: boolean
}

interface SummaryRun {
  candidates: number
  emailsSent: number
  skipped: number
  failed: number
  pages: number
  hasMore: boolean
}

/** Claims a send so a second cron run cannot duplicate it. */
async function claimSend(
  supabase: SupabaseClient,
  userId: string,
  kind: string,
  windowKey: string
): Promise<boolean> {
  const { error } = await supabase
    .from('notification_sends')
    .insert({ user_id: userId, kind, window_key: windowKey })

  if (!error) return true
  if (error.code === '23505') return false
  throw new Error(`Could not record notification send: ${error.message}`)
}

/** Releases a claim after a failed send, so the next run retries it. */
async function releaseClaim(
  supabase: SupabaseClient,
  userId: string,
  kind: string,
  windowKey: string
): Promise<void> {
  await supabase
    .from('notification_sends')
    .delete()
    .eq('user_id', userId)
    .eq('kind', kind)
    .eq('window_key', windowKey)
}

async function sendClaimed(
  supabase: SupabaseClient,
  userId: string,
  kind: string,
  windowKey: string,
  message: { to: string; subject: string; html: string }
): Promise<boolean> {
  const claimed = await claimSend(supabase, userId, kind, windowKey)
  if (!claimed) return false

  const outcome = await sendEmail(message)
  if (!outcome.sent) {
    // A rejected send is the one failure a re-run cannot see: the claim is
    // released, so the ledger stays empty and the run only reports `skipped`.
    // Logging the provider's reason is what turns "nobody gets emails" into a
    // verified-sender or bad-key sentence.
    logEvent('warn', 'cron.notifications.send_failed', {
      user_id: userId,
      kind,
      window_key: windowKey,
      reason: outcome.reason || 'unknown',
    })
    await releaseClaim(supabase, userId, kind, windowKey)
    return false
  }
  return true
}

async function processUser(
  supabase: SupabaseClient,
  user: UserPrefs,
  now: Date,
  result: SummaryRun,
  options: RunOptions
): Promise<void> {
  if (!user.email) {
    result.skipped++
    return
  }

  const trial = options.summaries ? trialReminder(user, now) : null
  // The digests are opt-in, the trial notice is not: an account email should not
  // depend on a marketing toggle, and it is sent even with digests switched off.
  const digestsOn = Boolean(user.notifications_email)
  const due = options.summaries && digestsOn ? dueSummaryWindows(user, now, user.timezone) : []
  // Checked before the trade read so an hourly pass only queries the journal of
  // users who are actually in their reminder window.
  const journalDue =
    options.journal &&
    digestsOn &&
    Boolean(user.notifications_journal_reminders) &&
    (options.force || isJournalReminderHour(now, user.timezone))
  const needsTrades = due.length > 0 || journalDue

  if (!needsTrades && !trial) {
    result.skipped++
    return
  }

  let tradeList: TradeLike[] = []
  if (needsTrades) {
    const since = Math.min(
      ...due.map((window) => window.since.getTime()),
      journalDue ? now.getTime() - 24 * 60 * 60 * 1000 : Number.POSITIVE_INFINITY
    )

    const { data: tradeData, error: tradesError } = await supabase.rpc('notification_trades', {
      p_user_id: user.id,
      p_since: new Date(Number.isFinite(since) ? since : now.getTime() - 24 * 60 * 60 * 1000).toISOString(),
    })

    if (tradesError) throw new Error(`Could not load trades for ${user.id}: ${tradesError.message}`)
    tradeList = (tradeData || []) as TradeLike[]
  }

  if (journalDue) {
    if (shouldSendJournalReminder(user, tradeList, now, user.timezone, options.force)) {
      const { subject, html } = renderJournalReminderEmail({
        name: user.full_name,
        appUrl: process.env.NEXT_PUBLIC_APP_URL,
      })
      const sent = await sendClaimed(
        supabase,
        user.id,
        'journal',
        zonedDayKey(now, user.timezone),
        { to: user.email, subject, html }
      )
      if (sent) result.emailsSent++
      else result.skipped++
    } else {
      result.skipped++
    }
  }

  for (const window of due) {
    const summary = summarizeTrades(tradeList, window.since, window.until)
    if (summary.trades === 0) {
      result.skipped++
      continue
    }

    const { subject, html } = renderSummaryEmail({
      name: user.full_name,
      title: window.label,
      summary,
      currency: user.currency || 'USD',
      appUrl: process.env.NEXT_PUBLIC_APP_URL,
    })

    const sent = await sendClaimed(
      supabase,
      user.id,
      window.kind,
      zonedDayKey(window.until, user.timezone),
      { to: user.email, subject, html }
    )
    if (sent) result.emailsSent++
    else result.skipped++
  }

  if (trial) {
    const { subject, html } = renderTrialReminderEmail({
      name: user.full_name,
      kind: trial.kind,
      daysLeft: trial.daysLeft,
      appUrl: process.env.NEXT_PUBLIC_APP_URL,
    })
    // The claim is keyed by the trial's end date, so the daily runs between here
    // and the end cannot send this twice.
    const sent = await sendClaimed(supabase, user.id, trial.kind, trial.windowKey, {
      to: user.email,
      subject,
      html,
    })
    if (sent) result.emailsSent++
    else result.skipped++
  }
}

export async function GET(req: Request) {
  if (!hasValidBearer(req, process.env.CRON_SECRET)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  if (!isEmailConfigured()) {
    return NextResponse.json({ error: 'Email is not configured (set RESEND_API_KEY)' }, { status: 503 })
  }

  const now = new Date()
  const deadline = Date.now() + TIME_BUDGET_MS
  const supabase = getAdminClient()

  // Every hourly pass handles journal reminders; the digests keep their single
  // daily pass. `?job=summary|journal` forces one side, which is what makes a
  // manual run useful at any hour of the day.
  const job = (() => {
    try {
      return new URL(req.url).searchParams.get('job')
    } catch {
      return null
    }
  })()
  const forced = job === 'summary' || job === 'journal' || job === 'all'
  const options: RunOptions = {
    summaries:
      job === 'summary' ||
      job === 'all' ||
      (job === null && now.getUTCHours() === SUMMARY_HOUR_UTC),
    journal: job !== 'summary',
    force: forced,
  }
  const result: SummaryRun = {
    candidates: 0,
    emailsSent: 0,
    skipped: 0,
    failed: 0,
    pages: 0,
    hasMore: false,
  }

  try {
    for (let page = 0; ; page++) {
      if (Date.now() > deadline) {
        result.hasMore = true
        break
      }

      const from = page * PAGE_SIZE
      const { data: users, error } = await supabase
        .from('users')
        .select(
          'id, email, full_name, currency, timezone, notifications_daily, notifications_weekly, notifications_monthly_email, notifications_journal_reminders, notifications_email, subscription_status, subscription_tier, trial_ends_at'
        )
        .order('id', { ascending: true })
        .range(from, from + PAGE_SIZE - 1)

      if (error) throw new Error(`Could not load users: ${error.message}`)
      if (!users || users.length === 0) break

      result.pages++
      result.candidates += users.length

      for (let index = 0; index < users.length; index += CONCURRENCY) {
        if (Date.now() > deadline) {
          result.hasMore = true
          break
        }

        const chunk = (users as UserPrefs[]).slice(index, index + CONCURRENCY)
        const outcomes = await Promise.allSettled(
          chunk.map((user) => processUser(supabase, user, now, result, options))
        )

        for (const outcome of outcomes) {
          if (outcome.status === 'rejected') {
            result.failed++
            logEvent('error', 'cron.notifications.user', { error: outcome.reason })
          }
        }
      }

      if (result.hasMore || users.length < PAGE_SIZE) break
    }

    logEvent('info', 'cron.notifications.complete', {
      ...result,
      summaries: options.summaries,
      journal: options.journal,
    })
    return NextResponse.json({ success: true, ...result })
  } catch (error: unknown) {
    return apiError('cron.notifications', error, 500, 'Could not run the notification job.')
  }
}
