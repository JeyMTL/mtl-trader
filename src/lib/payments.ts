import { PLANS } from '@/lib/plans'
import { shouldApplyPlan, planFields, type AccountState } from '@/lib/subscription'
import { getAdminClient } from '@/lib/server-auth'

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
  provider: 'paypal' | 'bank'
  providerEventId: string
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
  const expected = PAID_PLAN_PRICES[order.planId]
  if (!expected) return { applied: false, reason: 'invalid_plan' }
  if (Number(order.amount) !== Number(expected)) return { applied: false, reason: 'amount_mismatch' }

  const supabase = getAdminClient()
  const { data: account, error: readError } = await supabase
    .from('users')
    .select('subscription_tier, subscription_status, max_trades, trial_ends_at')
    .eq('id', order.userId)
    .single()

  if (readError || !account) return { applied: false, reason: 'unknown_user' }

  const shouldApply = shouldApplyPlan(account as AccountState, order.planId)

  // ON CONFLICT DO NOTHING: an empty result means this event was already handled.
  const { data: inserted, error: insertError } = await supabase
    .from('payment_events')
    .upsert(
      {
        user_id: order.userId,
        provider: order.provider,
        provider_event_id: order.providerEventId,
        plan_id: order.planId,
        amount: Number(order.amount),
        status: shouldApply ? 'applied' : 'skipped_downgrade',
      },
      { onConflict: 'provider,provider_event_id', ignoreDuplicates: true }
    )
    .select('id')

  if (insertError) throw new Error(insertError.message)
  if (!inserted || inserted.length === 0) return { applied: false, reason: 'duplicate' }
  if (!shouldApply) return { applied: false, reason: 'would_downgrade' }

  const { error: updateError } = await supabase
    .from('users')
    .update(planFields(order.planId))
    .eq('id', order.userId)

  if (updateError) throw new Error(updateError.message)
  return { applied: true, reason: 'applied' }
}

export async function getPayPalAccessToken(): Promise<string> {
  const auth = Buffer.from(`${process.env.PAYPAL_CLIENT_ID}:${process.env.PAYPAL_CLIENT_SECRET}`).toString('base64')
  const res = await fetch(`${PAYPAL_BASE}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  })
  const data = await res.json()
  return data.access_token
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
