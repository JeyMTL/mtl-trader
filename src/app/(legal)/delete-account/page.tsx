import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Delete your account',
  description:
    'How to delete your MTL Ledger account and everything attached to it, from the app or by email.',
}

/**
 * The deletion URL Google Play requires for any app that creates accounts.
 *
 * It has to be reachable without signing in — a policy reviewer opens it in a
 * logged-out browser to check that it exists and says something — so it lives in
 * the public legal group, not behind the dashboard.
 */
const UPDATED = '3 November 2026'

export default function DeleteAccountPage() {
  return (
    <article className="prose-legal">
      <p className="eyebrow">Account</p>
      <h1 className="mt-1.5 text-3xl font-semibold tracking-tight text-white">
        Delete your account
      </h1>
      <p className="mt-2 text-xs text-gray-500">Last updated {UPDATED}</p>

      <p className="mt-6">
        You can delete your MTL Ledger account and every trade, photo, note and backtest stored
        with it. There is no charge, and you do not need to talk to anyone first.
      </p>

      <h2>Option 1 — in the app or on the web (immediate)</h2>
      <ol>
        <li>
          Open <Link href="/dashboard/settings">Settings</Link>.
        </li>
        <li>
          Scroll to the bottom and choose <strong>Delete account</strong>.
        </li>
        <li>
          Type the email address on your account to confirm, then confirm again.
        </li>
      </ol>
      <p>
        Deletion runs immediately: your trades, journal media, backtests, AI reviews, sync tokens
        and profile are removed, followed by the sign-in identity itself. Anything still open in
        another tab or on another device stops working as soon as its session expires.
      </p>

      <h2>Option 2 — by email</h2>
      <p>
        If you cannot sign in, email <strong>support@mtlledger.com</strong> from the address on the
        account with the subject &ldquo;Delete my account&rdquo;. We reply within two business days and
        delete the account within 30 days of confirming you own it.
      </p>

      <h2>What is deleted</h2>
      <ul>
        <li>Your profile: name, email, avatar, plan and trial dates.</li>
        <li>Every trade, including notes, strategy labels, tags and screenshots or voice notes.</li>
        <li>Backtest runs and every AI review generated for you.</li>
        <li>Sync tokens, broker connection details and any pending rotation codes.</li>
      </ul>

      <h2>What is kept, and for how long</h2>
      <ul>
        <li>
          <strong>Payment records.</strong> The payment provider keeps its own transaction history,
          and we keep the minimum record of a completed payment (amount, date, plan, provider
          reference) for tax and accounting obligations. These rows contain no journal content and
          are retained for the period the tax authority requires, then deleted.
        </li>
        <li>
          <strong>Aggregate diagnostics.</strong> Anonymous, non-identifying event counts created
          before deletion may remain in aggregate form; they are not linked back to your account.
        </li>
        <li>
          <strong>Backups.</strong> Encrypted backups are deleted within 30 days, after which
          deleted content is gone from them as well.
        </li>
      </ul>

      <h2>Subscriptions</h2>
      <p>
        A card subscription bought through the website is cancelled when you delete your account: the
        billing agreement is stopped first, and if that cannot be confirmed the deletion is refused so
        a card is never charged for a deleted account. Nothing is deleted until the cancellation has gone
        through.
      </p>
      <p>
        A subscription sold by <strong>Google Play</strong> is different — Google owns that agreement, and no
        app can cancel it. Cancel it in Google Play &rarr; Payments &amp; subscriptions before deleting, or it
        keeps renewing against a Play account that no longer has an MTL Ledger login. If you have already
        deleted and want that charge refunded, email us.
      </p>
      <p>
        A subscription started under our earlier <strong>PayPal</strong> checkout also renews outside this app.
        The deletion form refuses while one is still billing and asks you to email support, so it cannot be
        removed with the charge still running.
      </p>

      <h2>Questions</h2>
      <p>
        See the <Link href="/privacy">Privacy Policy</Link> for what is collected in the first
        place, or <Link href="/support">contact support</Link> if anything here is unclear.
      </p>
    </article>
  )
}
