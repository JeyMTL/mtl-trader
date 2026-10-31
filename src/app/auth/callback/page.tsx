'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { Logo } from '@/components/logo'

/**
 * Landing page for the Google OAuth redirect.
 *
 * Supabase sends the browser back here with `?code=`. The code is exchanged for
 * a cookie session, the profile row is created (idempotently) through the same
 * route email signups use, and only then does the user reach the dashboard.
 * Without this step a Google user would arrive authenticated but profileless.
 */
export default function AuthCallbackPage() {
  const router = useRouter()
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false

    const finish = async () => {
      const code = new URLSearchParams(window.location.search).get('code')
      if (code) {
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)
        if (exchangeError) {
          if (!cancelled) setError(exchangeError.message)
          return
        }
      }

      const { data, error: sessionError } = await supabase.auth.getSession()
      if (cancelled) return
      if (sessionError || !data.session) {
        setError('We could not finish the sign-in. Please try again.')
        return
      }

      const user = data.session.user
      // The profile row is what the dashboard's plan check reads. If this write
      // fails the user is authenticated but profileless, and that account is
      // unusable: report it here instead of routing them into it silently.
      let profileError = ''
      try {
        const profileResponse = await fetch('/api/auth/signup', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            userId: user.id,
            email: user.email,
            fullName: user.user_metadata?.full_name ?? '',
          }),
        })
        if (!profileResponse.ok) {
          const body = await profileResponse.json().catch(() => null)
          profileError =
            body?.error || `Profile setup failed (HTTP ${profileResponse.status}).`
        }
      } catch {
        profileError =
          'Could not reach the server to finish setting up your profile.'
      }

      if (cancelled) return
      if (profileError) {
        setError(profileError)
        return
      }

      // Only a same-origin absolute path is honoured, so `?next=` cannot be an
      // open redirect.
      const requested = new URLSearchParams(window.location.search).get('next')
      const target =
        requested && requested.startsWith('/') && !requested.startsWith('//')
          ? requested
          : '/dashboard'
      router.replace(target)
    }

    finish()
    return () => {
      cancelled = true
    }
  }, [router])

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-4">
      <div className="w-full max-w-md text-center">
        <Link href="/" className="inline-flex items-center gap-2 mb-6">
          <Logo size="md" />
        </Link>
        {error ? (
          <>
            <h1 className="text-xl font-bold text-white">Sign-in did not finish</h1>
            <p className="text-gray-400 mt-2 text-sm">{error}</p>
            <p className="text-gray-500 mt-2 text-xs">
              Your Google account is linked. Fixing the server and retrying is
              safe — the profile write is idempotent.
            </p>
            <div className="mt-6 flex flex-col gap-3">
              <button
                type="button"
                onClick={() => window.location.reload()}
                className="btn-gradient text-white px-6 py-3 rounded-xl font-semibold"
              >
                Try again
              </button>
              <Link
                href="/auth/login"
                className="text-sm text-gray-400 transition-colors hover:text-white"
              >
                Back to login
              </Link>
            </div>
          </>
        ) : (
          <>
            <h1 className="text-xl font-bold text-white">Finishing sign-in…</h1>
            <p className="text-gray-400 mt-2 text-sm">
              Verifying your Google account and opening your journal.
            </p>
            <div className="mt-6 h-1 w-40 mx-auto rounded-full bg-border overflow-hidden">
              <div className="h-full w-1/2 bg-primary animate-pulse" />
            </div>
          </>
        )}
      </div>
    </div>
  )
}
