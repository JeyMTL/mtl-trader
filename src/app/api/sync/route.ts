import { NextResponse } from 'next/server'
import { getAdminClient, getAuthUser } from '@/lib/server-auth'
import { randomBytes, timingSafeEqual } from 'node:crypto'
import { rateLimit } from '@/lib/rate-limit'
import { apiError, logEvent } from '@/lib/log'

interface MT5Trade {
  ticket: number
  symbol: string
  type: 'BUY' | 'SELL'
  entry_price: number
  exit_price: number
  lot_size: number
  stop_loss: number
  take_profit: number
  pnl: number
  commission: number
  swap: number
  open_time: string
  close_time: string
  timeframe: string
  strategy: string
}

export async function POST(req: Request) {
  try {
    const body = await req.json() as { trades?: unknown; userId?: unknown; token?: unknown }
    const trades = body.trades
    const userId = typeof body.userId === 'string' ? body.userId : ''
    const token = typeof body.token === 'string' ? body.token : ''

    if (!Array.isArray(trades) || !userId || !token) {
      return NextResponse.json({ error: 'Missing trades, userId, or token' }, { status: 400 })
    }
    if (trades.length > 1000) {
      return NextResponse.json({ error: 'Sync batch is limited to 1000 trades' }, { status: 413 })
    }

    // The agent polls every 60s, so 240/hour leaves room for retries without
    // letting a leaked token hammer the database.
    const limit = await rateLimit(`sync:${userId}`, 240, 60 * 60 * 1000)
    if (!limit.ok) {
      return NextResponse.json(
        { error: 'Too many sync requests. The agent will retry shortly.' },
        { status: 429, headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) } }
      )
    }

    const { data: user, error: userError } = await getAdminClient()
      .from('users')
      .select('id, agent_token')
      .eq('id', userId)
      .maybeSingle()

    // One response for "no such account" and "wrong token": distinguishing them
    // let anyone probe whether a user id exists without holding a token.
    const storedToken = Buffer.from(user?.agent_token || '')
    const suppliedToken = Buffer.from(token)
    const tokenValid =
      !userError &&
      Boolean(user) &&
      storedToken.length === suppliedToken.length &&
      timingSafeEqual(storedToken, suppliedToken)

    if (!tokenValid) {
      return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
    }

    const { data: authData } = await getAdminClient().auth.admin.getUserById(userId)
    if (!authData.user?.email_confirmed_at) {
      return NextResponse.json({ error: 'Email verification is required before syncing trades' }, { status: 403 })
    }

    if (!trades.every(isValidTrade)) {
      return NextResponse.json({ error: 'One or more trades has invalid data' }, { status: 400 })
    }
    if (trades.length === 0) {
      return NextResponse.json({ message: 'No new trades', imported: 0 })
    }

    const supabase = getAdminClient()
    const incomingTickets = [...new Set(trades.map((trade) => trade.ticket))]
    const { data: existingTrades, error: existingError } = await supabase
      .from('trades')
      .select('ticket')
      .eq('user_id', userId)
      .in('ticket', incomingTickets)

    if (existingError) {
      return apiError('sync.existing', existingError, 500, 'Could not check existing trades.')
    }

    const existingTickets = new Set(existingTrades.map(t => t.ticket))

    const seenTickets = new Set(existingTickets)
    const newTrades = trades.filter((trade) => {
      if (seenTickets.has(trade.ticket)) return false
      seenTickets.add(trade.ticket)
      return true
    })

    if (newTrades.length === 0) {
      return NextResponse.json({ message: 'No new trades', imported: 0 })
    }

    const tradesToInsert = newTrades.map((trade) => ({
      user_id: userId,
      ticket: trade.ticket,
      symbol: trade.symbol,
      type: trade.type,
      entry_price: trade.entry_price,
      exit_price: trade.exit_price,
      lot_size: trade.lot_size,
      stop_loss: trade.stop_loss || 0,
      take_profit: trade.take_profit || 0,
      pnl: trade.pnl,
      commission: trade.commission || 0,
      swap: trade.swap || 0,
      open_time: trade.open_time,
      close_time: trade.close_time,
      timeframe: trade.timeframe || '',
      strategy: trade.strategy || '',
    }))

    const { data: inserted, error: insertError } = await supabase
      .from('trades')
      .insert(tradesToInsert)
      .select('id')

    if (insertError) {
      return apiError('sync.insert', insertError, 500, 'Could not save the synced trades.')
    }

    // Marks a hosted connection as live, so the app can show "last trade 12s
    // ago". Best-effort: desktop-agent users have no row here, and a failed
    // stamp must never fail a sync whose trades are already saved.
    const now = new Date().toISOString()
    try {
      await supabase
        .from('broker_connections')
        .update({ status: 'connected', last_sync_at: now, last_error: null, updated_at: now })
        .eq('user_id', userId)
    } catch {
      // The migration may not be applied yet; the sync itself succeeded.
    }

    // `trades_remaining` is not authoritative: the enforce_trade_quota trigger
    // enforces the monthly limit from `max_trades`, so we no longer mutate it here.
    return NextResponse.json({ message: 'Sync complete', imported: inserted!.length })
  } catch (error: unknown) {
    return apiError('sync.post', error, 500, 'Could not sync trades.')
  }
}

export async function GET(req: Request) {
  try {
    const url = new URL(req.url)
    const userId = url.searchParams.get('userId')

    if (!userId) {
      return NextResponse.json({ error: 'Missing userId' }, { status: 400 })
    }

    const authUser = await getAuthUser(req)
    if (!authUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    if (authUser.id !== userId) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    const { data: user, error: userError } = await getAdminClient()
      .from('users')
      .select('id, agent_token')
      .eq('id', userId)
      .single()

    if (userError || !user) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    if (!user.agent_token) {
      const token = generateToken()
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

function generateToken(): string {
  return randomBytes(32).toString('hex')
}

function isValidTrade(value: unknown): value is MT5Trade {
  if (!value || typeof value !== 'object') return false
  const trade = value as Record<string, unknown>
  const numericFields = ['ticket', 'entry_price', 'exit_price', 'lot_size', 'pnl']
  const hasValidNumbers = numericFields.every((field) => typeof trade[field] === 'number' && Number.isFinite(trade[field]))
  const optionalNumbers = ['stop_loss', 'take_profit', 'commission', 'swap']
  const hasValidOptionalNumbers = optionalNumbers.every((field) =>
    trade[field] === undefined || (typeof trade[field] === 'number' && Number.isFinite(trade[field]))
  )
  const hasValidDates =
    typeof trade.open_time === 'string' &&
    Number.isFinite(Date.parse(trade.open_time)) &&
    typeof trade.close_time === 'string' &&
    Number.isFinite(Date.parse(trade.close_time))
  const hasValidIdentity = Number.isInteger(trade.ticket) && (trade.ticket as number) > 0 &&
    typeof trade.symbol === 'string' && trade.symbol.length > 0 && trade.symbol.length <= 32 &&
    (trade.type === 'BUY' || trade.type === 'SELL')
  const hasValidOptionalText = ['timeframe', 'strategy'].every((field) =>
    trade[field] === undefined || (typeof trade[field] === 'string' && trade[field].length <= 100)
  )
  return hasValidNumbers && hasValidOptionalNumbers && hasValidDates && hasValidIdentity && hasValidOptionalText
}
