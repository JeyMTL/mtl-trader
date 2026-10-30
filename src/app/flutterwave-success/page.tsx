'use client'

import { Suspense, useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { CheckCircle, Loader2, XCircle } from 'lucide-react'
import { authedFetch } from '@/lib/api'

function FlutterwaveSuccessContent() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const transactionId = searchParams.get('transaction_id')
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>(
    transactionId ? 'loading' : 'error'
  )
  const [message, setMessage] = useState(
    'Something went wrong. Please try again or contact support.'
  )

  useEffect(() => {
    if (!transactionId) return

    let cancelled = false

    async function verify() {
      try {
        const res = await authedFetch('/api/flutterwave/verify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ transactionId }),
        })
        const data = await res.json()
        if (cancelled) return
        if (data.success) {
          setStatus('success')
        } else {
          setStatus('error')
          if (typeof data.error === 'string') setMessage(data.error)
        }
      } catch {
        if (!cancelled) setStatus('error')
      }
    }

    verify()
    return () => {
      cancelled = true
    }
  }, [transactionId])

  useEffect(() => {
    if (status !== 'success') return
    const timer = setTimeout(() => router.push('/dashboard/settings'), 3000)
    return () => clearTimeout(timer)
  }, [status, router])

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-4">
      <div className="text-center max-w-md">
        {status === 'loading' && (
          <>
            <Loader2 className="w-16 h-16 text-primary mx-auto mb-4 animate-spin" />
            <h1 className="text-2xl font-bold text-white mb-2">
              Confirming your subscription...
            </h1>
            <p className="text-gray-400">
              Please wait while we verify the payment with Flutterwave.
            </p>
          </>
        )}
        {status === 'success' && (
          <>
            <CheckCircle className="w-16 h-16 text-success mx-auto mb-4" />
            <h1 className="text-2xl font-bold text-white mb-2">
              Subscription active
            </h1>
            <p className="text-gray-400 mb-6">
              Your card is now subscribed and renews monthly. You can stop the
              renewal any time from Settings. Redirecting...
            </p>
            <Link
              href="/dashboard/settings"
              className="text-primary hover:text-primary-light transition-colors"
            >
              Go to Settings →
            </Link>
          </>
        )}
        {status === 'error' && (
          <>
            <XCircle className="w-16 h-16 text-danger mx-auto mb-4" />
            <h1 className="text-2xl font-bold text-white mb-2">
              Payment not confirmed
            </h1>
            <p className="text-gray-400 mb-6">{message}</p>
            <Link
              href="/pricing"
              className="text-primary hover:text-primary-light transition-colors"
            >
              Back to plans →
            </Link>
          </>
        )}
      </div>
    </div>
  )
}

export default function FlutterwaveSuccessPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen bg-background flex items-center justify-center px-4">
          <Loader2 className="w-16 h-16 text-primary animate-spin" />
        </div>
      }
    >
      <FlutterwaveSuccessContent />
    </Suspense>
  )
}
