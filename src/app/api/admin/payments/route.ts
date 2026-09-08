import { NextResponse } from 'next/server'
import { getAdminClient, requireAdmin } from '@/lib/server-auth'

export async function GET(req: Request) {
  try {
    const { user, error } = await requireAdmin(req)
    if (!user) {
      return NextResponse.json({ error }, { status: error === 'Unauthorized' ? 401 : 403 })
    }

    const supabase = getAdminClient()

    const { data: requests, error: dbError } = await supabase
      .from('payment_requests')
      .select('*, users!inner(id, email, full_name)')
      .order('created_at', { ascending: false })

    if (dbError) {
      return NextResponse.json({ error: dbError.message }, { status: 500 })
    }

    return NextResponse.json({ requests: requests || [] })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}

export async function POST(req: Request) {
  try {
    const { requestId, action } = await req.json()

    if (!requestId || !action) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
    }

    if (action !== 'approve' && action !== 'reject') {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }

    const { user, error } = await requireAdmin(req)
    if (!user) {
      return NextResponse.json({ error }, { status: error === 'Unauthorized' ? 401 : 403 })
    }

    const supabase = getAdminClient()

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
      .update({ status: newStatus, reviewed_by: user.id, reviewed_at: new Date().toISOString() })
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
