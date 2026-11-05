import { NextResponse } from 'next/server'
import { getAdminClient, requireAdmin } from '@/lib/server-auth'
import { apiError, logEvent } from '@/lib/log'
import { readJsonBody } from '@/lib/request'

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
      return apiError('admin.payments.list', dbError, 500, 'Could not load payment requests.')
    }

    return NextResponse.json(
      { requests: requests || [] },
      { headers: { 'Cache-Control': 'no-store' } }
    )
  } catch (error: unknown) {
    return apiError('admin.payments', error, 500, 'Could not load payment requests.')
  }
}

export async function POST(req: Request) {
  try {
    const parsed = await readJsonBody<{ requestId?: unknown; action?: unknown }>(req, {
      maxBytes: 8 * 1024,
    })
    if (!parsed.ok) return parsed.response
    const { requestId, action } = parsed.value

    if (typeof requestId !== 'string' || !requestId || !action) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
    }

    if (action !== 'approve' && action !== 'reject') {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }

    const { user, error } = await requireAdmin(req)
    if (!user) {
      return NextResponse.json({ error }, { status: error === 'Unauthorized' ? 401 : 403 })
    }

    const { data: result, error: reviewError } = await getAdminClient().rpc('review_bank_payment_request', {
      p_request_id: requestId,
      p_reviewer_id: user.id,
      p_action: action,
    })

    if (reviewError) {
      return apiError('admin.payments.review', reviewError, 500, 'Could not review the payment request.')
    }
    if (result === 'not_found') {
      return NextResponse.json({ error: 'Payment request not found' }, { status: 404 })
    }
    if (result === 'already_processed') {
      return NextResponse.json({ error: 'Request already processed' }, { status: 409 })
    }
    if (result === 'invalid_action') {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }
    if (result === 'invalid_plan' || result === 'amount_mismatch' || result === 'unknown_user') {
      return NextResponse.json({ error: 'Payment request has an invalid plan, amount, or account' }, { status: 400 })
    }
    if (result !== 'applied' && result !== 'would_downgrade' && result !== 'duplicate' && result !== 'rejected') {
      throw new Error(`Unexpected bank payment review result: ${String(result)}`)
    }

    logEvent('info', 'admin.payments.review', { requestId, action, reviewer: user.id, result })
    return NextResponse.json({
      success: true,
      note: result === 'would_downgrade' ? 'Account is already on a higher plan' : undefined,
    })
  } catch (error: unknown) {
    return apiError('admin.payments', error, 500, 'Could not load payment requests.')
  }
}
