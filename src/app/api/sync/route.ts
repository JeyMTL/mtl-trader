import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

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
    const { trades, userId, token } = await req.json()

    if (!trades || !userId || !token) {
      return NextResponse.json({ error: 'Missing trades, userId, or token' }, { status: 400 })
    }

    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, agent_token')
      .eq('id', userId)
      .single()

    if (userError || !user) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    if (user.agent_token !== token) {
      return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
    }

    const { data: existingTrades } = await supabase
      .from('trades')
      .select('ticket')
      .eq('user_id', userId)

    const existingTickets = new Set(existingTrades?.map(t => t.ticket) || [])

    const newTrades = trades.filter((trade: MT5Trade & { ticket: number }) => !existingTickets.has(trade.ticket))

    if (newTrades.length === 0) {
      return NextResponse.json({ message: 'No new trades', imported: 0 })
    }

    const tradesToInsert = newTrades.map((trade: MT5Trade & { ticket: number }) => ({
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
      return NextResponse.json({ error: insertError.message }, { status: 500 })
    }

    const { data: userData } = await supabase
      .from('users')
      .select('trades_remaining')
      .eq('id', userId)
      .single()

    if (userData && userData.trades_remaining !== -1) {
      await supabase
        .from('users')
        .update({ trades_remaining: Math.max(0, userData.trades_remaining - inserted!.length) })
        .eq('id', userId)
    }

    return NextResponse.json({ message: 'Sync complete', imported: inserted!.length })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}

export async function GET(req: Request) {
  try {
    const url = new URL(req.url)
    const userId = url.searchParams.get('userId')

    if (!userId) {
      return NextResponse.json({ error: 'Missing userId' }, { status: 400 })
    }

    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, agent_token')
      .eq('id', userId)
      .single()

    if (userError || !user) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    if (!user.agent_token) {
      const token = generateToken()
      await supabase
        .from('users')
        .update({ agent_token: token })
        .eq('id', userId)

      return NextResponse.json({ token, isNew: true })
    }

    return NextResponse.json({ token: user.agent_token, isNew: false })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}

function generateToken(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  let result = ''
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return result
}
