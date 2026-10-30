'use client'

import Link from 'next/link'
import { useState } from 'react'
import { ArrowLeft, Mail, Send } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Logo } from '@/components/logo'
import { useToast } from '@/components/toast'

export default function ForgotPasswordPage() {
  const { toast } = useToast()
  const [email, setEmail] = useState('')
  const [loading, setLoading] = useState(false)
  const [sent, setSent] = useState(false)

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault()
    if (loading) return
    setLoading(true)

    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/auth/reset`,
    })

    setLoading(false)

    if (error) {
      toast(error.message, { tone: 'error' })
      return
    }

    // Deliberately identical for known and unknown addresses: no account
    // enumeration from this form.
    setSent(true)
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <Link href="/" className="mb-6 inline-flex items-center gap-2">
            <Logo size="md" />
          </Link>
          <p className="eyebrow">Account recovery</p>
          <h1 className="mt-1.5 text-2xl font-semibold tracking-tight text-white">Reset your password</h1>
          <p className="mt-2 text-sm text-gray-400">
            Enter the email on your account and we&apos;ll send a recovery link.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="panel space-y-5 p-6 sm:p-8">
          {sent ? (
            <div className="space-y-4">
              <div className="flex items-start gap-3 rounded-xl border border-success/40 bg-success/10 px-4 py-3 text-sm text-success">
                <Mail className="mt-0.5 h-4 w-4 shrink-0" />
                <p>
                  If an account exists for <strong className="font-semibold">{email.trim()}</strong>, a recovery
                  link is on its way. The link expires in one hour.
                </p>
              </div>
              <p className="text-xs leading-relaxed text-gray-500">
                Nothing arrived? Check spam, then try again in a minute. Repeated requests are rate limited.
              </p>
              <button
                type="button"
                onClick={() => setSent(false)}
                className="btn btn-secondary w-full"
              >
                Use a different email
              </button>
            </div>
          ) : (
            <>
              <div>
                <label htmlFor="email" className="field-label">Email</label>
                <div className="relative">
                  <Mail className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-500" />
                  <input
                    id="email"
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    className="input pl-9"
                    placeholder="you@example.com"
                    autoComplete="email"
                    required
                  />
                </div>
              </div>

              <button type="submit" disabled={loading} className="btn btn-primary w-full">
                {loading ? 'Sending…' : 'Send recovery link'}
                <Send className="h-4 w-4" />
              </button>
            </>
          )}

          <Link
            href="/auth/login"
            className="flex items-center justify-center gap-1.5 text-xs font-medium text-gray-500 hover:text-white"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            Back to login
          </Link>
        </form>
      </div>
    </div>
  )
}
