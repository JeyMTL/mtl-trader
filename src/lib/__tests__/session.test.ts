import { describe, expect, it, vi } from 'vitest'
import type { User } from '@supabase/supabase-js'

import { isTransientAuthError, resolveSession } from '@/lib/session'

const user = {
  id: 'user-1',
  email: 'jey@example.com',
  email_confirmed_at: '2026-11-01T00:00:00Z',
} as unknown as User

const unverified = {
  id: 'user-2',
  email: 'new@example.com',
  email_confirmed_at: null,
} as unknown as User

function client({
  session,
  user: live,
  error,
}: {
  session?: User | null
  user?: User | null
  error?: { name?: string; message?: string } | null
}) {
  return {
    auth: {
      getSession: vi.fn(async () => ({
        data: { session: session ? { user: session } : null },
        error: null,
      })),
      getUser: vi.fn(async () => ({
        data: { user: live ?? null },
        error: error ?? null,
      })),
    },
  } as never
}

describe('resolveSession', () => {
  it('keeps a signed-in trader signed in when the server answers', async () => {
    const outcome = await resolveSession(client({ session: user, user }))
    expect(outcome).toMatchObject({ status: 'signed-in', offline: false })
  })

  it('does not sign anyone out because the network failed', async () => {
    const outcome = await resolveSession(
      client({
        session: user,
        error: { name: 'AuthRetryableFetchError', message: 'Failed to fetch' },
      })
    )
    expect(outcome).toMatchObject({
      status: 'signed-in',
      offline: true,
      email: 'jey@example.com',
    })
  })

  it('treats a rejected token as a real sign-out', async () => {
    const outcome = await resolveSession(
      client({
        session: user,
        error: { name: 'AuthApiError', message: 'Invalid Refresh Token' },
      })
    )
    expect(outcome.status).toBe('signed-out')
  })

  it('sends a visitor with no session at all to the login form', async () => {
    const outcome = await resolveSession(client({ session: null }))
    expect(outcome.status).toBe('signed-out')
  })

  it('names an unconfirmed account instead of pretending it is signed out', async () => {
    const outcome = await resolveSession(
      client({ session: null, user: unverified })
    )
    expect(outcome).toEqual({ status: 'unverified', email: 'new@example.com' })
  })

  it('picks a server-side session up in a tab that has no cache yet', async () => {
    const outcome = await resolveSession(client({ session: null, user }))
    expect(outcome).toMatchObject({ status: 'signed-in', offline: false })
  })
})

describe('isTransientAuthError', () => {
  it('recognises the shapes a dropped connection takes', () => {
    expect(isTransientAuthError({ name: 'AuthRetryableFetchError' })).toBe(true)
    expect(isTransientAuthError({ message: 'TypeError: Failed to fetch' })).toBe(true)
    expect(isTransientAuthError({ message: 'request timed out' })).toBe(true)
    expect(isTransientAuthError({ message: 'Invalid login credentials' })).toBe(false)
    expect(isTransientAuthError(null)).toBe(false)
  })
})
