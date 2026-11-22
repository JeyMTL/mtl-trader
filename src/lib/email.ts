import { Resend } from 'resend'

/**
 * Email sending via Resend.
 *
 * Degrades gracefully: with no `RESEND_API_KEY` the app still runs, and
 * `sendEmail` returns `{ sent: false, reason: 'not_configured' }` instead of
 * throwing. Callers (cron jobs) treat that as "skip", not "error".
 */

let client: Resend | null = null

export function isEmailConfigured(): boolean {
  return Boolean(process.env.RESEND_API_KEY)
}

function getClient(): Resend {
  if (!client) client = new Resend(process.env.RESEND_API_KEY)
  return client
}

export interface SendEmailInput {
  to: string
  subject: string
  html: string
}

export interface SendEmailResult {
  sent: boolean
  id?: string
  reason?: string
}

export async function sendEmail({ to, subject, html }: SendEmailInput): Promise<SendEmailResult> {
  if (!isEmailConfigured()) {
    return { sent: false, reason: 'not_configured' }
  }

  const from = process.env.EMAIL_FROM || 'MTL Ledger <onboarding@resend.dev>'
  // Reports and notifications go out from the sending address, which is not a
  // mailbox anyone reads. A customer who answers one should reach a person, so
  // replies are routed to the support inbox unless an override is configured.
  const replyTo = process.env.EMAIL_REPLY_TO || 'support@mtlledger.com'

  try {
    const { data, error } = await getClient().emails.send({ from, to, subject, html, replyTo })
    if (error) return { sent: false, reason: error.message }
    return { sent: true, id: data?.id }
  } catch (error) {
    return { sent: false, reason: error instanceof Error ? error.message : 'send failed' }
  }
}
