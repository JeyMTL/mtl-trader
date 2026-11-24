import { getAdminClient } from './server-auth'
import { logEvent } from './log'
import { sendPushToUser } from './push'
import { propStatusLevel, type PropStatus } from './prop-rules'
import {
  formatCountdown,
  normalizePlaybook,
  reminderState,
  type Playbook,
} from './playbook'

/**
 * The notifications nobody can see coming on their own.
 *
 * "Sync stopped" is already handled by the supervisor, which is the only party
 * that knows a terminal died. These two are different: both are states the
 * customer is *in*, computed from rows the journal already has, and both stay
 * true for a while. That makes "notify on every sweep" and "never notify" the
 * two easy wrong answers, which is why every send here goes through
 * `pushOnce` and a row in `push_events`.
 *
 * Prop breaches are checked from `/api/sync` after trades land, not from a cron:
 * a trader with the supervisor running has no app open, and a daily sweep would
 * tell them hours after the account was already gone. The cron still sweeps as a
 * safety net for trades entered by hand.
 */

export type PushKind = 'trial_ending' | 'prop_breach' | 'session_soon'

/** How far ahead a trial ending counts as news. */
const TRIAL_NOTICE_HOURS = 24

/** Bounded sweep: one cron run must not try to read a whole customer base. */
const SWEEP_LIMIT = 500

type Claim = 'claimed' | 'duplicate' | 'unavailable'

/**
 * Reserves the right to send this notification exactly once.
 *
 * `unavailable` means the migration has not been applied. Nothing is sent in
 * that case: without a record of what was already said, a sweep is a source of
 * duplicates, and a missing notification is the smaller failure.
 */
async function claim(userId: string, kind: PushKind, eventKey: string): Promise<Claim> {
  const { error } = await getAdminClient()
    .from('push_events')
    .insert({ user_id: userId, kind, event_key: eventKey })

  if (!error) return 'claimed'
  // 23505: the primary key already holds this notification.
  if (error.code === '23505') return 'duplicate'
  if (error.code === '42P01') {
    logEvent('warn', 'push_events.missing_table', { hint: '20261131_push_events.sql' })
    return 'unavailable'
  }
  logEvent('error', 'push_events.claim', { userId, kind, error: error.message })
  return 'unavailable'
}

/** Gives the claim back, so a send that delivered nothing can be tried again. */
async function release(userId: string, kind: PushKind, eventKey: string): Promise<void> {
  const { error } = await getAdminClient()
    .from('push_events')
    .delete()
    .eq('user_id', userId)
    .eq('kind', kind)
    .eq('event_key', eventKey)
  if (error) logEvent('error', 'push_events.release', { userId, kind, error: error.message })
}

/**
 * Sends one notification, at most once per `eventKey`.
 *
 * Returns whether something was sent. A no-op from FCM (no service account, no
 * registered device) is treated as "not sent yet" rather than "done", because
 * the reason it did not go out is not going to be cured by the event expiring.
 */
async function pushOnce(
  userId: string,
  kind: PushKind,
  eventKey: string,
  notification: { title: string; body: string; data?: Record<string, string> }
): Promise<boolean> {
  if ((await claim(userId, kind, eventKey)) !== 'claimed') return false

  try {
    const result = await sendPushToUser(userId, notification)
    if (result.sent > 0) return true
    await release(userId, kind, eventKey)
    return false
  } catch (error: unknown) {
    await release(userId, kind, eventKey)
    logEvent('error', 'push_events.send', { userId, kind, error })
    return false
  }
}

/** Money as the notification says it: no currency, two decimals, sign kept. */
function amount(value: number): string {
  const rounded = Math.round(value * 100) / 100
  return rounded.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

/**
 * The reminder for a session that is about to start.
 *
 * The maths is the web reminder's own (`reminderState`), so the push, the banner
 * and the phone's local alarms all open and close on the same clock. What
 * differs is who runs it: a schedule on this plan can only fire once a day,
 * which cannot land an arbitrary session time, so the supervisor calls this
 * every cycle. The cron calls it too, as the backstop for accounts whose
 * terminal is not attached.
 *
 * Deduped on the occurrence key (`session id + start instant`), so the same
 * session is one notification no matter how many times either caller asks.
 */
export async function notifySessionStarting(now: Date = new Date()): Promise<number> {
  const admin = getAdminClient()
  const { data, error } = await admin
    .from('playbooks')
    .select('user_id, rules, days, sessions, reminder_minutes, reminders_enabled')
    .eq('reminders_enabled', true)
    .limit(SWEEP_LIMIT)
  if (error) {
    logEvent('warn', 'push_events.session_sweep', { error: error.message })
    return 0
  }

  const rows = (data ?? []) as (Record<string, unknown> & { user_id: string })[]
  if (rows.length === 0) return 0

  const zones = await admin
    .from('users')
    .select('id, timezone')
    .in('id', rows.map((row) => row.user_id))
  const timeZoneOf = new Map<string, string | null>(
    ((zones.data ?? []) as { id: string; timezone: string | null }[]).map((row) => [
      row.id,
      row.timezone,
    ])
  )

  let sent = 0
  for (const row of rows) {
    try {
      const playbook: Playbook = normalizePlaybook({
        rules: row.rules,
        days: row.days,
        sessions: row.sessions,
        reminderMinutes: row.reminder_minutes,
        remindersEnabled: row.reminders_enabled,
      })
      const state = reminderState(playbook, now, timeZoneOf.get(row.user_id) ?? null)
      if (!state?.due) continue

      const done = await pushOnce(row.user_id, 'session_soon', state.key, {
        title: `${state.occurrence.session.label} starts ${formatCountdown(state.minutesUntil)}`,
        body: 'Read the rules before the first trade — not after it.',
        data: { kind: 'session_soon' },
      })
      if (done) sent += 1
    } catch (failure: unknown) {
      logEvent('error', 'push_events.session_one', { userId: row.user_id, error: failure })
    }
  }
  return sent
}

const BREACH_COPY: Record<string, { title: string; body: (status: PropStatus) => string }> = {
  breach_daily: {
    title: 'Daily loss limit breached',
    body: (status) =>
      `Today is ${amount(status.daily_pnl)} against a ${amount(status.daily_loss_limit)} daily loss cap. ` +
      'Open MTL Ledger to review the day before it gets worse.',
  },
  breach_drawdown: {
    title: 'Drawdown limit breached',
    body: (status) =>
      `Drawdown is ${amount(status.drawdown)} against a ${amount(status.drawdown_limit)} limit. ` +
      'Open MTL Ledger to review the account.',
  },
  breach_consistency: {
    title: 'Consistency rule breached',
    body: (status) =>
      `Your best day is ${status.consistency.toFixed(0)}% of total profit, over the ` +
      `${amount(status.consistency_pct)}% consistency limit. Open MTL Ledger to review it.`,
  },
}

/**
 * Tells a trader that their prop account has broken a rule.
 *
 * The status comes from the `prop_status` RPC, so the push and the compliance
 * card cannot disagree: the browser is not deciding either. One notification per
 * rule per day — the account stays breached all day, and repeating it would turn
 * the alert into noise the trader learns to ignore.
 */
export async function notifyPropBreach(userId: string, now: Date = new Date()): Promise<boolean> {
  const { data, error } = await getAdminClient().rpc('prop_status', { p_user_id: userId })
  if (error) {
    logEvent('warn', 'push_events.prop_status', { userId, error: error.message })
    return false
  }
  if (!data) return false

  const status = data as PropStatus
  if (propStatusLevel(status.status) !== 'breach') return false

  const copy = BREACH_COPY[status.status]
  if (!copy) return false

  const day = now.toISOString().slice(0, 10)
  return pushOnce(userId, 'prop_breach', `${status.status}:${day}`, {
    title: copy.title,
    body: copy.body(status),
    data: { kind: 'prop_breach', status: status.status },
  })
}

/**
 * Sweeps every account with prop rules saved, for the cron's safety net.
 *
 * Sequential on purpose: the RPC is a query per account and a burst of five
 * hundred parallel ones against the same tables would slow the site down for
 * everybody else. The limit is what keeps one run bounded.
 */
export async function sweepPropBreaches(now: Date = new Date()): Promise<number> {
  const { data, error } = await getAdminClient()
    .from('prop_rules')
    .select('user_id')
    .limit(SWEEP_LIMIT)
  if (error) {
    logEvent('warn', 'push_events.sweep', { error: error.message })
    return 0
  }

  let sent = 0
  for (const row of (data ?? []) as { user_id: string }[]) {
    try {
      if (await notifyPropBreach(row.user_id, now)) sent += 1
    } catch (failure: unknown) {
      // One account's bad data must not stop the sweep for everyone after it.
      logEvent('error', 'push_events.sweep_one', { userId: row.user_id, error: failure })
    }
  }
  return sent
}

/**
 * Reminds the people whose trial is inside its last day.
 *
 * Not "if it exists": a trial that ended an hour ago is already handled by the
 * gates in `subscription.ts`, and waking someone to tell them something they can
 * no longer act on is worse than silence. The key is the trial's end date, so a
 * rerun of the cron on the same day sends nothing.
 */
export async function notifyTrialEnding(now: Date = new Date()): Promise<number> {
  const until = new Date(now.getTime() + TRIAL_NOTICE_HOURS * 60 * 60 * 1000)

  const { data, error } = await getAdminClient()
    .from('users')
    .select('id, trial_ends_at')
    .eq('subscription_status', 'trial')
    .gt('trial_ends_at', now.toISOString())
    .lte('trial_ends_at', until.toISOString())
    .limit(SWEEP_LIMIT)
  if (error) {
    logEvent('warn', 'push_events.trial_sweep', { error: error.message })
    return 0
  }

  let sent = 0
  for (const row of (data ?? []) as { id: string; trial_ends_at: string }[]) {
    try {
      const day = row.trial_ends_at.slice(0, 10)
      const done = await pushOnce(row.id, 'trial_ending', day, {
        title: 'Your free trial ends tomorrow',
        body:
          'Less than a day of your trial is left. Charts, autosync and prop monitoring stop when it does — ' +
          'open MTL Ledger to keep them.',
        data: { kind: 'trial_ending' },
      })
      if (done) sent += 1
    } catch (failure: unknown) {
      logEvent('error', 'push_events.trial_one', { userId: row.id, error: failure })
    }
  }
  return sent
}
