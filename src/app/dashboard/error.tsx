'use client'

import { useEffect } from 'react'
import Link from 'next/link'
import { AlertTriangle, RefreshCw } from 'lucide-react'

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    // Surfaces in the browser console and any attached error monitor.
    console.error('Dashboard render failed', error)
  }, [error])

  return (
    <div className="mx-auto max-w-md panel p-6 text-center">
      <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full border border-danger/40 bg-danger/10">
        <AlertTriangle className="h-5 w-5 text-danger" />
      </div>
      <h1 className="mt-4 text-lg font-semibold text-white">This screen didn&apos;t load</h1>
      <p className="mt-1 text-sm text-gray-400">
        Your data is safe — the page failed to render. Retrying usually fixes a dropped connection.
      </p>
      {error.digest && <p className="num mt-3 text-[11px] text-gray-600">reference {error.digest}</p>}

      <div className="mt-5 flex flex-col gap-2 sm:flex-row">
        <button onClick={reset} className="btn btn-primary flex-1">
          <RefreshCw className="h-4 w-4" />
          Try again
        </button>
        <Link href="/dashboard" className="btn btn-secondary flex-1">
          Back to dashboard
        </Link>
      </div>
    </div>
  )
}
