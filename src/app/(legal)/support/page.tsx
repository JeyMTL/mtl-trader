import Link from 'next/link'

export const metadata = {
  title: 'Support',
  description: 'Get help with MTL Trader: billing, your data, imports, and the journal.',
}

const EMAIL = 'jfx064@gmail.com'

const FAQ = [
  {
    q: 'How do I cancel or change my plan?',
    a: 'Settings → Plans & billing. A paid month stays open until the period ends; nothing is charged again after the cancellation. Refunds follow the policy on the refunds page.',
  },
  {
    q: 'Can I get my data out?',
    a: 'Yes. Settings → Data → Export downloads a machine-readable copy of your account and every trade. It is the same data the app shows you, not a summary.',
  },
  {
    q: 'How do I delete my account?',
    a: 'Settings → Data → Delete account. Everything tied to the account is removed after you confirm by email. Export first if you want a copy.',
  },
  {
    q: 'Which files can I import?',
    a: 'MT5 reports (the XML ReportHistory file), MT5 CSV exports, most broker CSVs, and Excel .xlsx — including files saved as CSV with tabs or semicolons instead of commas.',
  },
  {
    q: 'Why do my trade P&L and MT5’s profit column differ?',
    a: 'Trades are stored net: profit plus commission plus swap. MT5 lists those in separate columns, so a single trade differs by its costs while the totals still match MT5’s total net profit.',
  },
  {
    q: 'A chart or a page will not load. What do you need from me?',
    a: 'The time it happened, the email on the account, and the browser or phone you were on. A screenshot of the console is ideal but not required.',
  },
]

export default function SupportPage() {
  return (
    <div className="space-y-8 text-sm leading-relaxed text-gray-300">
      <header className="space-y-3">
        <h1 className="text-3xl font-bold text-white">Support</h1>
        <p>
          A real person reads every message. Most questions are answered the same week, and anything
          that looks like a bug gets a fix rather than a workaround.
        </p>
      </header>

      <section className="rounded-xl border border-border bg-surface p-5">
        <h2 className="text-lg font-semibold text-white">Email us</h2>
        <p className="mt-2">
          <a
            href={`mailto:${EMAIL}?subject=${encodeURIComponent('MTL Trader support')}`}
            className="text-primary font-semibold hover:underline"
          >
            {EMAIL}
          </a>
        </p>
        <p className="mt-3 text-gray-400">
          Include the email on your account, what you expected, and what happened instead. Never send
          your password — nothing in the app needs it, and support will not ask for it.
        </p>
      </section>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-white">Common questions</h2>
        <dl className="space-y-4">
          {FAQ.map((item) => (
            <div key={item.q} className="rounded-xl border border-border bg-surface p-4">
              <dt className="font-semibold text-white">{item.q}</dt>
              <dd className="mt-1.5 text-gray-400">{item.a}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold text-white">Rate the app</h2>
        <p>
          A short review is the cheapest way to help: it is what makes the app findable to the next
          trader. If something is broken, write to support first — a one-star review is harder to
          answer than an email.
        </p>
        <a
          href="https://play.google.com/store/apps/details?id=com.mtltrader.app"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-block rounded-lg bg-primary px-4 py-2 font-semibold text-black"
        >
          Open the Play Store listing
        </a>
      </section>

      <section className="space-y-2 border-t border-border pt-6 text-gray-500">
        <p>
          Billing and refunds are governed by the{' '}
          <Link href="/refunds" className="text-primary hover:underline">
            refund policy
          </Link>
          , and the service by the{' '}
          <Link href="/terms" className="text-primary hover:underline">
            terms
          </Link>
          . What is stored, and what is not, is in the{' '}
          <Link href="/privacy" className="text-primary hover:underline">
            privacy policy
          </Link>
          .
        </p>
      </section>
    </div>
  )
}
