import { describe, it, expect, beforeEach, vi } from 'vitest'

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  /** Rows already claimed in `push_events`, as `${user}:${kind}:${key}`. */
  claimed: new Set<string>(),
  tableMissing: false,
  propStatus: null as Row | null,
  propError: null as { message: string } | null,
  trialUsers: [] as Row[],
  propRuleUsers: [] as Row[],
  playbookRows: [] as Row[],
  userZones: [] as Row[],
  /** Every window the users query asked for, so the trial cut-off is testable. */
  windows: [] as { gt?: string; lte?: string }[],
  sends: [] as { userId: string; title: string; body: string }[],
  sendResult: { sent: 1, failed: 0, skipped: false },
  deleted: [] as Row[],
}))

/** Just enough query builder for the three tables this module touches. */
function chain(table: string) {
  const filters: Record<string, unknown> = {}
  const build: Record<string, unknown> = {
    select: () => build,
    in: () => ({
      then: (resolve: (value: unknown) => unknown) =>
        Promise.resolve({ data: state.userZones, error: null }).then(resolve),
    }),
    limit: async () => {
      if (table === 'prop_rules') return { data: state.propRuleUsers, error: null }
      if (table === 'playbooks') return { data: state.playbookRows, error: null }
      return { data: state.trialUsers, error: null }
    },
    eq: (column: string, value: unknown) => {
      filters[column] = value
      return build
    },
    gt: (column: string, value: unknown) => {
      filters[`gt:${column}`] = value
      return build
    },
    lte: (column: string, value: unknown) => {
      filters[`lte:${column}`] = value
      state.windows.push({ gt: filters['gt:trial_ends_at'] as string, lte: value as string })
      return build
    },
    insert: async (row: Row) => {
      if (state.tableMissing) return { error: { code: '42P01', message: 'missing table' } }
      const key = `${row.user_id}:${row.kind}:${row.event_key}`
      if (state.claimed.has(key)) {
        return { error: { code: '23505', message: 'duplicate key value' } }
      }
      state.claimed.add(key)
      return { error: null }
    },
    delete: () => {
      const pending: Row = {}
      const builder: Record<string, unknown> = {
        eq: (column: string, value: unknown) => {
          pending[column as string] = value
          return builder
        },
        then: (resolve: (value: unknown) => unknown) => {
          const key = `${pending.user_id}:${pending.kind}:${pending.event_key}`
          state.claimed.delete(key)
          state.deleted.push(pending)
          return Promise.resolve({ error: null }).then(resolve)
        },
      }
      return builder
    },
  }
  return build
}

vi.mock('@/lib/server-auth', () => ({
  getAdminClient: () => ({
    from: (table: string) => chain(table),
    rpc: async () => ({ data: state.propStatus, error: state.propError }),
  }),
}))

vi.mock('@/lib/push', () => ({
  sendPushToUser: async (
    userId: string,
    notification: { title: string; body: string }
  ) => {
    state.sends.push({ userId, ...notification })
    return state.sendResult
  },
}))

vi.mock('@/lib/log', () => ({ logEvent: () => {} }))

import {
  notifyPropBreach,
  notifySessionStarting,
  notifyTrialEnding,
  sweepPropBreaches,
} from '@/lib/push-events'

function breachStatus(over: Row = {}): Row {
  return {
    configured: true,
    status: 'breach_daily',
    daily_pnl: -520.4,
    daily_loss_limit: 500,
    drawdown: 0,
    drawdown_limit: 1000,
    consistency: 0,
    consistency_pct: 30,
    ...over,
  }
}

beforeEach(() => {
  state.claimed.clear()
  state.tableMissing = false
  state.propStatus = null
  state.propError = null
  state.trialUsers = []
  state.propRuleUsers = []
  state.playbookRows = []
  state.userZones = []
  state.windows = []
  state.sends = []
  state.sendResult = { sent: 1, failed: 0, skipped: false }
  state.deleted = []
})

describe('prop breach notifications', () => {
  it('wakes the trader once with the numbers that broke', async () => {
    state.propStatus = breachStatus()

    expect(await notifyPropBreach('u1', new Date('2026-11-24T10:00:00Z'))).toBe(true)

    expect(state.sends).toHaveLength(1)
    expect(state.sends[0].title).toBe('Daily loss limit breached')
    expect(state.sends[0].body).toContain('-520.40')
    expect(state.sends[0].body).toContain('500.00')
  })

  it('says nothing while the account is merely close to a limit', async () => {
    state.propStatus = breachStatus({ status: 'warn_daily' })
    expect(await notifyPropBreach('u1')).toBe(false)
    expect(state.sends).toEqual([])
  })

  it('says nothing for an account that keeps no prop rules', async () => {
    state.propStatus = { configured: false }
    expect(await notifyPropBreach('u1')).toBe(false)
    expect(state.sends).toEqual([])
  })

  it('does not repeat itself while the breach lasts, but does speak on a new day', async () => {
    state.propStatus = breachStatus()
    const monday = new Date('2026-11-24T10:00:00Z')
    const tuesday = new Date('2026-11-25T10:00:00Z')

    await notifyPropBreach('u1', monday)
    await notifyPropBreach('u1', monday)
    expect(state.sends).toHaveLength(1)

    await notifyPropBreach('u1', tuesday)
    expect(state.sends).toHaveLength(2)
  })

  it('uses the drawdown wording when drawdown is the rule that broke', async () => {
    state.propStatus = breachStatus({ status: 'breach_drawdown', drawdown: 1040, drawdown_limit: 1000 })
    await notifyPropBreach('u1')
    expect(state.sends[0].title).toBe('Drawdown limit breached')
    expect(state.sends[0].body).toContain('1,040.00')
  })

  it('gives the claim back when nothing was actually delivered', async () => {
    state.propStatus = breachStatus()
    state.sendResult = { sent: 0, failed: 0, skipped: true }

    expect(await notifyPropBreach('u1')).toBe(false)
    expect(state.deleted).toHaveLength(1)

    // The retry has to be able to deliver, which it could not if the claim had
    // survived the failed send.
    state.sendResult = { sent: 1, failed: 0, skipped: false }
    expect(await notifyPropBreach('u1')).toBe(true)
    expect(state.sends).toHaveLength(2)
  })

  it('stays quiet rather than spamming when the dedupe table is missing', async () => {
    state.propStatus = breachStatus()
    state.tableMissing = true

    expect(await notifyPropBreach('u1')).toBe(false)
    expect(state.sends).toEqual([])
  })

  it('sweeps every account with rules saved', async () => {
    state.propRuleUsers = [{ user_id: 'u1' }, { user_id: 'u2' }]
    state.propStatus = breachStatus()

    expect(await sweepPropBreaches()).toBe(2)
    expect(state.sends).toHaveLength(2)
  })
})

describe('session reminders', () => {
  const playbook = {
    user_id: 'u1',
    rules: ['No trades before the London open.'],
    days: [1, 2, 3, 4, 5],
    sessions: [{ id: 's1', label: 'London', start: '13:09', end: '15:00' }],
    reminder_minutes: 60,
    reminders_enabled: true,
  }

  beforeEach(() => {
    state.playbookRows = [playbook]
    state.userZones = [{ id: 'u1', timezone: 'UTC' }]
  })

  it('pushes when the session is inside the lead window, with the countdown', async () => {
    expect(await notifySessionStarting(new Date('2026-11-24T12:30:00Z'))).toBe(1)
    expect(state.sends).toHaveLength(1)
    expect(state.sends[0].title).toBe('London starts in 39 min')
  })

  it('says nothing an hour earlier', async () => {
    expect(await notifySessionStarting(new Date('2026-11-24T10:00:00Z'))).toBe(0)
    expect(state.sends).toEqual([])
  })

  it('does not start over while the window is open', async () => {
    const at = new Date('2026-11-24T12:30:00Z')
    await notifySessionStarting(at)
    await notifySessionStarting(new Date('2026-11-24T12:35:00Z'))
    expect(state.sends).toHaveLength(1)
  })

  it('says nothing to a trader with no rules to review', async () => {
    state.playbookRows = [{ ...playbook, rules: [] }]
    expect(await notifySessionStarting(new Date('2026-11-24T12:30:00Z'))).toBe(0)
    expect(state.sends).toEqual([])
  })
})

describe('trial ending notifications', () => {
  it('asks only for trials ending inside the next day', async () => {
    const now = new Date('2026-11-24T10:00:00Z')
    state.trialUsers = [{ id: 'u1', trial_ends_at: '2026-11-25T06:00:00Z' }]

    expect(await notifyTrialEnding(now)).toBe(1)

    expect(state.windows).toHaveLength(1)
    expect(state.windows[0].gt).toBe(now.toISOString())
    expect(state.windows[0].lte).toBe(new Date('2026-11-25T10:00:00Z').toISOString())
    expect(state.sends[0].title).toContain('trial')
  })

  it('sends once per trial, not once per sweep', async () => {
    state.trialUsers = [{ id: 'u1', trial_ends_at: '2026-11-25T06:00:00Z' }]

    await notifyTrialEnding()
    await notifyTrialEnding()

    expect(state.sends).toHaveLength(1)
  })
})
