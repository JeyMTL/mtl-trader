import Link from 'next/link'

export const metadata = {
  title: 'Support',
  description: 'Get help with MTL Ledger: billing, your data, imports, and the journal.',
}

const EMAIL = 'support@mtlledger.com'

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
    q: 'How do I pin entry, stop and target levels from a chart?',
    a: 'Open the trade form and choose Pin levels from chart. The live chart opens with three markers: tap the price you want for entry, stop or target and it fills the form, so nothing is typed from another window. The same markers can be dragged on the phone\u2019s chart before you save the trade.',
  },
  {
    q: 'What is the difference between a soft lock and a hard lock?',
    a: 'Both are set in Rules with your daily loss limit. A soft lock freezes MT5 and keeps the journal open, and can be lifted only by writing down a reason that is stored with the day. A hard lock freezes MT5 and locks the journal completely until the next trading day, with no release. The MT5 guard that syncs your trades enforces it in the terminal: it refuses programmatic orders and deletes pending ones, though a manual market order can still fill before it is seen.',
  },
  {
    q: 'What is in the chart desk?',
    a: 'Candles from seconds to daily, session VWAP and Asia, London and New York high/low levels, and drawing tools for levels, trends, fibs, zones, vertical lines and measurements. You can pin entry, stop and target straight off the chart, compare a second instrument, save layouts and templates, and open the whole desk full screen. Settings cover precision, a log scale, the 24-hour clock, countdown to bar close and the canvas background.',
  },
  {
    q: 'Where do price alerts arrive?',
    a: 'On the web an alert is a line on the chart: it fires visibly and can be hidden once fired, but it does not message you while the tab is closed. On Android the same price levels become local push notifications — allow notifications, then use Send test alert in Alerts to check that the phone receives one.',
  },
  {
    q: 'What does the backtester do, and what is market replay?',
    a: 'Both are Pro. The backtester runs saved tests and can suggest rules from your own trades. The compiler turns a plain-English description, a voice note or a screenshot into runnable rules that you read and correct before anything runs. Market replay steps the chart candle by candle so you can rehearse a session with the levels you would have had.',
  },
  {
    q: 'How does the prop-firm tracker work?',
    a: 'Enter the evaluation size, profit target, maximum drawdown and consistency limit. The prop screen shows how much of each limit is left and warns when a setup would break one. It tracks and simulates the evaluation; it never places or manages an order.',
  },
  {
    q: 'What are the two ways to sync MT5?',
    a: 'Hosted sync asks for your broker, server, account number and the investor (read-only) password once, then our supervisor connects for you. The other way is your own terminal: install the guard EA and paste the sync token from the sync page into its inputs. Hosted sync stores the investor password encrypted so it can reconnect; your trading password is never asked for, and Disconnect deletes the stored password. The guard also enforces the daily stop.',
  },
  {
    q: 'Which languages does the app support, and does it work offline?',
    a: 'The Android app has a language picker backed by downloadable packs, with more than thirty languages. The web app is in English. The phone also keeps the chart candles it has already loaded, so if the feed drops it shows that saved copy and the time it was fetched instead of an empty chart.',
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
            href={`mailto:${EMAIL}?subject=${encodeURIComponent('MTL Ledger support')}`}
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
