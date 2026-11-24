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
    a: 'Both are set in Rules with your daily loss limit. In MT5 the two behave the same: while locked, the guard deletes resting orders and closes any position opened after the limit was hit. The difference is the journal. A soft lock, which every paid plan includes, leaves it open, and can be lifted only by writing down a reason that is stored with the day. A hard lock, sold with Pro, closes the journal until the next trading day. Two limits are worth knowing: the guard cannot block a manual market-order click, which fills before the terminal reports it, and it only stops another expert advisor that checks it first. If the journal cannot be reached for five minutes, the lock releases, so an outage can never leave you unable to close a position.',
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
    q: 'What does the AI summary include?',
    a: 'A written summary of the trades already in your journal: a headline, what looks strong, what looks risky, and the numbers each point rests on. It reads your own record and describes it. It does not score you, forecast a market, or recommend a trade. The AI summary is part of Pro, which includes forty a month; the free trial runs at the same allowance so you can judge it before paying.',
  },
  {
    q: 'What is the Pro rules builder?',
    a: 'It is a transcription tool for rules you already use. You describe your entry and exit conditions — typed, spoken, or read from a screenshot — and it turns that description into editable rules you can correct line by line. The rules are only ever tested against saved historical candles: nothing is sent to a broker and no order is placed.',
  },
  {
    q: 'What does the backtester do, and what is market replay?',
    a: 'Both are Pro. The backtester replays saved historical sessions against the rules you wrote and reports how those rules would have performed — win rate, profit factor, expectancy, drawdown and the trades it would have taken. Market replay steps the chart candle by candle so you can walk a session with only the levels you would have had at the time. Neither is connected to a live account, and neither places an order.',
  },
  {
    q: 'How does the prop-firm tracker work?',
    a: 'Enter the evaluation size, profit target, maximum drawdown and consistency limit. The prop screen shows how much of each limit is left and warns when a setup would break one. It tracks and simulates the evaluation; it never places or manages an order.',
  },
  {
    q: 'What are the two ways to sync MT5?',
    a: 'Right now there is one way: your own terminal. Install the guard EA, paste the sync token from the sync page into its inputs, and allow this site under Tools → Options → Expert Advisors → “Allow WebRequest for listed URL”. The guard syncs closed trades and enforces the daily stop set in Rules. The phone-only connection (where you hand over an investor password and our supervisor connects for you) is not open yet, because it needs a host we do not run — a phone cannot run an expert advisor.',
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
