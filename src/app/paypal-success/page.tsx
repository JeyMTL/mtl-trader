'use client'

import { useEffect, useState } from 'react'
import { useSearchParams, useRouter } from 'next/navigation'
import { CheckCircle, Loader2, XCircle } from 'lucide-react'
import Link from 'next/link'

export default function PayPalSuccessPage() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const orderId = searchParams.get('token')
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>(
    orderId ? 'loading' : 'error'
  )

  useEffect(() => {
    if (!orderId) return

    let cancelled = false

    async function capture() {
      try {
        const res = await fetch('/api/paypal/capture', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ orderId }),
        })
        const data = await res.json()
        if (!cancelled) {
          setStatus(data.success ? 'success' : 'error')
        }
      } catch {
        if (!cancelled) {
          setStatus('error')
        }
      }
    }
    capture()
    return () => { cancelled = true }
  }, [orderId])

  useEffect(() => {
    if (status === 'success') {
      const timer = setTimeout(() => router.push('/dashboard'), 3000)
      return () => clearTimeout(timer)
    }
  }, [status, router])

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-4">
      <div className="text-center max-w-md">
        {status === 'loading' && (
          <>
            <Loader2 className="w-16 h-16 text-primary mx-auto mb-4 animate-spin" />
            <h1 className="text-2xl font-bold text-white mb-2">Processing Payment...</h1>
            <p className="text-gray-400">Please wait while we verify your payment.</p>
          </>
        )}
        {status === 'success' && (
          <>
            <CheckCircle className="w-16 h-16 text-success mx-auto mb-4" />
            <h1 className="text-2xl font-bold text-white mb-2">Payment Successful!</h1>
            <p className="text-gray-400 mb-6">Your account has been upgraded. Redirecting to dashboard...</p>
            <Link href="/dashboard" className="text-primary hover:text-primary-light transition-colors">
              Go to Dashboard →
            </Link>
          </>
        )}
        {status === 'error' && (
          <>
            <XCircle className="w-16 h-16 text-danger mx-auto mb-4" />
            <h1 className="text-2xl font-bold text-white mb-2">Payment Failed</h1>
            <p className="text-gray-400 mb-6">Something went wrong. Please try again or contact support.</p>
            <Link href="/dashboard/settings" className="text-primary hover:text-primary-light transition-colors">
              Back to Settings →
            </Link>
          </>
        )}
      </div>
    </div>
  )
}
