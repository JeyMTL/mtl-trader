import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

type Row = Record<string, unknown>

// Shared, mutable fixtures the hoisted mocks read from.
const state = vi.hoisted(() => ({
  users: [] as Row[],
  trades: [] as Row[],
  emailConfigured: true,
  sent: [] as Array<{ to: string; subject: string; html: string }>,
}))

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => ({
    from: (table: string) => {
      const result = Promise.resolve({
        data: table === 'users' ? state.users : state.trades,
        error: null,
      })
      const chain = {
        select: () => chain,
        eq: () => chain,
        limit: () => result,
        then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) =>
          result.then(resolve, reject),
      }
      return chain
    },
  }),
}))

vi.mock('@/lib/email', () => ({
  isEmailConfigured: () => state.emailConfigured,
  sendEmail: (input: { to: string; subject: string; html: string }) => {
    state.sent.push(input)
    return Promise.resolve({ sent: true, id: `email-${state.sent.length}` })
  },
}))

const NO_HEADERS = {}
const AUTH_HEADERS = { authorization: 'Bearer test-secret' }

async function runCron(headers: Record<string, string> = {}) {
  const { GET } = await import('@/app/api/cron/notifications/route')
  const res = await GET(new Request('http://localhost/api/cron/notifications', { headers }))
  const body = (await res.json()) as Record<string, number | boolean>
  return { res, body }
}

function user(overrides: Row = {}): Row {
  return {
    id: 'u1',
    email: 'ann@example.com',
    full_name: 'Ann',
    currency: 'USD',
    timezone: 'UTC',
    notifications_daily: false,
    notifications_weekly: false,
    notifications_monthly_email: false,
    notifications_journal_reminders: false,
    ...overrides,
  }
}

beforeEach(() => {
  state.users = []
  state.trades = []
  state.emailConfigured = true
  state.sent = []
  process.env.CRON_SECRET = 'test-secret'
  process.env.NEXT_PUBLIC_APP_URL = 'https://app.example.com'
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-06-02T07:00:00.000Z')) // Tuesday
})

afterEach(() => {
  vi.useRealTimers()
})

describe('notifications cron', () => {
  it('rejects a request without the bearer secret', async () => {
    const { res } = await runCron(NO_HEADERS)
    expect(res.status).toBe(401)
  })

  it('returns 503 when email is not configured', async () => {
    state.emailConfigured = false
    const { res } = await runCron(AUTH_HEADERS)
    expect(res.status).toBe(503)
  })

  it('sends the daily summary for a non-empty window', async () => {
    state.users = [user({ notifications_daily: true })]
    state.trades = [{ pnl: 100, close_time: '2026-06-01T10:00:00.000Z' }]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(1)
    expect(state.sent[0].to).toBe('ann@example.com')
    expect(state.sent[0].subject).toContain('Your daily summary')
    expect(state.sent[0].subject).toContain('1 trade')
  })

  it('skips an empty summary window', async () => {
    state.users = [user({ notifications_daily: true })]
    state.trades = []

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(0)
    expect(body.skipped).toBe(1)
  })

  it('sends a journal reminder on a weekday when nothing was journaled today', async () => {
    state.users = [user({ notifications_journal_reminders: true })]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(1)
    expect(state.sent[0].subject.toLowerCase()).toContain('journal')
  })

  it('does not send a journal reminder once a trade exists today', async () => {
    state.users = [user({ notifications_journal_reminders: true })]
    state.trades = [{ pnl: 5, close_time: '2026-06-02T01:00:00.000Z' }]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(0)
  })

  it('sends the weekly report only on Mondays', async () => {
    state.users = [user({ notifications_weekly: true })]
    state.trades = [{ pnl: 50, close_time: '2026-06-01T10:00:00.000Z' }]

    const midweek = await runCron(AUTH_HEADERS)
    expect(midweek.body.emailsSent).toBe(0)

    vi.setSystemTime(new Date('2026-06-01T07:00:00.000Z')) // Monday
    state.sent = []
    state.trades = [{ pnl: 50, close_time: '2026-05-29T10:00:00.000Z' }]
    const monday = await runCron(AUTH_HEADERS)
    expect(monday.body.emailsSent).toBe(1)
    expect(state.sent[0].subject).toContain('Your weekly report')
  })

  it('drives the monthly email from its own preference', async () => {
    vi.setSystemTime(new Date('2026-06-01T07:00:00.000Z')) // 1st
    state.users = [user({ notifications_monthly_email: true })]
    state.trades = [{ pnl: 50, close_time: '2026-05-15T10:00:00.000Z' }]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(1)
    expect(state.sent[0].subject).toContain('Your monthly overview')
  })

  it('honors the user timezone when deciding the working day', async () => {
    // Saturday 02:00 UTC is still Friday 22:00 in New York.
    vi.setSystemTime(new Date('2026-06-06T02:00:00.000Z'))
    state.users = [user({ notifications_journal_reminders: true, timezone: 'America/New_York' })]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(1)
  })
})
