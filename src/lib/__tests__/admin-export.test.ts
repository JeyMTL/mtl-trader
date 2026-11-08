import { describe, it, expect, beforeEach, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  admin: true,
  rows: [] as Row[],
  error: null as { message: string } | null,
}))

vi.mock('@/lib/server-auth', () => ({
  requireAdmin: async () =>
    state.admin
      ? { user: { id: 'admin-1' }, error: null }
      : { user: null, error: 'Forbidden' },
  getAdminClient: () => ({
    from: () => ({
      select: () => ({
        order: async () => ({ data: state.rows, error: state.error }),
      }),
    }),
  }),
}))

import { GET } from '@/app/api/admin/payments/export/route'

function request() {
  return new Request('http://localhost/api/admin/payments/export')
}

describe('admin payment export', () => {
  beforeEach(() => {
    state.admin = true
    state.error = null
    state.rows = [
      {
        id: 'req-1',
        created_at: '2026-06-01T10:00:00Z',
        status: 'approved',
        plan_id: 'pro',
        amount: 29,
        reference: 'MTL-001',
        reviewed_at: null,
        reviewed_by: null,
        users: { email: 'trader@example.com', full_name: 'Jane "JT" Okafor, Jr.' },
      },
    ]
  })

  it('returns a CSV attachment with a header row', async () => {
    const res = await GET(request())

    expect(res.status).toBe(200)
    expect(res.headers.get('Content-Type')).toContain('text/csv')
    expect(res.headers.get('Content-Disposition')).toMatch(/attachment; filename="payment-requests-\d{4}-\d{2}-\d{2}\.csv"/)

    const bytes = new Uint8Array(await res.arrayBuffer())
    expect([bytes[0], bytes[1], bytes[2]]).toEqual([0xef, 0xbb, 0xbf])
    const body = new TextDecoder('utf-8', { ignoreBOM: true }).decode(bytes)
    const [header, row] = body.replace(/^\uFEFF/, '').trim().split('\r\n')
    expect(header).toBe('"request_id","created_at","status","plan_id","amount","reference","user_email","user_name","reviewed_at","reviewed_by"')
    expect(row).toContain('"trader@example.com"')
    expect(row).toContain('"Jane ""JT"" Okafor, Jr."')
    expect(row).toContain('"29"')
  })

  it('neutralises spreadsheet formulas in user-supplied fields', async () => {
    state.rows = [
      {
        id: 'req-2',
        created_at: '2026-06-01T10:00:00Z',
        status: 'approved',
        plan_id: 'pro',
        amount: 29,
        reference: '=HYPERLINK("https://evil.example")',
        reviewed_at: null,
        reviewed_by: null,
        users: { email: 'trader@example.com', full_name: '=2+2' },
      },
    ]

    const res = await GET(request())
    const body = await res.text()
    expect(body).toContain(`"'=HYPERLINK(""https://evil.example"")"`)
    expect(body).toContain(`"'=2+2"`)
  })

  it('rejects callers who are not admins', async () => {
    state.admin = false
    const res = await GET(request())
    expect(res.status).toBe(403)
  })

  it('reports a database failure instead of an empty file', async () => {
    state.error = { message: 'boom' }
    const res = await GET(request())
    expect(res.status).toBe(500)
  })
})
