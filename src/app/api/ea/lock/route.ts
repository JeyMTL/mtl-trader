import { NextResponse } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { getAdminClient } from '@/lib/server-auth'
import { apiError } from '@/lib/log'
import { clientKey, rateLimit } from '@/lib/rate-limit'
import {
  computeDayLock,
  computeDayState,
  normalizeDailyStop,
  normalizeLockMode,
  type DayState,
} from '@/lib/daily-stop'
import { zonedDayBounds } from '@/lib/notification-schedule'
import { loadDayTrades } from '@/lib/day-trades'

/**
 * The daily stop, as the MT5 guard EA sees it.
 *
 * The EA cannot call the Supabase-authenticated `/api/day-state`: it has no
 * browser session. It authenticates with the same `agent_token` the sync EA
 * already uses, and this route reads the same rules through the same pure
 * `computeDayState` — so the wall the trader sees and the wall the EA enforces
 * cannot disagree about the number.
 *
 * Both `soft` and `hard` lock here. Soft is the MT5 freeze with the journal
 * left open; hard adds the journal wall. `off` never reaches the EA.
 *
 * If the migration is missing or the answer cannot be computed, the route says
 * `locked: false`. A server bug must never leave a trader unable to close a
 * position.
 */

export const dynamic = 'force-dynamic'

const PLAYBOOK_COLUMNS = 'daily_loss_limit, max_trades_per_day, lock_mode'
const TRADE_COLUMNS = 'pnl, close_time'

function isMissingSchema(error: { code?: string } | null | undefined): boolean {
  return error?.code === '42P01' || error?.code === '42703'
}

function reasonFor(state: DayState): string {
  if (state.capReached && !(state.lossLimit > 0 && state.lossUsed >= state.lossLimit)) {
    return `Daily entry cap reached (${state.tradesCount}/${state.maxTrades}).`
  }
  return `Daily loss budget reached (${state.lossUsed.toFixed(2)} of ${state.lossLimit.toFixed(2)}).`
}

async function authorised(req: Request, userId: string): Promise<boolean> {
  const header = req.headers.get('authorization') ?? ''
  if (!header.startsWith('Bearer ')) return false
  const supplied = Buffer.from(header.slice('Bearer '.length))

  const { data: user, error } = await getAdminClient()
    .from('users')
    .select('id, agent_token')
    .eq('id', userId)
    .maybeSingle()

  // One answer for "no such account" and "wrong token", so the route cannot be
  // used to discover which user ids exist.
  const stored = Buffer.from(user?.agent_token || '')
  return (
    !error && Boolean(user) && stored.length === supplied.length && timingSafeEqual(stored, supplied)
  )
}

export async function GET(req: Request) {
  try {
    const userId = new URL(req.url).searchParams.get('userId') ?? ''
    if (!userId) {
      return NextResponse.json({ error: 'userId is required.' }, { status: 400 })
    }

    // A 30-second poll is 120 requests an hour; 600 leaves room for retries and
    // for a second terminal without letting an unauthenticated caller hammer
    // the token comparison.
    const limit = await rateLimit(clientKey(req, 'ea-lock'), 600, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many lock checks. The EA will retry shortly.' },
        {
          status: 429,
          headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) },
        }
      )
    }

    if (!(await authorised(req, userId))) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const admin = getAdminClient()
    const [playbookResult, profileResult] = await Promise.all([
      admin.from('playbooks').select(PLAYBOOK_COLUMNS).eq('user_id', userId).maybeSingle(),
      admin.from('users').select('timezone').eq('id', userId).maybeSingle(),
    ])

    if (isMissingSchema(playbookResult.error)) {
      return NextResponse.json(
        { locked: false, mode: 'off', missing: true },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    const mode = normalizeLockMode(playbookResult.data?.lock_mode)
    if (mode === 'off') {
      return NextResponse.json(
        { locked: false, mode, missing: false },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    const rules = normalizeDailyStop({
      limit: playbookResult.data?.daily_loss_limit,
      maxTrades: playbookResult.data?.max_trades_per_day,
      timeZone: profileResult.data?.timezone,
    })
    if (!rules.limit && !rules.maxTrades) {
      return NextResponse.json(
        { locked: false, mode, missing: false },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    const now = new Date()
    const bounds = zonedDayBounds(now, rules.timeZone)
    let trades
    let dayResult
    try {
      ;[trades, dayResult] = await Promise.all([
        loadDayTrades(userId, bounds, TRADE_COLUMNS),
        admin
          .from('trading_days')
          .select('override_at')
          .eq('user_id', userId)
          .eq('day_key', bounds.key)
          .maybeSingle(),
      ])
    } catch {
      // Fail open, loudly in the log. A lock that survives a server outage is
      // worse than a day that ends a minute late.
      return NextResponse.json(
        {
          locked: false,
          mode,
          missing: isMissingSchema(dayResult?.error),
          error: 'Could not read the day; the lock is released for this poll.',
        },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    if (dayResult.error) {
      return NextResponse.json(
        {
          locked: false,
          mode,
          missing: isMissingSchema(dayResult.error),
          error: 'Could not read the day; the lock is released for this poll.',
        },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    const state = computeDayState({ rules, trades, now })
    const overrideAt = dayResult.data?.override_at
      ? new Date(dayResult.data.override_at as string)
      : null
    // Same rule as the app: a lift is one grace run, and the stop re-arms on the
    // trades taken after it. The desk the trader sees and the wall the EA
    // enforces must not disagree about whether today is still open.
    const { active: locked } = computeDayLock({
      rules,
      mode,
      state,
      trades,
      overrideAt,
      now,
    })

    return NextResponse.json(
      {
        locked,
        mode,
        missing: false,
        dayKey: state.dayKey,
        // The instant the limit was reached. The EA uses it to distinguish a
        // fill opened after the stop from a position that was already open.
        since: state.stopAt,
        until: state.dayEnd,
        serverTime: now.toISOString(),
        reason: locked
          ? reasonFor(state)
          : overrideAt
            ? 'Stop lifted today.'
            : 'Inside the limits.',
        state: {
          realizedPnl: state.realizedPnl,
          lossLimit: state.lossLimit,
          tradesCount: state.tradesCount,
          maxTrades: state.maxTrades,
        },
      },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('ea_lock.get', error, 500, 'Could not read the lock state.')
  }
}
