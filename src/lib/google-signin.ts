import { supabase } from '@/lib/supabase'

/**
 * Google sign-in without the Supabase-hosted OAuth redirect.
 *
 * `signInWithOAuth` bounces the browser through
 * `<project-ref>.supabase.co/auth/v1/callback`, and Google names that host on
 * its account chooser ("continue to oknrivipgpptsebeyvsq.supabase.co"). Google
 * Identity Services instead hands the page an ID token while the browser stays
 * on our own origin, so the chooser reads "continue to mtlledger.com".
 * Supabase still mints the session, it just receives the token directly.
 */

export type GoogleSignInOutcome = { ok: true } | { ok: false; error: string }

/** Only a same-origin absolute path is honoured, so `?next=` cannot be an open redirect. */
function nextPath(): string {
  const requested = new URLSearchParams(window.location.search).get('next')
  return requested && requested.startsWith('/') && !requested.startsWith('//')
    ? requested
    : '/dashboard'
}

export async function completeGoogleSignIn(idToken: string): Promise<GoogleSignInOutcome> {
  const { data, error } = await supabase.auth.signInWithIdToken({
    provider: 'google',
    token: idToken,
  })

  if (error) return { ok: false, error: error.message }

  const user = data.user
  if (!user) return { ok: false, error: 'Google sign-in returned no user. Please try again.' }

  // The profile row is what the dashboard's plan check reads, so a Google user
  // without one would be authenticated and unusable. The route is idempotent —
  // the same write the OAuth callback performs.
  try {
    const profileResponse = await fetch('/api/auth/signup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userId: user.id,
        email: user.email,
        fullName:
          user.user_metadata?.full_name ?? user.user_metadata?.name ?? '',
      }),
    })
    if (!profileResponse.ok) {
      const body = await profileResponse.json().catch(() => null)
      return {
        ok: false,
        error: body?.error || `Profile setup failed (HTTP ${profileResponse.status}).`,
      }
    }
  } catch {
    return { ok: false, error: 'Could not reach the server to finish setting up your profile.' }
  }

  // A full navigation rather than router.push so middleware and server
  // components read the freshly written session cookies.
  window.location.assign(nextPath())
  return { ok: true }
}
