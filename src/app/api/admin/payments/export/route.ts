import { NextResponse } from 'next/server'
import { getAdminClient, requireAdmin } from '@/lib/server-auth'
import { apiError } from '@/lib/log'

function csvCell(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value)
  // Quoting does not stop a spreadsheet from evaluating a cell that begins
  // with a formula marker. Prefix those with an apostrophe so an imported name
  // or reference is displayed as text instead of executed.
  const safe = /^[=+\-@\t\r]/.test(text) ? `'${text}` : text
  return `"${safe.replace(/"/g, '""')}"`
}

function toCsv(rows: unknown[][]): string {
  // A leading BOM keeps Excel happy with UTF-8 names and references.
  return '\uFEFF' + rows.map(row => row.map(csvCell).join(',')).join('\r\n') + '\r\n'
}

export async function GET(req: Request) {
  try {
    const { user, error } = await requireAdmin(req)
    if (!user) {
      return NextResponse.json({ error }, { status: error === 'Unauthorized' ? 401 : 403 })
    }

    const { data, error: dbError } = await getAdminClient()
      .from('payment_requests')
      .select('*, users!inner(id, email, full_name)')
      .order('created_at', { ascending: false })

    if (dbError) {
      return apiError('admin.payments.export', dbError, 500, 'Could not export payment requests.')
    }

    const rows: unknown[][] = [
      ['request_id', 'created_at', 'status', 'plan_id', 'amount', 'reference', 'user_email', 'user_name', 'reviewed_at', 'reviewed_by'],
      ...(data || []).map((request: Record<string, unknown>) => {
        const owner = request.users as { email?: string; full_name?: string } | null
        return [
          request.id,
          request.created_at,
          request.status,
          request.plan_id,
          request.amount,
          request.reference,
          owner?.email,
          owner?.full_name,
          request.reviewed_at,
          request.reviewed_by,
        ]
      }),
    ]

    const filename = `payment-requests-${new Date().toISOString().slice(0, 10)}.csv`

    return new NextResponse(toCsv(rows), {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="${filename}"`,
        'Cache-Control': 'no-store',
      },
    })
  } catch (error: unknown) {
    return apiError('admin.payments.export', error, 500, 'Could not export payment requests.')
  }
}
