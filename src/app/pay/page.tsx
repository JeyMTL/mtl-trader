'use client'

import { useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { AlertCircle, Loader2 } from 'lucide-react'
import { Logo } from '@/components/logo'

/**
 * Where Paddle's checkout link lands.
 *
 * `POST /api/checkout/card` and `/api/paddle/checkout` return Paddle's
 * `checkout.url`, which is *not* a hosted Paddle page: it is this deployment's
 * default payment link with `?_ptxn=<transaction id>` appended. Opening it
 * renders whatever lives at that link, and Paddle expects that page to run
 * Paddle.js and open the transaction named in `_ptxn`. Set the default payment
 * link in the Paddle dashboard to `/pay`, or the customer is redirected to a
 * page that quietly shows nothing.
 *
 * The token is the client-side token (sandbox tokens start with `test_`), not
 * the API key — it can only open checkouts, which is what makes it safe to
 * publish. It is fetched from `/api/paddle/client-token` at runtime rather than
 * inlined as `NEXT_PUBLIC_*`, so a token saved with the wrong scope shows up as
 * a 503 on that route instead of a page that quietly says "not configured".
 */

const PADDLE_SCRIPT = 'https://cdn.paddle.com/paddle/v2/paddle.js'

interface PaddleCheckout {
  open: (options: { transactionId: string }) => void
}

interface PaddleGlobal {
  Environment?: { set: (environment: 'sandbox' | 'production') => void }
  Initialize: (options: { token: string }) => void
  Checkout: PaddleCheckout
}

declare global {
  interface Window {
    Paddle?: PaddleGlobal
  }
}

type Problem = 'missing' | 'unconfigured' | 'failed'

/** Distinguishes "nothing to pay" from "Paddle refused" without a second state. */
class CheckoutProblem extends Error {
  readonly problem: Problem

  constructor(problem: Problem, message: string) {
    super(message)
    this.name = 'CheckoutProblem'
    this.problem = problem
  }
}

/** Loads Paddle.js once; a second mount reuses the global it left behind. */
function loadPaddle(): Promise<PaddleGlobal> {
  const loaded = window.Paddle
  if (loaded) return Promise.resolve(loaded)

  return new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = PADDLE_SCRIPT
    script.async = true
    script.onload = () => {
      if (window.Paddle) resolve(window.Paddle)
      else reject(new CheckoutProblem('failed', 'Paddle.js loaded but did not register itself.'))
    }
    script.onerror = () =>
      reject(new CheckoutProblem('failed', 'Could not load Paddle.js. Check your connection.'))
    document.head.appendChild(script)
  })
}

/**
 * The client-side token, read from the server so rotating it needs no rebuild.
 * A missing token and an unreachable route are the same problem to a customer:
 * card payments are not wired up yet.
 */
async function fetchClientToken(): Promise<string> {
  try {
    const response = await fetch('/api/paddle/client-token', { cache: 'no-store' })
    const body = (await response.json()) as { token?: string | null }
    const token = (body.token || '').trim()
    if (token) return token
  } catch {
    // Fall through: an unreachable route means the same thing as no token.
  }
  throw new CheckoutProblem(
    'unconfigured',
    'Card payments are not configured for this deployment yet.'
  )
}

/**
 * Opens the transaction Paddle named in the URL.
 *
 * Everything that can fail throws rather than setting state, so the effect only
 * talks to React from a promise callback — state set synchronously inside an
 * effect would render twice before anything has happened.
 */
async function openCheckout(): Promise<void> {
  const transactionId = new URLSearchParams(window.location.search).get('_ptxn') || ''
  if (!transactionId) {
    throw new CheckoutProblem('missing', 'This page needs a transaction id.')
  }

  const token = await fetchClientToken()
  const paddle = await loadPaddle()
  // A sandbox token against the live checkout (or the reverse) fails with an
  // opaque error, so the environment is chosen from the token itself.
  if (token.startsWith('test_')) paddle.Environment?.set('sandbox')
  paddle.Initialize({ token })
  paddle.Checkout.open({ transactionId })
}

export default function PayPage() {
  const [problem, setProblem] = useState<Problem | null>(null)
  const [detail, setDetail] = useState('')
  // React 18 runs effects twice in development; opening the same transaction
  // twice would show two overlays over each other.
  const started = useRef(false)

  useEffect(() => {
    if (started.current) return
    started.current = true

    void openCheckout().catch((error: unknown) => {
      setProblem(error instanceof CheckoutProblem ? error.problem : 'failed')
      setDetail(
        error instanceof Error ? error.message : 'Could not open the checkout. Please try again.'
      )
    })
  }, [])

  if (!problem) {
    return (
      <Shell>
        <Loader2 className="mx-auto h-8 w-8 animate-spin text-primary" />
        <h1 className="mt-4 text-xl font-bold text-white">Opening secure checkout</h1>
        <p className="mt-2 text-sm text-gray-400">
          Paddle handles the card details — they never touch this app.
        </p>
      </Shell>
    )
  }

  return (
    <Shell>
      <AlertCircle className="mx-auto h-8 w-8 text-red-400" />
      <h1 className="mt-4 text-xl font-bold text-white">
        {problem === 'missing' ? 'No payment to open' : 'Checkout could not open'}
      </h1>
      <p className="mt-2 text-sm text-gray-400">
        {problem === 'missing'
          ? `${detail} Start the upgrade from the pricing page.`
          : detail}
      </p>
      <Link
        href="/pricing"
        className="btn btn-gradient mt-6 inline-flex w-full items-center justify-center py-3 font-semibold text-white"
      >
        Back to pricing
      </Link>
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-background">
      <nav className="border-b border-border bg-surface/50 backdrop-blur-sm">
        <div className="mx-auto flex h-16 max-w-7xl items-center px-4 sm:px-6 lg:px-8">
          <Link href="/" className="flex items-center gap-2">
            <Logo size="sm" />
          </Link>
        </div>
      </nav>

      <div className="flex min-h-[60vh] items-center justify-center px-4 py-20">
        <div className="w-full max-w-md rounded-2xl border border-border bg-surface p-8 text-center">
          {children}
        </div>
      </div>
    </div>
  )
}
