import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description: 'What data MTL Trader collects, why it is processed, who processes it, and how to access or delete it.',
}

const UPDATED = '25 October 2026'

export default function PrivacyPage() {
  return (
    <article className="prose-legal">
      <p className="eyebrow">Legal</p>
      <h1 className="mt-1.5 text-3xl font-semibold tracking-tight text-white">Privacy Policy</h1>
      <p className="mt-2 text-xs text-gray-500">Last updated {UPDATED}</p>

      <p className="mt-6">
        This policy explains what personal data <strong>Jeremiah Chipeta</strong>, trading as
        MTL Trader (&ldquo;we&rdquo;), collects when you use the journal, why we process it, and the choices you have. It
        covers the web app and the mobile app, which load the same service.
      </p>

      <h2>1. Data we collect</h2>
      <ul>
        <li>
          <strong>Account data</strong> — name, email address, timezone, display currency, password (stored only
          as a hash by our authentication provider), and email verification status.
        </li>
        <li>
          <strong>Trading journal data</strong> — the trades you enter or import: symbol, direction, prices, size,
          stop loss, take profit, commission, swap, strategy, notes, tags, and timestamps.
        </li>
        <li>
          <strong>Cash records</strong> — deposits and withdrawals you record yourself, with descriptions.
        </li>
        <li>
          <strong>Subscription data</strong> — plan, trial dates, period end, payment status, PayPal order and
          capture identifiers, and the reference of any bank transfer. We never see or store your card or bank
          credentials.
        </li>
        <li>
          <strong>Sync configuration</strong> — the broker name, server and account login you enter for MetaTrader
          sync, plus a hashed sync token. The token is what the desktop agent uses to authenticate.
        </li>
        <li>
          <strong>AI reviews</strong> — the summaries and trade details you submit for review, and the generated
          text, stored against your account.
        </li>
        <li>
          <strong>Technical data</strong> — IP-derived rate-limiting keys, error events, timestamps and basic
          request metadata used to keep the service secure and working. Theme preference is stored in your
          browser, not on our servers.
        </li>
      </ul>

      <h2>2. Why we process it</h2>
      <ul>
        <li>To provide the journal: storing trades and computing statistics (performance of a contract).</li>
        <li>To authenticate you, verify email addresses and reset passwords (contract and security).</li>
        <li>To take payments, activate plans and prevent duplicate charges (contract and legal obligations).</li>
        <li>To send the transactional email you expect: verification, recovery, weekly and monthly summaries (contract; marketing email only with consent).</li>
        <li>To generate an AI review when you ask for one (consent, withdrawn by not requesting reviews).</li>
        <li>To detect abuse, enforce quotas and rate limits, and keep the service available (legitimate interests).</li>
      </ul>

      <h2>3. Who processes data for us</h2>
      <ul>
        <li><strong>Supabase</strong> — database, authentication and file storage.</li>
        <li><strong>Vercel</strong> — application hosting and scheduled jobs.</li>
        <li><strong>PayPal</strong> — subscription checkout and payment capture.</li>
        <li><strong>Resend</strong> — transactional and summary email delivery.</li>
        <li><strong>An AI provider</strong> (Google Gemini, or Anthropic where configured) — receives the trade summary you submit for a review. Reviews are not used by us to train models.</li>
      </ul>
      <p>
        These providers process data on our instructions and under their own safeguards. Some are located
        outside your country; transfers rely on standard contractual clauses or an equivalent mechanism.
      </p>

      <h2>4. What we do not do</h2>
      <ul>
        <li>We do not sell your personal data.</li>
        <li>We do not use your trades to advertise to you.</li>
        <li>We do not connect to your broker or place trades on your behalf.</li>
      </ul>

      <h2>5. Retention</h2>
      <p>
        Journal data is kept while your account exists. Deleting your account removes your trades, deposits,
        profile, sync configuration, AI reviews and authentication record. Payment records are retained for as
        long as accounting and tax law requires, in a form that no longer includes your journal content. Rate
        limit counters expire automatically.
      </p>

      <h2>6. Your rights</h2>
      <p>
        Depending on where you live, you may have the right to access, correct, export, restrict or delete your
        data, and to object to certain processing. Two of these are built in:
      </p>
      <ul>
        <li><strong>Export</strong> — Settings → Data → Export gives you a machine-readable copy of your account and trades.</li>
        <li><strong>Deletion</strong> — Settings → Data → Delete account removes the data described above after email confirmation.</li>
      </ul>
      <p>
        For anything else, write to <strong>jfx064@gmail.com</strong>. We answer within 30 days and may ask you to
        verify your identity. You also have the right to complain to your local data protection authority.
      </p>

      <h2>7. Security</h2>
      <p>
        Data is transmitted over TLS and access is restricted by row-level security so that each account can
        read only its own records. Passwords are hashed by our authentication provider, sync tokens are stored
        hashed, and administrative access requires an explicitly flagged account. No system is perfectly
        secure; if a breach affects your data we will notify you and the relevant authority as required.
      </p>

      <h2>8. Children</h2>
      <p>The service is for adults. We do not knowingly collect data from anyone under 18.</p>

      <h2>9. Changes</h2>
      <p>
        We will update this page when the way we handle data changes, and will notify account holders by email
        about changes that materially affect them. The date at the top always reflects the current version.
      </p>

      <h2>10. Contact</h2>
      <p>
        Data controller: <strong>[legal entity]</strong>, <strong>[registered address]</strong>.
        Email: <strong>jfx064@gmail.com</strong>. See also our <Link href="/terms">Terms of Service</Link> and{' '}
        <Link href="/refunds">Refund Policy</Link>.
      </p>
    </article>
  )
}
