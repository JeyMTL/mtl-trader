import { PLANS } from '@/lib/plans'
import { getAdminClient } from '@/lib/server-auth'
import type { BillingInterval } from '@/types'

/**
 * Server-only payment application.
 *
 * Every paid order (PayPal capture or, later, bank payment) flows through
 * `applyPaidOrder`, which:
 *   1. rejects unknown plans or amounts that do not match the displayed price,
 *   2. records the order in `payment_events`, keyed by a unique provider event id
 *      so replaying the same payment is a no-op (idempotent), and
 *   3. applies the plan only if it would not downgrade an active subscription.
 *
 * The capture route, the webhook, and reconciliation all call this, so they can
 * never disagree about what a payment does.
 */

// Sandbox and live differ only by this base URL. Override with PAYPAL_API_BASE
// (e.g. https://api-m.sandbox.paypal.com) to test without touching live money.
export const PAYPAL_BASE = process.env.PAYPAL_API_BASE || 'https://api-m.paypal.com'

// Derived from PLANS so a payment can never apply a price the UI never showed.
export const PAID_PLAN_PRICES: Record<string, string> = Object.fromEntries(
  PLANS.filter((p) => p.price > 0).map((p) => [p.id, p.price.toFixed(2)])
)

/** Yearly prices, for the plans that have one. Same currency as the monthly ones. */
export const ANNUAL_PLAN_PRICES: Record<string, string> = Object.fromEntries(
  PLANS.filter((p) => typeof p.annual_price === 'number' && p.annual_price > 0).map((p) => [
    p.id,
    (p.annual_price as number).toFixed(2),
  ])
)

/**
 * The price a payment for this plan and cadence must match exactly.
 *
 * Annual is a separate amount, not `monthly × 12`: at $120 and $290 the customer
 * gets two months free, which is the whole point of paying up front. The amount a
 * webhook applies is read from here, never from the provider's total (which
 * includes tax).
 */
export function priceForPlan(planId: string, interval: BillingInterval = 'month'): string | undefined {
  return interval === 'year' ? ANNUAL_PLAN_PRICES[planId] : PAID_PLAN_PRICES[planId]
}

export type ApplyReason =
  | 'applied'
  | 'duplicate'
  | 'amount_mismatch'
  | 'invalid_plan'
  | 'would_downgrade'
  | 'unknown_user'

export interface ApplyResult {
  applied: boolean
  reason: ApplyReason
}

export interface PaidOrder {
  userId: string
  planId: string
  amount: number | string
  provider: 'paypal' | 'bank' | 'flutterwave' | 'paddle'
  providerEventId: string
  /** `year` buys 365 days through `apply_annual_order`; default is 30 days. */
  interval?: BillingInterval
}

/** PayPal order metadata is a JSON string in `custom_id`. */
export function parseCustomId(customId: unknown): { userId: string; planId: string } | null {
  if (typeof customId !== 'string' || !customId) return null
  try {
    const parsed = JSON.parse(customId) as { userId?: unknown; planId?: unknown }
    if (typeof parsed.userId !== 'string' || typeof parsed.planId !== 'string') return null
    return { userId: parsed.userId, planId: parsed.planId }
  } catch {
    return null
  }
}

export async function applyPaidOrder(order: PaidOrder): Promise<ApplyResult> {
  const interval = order.interval ?? 'month'
  const expected = priceForPlan(order.planId, interval)
  if (!expected) return { applied: false, reason: 'invalid_plan' }
  if (Number(order.amount) !== Number(expected)) return { applied: false, reason: 'amount_mismatch' }

  // Annual periods are a separate function rather than a day count argument: the
  // existing five-argument `apply_paid_order` is called by every provider, and
  // changing its signature would break whichever caller is not refreshed with it.
  const { data, error } = await getAdminClient().rpc(
    interval === 'year' ? 'apply_annual_order' : 'apply_paid_order',
    {
      p_user_id: order.userId,
      p_provider: order.provider,
      p_provider_event_id: order.providerEventId,
      p_plan_id: order.planId,
      p_amount: Number(order.amount),
    }
  )

  if (error) throw new Error(`Could not apply paid order: ${error.message}`)
  if (
    data === 'applied' ||
    data === 'duplicate' ||
    data === 'amount_mismatch' ||
    data === 'invalid_plan' ||
    data === 'would_downgrade' ||
    data === 'unknown_user'
  ) {
    return { applied: data === 'applied', reason: data }
  }

  throw new Error(`Unexpected paid-order result: ${String(data)}`)
}

export async function getPayPalAccessToken(): Promise<string> {
  const clientId = process.env.PAYPAL_CLIENT_ID
  const clientSecret = process.env.PAYPAL_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    throw new Error('PayPal payments are not configured')
  }

  const auth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64')
  const res = await fetch(`${PAYPAL_BASE}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  })
  if (!res.ok) {
    throw new Error(`PayPal token request failed (${res.status})`)
  }

  const data = await res.json() as { access_token?: unknown }
  if (typeof data.access_token !== 'string' || !data.access_token) {
    throw new Error('PayPal token response did not include an access token')
  }
  return data.access_token
}

export type RevokeReason = 'revoked' | 'duplicate' | 'unknown_user' | 'invalid_plan'

/**
 * Reverses a payment: refunds, reversals and disputes drop the account back to
 * free immediately. Keyed by `providerEventId` like `applyPaidOrder`, so a
 * replayed refund can never double-apply.
 */
export async function revokePaidOrder(order: PaidOrder): Promise<RevokeReason> {
  const { data, error } = await getAdminClient().rpc('revoke_paid_order', {
    p_user_id: order.userId,
    p_provider: order.provider,
    p_provider_event_id: order.providerEventId,
    p_plan_id: order.planId,
    p_amount: Number(order.amount),
  })

  if (error) throw new Error(`Could not revoke paid order: ${error.message}`)
  if (
    data === 'revoked' ||
    data === 'duplicate' ||
    data === 'unknown_user' ||
    data === 'invalid_plan'
  ) {
    return data
  }

  throw new Error(`Unexpected paid-order revocation result: ${String(data)}`)
}

/** Downgrades every account whose paid period has already ended. Returns the count. */
export async function expireLapsedSubscriptions(): Promise<number> {
  const { data, error } = await getAdminClient().rpc('expire_lapsed_subscriptions')
  if (error) throw new Error(`Could not expire lapsed subscriptions: ${error.message}`)
  return typeof data === 'number' ? data : Number(data ?? 0)
}

export interface RefundEventDetails {
  refundId: string
  amount: string
  customId: string | null
  captureId: string | null
}

/**
 * Refund and reversal webhooks describe the refund, not the original capture.
 * PayPal does not always echo `custom_id` on the refund, so the capture id is
 * read from the `up` link and used to look the order up in `payment_events`.
 */
export function parseRefundEvent(event: {
  resource?: {
    id?: string
    custom_id?: string
    amount?: { value?: string }
    links?: Array<{ rel?: string; href?: string }>
  }
}): RefundEventDetails | null {
  const refundId = event.resource?.id
  if (typeof refundId !== 'string' || !refundId) return null

  const upLink = (event.resource?.links || []).find(
    (link) => link.rel === 'up' && typeof link.href === 'string'
  )
  const captureId = upLink?.href?.match(/\/captures\/([A-Za-z0-9_-]+)\/?$/)?.[1] ?? null

  return {
    refundId,
    amount: event.resource?.amount?.value ?? '0',
    customId: typeof event.resource?.custom_id === 'string' ? event.resource.custom_id : null,
    captureId,
  }
}

interface PayPalWebhookEvent {
  id?: string
  event_type?: string
  resource?: {
    id?: string
    custom_id?: string
    amount?: { value?: string }
  }
}

/**
 * Reads recent webhook events from PayPal and turns completed captures into
 * orders we can (re)apply. PayPal stores these events even when a delivery to our
 * endpoint fails, so this recovers payments the webhook never received.
 */
export async function fetchRecentCompletedCaptures(pageSize = 100): Promise<{ orders: PaidOrder[]; scanned: number }> {
  const token = await getPayPalAccessToken()
  const res = await fetch(`${PAYPAL_BASE}/v1/notifications/webhooks-events?page_size=${pageSize}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) {
    throw new Error(`PayPal webhook events request failed (${res.status})`)
  }

  const data = (await res.json()) as { events?: PayPalWebhookEvent[] }
  const events = data.events || []
  const orders: PaidOrder[] = []

  for (const event of events) {
    if (event.event_type !== 'PAYMENT.CAPTURE.COMPLETED') continue
    const parsed = parseCustomId(event.resource?.custom_id)
    const captureId = event.resource?.id
    if (!parsed || !captureId) continue
    orders.push({
      userId: parsed.userId,
      planId: parsed.planId,
      amount: event.resource?.amount?.value ?? '0',
      provider: 'paypal',
      // Same id the webhook uses, so reconciliation de-dupes against it.
      providerEventId: `paypal:capture:${captureId}`,
    })
  }

  return { orders, scanned: events.length }
}
