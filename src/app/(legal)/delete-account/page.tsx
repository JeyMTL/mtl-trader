import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Delete your account',
  description:
    'How to delete your MTL Trader account and everything attached to it, from the app or by email.',
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
        You can delete your MTL Trader account and every trade, photo, note and backtest stored
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
        If you cannot sign in, email <strong>jfx064@gmail.com</strong> from the address on the
        account with the subject &ldquo;Delete my account&rdquo;. We reply within two business days and
        delete the account within 30 days of confirming you own it.
      </p>

      <h2>What is deleted</h2>
      <ul>
        <li>Your profile: name, email, avatar, plan and trial dates.</li>
        <li>Every trade, including notes, strategy labels, tags and screenshots or voice notes.</li>
        <li>Backtest runs and saved drawings, and every AI review generated for you.</li>
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
          <strong>Backups.</strong> Encrypted database backups roll off within 30 days, after which
          deleted content is gone from them as well.
        </li>
      </ul>

      <h2>Cancelling a subscription first</h2>
      <p>
        Deleting your account does not automatically cancel a card subscription — the payment
        provider bills independently of the app. Cancel from{' '}
        <Link href="/dashboard/settings">Settings</Link> before you delete, or the card keeps
        renewing with no account to apply it to. If that happens, email us and we will cancel it and
        refund any charge taken after the deletion.
      </p>

      <h2>Questions</h2>
      <p>
        See the <Link href="/privacy">Privacy Policy</Link> for what is collected in the first
        place, or <Link href="/support">contact support</Link> if anything here is unclear.
      </p>
    </article>
  )
}
