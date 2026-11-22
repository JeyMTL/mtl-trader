import type { SupabaseClient, User } from '@supabase/supabase-js'

/**
 * What the browser actually knows about the session, as one decision.
 *
 * The old check asked the network who the user was and treated "I could not
 * find out" as "nobody is signed in", which sent a trader with a perfectly good
 * cookie back to the login form every time Supabase hiccuped or the phone lost
 * signal for a second. A cached session is proof enough to render the app; only
 * a session that is genuinely absent is a signed-out visitor.
 */
export type SessionResolution =
  | {
      status: 'signed-in'
      user: User
      email: string | null
      /** True when the answer came from the cached session, not the server. */
      offline: boolean
    }
  | { status: 'unverified'; email: string | null }
  | { status: 'signed-out' }

/** A failed call that is about the network, not about the credentials. */
export function isTransientAuthError(error: unknown): boolean {
  if (!error) return false
  const name = (error as { name?: string }).name ?? ''
  if (name === 'AuthRetryableFetchError') return true
  const message = (error as { message?: string }).message ?? ''
  return /failed to fetch|network|timed? ?out|load failed|offline/i.test(message)
}

/**
 * Resolves the session without punishing a slow network.
 *
 * Order matters: the cached session is checked first, so a page load needs no
 * round trip to know whether to redirect. `getUser()` then confirms it, and its
 * failure is only fatal when there was no cached session to fall back on.
 */
export async function resolveSession(
  client: Pick<SupabaseClient, 'auth'>
): Promise<SessionResolution> {
  const {
    data: { session },
  } = await client.auth.getSession()

  if (!session?.user) {
    // No cached session: ask the server once, in case another tab signed in.
    const { data, error } = await client.auth.getUser()
    if (error || !data.user) return { status: 'signed-out' }
    if (!data.user.email_confirmed_at) {
      return { status: 'unverified', email: data.user.email ?? null }
    }
    return {
      status: 'signed-in',
      user: data.user,
      email: data.user.email ?? null,
      offline: false,
    }
  }

  const cached = session.user
  const { data, error } = await client.auth.getUser()

  if (error && isTransientAuthError(error)) {
    // The cookie is still there and only the network failed: keep the trader
    // where they are. A stale token will be refreshed on the next request.
    return {
      status: 'signed-in',
      user: cached,
      email: cached.email ?? null,
      offline: true,
    }
  }

  if (error || !data.user) {
    // The server rejected the token and it could not be refreshed: that is a
    // real sign-out, and the stored session is already gone.
    return { status: 'signed-out' }
  }

  if (!data.user.email_confirmed_at) {
    return { status: 'unverified', email: data.user.email ?? null }
  }

  return {
    status: 'signed-in',
    user: data.user,
    email: data.user.email ?? null,
    offline: false,
  }
}
