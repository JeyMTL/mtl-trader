import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

type Row = Record<string, unknown>

// Shared, mutable fixtures the hoisted mocks read from.
const state = vi.hoisted(() => ({
  users: [] as Row[],
  trades: [] as Row[],
  sends: new Set<string>(),
  emailConfigured: true,
  sent: [] as Array<{ to: string; subject: string; html: string }>,
}))

function makeClient() {
  return {
    from(table: string) {
      if (table === 'users') {
        const builder = {
          select: () => builder,
          eq: () => builder,
          order: () => builder,
          range: (from: number, to: number) =>
            Promise.resolve({ data: state.users.slice(from, to + 1), error: null }),
          then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) =>
            Promise.resolve({ data: state.users, error: null }).then(resolve, reject),
        }
        return builder
      }

      if (table === 'notification_sends') {
        const claim = (row: Row) => {
          const id = `${row.user_id}:${row.kind}:${row.window_key}`
          if (state.sends.has(id)) {
            return Promise.resolve({ data: null, error: { code: '23505', message: 'duplicate key' } })
          }
          state.sends.add(id)
          return Promise.resolve({ data: row, error: null })
        }

        const remove = () => {
          const filters: Record<string, unknown> = {}
          const builder = {
            eq(column: string, value: unknown) {
              filters[column] = value
              return builder
            },
            then(resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) {
              state.sends.delete(`${filters.user_id}:${filters.kind}:${filters.window_key}`)
              return Promise.resolve({ data: null, error: null }).then(resolve, reject)
            },
          }
          return builder
        }

        return {
          insert: (row: Row) => claim(row),
          delete: () => remove(),
        }
      }

      throw new Error(`Unexpected table: ${table}`)
    },
    rpc(name: string, args: Row) {
      if (name !== 'notification_trades') throw new Error(`Unexpected rpc: ${name}`)
      if (args?.p_user_id === 'bad-user') {
        return Promise.resolve({ data: null, error: { message: 'boom' } })
      }
      return Promise.resolve({ data: state.trades, error: null })
    },
  }
}

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => makeClient(),
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
    notifications_email: true,
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
  state.sends.clear()
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

  it('never sends the same email twice when the cron is re-run', async () => {
    state.users = [user({ notifications_journal_reminders: true })]

    const first = await runCron(AUTH_HEADERS)
    const second = await runCron(AUTH_HEADERS)

    expect(first.body.emailsSent).toBe(1)
    expect(second.body.emailsSent).toBe(0)
    expect(state.sent).toHaveLength(1)
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

  it('emails a trial that is within three days of ending, even with digests off', async () => {
    state.users = [
      user({
        notifications_email: false,
        subscription_status: 'trial',
        subscription_tier: 'free',
        trial_ends_at: '2026-06-04T07:00:00.000Z',
      }),
    ]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(1)
    expect(state.sent[0].subject).toContain('trial ends in 2 days')
  })

  it('keeps the trial notice out of accounts that have already paid', async () => {
    state.users = [
      user({
        subscription_status: 'active',
        subscription_tier: 'pro',
        trial_ends_at: '2026-06-04T07:00:00.000Z',
      }),
    ]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(0)
  })

  it('still requires the digest opt-in for summaries', async () => {
    state.users = [
      user({ notifications_email: false, notifications_daily: true, subscription_status: 'active' }),
    ]
    state.trades = [{ pnl: 100, close_time: '2026-06-01T10:00:00.000Z' }]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(0)
    expect(state.sent).toHaveLength(0)
  })

  it('isolates a failing user from the rest of the run', async () => {
    state.users = [
      user({ id: 'bad-user', email: 'bad@example.com', notifications_journal_reminders: true }),
      user({ id: 'good-user', email: 'good@example.com', notifications_journal_reminders: true }),
    ]

    const { body } = await runCron(AUTH_HEADERS)
    expect(body.emailsSent).toBe(1)
    expect(body.failed).toBe(1)
    expect(state.sent).toHaveLength(1)
    expect(state.sent[0].to).toBe('good@example.com')
  })
})
