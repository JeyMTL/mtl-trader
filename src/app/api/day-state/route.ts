import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import {
  computeDayLock,
  computeDayState,
  DEFAULT_DAILY_STOP,
  effectiveLockMode,
  normalizeDailyStop,
  normalizeLockMode,
  type DailyStopDebrief,
  type DailyStopOverride,
  type DayState,
  type DayStateResponse,
  type LockMode,
  type TradeForDay,
} from '@/lib/daily-stop'
import { zonedDayBounds } from '@/lib/timezone'
import { loadDayTrades } from '@/lib/day-trades'
import type { AccountState } from '@/lib/subscription'

/**
 * Today's daily-stop state, and the trader's answer to it.
 *
 * GET is read-only: it loads the limit from the playbook, the timezone from the
 * profile and the day's closed trades, then returns one computed number. The
 * browser never decides whether a limit was breached, for the same reason the
 * prop-rule card never does — a client clock or a stale tab must not be able to
 * open the day early.
 *
 * POST records the two things that cannot be derived from trades: the debrief
 * after a stop and the reason for overriding it. Both are scoped to the local
 * day, so tomorrow starts clean without a job to reset anything.
 */

export const dynamic = 'force-dynamic'

const PLAYBOOK_COLUMNS = 'daily_loss_limit, max_trades_per_day, lock_mode'
const TRADE_COLUMNS = 'id, pnl, close_time, open_time, created_at, tags'

interface Loaded {
  state: DayState
  rules: { limit: number; maxTrades: number; timeZone: string }
  lockMode: LockMode
  bounds: { key: string; start: Date; end: Date }
  debrief: DailyStopDebrief | null
  override: DailyStopOverride | null
  missing: boolean
  /** Every trade that belongs to today, by any of its three clocks. */
  trades: TradeForDay[]
  now: Date
}

/** A column or table the migration has not created yet is not a server error. */
function isMissingSchema(error: { code?: string } | null | undefined): boolean {
  return error?.code === '42P01' || error?.code === '42703'
}

async function load(userId: string, now: Date): Promise<Loaded> {
  const admin = getAdminClient()

  const [playbookResult, profileResult] = await Promise.all([
    admin.from('playbooks').select(PLAYBOOK_COLUMNS).eq('user_id', userId).maybeSingle(),
    admin
      .from('users')
      .select('timezone, subscription_tier, subscription_status, trial_ends_at, current_period_end, max_trades')
      .eq('id', userId)
      .maybeSingle(),
  ])

  const rules = normalizeDailyStop({
    limit: playbookResult.data?.daily_loss_limit ?? DEFAULT_DAILY_STOP.limit,
    maxTrades: playbookResult.data?.max_trades_per_day ?? DEFAULT_DAILY_STOP.maxTrades,
    timeZone: profileResult.data?.timezone ?? DEFAULT_DAILY_STOP.timeZone,
  })
  // Hard is Pro. Basic keeps the soft freeze, so a row saved on Pro cannot keep
  // walling the journal after the plan lapses.
  const lockMode = effectiveLockMode(
    normalizeLockMode(playbookResult.data?.lock_mode),
    (profileResult.data ?? {}) as AccountState
  )
  const bounds = zonedDayBounds(now, rules.timeZone)

  // The rows are keyed on the local day, which is only known after the profile
  // timezone is read — a UTC-keyed first attempt would look correct for most
  // traders and silently use the wrong day for everyone else.
  const [trades, dayResult] = await Promise.all([
    loadDayTrades(userId, bounds, TRADE_COLUMNS),
    admin
      .from('trading_days')
      .select('debrief_followed, debrief_valid, debrief_note, override_reason, override_at')
      .eq('user_id', userId)
      .eq('day_key', bounds.key)
      .maybeSingle(),
  ])

  const missing = isMissingSchema(playbookResult.error) || isMissingSchema(dayResult.error)
  const dayRow = dayResult.data
  const state = computeDayState({ rules, trades, now })

  const debrief: DailyStopDebrief | null = dayRow
    ? {
        followed: typeof dayRow.debrief_followed === 'boolean' ? dayRow.debrief_followed : null,
        valid: typeof dayRow.debrief_valid === 'boolean' ? dayRow.debrief_valid : null,
        note: dayRow.debrief_note ?? '',
      }
    : null

  const override: DailyStopOverride | null = dayRow?.override_at
    ? {
        reason: dayRow.override_reason ?? '',
        at: dayRow.override_at,
      }
    : null

  return {
    state,
    rules,
    lockMode,
    bounds,
    debrief,
    override,
    missing,
    trades,
    now,
  }
}

/** The instant a written override was recorded, or null when there is none. */
function overrideInstant(override: DailyStopOverride | null): Date | null {
  if (!override) return null
  const at = new Date(override.at)
  return Number.isNaN(at.getTime()) ? null : at
}

function toResponse(loaded: Loaded): DayStateResponse {
  const { active } = computeDayLock({
    rules: loaded.rules,
    mode: loaded.lockMode,
    state: loaded.state,
    trades: loaded.trades,
    overrideAt: overrideInstant(loaded.override),
    now: loaded.now,
  })
  return {
    configured: loaded.state.configured,
    missing: loaded.missing || undefined,
    day: {
      key: loaded.state.dayKey,
      start: loaded.state.dayStart,
      end: loaded.state.dayEnd,
    },
    rules: loaded.rules,
    state: loaded.state,
    // `off` keeps the journal's existing behaviour exactly. Otherwise the lock
    // follows the rule, not just the day: before a lift that means the day's
    // breach, after one it means the fresh budget taken since the lift.
    lock: { mode: loaded.lockMode, active },
    overridden: Boolean(loaded.override),
    debrief: loaded.debrief,
    override: loaded.override,
  }
}

export async function GET(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const loaded = await load(user.id, new Date())
    return NextResponse.json(toResponse(loaded), {
      headers: { 'Cache-Control': 'no-store' },
    })
  } catch (error: unknown) {
    return apiError('day_state.get', error, 500, 'Could not read today’s daily stop.')
  }
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const parsed = await readJsonBody<{
      action?: unknown
      followed?: unknown
      valid?: unknown
      note?: unknown
      reason?: unknown
    }>(req, { maxBytes: 8 * 1024 })
    if (!parsed.ok) return parsed.response
    const body = parsed.value

    const action = body.action
    if (action !== 'debrief' && action !== 'override') {
      return NextResponse.json(
        { error: 'action must be "debrief" or "override".' },
        { status: 400 }
      )
    }

    const now = new Date()
    const loaded = await load(user.id, now)
    if (loaded.missing) {
      return NextResponse.json(
        { error: 'Daily stop needs the 20261122_daily_stop.sql migration.' },
        { status: 503 }
      )
    }

    const admin = getAdminClient()
    if (action === 'debrief') {
      const note = typeof body.note === 'string' ? body.note.trim().slice(0, 1000) : ''
      const followed = typeof body.followed === 'boolean' ? body.followed : null
      const valid = typeof body.valid === 'boolean' ? body.valid : null
      if (followed === null) {
        return NextResponse.json(
          { error: 'Answer whether you stopped at the limit.' },
          { status: 400 }
        )
      }

      const { error } = await admin.from('trading_days').upsert(
        {
          user_id: user.id,
          day_key: loaded.state.dayKey,
          timezone: loaded.rules.timeZone,
          stopped_pnl: loaded.state.realizedPnl,
          stopped_at: now.toISOString(),
          debrief_followed: followed,
          debrief_valid: valid,
          debrief_note: note,
          updated_at: now.toISOString(),
        },
        { onConflict: 'user_id,day_key' }
      )
      if (error) {
        logEvent('error', 'day_state.debrief', { userId: user.id, error: error.message })
        return apiError('day_state.debrief', error, 500, 'Could not save your debrief.')
      }
      return NextResponse.json({ ok: true })
    }

    // Hard is the one promise the app cannot walk back. The EA is refusing
    // orders and the journal is shut, so a server that accepted an override
    // would leave the browser and the terminal disagreeing about the same day.
    // It clears when the trading day rolls over, not when the trader asks.
    if (loaded.lockMode === 'hard') {
      return NextResponse.json(
        {
          error:
            'This is a hard daily stop — it cannot be lifted today. It clears at the start of your next trading day.',
        },
        { status: 403 }
      )
    }

    // One lift per day, and only one. Once the grace run has itself been lost,
    // asking again would make the stop a switch the trader can keep resetting;
    // the answer there is a clear message, not another frozen minute.
    if (loaded.override) {
      const resumed = computeDayLock({
        rules: loaded.rules,
        mode: loaded.lockMode,
        state: loaded.state,
        trades: loaded.trades,
        overrideAt: overrideInstant(loaded.override),
        now,
      })
      if (resumed.active) {
        return NextResponse.json(
          {
            error:
              'You already lifted this stop once today, and the fresh budget went too. Today is closed.',
          },
          { status: 403 }
        )
      }
    }

    // A soft stop is a speed bump: the guard acts in MT5 while the journal stays
    // usable, and the written reason is what turns an override into a decision
    // on the record rather than a silent undo.
    const reason = typeof body.reason === 'string' ? body.reason.trim().slice(0, 500) : ''
    if (reason.length < 10) {
      return NextResponse.json(
        { error: 'Say why you are overriding the stop (at least 10 characters).' },
        { status: 400 }
      )
    }

    const { error } = await admin.from('trading_days').upsert(
      {
        user_id: user.id,
        day_key: loaded.state.dayKey,
        timezone: loaded.rules.timeZone,
        stopped_pnl: loaded.state.realizedPnl,
        override_reason: reason,
        override_at: now.toISOString(),
        updated_at: now.toISOString(),
      },
      { onConflict: 'user_id,day_key' }
    )
    if (error) {
      logEvent('error', 'day_state.override', { userId: user.id, error: error.message })
      return apiError('day_state.override', error, 500, 'Could not save the override.')
    }

    return NextResponse.json({ ok: true })
  } catch (error: unknown) {
    return apiError('day_state.post', error, 500, 'Could not save your answer.')
  }
}
