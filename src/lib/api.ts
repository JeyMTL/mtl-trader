import { supabase } from '@/lib/supabase'

/**
 * A call to our own API with the signed-in session's bearer token.
 *
 * A token that expired while the tab was asleep comes back as a 401 even though
 * the refresh token is still good, so a 401 gets one session refresh and one
 * retry before the caller is told the session is gone. Anything else is
 * returned as it came.
 */
export async function authedFetch(input: string, init: RequestInit = {}) {
  async function send() {
    const { data: { session } } = await supabase.auth.getSession()
    const headers = new Headers(init.headers)
    if (session?.access_token) {
      headers.set('Authorization', `Bearer ${session.access_token}`)
    }
    return fetch(input, { ...init, headers })
  }

  const response = await send()
  if (response.status !== 401) return response

  const { data, error } = await supabase.auth.refreshSession()
  if (error || !data.session) return response
  return send()
}
