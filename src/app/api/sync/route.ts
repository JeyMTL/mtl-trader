import { NextResponse } from 'next/server'
import { getAdminClient } from '@/lib/server-auth'
import { randomBytes, timingSafeEqual } from 'node:crypto'
import { rateLimit } from '@/lib/rate-limit'
import { hasValidBearer } from '@/lib/auth-guards'
import { apiError, logEvent } from '@/lib/log'
import { checkFeature } from '@/lib/plan-guard'

/**
 * Trade ingest for the desktop agent and the hosted sync supervisor.
 *
 * Reliability rules, in order of importance:
 *
 *  1. **Identity is the MT5 position**, not a closing deal. A position that
 *     scales out has several closing deals with different ticket ids, so keying
 *     on those inserted the same trade twice and doubled its P&L.
 *  2. **Re-sending is free.** Every row is an upsert; a duplicate is ignored
 *     rather than counted, so the agent may resend its whole window on every
 *     poll without corrupting anything.
 *  3. **A delete sticks.** Position ids the customer deleted are recorded by a
 *     database trigger and filtered here, so the next poll cannot resurrect them.
 *  4. **One bad row does not sink the batch.** Rows are validated individually
 *     and the response reports how many landed, were skipped, or were rejected.
 *  5. **Chunked writes.** A large first sync is split so a single oversized
 *     insert cannot time out after the customer has waited a minute for it.
 *
 * Two callers authenticate differently: the desktop agent with the customer's
 * `agent_token` (the original scheme), and the supervisor with a server-wide
 * `SYNC_SUPERVISOR_TOKEN` plus the `userId` it is syncing for.
 */

const MAX_BATCH = 5000
const CHUNK = 200

interface IncomingTrade {
  ticket?: unknown
  position_id?: unknown
  positionId?: unknown
  symbol: string
  type: 'BUY' | 'SELL'
  entry_price: number
  exit_price: number
  lot_size: number
  stop_loss?: number
  take_profit?: number
  pnl: number
  commission?: number
  swap?: number
  open_time: string
  close_time: string
  timeframe?: string
  strategy?: string
}

interface PreparedTrade {
  key: number
  ticket: number
  row: Record<string, unknown>
}

function numeric(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/**
 * Timestamps without an explicit offset are read as UTC. MT5 deal times are
 * broker-server time and the agent now sends them as UTC, but an older agent
 * sends a naive local string — treating it as UTC is still better than letting
 * each runtime guess, because `new Date('2026-01-01T10:00:00')` means *local*
 * time in JavaScript and shifted every trade by the machine's offset.
 */
function isoUtc(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null
  const raw = value.trim()
  const hasZone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw)
  const candidate = hasZone ? raw : `${raw}Z`
  const parsed = Date.parse(candidate)
  if (!Number.isFinite(parsed)) return null
  return new Date(parsed).toISOString()
}

function prepare(value: unknown, userId: string): PreparedTrade | string {
  if (!value || typeof value !== 'object') return 'not an object'
  const trade = value as Record<string, unknown>

  const identity =
    numeric(trade.position_id) ?? numeric(trade.positionId) ?? numeric(trade.ticket)
  if (identity === null || !Number.isInteger(identity) || identity <= 0) {
    return 'missing position id'
  }

  const symbol = typeof trade.symbol === 'string' ? trade.symbol.trim().toUpperCase() : ''
  if (!symbol || symbol.length > 32) return 'invalid symbol'
  if (!/^[A-Z0-9._#\-/]+$/.test(symbol)) return 'invalid symbol'

  if (trade.type !== 'BUY' && trade.type !== 'SELL') return 'invalid side'

  const entry = numeric(trade.entry_price)
  const exit = numeric(trade.exit_price)
  const lot = numeric(trade.lot_size)
  const pnl = numeric(trade.pnl)
  if (entry === null || exit === null || lot === null || pnl === null) return 'missing numbers'

  const open = isoUtc(trade.open_time)
  const close = isoUtc(trade.close_time)
  if (!open || !close) return 'invalid timestamps'
  if (Date.parse(close) < Date.parse(open)) return 'closed before it opened'
  // A future close is a clock problem, not a trade; it would also land in next
  // month's quota and heatmap.
  if (Date.parse(close) > Date.now() + 24 * 60 * 60 * 1000) return 'close time is in the future'

  const text = (field: unknown) =>
    typeof field === 'string' && field.length <= 100 ? field : ''

  return {
    key: identity,
    ticket: numeric(trade.ticket) ?? identity,
    row: {
      user_id: userId,
      position_id: identity,
      ticket: numeric(trade.ticket) ?? identity,
      symbol,
      type: trade.type,
      entry_price: entry,
      exit_price: exit,
      lot_size: lot,
      stop_loss: numeric(trade.stop_loss) ?? 0,
      take_profit: numeric(trade.take_profit) ?? 0,
      pnl,
      commission: numeric(trade.commission) ?? 0,
      swap: numeric(trade.swap) ?? 0,
      open_time: open,
      close_time: close,
      timeframe: text(trade.timeframe),
      strategy: text(trade.strategy),
    },
  }
}

async function authorised(req: Request, userId: string, token: string) {
  // Supervisor: one server-side secret, and it may sync for any customer it
  // holds a connection for. Never accepted from a browser because the header is
  // server-side only.
  if (hasValidBearer(req.headers.get('authorization') ? req : req, process.env.SYNC_SUPERVISOR_TOKEN)) {
    return 'supervisor' as const
  }

  const { data: user, error } = await getAdminClient()
    .from('users')
    .select('id, agent_token')
    .eq('id', userId)
    .maybeSingle()

  // One response for "no such account" and "wrong token": distinguishing them
  // let anyone probe whether a user id exists without holding a token.
  const stored = Buffer.from(user?.agent_token || '')
  const supplied = Buffer.from(token)
  const valid =
    !error && Boolean(user) && stored.length === supplied.length && timingSafeEqual(stored, supplied)

  if (!valid) return null

  const { data: authData } = await getAdminClient().auth.admin.getUserById(userId)
  if (!authData.user?.email_confirmed_at) return 'unverified' as const
  return 'agent' as const
}

export async function POST(req: Request) {
  try {
    const body = (await req.json().catch(() => ({}))) as {
      trades?: unknown
      userId?: unknown
      token?: unknown
    }

    const userId = typeof body.userId === 'string' ? body.userId : ''
    const token = typeof body.token === 'string' ? body.token : ''
    if (!Array.isArray(body.trades) || !userId) {
      return NextResponse.json({ error: 'Missing trades or userId' }, { status: 400 })
    }
    if (body.trades.length > MAX_BATCH) {
      return NextResponse.json(
        { error: `Sync batch is limited to ${MAX_BATCH} trades; send a smaller window` },
        { status: 413 }
      )
    }

    const limit = await rateLimit(`sync:${userId}`, 240, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many sync requests. The agent will retry shortly.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const auth = await authorised(req, userId, token)
    if (!auth) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
    if (auth === 'unverified') {
      return NextResponse.json(
        { error: 'Email verification is required before syncing trades' },
        { status: 403 }
      )
    }

    // Autosync is included from Basic, but a lapsed period or ended trial is
    // still refused. Checked after the token, so an unauthorised caller learns
    // nothing about the account's plan.
    const gate = await checkFeature(userId, 'sync')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    if (body.trades.length === 0) {
      return NextResponse.json({ imported: 0, skipped: 0, invalid: 0, suppressed: 0 })
    }

    const supabase = getAdminClient()

    // Prepare row by row: one malformed trade must not discard the other 900.
    const prepared: PreparedTrade[] = []
    const invalid: string[] = []
    for (const raw of body.trades) {
      const result = prepare(raw, userId)
      if (typeof result === 'string') invalid.push(result)
      else prepared.push(result)
    }

    if (prepared.length === 0) {
      logEvent('warn', 'sync.all_invalid', { userId, count: invalid.length, reasons: invalid.slice(0, 5) })
      return NextResponse.json(
        { error: 'No valid trades in the batch', invalid: invalid.length, reasons: [...new Set(invalid)] },
        { status: 400 }
      )
    }

    // Collapse duplicates inside the batch itself (a scale-out can repeat a
    // position), keeping the last observation, which carries the final P&L.
    const byKey = new Map<number, PreparedTrade>()
    for (const item of prepared) byKey.set(item.key, item)
    const unique = [...byKey.values()]
    const keys = unique.map((item) => item.key)
    const tickets = unique.map((item) => item.ticket)

    const [existingPosition, existingTicket, suppressed] = await Promise.all([
      supabase.from('trades').select('position_id').eq('user_id', userId).in('position_id', keys),
      supabase.from('trades').select('ticket').eq('user_id', userId).in('ticket', tickets),
      supabase.from('sync_suppressions').select('position_id').eq('user_id', userId).in('position_id', keys),
    ])

    // The migration may not be applied yet in a preview environment; a failed
    // suppression read must not break syncing, it only re-enables the old bug.
    if (existingPosition.error) {
      logEvent('warn', 'sync.existing', { userId, error: existingPosition.error.message })
    }

    const knownPositions = new Set<number>()
    for (const row of existingPosition.data ?? []) {
      if (row.position_id != null) knownPositions.add(Number(row.position_id))
    }
    // Rows written by the older agent carry only a ticket, and they compared
    // against the *ticket* rather than the position id — so the two sets have to
    // stay separate or the legacy match silently never fires.
    const knownTickets = new Set<number>()
    for (const row of existingTicket.data ?? []) {
      if (row.ticket != null) knownTickets.add(Number(row.ticket))
    }
    const deleted = new Set<number>((suppressed.data ?? []).map((row) => Number(row.position_id)))

    const suppressedCount = unique.filter((item) => deleted.has(item.key)).length
    const fresh = unique.filter(
      (item) =>
        !knownPositions.has(item.key) && !knownTickets.has(item.ticket) && !deleted.has(item.key)
    )
    const skipped = unique.length - fresh.length - suppressedCount

    if (fresh.length === 0) {
      await touchConnection(userId, 0)
      return NextResponse.json(
        { imported: 0, skipped, invalid: invalid.length, suppressed: suppressedCount },
        { status: 200 }
      )
    }

    let imported = 0
    for (let index = 0; index < fresh.length; index += CHUNK) {
      const chunk = fresh.slice(index, index + CHUNK).map((item) => item.row)
      const { data, error } = await supabase
        .from('trades')
        .upsert(chunk, { onConflict: 'user_id,position_id', ignoreDuplicates: true })
        .select('id')

      if (error) {
        // A partial sync is better than none: report what landed and let the
        // agent retry, which is safe because every write is idempotent.
        logEvent('error', 'sync.insert', {
          userId,
          error: error.message,
          imported,
          remaining: fresh.length - index,
        })
        if (imported === 0) {
          return apiError('sync.insert', error, 500, 'Could not save the synced trades.')
        }
        break
      }
      imported += data?.length ?? 0
    }

    await touchConnection(userId, imported)

    return NextResponse.json({
      imported,
      skipped,
      invalid: invalid.length,
      suppressed: suppressedCount,
    })
  } catch (error: unknown) {
    return apiError('sync.post', error, 500, 'Could not sync trades.')
  }
}

/**
 * Marks a hosted connection as live so the app can show "last trade 12s ago".
 * Best-effort: desktop-agent users have no row here, and a failure must never
 * fail a sync whose trades are already saved.
 */
async function touchConnection(userId: string, imported: number) {
  const now = new Date().toISOString()
  try {
    await getAdminClient()
      .from('broker_connections')
      .update({
        status: 'connected',
        last_sync_at: imported > 0 ? now : undefined,
        last_error: null,
        updated_at: now,
      })
      .eq('user_id', userId)
  } catch {
    // The table may not exist in an environment without the migration.
  }
}

export async function GET(req: Request) {
  try {
    const url = new URL(req.url)
    const userId = url.searchParams.get('userId')
    if (!userId) return NextResponse.json({ error: 'Missing userId' }, { status: 400 })

    const authHeader = req.headers.get('authorization') || ''
    const isSupervisor = hasValidBearer(req, process.env.SYNC_SUPERVISOR_TOKEN)
    if (!isSupervisor) {
      const { getAuthUser } = await import('@/lib/server-auth')
      const authUser = await getAuthUser(req)
      if (!authUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
      if (authUser.id !== userId) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    } else if (!authHeader) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { data: user, error } = await getAdminClient()
      .from('users')
      .select('id, agent_token')
      .eq('id', userId)
      .maybeSingle()

    if (error || !user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

    // Same gate as ingest: a lapsed account must not be able to set up an agent
    // that then 402s on every trade it sends.
    const gate = await checkFeature(userId, 'sync')
    if (!gate.allowed) {
      return NextResponse.json(
        { error: gate.message, code: 'upgrade_required' },
        { status: gate.status }
      )
    }

    if (!user.agent_token) {
      const token = randomBytes(32).toString('hex')
      const { error: updateError } = await getAdminClient()
        .from('users')
        .update({ agent_token: token })
        .eq('id', userId)
      if (updateError) {
        return apiError('sync.token', updateError, 500, 'Could not save the sync token.')
      }
      logEvent('info', 'sync.token.created', { userId })
      return NextResponse.json({ token, isNew: true })
    }

    return NextResponse.json({ token: user.agent_token, isNew: false })
  } catch (error: unknown) {
    return apiError('sync.get', error, 500, 'Could not load the sync token.')
  }
}
