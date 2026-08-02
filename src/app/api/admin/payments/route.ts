import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export async function GET() {
  try {
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )

    const { data: requests, error } = await supabase
      .from('payment_requests')
      .select('*, users!inner(id, email, full_name)')
      .order('created_at', { ascending: false })

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ requests: requests || [] })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}

export async function POST(req: Request) {
  try {
    const { requestId, action, adminId } = await req.json()

    if (!requestId || !action || !adminId) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
    }

    if (action !== 'approve' && action !== 'reject') {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )

    const { data: request, error: reqError } = await supabase
      .from('payment_requests')
      .select('*')
      .eq('id', requestId)
      .single()

    if (reqError || !request) {
      return NextResponse.json({ error: 'Payment request not found' }, { status: 404 })
    }

    if (request.status !== 'pending') {
      return NextResponse.json({ error: 'Request already processed' }, { status: 400 })
    }

    const newStatus = action === 'approve' ? 'approved' : 'rejected'

    await supabase
      .from('payment_requests')
      .update({ status: newStatus, reviewed_by: adminId, reviewed_at: new Date().toISOString() })
      .eq('id', requestId)

    if (action === 'approve') {
      const maxTrades = request.plan_id === 'pro' ? -1 : request.plan_id === 'basic' ? 50 : 10
      await supabase
        .from('users')
        .update({
          subscription_tier: request.plan_id,
          subscription_status: 'active',
          max_trades: maxTrades,
          trades_remaining: maxTrades === -1 ? -1 : maxTrades,
        })
        .eq('id', request.user_id)
    }

    return NextResponse.json({ success: true })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
