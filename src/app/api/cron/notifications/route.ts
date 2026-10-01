import { NextResponse } from 'next/server'
import { getAdminClient } from '@/lib/server-auth'
import { hasValidBearer } from '@/lib/auth-guards'
import { isEmailConfigured, sendEmail } from '@/lib/email'
import {
  renderJournalReminderEmail,
  renderSummaryEmail,
  summarizeTrades,
  type TradeLike,
} from '@/lib/summaries'
import { dueSummaryWindows, shouldSendJournalReminder } from '@/lib/notification-schedule'

/**
 * Sends the notification emails users opted into. Triggered by Vercel Cron with
 * `Authorization: Bearer $CRON_SECRET`.
 *
 *   - daily summary    → every day, for the previous calendar day
 *   - weekly report    → on Mondays, for the previous 7 days
 *   - monthly overview → on the 1st, for the previous calendar month
 *   - journal reminder → weekdays, when nothing has been journaled yet today
 *
 * Windows and working days are computed in each user's `timezone` (UTC
 * fallback). Only users with `notifications_email` on are considered, and empty
 * summary windows are skipped so nobody receives a "0 trades" email.
 *
 * Windows and the working-day decision live in `@/lib/notification-schedule` so
 * they can be unit tested without a database.
 */

export const dynamic = 'force-dynamic'

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
}

export async function GET(req: Request) {
  if (!hasValidBearer(req, process.env.CRON_SECRET)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  if (!isEmailConfigured()) {
    return NextResponse.json({ error: 'Email is not configured (set RESEND_API_KEY)' }, { status: 503 })
  }

  const now = new Date()

  const supabase = getAdminClient()
  const { data: users, error } = await supabase
    .from('users')
    .select(
      'id, email, full_name, currency, timezone, notifications_daily, notifications_weekly, notifications_monthly_email, notifications_journal_reminders'
    )
    .eq('notifications_email', true)
    .limit(500)

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  const result = { candidates: users?.length || 0, emailsSent: 0, skipped: 0, failed: 0 }

  for (const user of (users || []) as UserPrefs[]) {
    if (!user.email) {
      result.skipped++
      continue
    }

    const due = dueSummaryWindows(user, now, user.timezone)
    const journalDue = Boolean(user.notifications_journal_reminders)
    if (due.length === 0 && !journalDue) {
      result.skipped++
      continue
    }

    // Filtering client-side keeps one query per user; fine at this scale, and the
    // windows differ per email. Revisit if user counts grow.
    const { data: trades } = await supabase
      .from('trades')
      .select('pnl, close_time, open_time, created_at')
      .eq('user_id', user.id)

    const tradeList = (trades || []) as TradeLike[]

    if (journalDue) {
      if (shouldSendJournalReminder(user, tradeList, now, user.timezone)) {
        const { subject, html } = renderJournalReminderEmail({
          name: user.full_name,
          appUrl: process.env.NEXT_PUBLIC_APP_URL,
        })
        const outcome = await sendEmail({ to: user.email, subject, html })
        if (outcome.sent) result.emailsSent++
        else result.failed++
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

      const outcome = await sendEmail({ to: user.email, subject, html })
      if (outcome.sent) result.emailsSent++
      else result.failed++
    }
  }

  return NextResponse.json({ success: true, ...result })
}
