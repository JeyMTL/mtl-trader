import { createHmac, timingSafeEqual } from 'node:crypto'
import { getAdminClient } from '@/lib/server-auth'
import { PLANS } from '@/lib/plans'

/**
 * Flutterwave card subscriptions.
 *
 * A Flutterwave payment plan is a monthly card subscription: the first charge
 * creates it, and Flutterwave charges the saved card every month. Every charge
 * arrives as a `charge.completed` webhook and is applied through
 * `apply_paid_order`, so billing still means "one 30-day period per payment".
 *
 * Payment plans fix the payment method to card, which is why mobile money stays
 * a one-time option rather than a renewal source.
 */

export const FLW_BASE =
  process.env.FLUTTERWAVE_API_BASE || 'https://api.flutterwave.com'

export const FLW_CURRENCY = (process.env.FLUTTERWAVE_CURRENCY || 'USD').toUpperCase()

export function flutterwaveConfigured(): boolean {
  return Boolean(process.env.FLUTTERWAVE_SECRET_KEY)
}

export function webhookSecretConfigured(): boolean {
  return Boolean(process.env.FLUTTERWAVE_SECRET_HASH)
}

/** The plan id, when it is a paid plan the UI actually sells. */
export function isPaidPlanId(planId: unknown): planId is string {
  return (
    typeof planId === 'string' &&
    PLANS.some((plan) => plan.id === planId && plan.price > 0)
  )
}

/**
 * Flutterwave sends the dashboard "secret hash" in the `verif-hash` header.
 * Their newer docs also mention an HMAC of the body, so both are accepted:
 * the literal secret hash and `HMAC-SHA256(rawBody, secret)` in hex.
 */
export function isValidFlutterwaveSignature(
  header: string | null,
  rawBody: string
): boolean {
  const secret = process.env.FLUTTERWAVE_SECRET_HASH
  if (!secret || !header) return false

  const expected = Buffer.from(secret)
  const supplied = Buffer.from(header)
  if (supplied.length === expected.length && timingSafeEqual(supplied, expected)) {
    return true
  }

  const hmac = createHmac('sha256', secret).update(rawBody).digest('hex')
  const hmacBuf = Buffer.from(hmac)
  return (
    hmacBuf.length === supplied.length && timingSafeEqual(hmacBuf, supplied)
  )
}

interface FlwEnvelope<T> {
  status?: string
  message?: string
  data?: T
}

async function flwRequest<T>(
  path: string,
  init: RequestInit = {}
): Promise<T> {
  const key = process.env.FLUTTERWAVE_SECRET_KEY
  if (!key) throw new Error('Flutterwave payments are not configured')

  const res = await fetch(`${FLW_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(init.headers as Record<string, string> | undefined),
    },
    cache: 'no-store',
  })

  const body = (await res.json().catch(() => ({}))) as FlwEnvelope<T>
  if (!res.ok || body.status === 'error') {
    throw new Error(
      `Flutterwave ${path} failed (${res.status}): ${body.message || 'unknown error'}`
    )
  }
  return body.data as T
}

/**
 * Returns the remote payment-plan id for a plan, creating and caching it the
 * first time. Caching matters: a plan per checkout would create duplicate
 * subscriptions and disconnected renewals.
 */
export async function ensurePaymentPlan(planId: string): Promise<string> {
  if (!isPaidPlanId(planId)) throw new Error('Invalid plan')
  const plan = PLANS.find((item) => item.id === planId)!

  const admin = getAdminClient()
  const { data: cached, error } = await admin
    .from('billing_plans')
    .select('remote_plan_id')
    .eq('provider', 'flutterwave')
    .eq('plan_id', planId)
    .maybeSingle()

  if (error) throw new Error(`Could not read the payment plan: ${error.message}`)
  if (cached?.remote_plan_id) return String(cached.remote_plan_id)

  const created = await flwRequest<{ id?: number | string }>('/v3/payment-plans', {
    method: 'POST',
    body: JSON.stringify({
      name: `MTL Trader ${plan.name}`,
      amount: plan.price,
      interval: 'monthly',
      currency: FLW_CURRENCY,
    }),
  })
  if (created?.id == null) {
    throw new Error('Flutterwave did not return a payment plan id')
  }
  const remotePlanId = String(created.id)

  const { error: cacheError } = await admin.from('billing_plans').upsert(
    {
      provider: 'flutterwave',
      plan_id: planId,
      remote_plan_id: remotePlanId,
      amount: plan.price,
      currency: FLW_CURRENCY,
    },
    { onConflict: 'provider,plan_id' }
  )
  if (cacheError) {
    // The plan exists remotely; failing to cache it would only cost an extra
    // plan on the next attempt, so keep going.
    console.error('Could not cache the Flutterwave payment plan:', cacheError.message)
  }

  return remotePlanId
}

export interface CheckoutSession {
  url: string
  txRef: string
}

export async function createCheckoutSession(params: {
  userId: string
  email: string
  name?: string | null
  planId: string
  remotePlanId: string
  appUrl: string
}): Promise<CheckoutSession> {
  const plan = PLANS.find((item) => item.id === params.planId)
  if (!plan || plan.price <= 0) throw new Error('Invalid plan')

  const txRef = `mtl-${params.userId.slice(0, 8)}-${Date.now().toString(36)}`
  const data = await flwRequest<{ link?: string }>('/v3/payments', {
    method: 'POST',
    body: JSON.stringify({
      tx_ref: txRef,
      amount: plan.price,
      currency: FLW_CURRENCY,
      redirect_url: `${params.appUrl}/flutterwave-success`,
      payment_plan: params.remotePlanId,
      customer: {
        email: params.email,
        name: params.name || params.email,
      },
      customizations: {
        title: 'MTL Trader',
        description: `${plan.name} plan · monthly card subscription`,
      },
      meta: { userId: params.userId, planId: params.planId, txRef },
    }),
  })

  if (!data?.link) throw new Error('Flutterwave did not return a checkout link')
  return { url: data.link, txRef }
}

export interface VerifiedCharge {
  id: string
  status: string
  amount: number
  currency: string
  txRef: string
  customerEmail: string | null
  meta: { userId?: string; planId?: string } | null
  remotePlanId: string | null
}

function readMeta(value: unknown): VerifiedCharge['meta'] {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as { userId?: string; planId?: string }
  }
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value) as unknown
      if (parsed && typeof parsed === 'object') {
        return parsed as { userId?: string; planId?: string }
      }
    } catch {
      return null
    }
  }
  return null
}

/** Reads the transaction from Flutterwave; webhooks alone are never trusted. */
export async function verifyTransaction(
  transactionId: string
): Promise<VerifiedCharge> {
  const data = await flwRequest<Record<string, unknown>>(
    `/v3/transactions/${encodeURIComponent(transactionId)}/verify`
  )
  const customer =
    data.customer && typeof data.customer === 'object'
      ? (data.customer as { email?: unknown })
      : null

  return {
    id: String(data.id ?? transactionId),
    status: String(data.status ?? '').toLowerCase(),
    amount: Number(data.amount ?? 0),
    currency: String(data.currency ?? '').toUpperCase(),
    txRef: String(data.tx_ref ?? ''),
    customerEmail:
      typeof customer?.email === 'string' ? customer.email.toLowerCase() : null,
    meta: readMeta(data.meta),
    remotePlanId:
      data.payment_plan != null ? String(data.payment_plan) : null,
  }
}

export interface ResolvedCharge {
  userId: string
  planId: string
  email: string | null
  remotePlanId: string | null
}

/**
 * Finds the account and plan behind a charge. Renewals carry no custom meta, so
 * the lookup falls back to the customer email and the plan the account is on.
 */
export async function resolveChargeTarget(
  charge: Pick<VerifiedCharge, 'meta' | 'customerEmail' | 'remotePlanId'>
): Promise<ResolvedCharge | null> {
  const admin = getAdminClient()

  let userId = charge.meta?.userId ?? null
  let planId = isPaidPlanId(charge.meta?.planId) ? (charge.meta!.planId as string) : null
  let email = charge.customerEmail
  const remotePlanId = charge.remotePlanId

  if (!userId && email) {
    // Equality, not ILIKE: `_` and `%` in an address are wildcards, and a
    // multi-row match would throw (or worse, resolve a different account).
    const { data } = await admin
      .from('users')
      .select('id, email, subscription_tier')
      .eq('email', email)
      .maybeSingle()
    if (data?.id) {
      userId = String(data.id)
      email = String(data.email ?? email)
      if (!planId && isPaidPlanId(data.subscription_tier)) {
        planId = data.subscription_tier as string
      }
    }
  }

  if (userId && !planId) {
    const { data } = await admin
      .from('users')
      .select('subscription_tier')
      .eq('id', userId)
      .maybeSingle()
    if (isPaidPlanId(data?.subscription_tier)) {
      planId = data.subscription_tier as string
    }
  }

  if (!planId && remotePlanId) {
    const { data } = await admin
      .from('billing_plans')
      .select('plan_id')
      .eq('provider', 'flutterwave')
      .eq('remote_plan_id', remotePlanId)
      .maybeSingle()
    if (isPaidPlanId(data?.plan_id)) planId = data.plan_id as string
  }

  if (!userId || !planId) return null
  return { userId, planId, email, remotePlanId }
}

/** Remembers which account owns a Flutterwave subscription. */
export async function recordSubscription(target: ResolvedCharge): Promise<void> {
  const admin = getAdminClient()
  const { error } = await admin.from('billing_subscriptions').upsert(
    {
      user_id: target.userId,
      provider: 'flutterwave',
      email: target.email,
      remote_plan_id: target.remotePlanId,
      status: 'active',
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,provider' }
  )
  if (error) {
    console.error('Could not record the Flutterwave subscription:', error.message)
  }
}

/**
 * Stops future card charges for an email. Returns true when a live Flutterwave
 * subscription was found and cancelled; false when there was nothing to stop.
 */
export async function cancelRemoteSubscription(email: string): Promise<boolean> {
  if (!flutterwaveConfigured()) return false
  const subscriptions = await flwRequest<Array<Record<string, unknown>>>(
    `/v3/subscriptions?email=${encodeURIComponent(email)}`
  )
  const list = Array.isArray(subscriptions) ? subscriptions : []
  const active = list.find(
    (item) => String(item.status ?? '').toLowerCase() === 'active'
  )
  if (!active || active.id == null) return false

  await flwRequest(`/v3/subscriptions/${encodeURIComponent(String(active.id))}/cancel`, {
    method: 'PUT',
  })

  const admin = getAdminClient()
  await admin
    .from('billing_subscriptions')
    .update({ status: 'cancelled', updated_at: new Date().toISOString() })
    .eq('provider', 'flutterwave')
    .eq('email', email.trim().toLowerCase())

  return true
}
