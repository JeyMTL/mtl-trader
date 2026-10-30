'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, CheckCircle2, KeyRound, Lock } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Logo } from '@/components/logo'

type Phase = 'checking' | 'ready' | 'invalid' | 'done'

export default function ResetPasswordPage() {
  const [phase, setPhase] = useState<Phase>('checking')
  const [error, setError] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false

    async function establishSession() {
      const url = new URL(window.location.href)
      const hash = new URLSearchParams(url.hash.replace(/^#/, ''))
      const describe =
        url.searchParams.get('error_description') ||
        hash.get('error_description')

      if (describe) {
        if (!cancelled) {
          setError(describe)
          setPhase('invalid')
        }
        return
      }

      // A refresh after the link was already consumed keeps the session.
      const { data: { session } } = await supabase.auth.getSession()
      if (session) {
        if (!cancelled) setPhase('ready')
        return
      }

      const code = url.searchParams.get('code')
      const tokenHash = url.searchParams.get('token_hash') || hash.get('token_hash')
      const accessToken = hash.get('access_token')
      const refreshToken = hash.get('refresh_token')

      let failure = ''

      if (code) {
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)
        if (exchangeError) failure = exchangeError.message
      } else if (tokenHash) {
        const { error: otpError } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: 'recovery' })
        if (otpError) failure = otpError.message
      } else if (accessToken && refreshToken) {
        const { error: sessionError } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        })
        if (sessionError) failure = sessionError.message
      } else {
        failure = 'This page needs a recovery link. Request a new one and open it from the same browser.'
      }

      if (cancelled) return

      // Strip the one-time credentials from the address bar and history.
      window.history.replaceState({}, '', '/auth/reset')

      if (failure) {
        setError(failure)
        setPhase('invalid')
      } else {
        setPhase('ready')
      }
    }

    establishSession()
    return () => {
      cancelled = true
    }
  }, [])

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault()
    setError('')

    if (password.length < 8) {
      setError('Use at least 8 characters.')
      return
    }
    if (password !== confirm) {
      setError('The two passwords do not match.')
      return
    }

    setSaving(true)
    const { error: updateError } = await supabase.auth.updateUser({ password })
    setSaving(false)

    if (updateError) {
      setError(updateError.message)
      return
    }

    setPassword('')
    setConfirm('')
    setPhase('done')
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <Link href="/" className="mb-6 inline-flex items-center gap-2">
            <Logo size="md" />
          </Link>
          <p className="eyebrow">Account recovery</p>
          <h1 className="mt-1.5 text-2xl font-semibold tracking-tight text-white">
            {phase === 'done' ? 'Password updated' : 'Choose a new password'}
          </h1>
        </div>

        <div className="panel p-6 sm:p-8">
          {phase === 'checking' && (
            <div className="space-y-3" aria-live="polite">
              <div className="skeleton h-4 w-3/4" />
              <div className="skeleton h-10 w-full" />
              <div className="skeleton h-10 w-full" />
              <p className="pt-1 text-xs text-gray-500">Verifying your recovery link…</p>
            </div>
          )}

          {phase === 'invalid' && (
            <div className="space-y-4">
              <div className="flex items-start gap-3 rounded-xl border border-danger/40 bg-danger/10 px-4 py-3 text-sm text-danger">
                <KeyRound className="mt-0.5 h-4 w-4 shrink-0" />
                <p>{error || 'This recovery link is no longer valid.'}</p>
              </div>
              <p className="text-xs leading-relaxed text-gray-500">
                Recovery links expire after one hour and only work once. Request a fresh link and open it in this
                browser.
              </p>
              <Link href="/auth/forgot" className="btn btn-primary w-full">
                Request a new link
                <ArrowRight className="h-4 w-4" />
              </Link>
            </div>
          )}

          {phase === 'ready' && (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label htmlFor="password" className="field-label">New password</label>
                <div className="relative">
                  <Lock className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-500" />
                  <input
                    id="password"
                    type="password"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    className="input pl-9"
                    placeholder="At least 8 characters"
                    autoComplete="new-password"
                    minLength={8}
                    required
                  />
                </div>
              </div>

              <div>
                <label htmlFor="confirm" className="field-label">Confirm password</label>
                <div className="relative">
                  <Lock className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-500" />
                  <input
                    id="confirm"
                    type="password"
                    value={confirm}
                    onChange={(event) => setConfirm(event.target.value)}
                    className="input pl-9"
                    placeholder="Repeat it"
                    autoComplete="new-password"
                    minLength={8}
                    required
                  />
                </div>
              </div>

              {error && (
                <div className="rounded-lg border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger" role="alert">
                  {error}
                </div>
              )}

              <button type="submit" disabled={saving} className="btn btn-primary w-full">
                {saving ? 'Saving…' : 'Set new password'}
              </button>

              <p className="text-xs leading-relaxed text-gray-500">
                Setting a new password signs out every other device on this account.
              </p>
            </form>
          )}

          {phase === 'done' && (
            <div className="space-y-4 text-center">
              <CheckCircle2 className="mx-auto h-8 w-8 text-success" />
              <div>
                <p className="text-sm font-medium text-white">You&apos;re signed in with the new password.</p>
                <p className="mt-1 text-xs text-gray-500">Other sessions have been signed out.</p>
              </div>
              <Link href="/dashboard" className="btn btn-primary w-full">
                Open the journal
                <ArrowRight className="h-4 w-4" />
              </Link>
            </div>
          )}
        </div>

        {phase !== 'done' && (
          <Link
            href="/auth/login"
            className="mt-5 flex items-center justify-center gap-1.5 text-xs font-medium text-gray-500 hover:text-white"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            Back to login
          </Link>
        )}
      </div>
    </div>
  )
}
