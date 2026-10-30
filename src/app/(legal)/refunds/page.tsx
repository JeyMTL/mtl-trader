import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Refund Policy',
  description: 'How trials, cancellation, billing errors and refunds work for MTL Trader subscriptions.',
}

const UPDATED = '25 October 2026'

export default function RefundPolicyPage() {
  return (
    <article className="prose-legal">
      <p className="eyebrow">Legal</p>
      <h1 className="mt-1.5 text-3xl font-semibold tracking-tight text-white">Refund Policy</h1>
      <p className="mt-2 text-xs text-gray-500">Last updated {UPDATED}</p>

      <p className="mt-6">
        This policy applies to subscriptions sold by <strong>Jeremiah Chipeta</strong>, trading as
        MTL Trader, through our card subscription, PayPal or bank transfer. It does not limit any
        statutory rights you have as a consumer in your country of residence.
      </p>

      <h2>1. Try before you pay</h2>
      <p>
        Every new account starts with a 30-day free trial and no payment details are required. Use the trial to
        confirm the journal fits how you trade — that is the intended way to evaluate the product.
      </p>

      <h2>2. Monthly subscriptions</h2>
      <ul>
        <li>Paid plans are billed monthly in advance and renew automatically.</li>
        <li>You can cancel at any time from Settings. Cancellation stops the next charge.</li>
        <li>You keep access until the end of the period you have already paid for.</li>
        <li>We do not automatically refund a period that has already started and been used, except as set out below.</li>
      </ul>

      <h2>3. When we do refund</h2>
      <ul>
        <li><strong>Duplicate charge</strong> — an accidental second payment for the same period is refunded in full.</li>
        <li><strong>Charged after cancellation</strong> — if a charge was taken after you cancelled, it is refunded in full.</li>
        <li><strong>Service unavailable</strong> — if the journal is unavailable for a sustained period you paid for, we refund the affected part of that period.</li>
        <li><strong>Unauthorised payment</strong> — a payment you did not authorise is refunded once verified.</li>
        <li><strong>First payment within 14 days</strong> — if this is your first paid month and you have not materially used the paid features, contact us within 14 days of the charge and we will refund the month and close the subscription.</li>
      </ul>

      <h2>4. EU/UK consumers</h2>
      <p>
        Digital services supplied immediately can lose the 14-day right of withdrawal once supply begins with
        your consent. By starting a paid plan you ask us to begin supply straight away. Even so, the first-payment
        refund above applies, and mandatory consumer rights always prevail.
      </p>

      <h2>5. How to request a refund</h2>
      <p>
        Email <strong>jfx064@gmail.com</strong> from the address on your account with the PayPal transaction ID or
        bank reference and the date of payment. We reply within two business days. Approved refunds are returned
        by the original payment method: PayPal payments usually within 5 business days, bank transfers within 10
        business days of receiving the return details.
      </p>

      <h2>6. Chargebacks</h2>
      <p>
        If something is wrong, contact us first — most issues are resolved the same week. A chargeback filed
        without contacting us suspends the account while the payment provider investigates.
      </p>

      <h2>7. Contact</h2>
      <p>
        Billing questions: <strong>jfx064@gmail.com</strong>. See also our <Link href="/terms">Terms of Service</Link>{' '}
        and <Link href="/privacy">Privacy Policy</Link>.
      </p>
    </article>
  )
}
