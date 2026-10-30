import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Terms of Service',
  description: 'The terms that govern your use of MTL Trader, including subscriptions, acceptable use and liability.',
}

const UPDATED = '25 October 2026'

export default function TermsPage() {
  return (
    <article className="prose-legal">
      <p className="eyebrow">Legal</p>
      <h1 className="mt-1.5 text-3xl font-semibold tracking-tight text-white">Terms of Service</h1>
      <p className="mt-2 text-xs text-gray-500">Last updated {UPDATED}</p>

      <p className="mt-6">
        These terms are an agreement between you and <strong>Jeremiah Chipeta</strong>, trading as
        MTL Trader (&ldquo;MTL Trader&rdquo;, &ldquo;we&rdquo;, &ldquo;us&rdquo;), of{' '}
        <strong>Copperbelt, Zambia</strong>. By creating an account or using the service, you accept them.
        If you do not accept them, do not use the service.
      </p>

      <h2>1. The service</h2>
      <p>
        MTL Trader is a trading journal. It stores the trades you provide, calculates statistics, visualises
        performance, and produces written reviews of your own trading history. It is a record-keeping and
        analysis tool only.
      </p>
      <p>
        <strong>MTL Trader does not provide financial, investment, trading or tax advice.</strong> Nothing in the
        service — including automated reviews, statistics or labels — is a recommendation to buy or sell any
        instrument. You are solely responsible for your trading decisions and their outcomes.
      </p>

      <h2>2. Accounts</h2>
      <ul>
        <li>You must provide a valid email address and keep your password confidential.</li>
        <li>You must be at least 18 years old and legally able to enter this agreement.</li>
        <li>One person or business per account. You are responsible for activity under your account.</li>
        <li>Tell us promptly at <strong>[contact email]</strong> if you believe your account has been compromised.</li>
      </ul>

      <h2>3. Your data</h2>
      <p>
        You keep ownership of the trading data you upload. You grant us the limited licence needed to store,
        process and display it so we can operate the service — for example, generating your analytics and,
        where you request it, an AI review. How we handle personal data is described in our{' '}
        <Link href="/privacy">Privacy Policy</Link>.
      </p>
      <p>
        You are responsible for having the right to upload the data you provide, including any data belonging
        to a third party or employer.
      </p>

      <h2>4. Subscriptions, trials and billing</h2>
      <ul>
        <li>New accounts receive a 30-day free trial. No payment is taken during the trial.</li>
        <li>Paid plans are billed monthly in advance through PayPal or bank transfer, at the prices shown on the{' '}
          <Link href="/pricing">pricing page</Link>.</li>
        <li>Subscriptions renew automatically until cancelled. You can cancel from Settings at any time; access
          continues until the end of the period you have paid for.</li>
        <li>Bank transfers are activated once the transfer has been verified. References must match the amount
          and reference shown at checkout.</li>
        <li>Refunds are covered by our <Link href="/refunds">Refund Policy</Link>.</li>
      </ul>

      <h2>5. Acceptable use</h2>
      <p>You must not:</p>
      <ul>
        <li>attempt to access another person&apos;s account or data;</li>
        <li>probe, scan or overload the service, or circumvent usage limits and rate limits;</li>
        <li>reverse engineer, resell or redistribute the service except as permitted by law;</li>
        <li>upload malicious code, unlawful content, or data you have no right to process;</li>
        <li>use the service to break any applicable law or market regulation.</li>
      </ul>
      <p>We may suspend an account that materially breaches these rules, and will explain why unless the law prevents it.</p>

      <h2>6. Availability and changes</h2>
      <p>
        We work to keep the service available, but it is provided &ldquo;as is&rdquo;. Maintenance, third-party
        outages and factors outside our control may interrupt it. We may change or remove features; where a
        change materially reduces what you paid for, you may cancel and receive a pro-rata refund of the
        unused period.
      </p>

      <h2>7. Intellectual property</h2>
      <p>
        The service, its interface, and its underlying code and content belong to us or our licensors. These
        terms do not transfer any of that ownership to you. Third-party names and marks, including broker and
        platform names, belong to their owners; we are not affiliated with them.
      </p>

      <h2>8. Liability</h2>
      <p>
        To the maximum extent permitted by law, we are not liable for trading losses, lost profits, loss of
        data caused by your own actions, or indirect and consequential losses. Our total liability arising from
        the service is limited to the amount you paid us in the twelve months before the claim.
      </p>
      <p>
        Nothing in these terms excludes liability that cannot lawfully be excluded, including for fraud or for
        death or personal injury caused by negligence, or your statutory consumer rights.
      </p>

      <h2>9. Termination</h2>
      <p>
        You may delete your account at any time from Settings; deletion removes your trades, deposits, profile
        and payment records as described in the Privacy Policy. We may terminate this agreement if you
        materially breach it, or with reasonable notice if we discontinue the service.
      </p>

      <h2>10. Governing law</h2>
      <p>
        These terms are governed by the laws of <strong>[governing jurisdiction]</strong>, and disputes are
        subject to the courts of <strong>[venue]</strong>, without affecting any mandatory consumer protections
        in your country of residence.
      </p>

      <h2>11. Contact</h2>
      <p>
        Questions about these terms: <strong>[contact email]</strong>.
      </p>
    </article>
  )
}
