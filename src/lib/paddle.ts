/**
 * Paddle card subscriptions.
 *
 * Paddle is the merchant of record: it calculates and remits sales tax, issues
 * the receipt and takes the card charge, so the amount it collects is not always
 * the amount on our price list. That is why the amount applied to an account comes
 * from the plan catalogue and never from the transaction total — comparing a
 * taxed total against the list price would reject every European customer.
 *
 * What is checked instead is the *price id*: the transaction must contain the
 * price this deployment configured for that plan. A £1 test price or a stale
 * price from another environment therefore cannot buy a paid plan.
 *
 * Everything here is server-only: the API key never reaches the browser, and the
 * checkout link is produced by the API rather than Paddle.js so no publishable
 * token or client bundle is needed.
 */

import { createHmac, timingSafeEqual } from 'node:crypto'
import type { BillingInterval } from '@/types'

export const PADDLE_LIVE_BASE = 'https://api.paddle.com'
export const PADDLE_SANDBOX_BASE = 'https://sandbox-api.paddle.com'

/** How old a signed webhook may be before it is refused as a replay. */
export const SIGNATURE_TOLERANCE_SECONDS = 300

function env(name: string): string {
  return (process.env[name] || '').trim()
}

export function paddleEnvironment(): 'sandbox' | 'production' {
  return env('PADDLE_ENVIRONMENT').toLowerCase() === 'production' ? 'production' : 'sandbox'
}

/** Sandbox unless production is asked for explicitly — the safe direction. */
export function paddleBase(): string {
  const explicit = env('PADDLE_API_BASE')
  if (explicit) return explicit.replace(/\/+$/, '')
  return paddleEnvironment() === 'production' ? PADDLE_LIVE_BASE : PADDLE_SANDBOX_BASE
}

export function paddleCurrency(): string {
  return (env('PADDLE_CURRENCY') || 'USD').toUpperCase()
}

export function paddleConfigured(): boolean {
  return Boolean(env('PADDLE_API_KEY'))
}

export function webhookSecretConfigured(): boolean {
  return Boolean(env('PADDLE_WEBHOOK_SECRET'))
}

/**
 * The price id for a local plan and cadence, read at call time so a test or a
 * rotated environment variable is honoured without a module reload.
 * `basic` monthly → `PADDLE_PRICE_BASIC`; yearly → `PADDLE_PRICE_BASIC_ANNUAL`.
 */
export function priceIdFor(planId: string, interval: BillingInterval = 'month'): string | null {
  const suffix = interval === 'year' ? '_ANNUAL' : ''
  const key = `PADDLE_PRICE_${planId.replace(/[^a-z0-9]/gi, '_').toUpperCase()}${suffix}`
  return env(key) || null
}

/** Plan ids this deployment can actually sell on that cadence through Paddle. */
export function sellablePlanIds(
  paidPlanIds: string[],
  interval: BillingInterval = 'month'
): string[] {
  if (!paddleConfigured()) return []
  return paidPlanIds.filter((planId) => Boolean(priceIdFor(planId, interval)))
}

/** The value that must never be logged or returned: the API key. */
function apiKey(): string {
  const key = env('PADDLE_API_KEY')
  if (!key) throw new Error('Paddle payments are not configured')
  return key
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

async function readError(response: Response): Promise<string> {
  const text = await response.text().catch(() => '')
  try {
    const parsed = JSON.parse(text) as { error?: { detail?: string; code?: string } }
    return parsed.error?.detail || parsed.error?.code || `HTTP ${response.status}`
  } catch {
    return text.slice(0, 200) || `HTTP ${response.status}`
  }
}

async function paddleRequest<T>(
  path: string,
  init: RequestInit = {},
  fetchImpl: FetchLike = fetch
): Promise<T> {
  const response = await fetchImpl(`${paddleBase()}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${apiKey()}`,
      'Content-Type': 'application/json',
      ...(init.headers as Record<string, string> | undefined),
    },
    cache: 'no-store',
  })

  if (!response.ok) {
    throw new Error(`Paddle ${path} failed (${response.status}): ${await readError(response)}`)
  }
  const body = (await response.json().catch(() => ({}))) as { data?: T }
  return body.data as T
}

// ------------------------------------------------------------------ checkout

export interface PaddleCheckout {
  url: string
  transactionId: string
}

/**
 * Creates a transaction and returns its hosted checkout link.
 *
 * `custom_data` is the only thing that ties the payment back to an account: the
 * email is collected by Paddle, not trusted from here. It is copied onto the
 * subscription, so a renewal carries the same `userId` and `planId`.
 */
export async function createCheckoutTransaction(
  params: { planId: string; priceId: string; userId: string; interval?: BillingInterval },
  fetchImpl: FetchLike = fetch
): Promise<PaddleCheckout> {
  const data = await paddleRequest<{
    id?: string
    checkout?: { url?: string } | null
  }>(
    '/transactions',
    {
      method: 'POST',
      body: JSON.stringify({
        items: [{ price_id: params.priceId, quantity: 1 }],
        // `interval` travels with the payment so the webhook knows whether the
        // customer bought 30 days or a year. It is copied onto the subscription,
        // so a renewal carries it too.
        custom_data: {
          userId: params.userId,
          planId: params.planId,
          interval: params.interval ?? 'month',
        },
      }),
    },
    fetchImpl
  )

  const url = data?.checkout?.url
  if (typeof url !== 'string' || !url) {
    // Without a checkout URL the customer has nowhere to pay; failing here is
    // better than redirecting them to a Paddle page with no transaction.
    throw new Error('Paddle did not return a checkout url for the transaction')
  }
  return { url, transactionId: typeof data.id === 'string' ? data.id : '' }
}

// ----------------------------------------------------------------- webhooks

export interface ParsedSignature {
  ts: number
  /** One or more signatures; Paddle may rotate a secret and send both. */
  h1: string[]
}

export function parsePaddleSignature(header: string | null): ParsedSignature | null {
  if (!header) return null
  let ts: number | null = null
  const h1: string[] = []

  for (const part of header.split(';')) {
    const index = part.indexOf('=')
    if (index === -1) continue
    const key = part.slice(0, index).trim().toLowerCase()
    const value = part.slice(index + 1).trim()
    if (!key || !value) continue
    if (key === 'ts') {
      const parsed = Number(value)
      if (Number.isFinite(parsed)) ts = Math.trunc(parsed)
    } else if (key === 'h1') {
      h1.push(value.toLowerCase())
    }
  }

  return ts === null || h1.length === 0 ? null : { ts, h1 }
}

/**
 * Verifies `Paddle-Signature` over the exact bytes received.
 *
 * The timestamp is part of the signed payload *and* checked for freshness: a
 * valid signature from last week is still a valid signature, and without the
 * window an attacker could replay a captured `transaction.completed` body.
 */
export function isValidPaddleSignature(
  header: string | null,
  rawBody: string,
  options: { secret?: string; now?: number; toleranceSeconds?: number } = {}
): boolean {
  const secret = options.secret ?? env('PADDLE_WEBHOOK_SECRET')
  if (!secret) return false

  const parsed = parsePaddleSignature(header)
  if (!parsed) return false

  const now = options.now ?? Date.now()
  const tolerance = options.toleranceSeconds ?? SIGNATURE_TOLERANCE_SECONDS
  if (Math.abs(now / 1000 - parsed.ts) > tolerance) return false

  const expected = createHmac('sha256', secret).update(`${parsed.ts}:${rawBody}`).digest()
  return parsed.h1.some((candidate) => {
    const supplied = Buffer.from(candidate, 'hex')
    return supplied.length === expected.length && timingSafeEqual(supplied, expected)
  })
}

export interface PaddleTransactionEvent {
  transactionId: string
  status: string
  userId: string | null
  planId: string | null
  priceId: string | null
  /** Minor units (cents), straight from Paddle. `null` when absent. */
  totalCents: number | null
  currency: string | null
  subscriptionId: string | null
  customerEmail: string | null
  /** From `custom_data`; anything unrecognised is read as monthly. */
  interval: BillingInterval
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

/** Reads the parts of a `transaction.*` payload the billing code needs. */
export function parseTransactionEvent(data: unknown): PaddleTransactionEvent | null {
  const record = asRecord(data)
  if (!record) return null
  const transactionId = asString(record.id)
  if (!transactionId) return null

  const custom = asRecord(record.custom_data)
  const items = Array.isArray(record.items) ? record.items : []
  const firstItem = asRecord(items[0])
  const price = asRecord(firstItem?.price)
  const details = asRecord(record.details)
  const totals = asRecord(details?.totals)
  const customer = asRecord(record.customer)

  const total = Number(totals?.grand_total ?? totals?.total)
  return {
    transactionId,
    status: (asString(record.status) || '').toLowerCase(),
    userId: asString(custom?.userId),
    planId: asString(custom?.planId),
    priceId: asString(price?.id),
    totalCents: Number.isFinite(total) ? total : null,
    currency: asString(totals?.currency_code) ?? asString(record.currency_code),
    subscriptionId: asString(record.subscription_id),
    customerEmail: asString(customer?.email)?.toLowerCase() ?? null,
    interval: asString(custom?.interval) === 'year' ? 'year' : 'month',
  }
}

export interface PaddleAdjustmentEvent {
  adjustmentId: string
  action: string
  transactionId: string | null
  subscriptionId: string | null
}

/** Reads a `adjustment.*` payload; only refunds are acted on. */
export function parseAdjustmentEvent(data: unknown): PaddleAdjustmentEvent | null {
  const record = asRecord(data)
  if (!record) return null
  const adjustmentId = asString(record.id)
  if (!adjustmentId) return null
  return {
    adjustmentId,
    action: (asString(record.action) || '').toLowerCase(),
    transactionId: asString(record.transaction_id),
    subscriptionId: asString(record.subscription_id),
  }
}

// ------------------------------------------------------------- cancellation

/**
 * Stops future renewals at the end of the paid period. Access is untouched:
 * the customer paid for the days already on the clock, and the daily expiry job
 * is what downgrades them.
 */
export async function cancelPaddleSubscription(
  subscriptionId: string,
  fetchImpl: FetchLike = fetch
): Promise<boolean> {
  if (!paddleConfigured() || !subscriptionId) return false
  await paddleRequest(
    `/subscriptions/${encodeURIComponent(subscriptionId)}/cancel`,
    {
      method: 'POST',
      body: JSON.stringify({ effective_from: 'next_billing_period' }),
    },
    fetchImpl
  )
  return true
}
