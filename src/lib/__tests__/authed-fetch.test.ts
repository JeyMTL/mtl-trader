import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const state = vi.hoisted(() => ({
  token: 'expired-token' as string | null,
  refreshed: 0,
  refreshFails: false,
  sent: [] as string[],
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: async () => ({
        data: { session: state.token ? { access_token: state.token } : null },
      }),
      refreshSession: async () => {
        state.refreshed += 1
        if (state.refreshFails) {
          return { data: { session: null }, error: new Error('refresh rejected') }
        }
        state.token = 'fresh-token'
        return { data: { session: { access_token: 'fresh-token' } }, error: null }
      },
    },
  },
}))

import { authedFetch } from '@/lib/api'

beforeEach(() => {
  state.token = 'expired-token'
  state.refreshed = 0
  state.refreshFails = false
  state.sent = []
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('authedFetch', () => {
  it('refreshes the session once and retries after a 401', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (_input: string, init: RequestInit) => {
        const header = new Headers(init.headers).get('Authorization') ?? ''
        state.sent.push(header)
        return new Response(null, { status: header.includes('fresh-token') ? 200 : 401 })
      }),
    )

    const response = await authedFetch('/api/broker/connection')

    expect(response.status).toBe(200)
    expect(state.refreshed).toBe(1)
    expect(state.sent).toEqual(['Bearer expired-token', 'Bearer fresh-token'])
  })

  it('leaves a 200 alone', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(null, { status: 200 })),
    )

    const response = await authedFetch('/api/sync?userId=u1')

    expect(response.status).toBe(200)
    expect(state.refreshed).toBe(0)
    expect(state.sent.length).toBe(0)
  })

  it('returns the 401 when the refresh fails', async () => {
    state.refreshFails = true
    const fetchMock = vi.fn(async () => new Response(null, { status: 401 }))
    vi.stubGlobal('fetch', fetchMock)

    const response = await authedFetch('/api/sync?userId=u1')

    expect(response.status).toBe(401)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(state.refreshed).toBe(1)
  })
})
