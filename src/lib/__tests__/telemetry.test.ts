import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * The telemetry sink is the only place the app's crash and funnel events land,
 * so its refusals matter more than its success path: an event that is accepted
 * but malformed poisons every later query, and one that carries a journal note
 * would be a privacy incident rather than a bug.
 */

type Row = Record<string, unknown>

const state = vi.hoisted(() => ({
  user: null as { id: string } | null,
  insertError: null as { message: string } | null,
  inserted: [] as Row[],
  limited: false,
}))

vi.mock('@/lib/server-auth', () => ({
  getAuthUser: async () => state.user,
  getAdminClient: () => ({
    from: (table: string) => {
      if (table !== 'telemetry_events') throw new Error(`Unexpected table: ${table}`)
      return {
        insert: async (row: Row) => {
          state.inserted.push(row)
          return { error: state.insertError }
        },
      }
    },
  }),
}))

vi.mock('@/lib/rate-limit', () => ({
  clientKey: () => 'telemetry:test',
  rateLimit: async () => ({ ok: !state.limited, remaining: 10, retryAfterMs: 0 }),
}))

async function post(body: unknown) {
  const { POST } = await import('@/app/api/telemetry/route')
  const res = await POST(
    new Request('http://localhost/api/telemetry', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer t' },
      body: JSON.stringify(body),
    })
  )
  return res
}

const valid = {
  event: 'trade_saved',
  sessionId: 'abcdefghij0123456789',
  platform: 'android',
  appVersion: '1.0.0',
  properties: { mode: 'create' },
}

beforeEach(() => {
  state.user = null
  state.insertError = null
  state.inserted = []
  state.limited = false
})

describe('POST /api/telemetry', () => {
  it('stores an anonymous event, which is the only kind a launch produces', async () => {
    const res = await post({ ...valid, event: 'app_open' })
    expect(res.status).toBe(202)
    expect(state.inserted).toHaveLength(1)
    expect(state.inserted[0]).toMatchObject({
      user_id: null,
      event: 'app_open',
      platform: 'android',
      session_id: 'abcdefghij0123456789',
    })
  })

  it('attaches the signed-in user when a token resolves', async () => {
    state.user = { id: 'u1' }
    await post(valid)
    expect(state.inserted[0].user_id).toBe('u1')
  })

  it('refuses an event name that is not a slug', async () => {
    for (const event of ['Trade Saved', 'x', '../etc/passwd', 'a'.repeat(80)]) {
      const res = await post({ ...valid, event })
      expect(res.status, event).toBe(400)
    }
    expect(state.inserted).toHaveLength(0)
  })

  it('refuses a session id or platform that could not have come from the app', async () => {
    expect((await post({ ...valid, sessionId: 'short' })).status).toBe(400)
    expect((await post({ ...valid, platform: 'Android 15 (Pixel)' })).status).toBe(400)
    expect(state.inserted).toHaveLength(0)
  })

  it('drops a payload that is large enough to hide journal text', async () => {
    const res = await post({ ...valid, properties: { note: 'x'.repeat(4096) } })
    expect(res.status).toBe(413)
    expect(state.inserted).toHaveLength(0)
  })

  it('ignores an array masquerading as properties', async () => {
    await post({ ...valid, properties: ['a', 'b'] })
    expect(state.inserted[0].properties).toEqual({})
  })

  it('acknowledges a storage failure so the app never retries or shows an error', async () => {
    state.insertError = { message: 'boom' }
    const res = await post(valid)
    expect(res.status).toBe(202)
  })

  it('stays quiet when the rate limit is hit', async () => {
    state.limited = true
    const res = await post(valid)
    expect(res.status).toBe(429)
    expect(state.inserted).toHaveLength(0)
  })
})
