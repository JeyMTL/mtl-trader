import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'
import {
  computeDayState,
  DEFAULT_DAILY_STOP,
  normalizeDailyStop,
  normalizeLockMode,
  type DailyStopDebrief,
  type DailyStopOverride,
  type DayState,
  type DayStateResponse,
  type LockMode,
} from '@/lib/daily-stop'
import { zonedDayBounds } from '@/lib/notification-schedule'

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
}

/** A column or table the migration has not created yet is not a server error. */
function isMissingSchema(error: { code?: string } | null | undefined): boolean {
  return error?.code === '42P01' || error?.code === '42703'
}

async function load(userId: string, now: Date): Promise<Loaded> {
  const admin = getAdminClient()

  const [playbookResult, profileResult] = await Promise.all([
    admin.from('playbooks').select(PLAYBOOK_COLUMNS).eq('user_id', userId).maybeSingle(),
    admin.from('users').select('timezone').eq('id', userId).maybeSingle(),
  ])

  const rules = normalizeDailyStop({
    limit: playbookResult.data?.daily_loss_limit ?? DEFAULT_DAILY_STOP.limit,
    maxTrades: playbookResult.data?.max_trades_per_day ?? DEFAULT_DAILY_STOP.maxTrades,
    timeZone: profileResult.data?.timezone ?? DEFAULT_DAILY_STOP.timeZone,
  })
  const lockMode = normalizeLockMode(playbookResult.data?.lock_mode)
  const bounds = zonedDayBounds(now, rules.timeZone)

  // The rows are keyed on the local day, which is only known after the profile
  // timezone is read — a UTC-keyed first attempt would look correct for most
  // traders and silently use the wrong day for everyone else.
  const [tradesResult, dayResult] = await Promise.all([
    admin
      .from('trades')
      .select(TRADE_COLUMNS)
      .eq('user_id', userId)
      .gte('close_time', bounds.start.toISOString())
      .lt('close_time', bounds.end.toISOString()),
    admin
      .from('trading_days')
      .select('debrief_followed, debrief_valid, debrief_note, override_reason, override_at')
      .eq('user_id', userId)
      .eq('day_key', bounds.key)
      .maybeSingle(),
  ])

  if (tradesResult.error) {
    throw new Error(`Could not read today's trades: ${tradesResult.error.message}`)
  }

  const missing = isMissingSchema(playbookResult.error) || isMissingSchema(dayResult.error)
  const dayRow = dayResult.data
  const state = computeDayState({ rules, trades: tradesResult.data ?? [], now })

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
  }
}

function toResponse(loaded: Loaded): DayStateResponse {
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
    // A breach only locks a day that has not been overridden, and only when a
    // mode was chosen. `off` keeps the journal's existing behaviour exactly.
    lock: {
      mode: loaded.lockMode,
      active: loaded.state.breached && !loaded.override && loaded.lockMode !== 'off',
    },
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

    // A hard lock is the trader's commitment to the EA, not a banner. Letting the
    // journal override it would release the EA on the next poll, so the override
    // endpoint is the one place where hard has to mean hard. Support stays
    // reachable for a false breach, and the lock clears at the local reset.
    if (loaded.lockMode === 'hard') {
      return NextResponse.json(
        {
          error:
            'A hard lock cannot be overridden from the journal. It releases at the next reset; contact support if the day was recorded incorrectly.',
        },
        { status: 403 }
      )
    }

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
