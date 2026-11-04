/**
 * Google Play subscriptions.
 *
 * Google is the merchant of record for a Play purchase: it charges the card,
 * issues the receipt, renews the plan and refunds it. The app therefore cannot
 * be trusted to say what it bought — only Google can. The flow is:
 *
 *   1. the app completes Play's purchase sheet and receives a purchase token,
 *   2. the app posts that token to `/api/billing/google/verify`,
 *   3. this module asks Google what the token is worth (`subscriptionsv2.get`),
 *   4. the server applies the plan and *acknowledges* the purchase.
 *
 * Step 4 is not cosmetic. A purchase that is not acknowledged within three days
 * is refunded by Google automatically, so a customer would be charged, granted
 * access, and then silently refunded. `acknowledgeSubscription` is what closes
 * that window.
 *
 * Credentials are a Play Console service account, supplied as JSON (or base64
 * JSON) in `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Nothing here is reachable from the
 * browser: the private key signs a JWT that is exchanged for an access token and
 * is never sent to the client.
 */

import { createSign } from 'node:crypto'
import type { BillingInterval } from '@/types'

export const PLAY_API_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3'
export const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
const PLAY_SCOPE = 'https://www.googleapis.com/auth/androidpublisher'

/** How long an access token is reused before it is exchanged again. */
const TOKEN_SAFETY_MS = 60_000

export interface PlayProduct {
  planId: string
  interval: BillingInterval
}

/**
 * The subscription products created in the Play Console.
 *
 * Each entry is a *base plan*: Play sells monthly and yearly as separate base
 * plans under one subscription, so both cadences appear here. The ids must match
 * the console exactly — a product Play does not return is simply not offered in
 * the app, which is the failure this map exists to make visible.
 */
export const PLAY_PRODUCTS: Record<string, PlayProduct> = {
  basic_month: { planId: 'basic', interval: 'month' },
  basic_year: { planId: 'basic', interval: 'year' },
  pro_month: { planId: 'pro', interval: 'month' },
  pro_year: { planId: 'pro', interval: 'year' },
}

export function playPackageName(): string {
  return (process.env.GOOGLE_PLAY_PACKAGE_NAME || 'com.mtltrader.app').trim()
}

interface ServiceAccount {
  client_email: string
  private_key: string
}

/**
 * Reads the service-account key. Both a raw JSON paste and a base64 blob are
 * accepted because hosting dashboards differ in how well they preserve
 * multi-line values — the private key is a PEM block with real newlines.
 */
export function serviceAccount(): ServiceAccount | null {
  const raw = (process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || '').trim()
  if (!raw) return null

  let text = raw
  if (!raw.startsWith('{')) {
    try {
      text = Buffer.from(raw, 'base64').toString('utf8')
    } catch {
      return null
    }
  }

  try {
    const parsed = JSON.parse(text) as Partial<ServiceAccount>
    if (!parsed.client_email || !parsed.private_key) return null
    return { client_email: parsed.client_email, private_key: parsed.private_key }
  } catch {
    return null
  }
}

export function googlePlayConfigured(): boolean {
  return serviceAccount() !== null
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

function base64url(value: Buffer | string): string {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

/** The signed assertion Google's OAuth endpoint exchanges for an access token. */
export function serviceAccountJwt(account: ServiceAccount, now: number = Date.now()): string {
  const issuedAt = Math.floor(now / 1000)
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64url(
    JSON.stringify({
      iss: account.client_email,
      scope: PLAY_SCOPE,
      aud: GOOGLE_TOKEN_URL,
      iat: issuedAt,
      exp: issuedAt + 3600,
    })
  )
  const signer = createSign('RSA-SHA256')
  signer.update(`${header}.${claims}`)
  return `${header}.${claims}.${base64url(signer.sign(account.private_key))}`
}

let cachedToken: { token: string; expiresAt: number } | null = null

/** Test hook: forget the cached token so the next call exchanges a new one. */
export function resetAccessTokenCache(): void {
  cachedToken = null
}

export async function googleAccessToken(
  fetchImpl: FetchLike = fetch,
  now: number = Date.now()
): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > now + TOKEN_SAFETY_MS) {
    return cachedToken.token
  }

  const account = serviceAccount()
  if (!account) throw new Error('Google Play billing is not configured')

  const response = await fetchImpl(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: serviceAccountJwt(account, now),
    }).toString(),
    cache: 'no-store',
  })

  const body = (await response.json().catch(() => ({}))) as {
    access_token?: unknown
    expires_in?: unknown
  }
  if (!response.ok || typeof body.access_token !== 'string' || !body.access_token) {
    throw new Error(`Google token request failed (${response.status})`)
  }

  const lifetime = Number(body.expires_in)
  cachedToken = {
    token: body.access_token,
    expiresAt: now + (Number.isFinite(lifetime) && lifetime > 0 ? lifetime : 3600) * 1000,
  }
  return cachedToken.token
}

export interface PlaySubscription {
  productId: string | null
  /** Google's raw state, e.g. `SUBSCRIPTION_STATE_ACTIVE`. */
  state: string
  expiryTime: string | null
  acknowledged: boolean
  /** True while the buyer should keep access. */
  active: boolean
  planId: string | null
  interval: BillingInterval
}

/**
 * States that still carry access. `CANCELED` is included on purpose: Google uses
 * it for a subscription whose renewal was stopped, and the buyer keeps the period
 * they paid for — dropping them the moment they cancel would be a refund demand.
 */
const ACTIVE_STATES = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_CANCELED',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
])

/**
 * Reads `subscriptionsv2.get`. `active` also requires an expiry in the future, so
 * a state string that lags behind the clock can never grant a lapsed plan.
 */
export function parsePlaySubscription(
  payload: unknown,
  now: Date = new Date()
): PlaySubscription | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null
  const record = payload as Record<string, unknown>

  const lineItems = Array.isArray(record.lineItems) ? record.lineItems : []
  const first = lineItems[0] && typeof lineItems[0] === 'object'
    ? (lineItems[0] as Record<string, unknown>)
    : null

  const productId = typeof first?.productId === 'string' ? first.productId : null
  const expiryTime = typeof first?.expiryTime === 'string' ? first.expiryTime : null
  const state = (typeof record.subscriptionState === 'string' ? record.subscriptionState : '').toUpperCase()
  const catalogue = productId ? PLAY_PRODUCTS[productId] : undefined
  const unexpired = expiryTime ? new Date(expiryTime).getTime() > now.getTime() : false

  return {
    productId,
    state,
    expiryTime,
    acknowledged: record.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    active: ACTIVE_STATES.has(state) && unexpired,
    planId: catalogue?.planId ?? null,
    interval: catalogue?.interval ?? 'month',
  }
}

/** Asks Google what a purchase token is worth. Throws when it cannot. */
export async function verifyPlaySubscription(
  purchaseToken: string,
  fetchImpl: FetchLike = fetch
): Promise<PlaySubscription> {
  if (!purchaseToken) throw new Error('A purchase token is required')

  const token = await googleAccessToken(fetchImpl)
  const url =
    `${PLAY_API_BASE}/applications/${encodeURIComponent(playPackageName())}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`

  const response = await fetchImpl(url, {
    headers: { Authorization: `Bearer ${token}` },
    cache: 'no-store',
  })
  if (!response.ok) {
    throw new Error(`Google Play subscription lookup failed (${response.status})`)
  }

  const parsed = parsePlaySubscription(await response.json())
  if (!parsed) throw new Error('Google Play returned an unreadable subscription')
  return parsed
}

/**
 * Tells Google the purchase has been delivered. Without this the purchase is
 * automatically refunded after three days, which is why a failure here is
 * reported rather than swallowed.
 */
export async function acknowledgeSubscription(
  purchaseToken: string,
  productId: string,
  fetchImpl: FetchLike = fetch
): Promise<boolean> {
  if (!purchaseToken || !productId) return false

  const token = await googleAccessToken(fetchImpl)
  const url =
    `${PLAY_API_BASE}/applications/${encodeURIComponent(playPackageName())}` +
    `/purchases/subscriptions/${encodeURIComponent(productId)}` +
    `/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`

  const response = await fetchImpl(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
    cache: 'no-store',
  })
  return response.ok
}
