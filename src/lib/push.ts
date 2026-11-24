import { createSign } from 'node:crypto'
import { getAdminClient } from '@/lib/server-auth'

/**
 * Server-sent notifications, through Firebase Cloud Messaging.
 *
 * Without this, everything the server decides is invisible until the trader
 * opens the app: a broker connection that stopped working, a subscription about
 * to lapse. The phone has no other channel.
 *
 * Configuration is one env var, `FIREBASE_SERVICE_ACCOUNT`: the whole service
 * account JSON from Firebase → Project settings → Service accounts → Generate
 * new private key, pasted as a single line. With it unset, sends are skipped and
 * return `skipped: true` rather than throwing, so a deployment that has not set
 * it up behaves exactly as before.
 *
 * The access token is minted here rather than with a library: it is one RS256
 * JWT, and `node:crypto` is already a dependency of the runtime.
 */

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

interface SendResult {
  sent: number
  failed: number
  /** No service account configured, or nothing to send. */
  skipped: boolean
}

const TOKEN_URL = 'https://oauth2.googleapis.com/token'
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
const MAX_TOKENS_PER_USER = 10

let cachedToken: { value: string; expiresAt: number } | null = null

function base64url(value: string | Buffer): string {
  return Buffer.from(value).toString('base64url')
}

function serviceAccount(): ServiceAccount | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw) as Partial<ServiceAccount>
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) return null
    // A key pasted into a dashboard usually keeps its literal `\n` sequences.
    return {
      project_id: parsed.project_id,
      client_email: parsed.client_email,
      private_key: parsed.private_key.replace(/\\n/g, '\n'),
    }
  } catch {
    return null
  }
}

async function accessToken(account: ServiceAccount): Promise<string | null> {
  const now = Date.now()
  if (cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.value

  const issuedAt = Math.floor(now / 1000)
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64url(
    JSON.stringify({
      iss: account.client_email,
      scope: SCOPE,
      aud: TOKEN_URL,
      iat: issuedAt,
      exp: issuedAt + 3600,
    })
  )

  let assertion: string
  try {
    const signature = createSign('RSA-SHA256')
      .update(`${header}.${claims}`)
      .sign(account.private_key)
    assertion = `${header}.${claims}.${base64url(signature)}`
  } catch {
    // A malformed key is a configuration problem, not a request failure.
    return null
  }

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })
  if (!response.ok) return null

  const body = (await response.json()) as { access_token?: string; expires_in?: number }
  if (!body.access_token) return null
  cachedToken = {
    value: body.access_token,
    expiresAt: now + (body.expires_in ?? 3600) * 1000,
  }
  return cachedToken.value
}

/**
 * Sends one notification to every device the user has registered.
 *
 * A token FCM reports as unregistered is deleted: that device is gone (app
 * uninstalled, token rotated), and keeping it would slow every later send.
 */
export async function sendPushToUser(
  userId: string,
  notification: { title: string; body: string; data?: Record<string, string> }
): Promise<SendResult> {
  const account = serviceAccount()
  if (!account) return { sent: 0, failed: 0, skipped: true }

  const { data, error } = await getAdminClient()
    .from('push_tokens')
    .select('token')
    .eq('user_id', userId)
    .limit(MAX_TOKENS_PER_USER)
  if (error || !data || data.length === 0) return { sent: 0, failed: 0, skipped: true }

  const authorization = await accessToken(account)
  if (!authorization) return { sent: 0, failed: 0, skipped: true }

  const endpoint = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`
  let sent = 0
  let failed = 0
  const dead: string[] = []

  for (const row of data as { token: string }[]) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${authorization}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: row.token,
          notification: { title: notification.title, body: notification.body },
          data: notification.data ?? {},
          android: { priority: 'high' },
          apns: { payload: { aps: { sound: 'default' } } },
        },
      }),
    })

    if (response.ok) {
      sent += 1
      continue
    }

    failed += 1
    const text = await response.text().catch(() => '')
    if (text.includes('UNREGISTERED') || text.includes('INVALID_ARGUMENT')) {
      dead.push(row.token)
    }
  }

  if (dead.length) {
    await getAdminClient().from('push_tokens').delete().in('token', dead)
  }

  return { sent, failed, skipped: false }
}
