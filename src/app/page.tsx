'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { TRIAL_CTA, TRIAL_DAYS, TRIAL_TRUST_LINE } from '@/lib/subscription'
import {
  BarChart3,
  TrendingUp,
  Shield,
  ArrowRight,
  CandlestickChart,
  RefreshCw,
  FlaskConical,
  Smartphone,
  ChevronDown,
  Languages,
} from 'lucide-react'
import { PLAN_TAGLINES, PLANS } from '@/lib/plans'
import { formatCurrency } from '@/lib/utils'
import { Logo } from '@/components/logo'
import { GoogleSignInButton } from '@/components/google-signin-button'
import { PlanFeatureGroups } from '@/components/plan-feature-groups'
import { ProductPreview } from '@/components/landing/product-preview'
import { LanguagePicker } from '@/components/language-picker'

const features = [
  {
    icon: CandlestickChart,
    title: 'A real chart desk',
    description:
      'Seconds to daily candles, VWAP, session levels and drawings synced across web and Android.',
    tile: 'icon-tile-blue',
  },
  {
    icon: RefreshCw,
    title: 'MT5 auto sync',
    description:
      'Connect once and closed trades land here, or import MT5 reports, CSV and XLSX files.',
    tile: 'icon-tile-green',
  },
  {
    icon: Shield,
    title: 'Daily-stop guard',
    description:
      'Prop-firm limits plus a soft or hard daily stop enforced in your MT5 terminal.',
    tile: 'icon-tile-amber',
  },
  {
    icon: BarChart3,
    title: 'Analytics by setup',
    description:
      'Win rate, profit factor, expectancy and drawdown split by session, symbol and setup.',
    tile: 'icon-tile-blue',
  },
  {
    icon: TrendingUp,
    title: 'P&L calendar',
    description:
      'Equity curve, green and red P&L calendar, monthly reports and full account export.',
    tile: 'icon-tile-green',
  },
  {
    icon: FlaskConical,
    title: 'Backtest and replay',
    description:
      'Replay sessions candle by candle and test your own rules against saved history.',
    tile: 'icon-tile-amber',
  },
  {
    icon: Smartphone,
    title: 'Web and Android',
    description:
      'One account and the same journal; the Android app adds 30+ downloadable languages.',
    tile: 'icon-tile-violet',
  },
  {
    icon: Shield,
    title: 'Prop-firm simulator',
    description:
      'Check daily loss, drawdown, target and consistency rules before you risk a funded account.',
    tile: 'icon-tile-violet',
  },
]

const workflow = [
  {
    step: '01',
    title: 'Sync',
    description: 'MT5 trades, reports and imports land in one journal.',
    icon: RefreshCw,
  },
  {
    step: '02',
    title: 'Guard',
    description: 'Daily stop and prop-firm limits hold in the terminal.',
    icon: Shield,
  },
  {
    step: '03',
    title: 'Review',
    description: 'Analytics and AI reviews show what keeps repeating.',
    icon: BarChart3,
  },
  {
    step: '04',
    title: 'Backtest',
    description: 'Turn the pattern into rules and test it on saved history.',
    icon: FlaskConical,
  },
]

const faqs = [
  {
    question: 'Does MTL Ledger place trades for me?',
    answer:
      'No. It records and analyses trades you have already made. The daily-stop guard can clear resting orders and close post-stop fills in MT5, but it never opens a position.',
  },
  {
    question: 'What can I connect?',
    answer:
      'MT5 auto sync, plus MT5 reports, XML, CSV and XLSX imports. The Android app and the web app share one account, so the journal, drawings and layouts stay together.',
  },
  {
    question: 'What do I get in the free trial?',
    answer: `${TRIAL_DAYS} days of every Pro tool with no card required, including one AI review and one backtest a day. When the trial ends, the Free tier keeps 30 trades a month, the journal, the market view and the prop-firm simulator.`,
  },
  {
    question: 'Can I cancel a paid plan?',
    answer:
      'Yes. Card subscriptions renew monthly or yearly and can be stopped from Settings at any time. Access continues until the paid period ends.',
  },
]

export default function HomePage() {
  const [googleLoading, setGoogleLoading] = useState(false)
  const [authError, setAuthError] = useState('')

  // Supabase substitutes the project's Site URL whenever the requested redirect
  // is not allow-listed, which delivers the PKCE `code` to `/` instead of
  // `/auth/callback`. Without this the sign-in appears to do nothing: the code
  // is never exchanged and the user bounces back to the marketing page. Forward
  // it, carrying any error Supabase appended so the callback can explain itself.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const code = params.get('code')
    const forward = new URLSearchParams()
    if (code) forward.set('code', code)
    for (const key of ['error', 'error_code', 'error_description']) {
      const value = params.get(key)
      if (value) forward.set(key, value)
    }
    if (!forward.toString()) return
    window.location.replace(`/auth/callback?${forward.toString()}`)
  }, [])

  return (
    <div className="min-h-screen bg-background">
      <nav className="sticky top-0 z-50 border-b border-border bg-surface/50 backdrop-blur-sm">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex h-16 items-center justify-between">
            <Link href="/" className="flex items-center gap-2">
              <Logo size="sm" />
            </Link>
            <div className="hidden items-center gap-7 text-sm text-gray-400 md:flex">
              <a href="#features" className="transition-colors hover:text-white">Features</a>
              <a href="#workflows" className="transition-colors hover:text-white">Workflows</a>
              <a href="#pricing" className="transition-colors hover:text-white">Pricing</a>
              <a href="#faq" className="transition-colors hover:text-white">FAQ</a>
            </div>
            <div className="flex items-center gap-3 sm:gap-4">
              <LanguagePicker className="hidden sm:inline-flex" />
              <Link href="/auth/login" className="hidden text-sm text-gray-300 transition-colors hover:text-white sm:inline">
                Login
              </Link>
              <Link href="/auth/signup" className="rounded-lg bg-primary px-4 py-2 text-sm text-white transition-colors hover:bg-primary-dark">
                Start free trial
              </Link>
            </div>
          </div>
        </div>
      </nav>

      <section className="relative overflow-hidden px-4 pb-16 pt-20 sm:pt-24">
        <div className="absolute inset-0 hero-grid" />
        <div className="hero-blob left-[10%] top-[-120px] h-96 w-96 bg-primary" />
        <div className="hero-blob right-[12%] top-[-60px] h-80 w-80 bg-violet-500" style={{ animationDelay: '-5s' }} />
        <div className="hero-blob bottom-[-120px] left-[45%] h-72 w-72 bg-primary-light" style={{ animationDelay: '-9s', opacity: 0.22 }} />

        <div className="relative mx-auto max-w-7xl text-center">
          <div className="fade-up">
            <span className="badge-pill mb-8">
              <span className="inline-block h-1.5 w-1.5 rounded-full bg-success" />
              The professional trading journal
            </span>
          </div>
          <h1 className="fade-up-1 mb-6 text-5xl font-bold tracking-tight text-white md:text-6xl">
            Track. Analyze. <span className="text-gradient">Improve.</span>
          </h1>
          <p className="fade-up-2 mx-auto mb-9 max-w-2xl text-lg text-gray-400 sm:text-xl">
            Record every trade you take, measure how each setup performs, and turn the
            history into a plan. Built for MT5 traders on web and Android.
          </p>
          <div className="fade-up-3 flex flex-col justify-center gap-4 sm:flex-row">
            <Link href="/auth/signup" className="btn-gradient glow-primary flex items-center justify-center gap-2 rounded-xl px-8 py-4 text-lg font-semibold text-white">
              {TRIAL_CTA} <ArrowRight className="h-5 w-5" />
            </Link>
            <Link href="#pricing" className="rounded-xl border border-border px-8 py-4 text-lg text-gray-300 transition-colors hover:border-primary hover:text-white">
              View pricing
            </Link>
          </div>
          <p className="fade-up-3 mt-4 text-sm text-gray-500">{TRIAL_TRUST_LINE}</p>
          <div className="fade-up-3 mt-6 flex justify-center">
            <GoogleSignInButton
              text="signin_with"
              disabled={googleLoading}
              onStart={() => {
                setGoogleLoading(true)
                setAuthError('')
              }}
              onError={(message) => {
                setAuthError(message)
                setGoogleLoading(false)
              }}
            />
          </div>
          {authError && (
            <p className="mt-3 text-sm text-danger">{authError}</p>
          )}
          {/* The four claims the hero is making, in the order a phone trader
              cares about them: where the trades come from, what language they
              read in, where the app runs, and that the chart is not a mock. */}
          <div className="fade-up-3 mt-9 flex flex-wrap items-center justify-center gap-x-8 gap-y-3 text-sm text-gray-400">
            {[
              { icon: RefreshCw, label: 'MT5 Auto-Sync' },
              { icon: Languages, label: '30+ Languages' },
              { icon: Smartphone, label: 'Android & Web App' },
              { icon: CandlestickChart, label: 'Live chart data' },
            ].map((item) => (
              <span key={item.label} className="flex items-center gap-2">
                <item.icon className="h-4 w-4 text-primary-light" />
                {item.label}
              </span>
            ))}
          </div>
        </div>

        <div className="relative mt-14">
          <ProductPreview />
        </div>
      </section>

      <section id="features" className="scroll-mt-24 bg-surface/30 px-4 py-20">
        <div className="mx-auto max-w-7xl">
          <div className="mb-12 text-center">
            <p className="mb-3 text-xs font-semibold uppercase tracking-[0.16em] text-primary-light">
              Everything in one place
            </p>
            <h2 className="mb-3 text-3xl font-bold text-white md:text-4xl">
              The toolkit, without the tab-switching
            </h2>
            <p className="mx-auto max-w-xl text-gray-400">
              Journal, charting, risk controls and review share the same trades.
            </p>
          </div>
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            {features.map((feature) => (
              <div key={feature.title} className="card-hover rounded-xl border border-border bg-surface p-5">
                <div className={`icon-tile ${feature.tile} mb-4`}>
                  <feature.icon className="h-6 w-6" />
                </div>
                <h3 className="mb-2 text-base font-semibold text-white">{feature.title}</h3>
                <p className="text-sm leading-relaxed text-gray-400">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="workflows" className="scroll-mt-24 px-4 py-20">
        <div className="mx-auto max-w-7xl">
          <div className="mb-12 max-w-2xl">
            <p className="mb-3 text-xs font-semibold uppercase tracking-[0.16em] text-primary-light">
              One daily loop
            </p>
            <h2 className="mb-3 text-3xl font-bold text-white md:text-4xl">
              From terminal to next decision
            </h2>
            <p className="text-gray-400">
              Each step hands the next one its context, so a review starts from the trade
              instead of a blank page.
            </p>
          </div>
          <div className="grid gap-4 md:grid-cols-4">
            {workflow.map((item) => (
              <div key={item.step} className="relative rounded-xl border border-border bg-surface p-5">
                <div className="mb-5 flex items-center justify-between">
                  <span className="text-xs font-semibold tabular-nums text-gray-600">{item.step}</span>
                  <item.icon className="h-5 w-5 text-primary-light" />
                </div>
                <h3 className="mb-1.5 text-base font-semibold text-white">{item.title}</h3>
                <p className="text-sm leading-relaxed text-gray-400">{item.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="pricing" className="scroll-mt-24 bg-surface/30 px-4 py-20">
        <div className="mx-auto max-w-6xl">
          <div className="mb-12 text-center">
            <h2 className="mb-3 text-3xl font-bold text-white md:text-4xl">
              Simple, transparent pricing
            </h2>
            <p className="mx-auto max-w-2xl text-gray-400">
              {TRIAL_TRUST_LINE}. Upgrade only when the free tier stops being enough.
            </p>
          </div>
          <div className="grid gap-6 md:grid-cols-3">
            {PLANS.map((plan) => (
              <div
                key={plan.id}
                className={`card-hover flex h-full flex-col rounded-2xl border bg-surface p-6 sm:p-7 ${
                  plan.popular ? 'border-primary glow-primary' : 'border-border'
                }`}
              >
                {plan.popular && (
                  <div className="badge-pill mb-4 w-fit">MOST POPULAR</div>
                )}
                <h3 className="text-xl font-bold text-white">{plan.name}</h3>
                <p className="mt-1.5 min-h-10 text-sm text-gray-500">{PLAN_TAGLINES[plan.id]}</p>
                <div className="mb-6 mt-5">
                  <span className="text-4xl font-bold tabular-nums text-white">
                    {plan.price === 0 ? 'Free' : formatCurrency(plan.price)}
                  </span>
                  {plan.price > 0 && <span className="text-gray-400">/month</span>}
                </div>
                <div className="flex-1">
                  <PlanFeatureGroups plan={plan} perGroup={2} />
                </div>
                <Link
                  href={plan.price === 0 ? '/auth/signup' : '/pricing'}
                  className={`mt-8 block w-full rounded-xl py-3 text-center font-semibold transition-colors ${
                    plan.popular
                      ? 'btn-gradient text-white'
                      : 'border border-border text-gray-300 hover:border-primary hover:text-white'
                  }`}
                >
                  {plan.price === 0 ? TRIAL_CTA : `Choose ${plan.name}`}
                </Link>
                <Link href="/pricing" className="mt-3 text-center text-xs text-gray-500 transition-colors hover:text-white">
                  Compare all features
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="faq" className="scroll-mt-24 px-4 py-20">
        <div className="mx-auto max-w-4xl">
          <div className="mb-10 text-center">
            <h2 className="mb-3 text-3xl font-bold text-white md:text-4xl">Questions, answered</h2>
            <p className="text-gray-400">The short version before you open an account.</p>
          </div>
          <div className="grid gap-3 md:grid-cols-2">
            {faqs.map((faq) => (
              <details key={faq.question} className="group rounded-xl border border-border bg-surface p-5">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-sm font-medium text-white [&::-webkit-details-marker]:hidden">
                  {faq.question}
                  <ChevronDown className="h-4 w-4 shrink-0 text-gray-500 transition-transform group-open:rotate-180" />
                </summary>
                <p className="mt-3 text-sm leading-relaxed text-gray-400">{faq.answer}</p>
              </details>
            ))}
          </div>
          <p className="mt-6 text-center text-sm text-gray-500">
            Need more detail? <Link href="/faq" className="text-primary-light hover:text-white">Read the full FAQ</Link>.
          </p>
        </div>
      </section>

      <footer className="border-t border-border px-4 py-12">
        <div className="mx-auto max-w-7xl">
          <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <Logo size="sm" />
              <p className="mt-4 max-w-xs text-sm leading-relaxed text-gray-500">
                A trading journal, chart desk and backtester for MT5 traders. Web and Android,
                one account.
              </p>
            </div>
            <div>
              <h3 className="mb-4 text-xs font-semibold uppercase tracking-[0.14em] text-gray-500">Product</h3>
              <ul className="space-y-2.5 text-sm text-gray-400">
                <li><a href="#features" className="hover:text-white">Features</a></li>
                <li><a href="#workflows" className="hover:text-white">Workflows</a></li>
                <li><Link href="/pricing" className="hover:text-white">Pricing</Link></li>
                <li><a href="https://play.google.com/store/apps/details?id=com.mtltrader.app" className="hover:text-white" target="_blank" rel="noreferrer">Android app</a></li>
              </ul>
            </div>
            <div>
              <h3 className="mb-4 text-xs font-semibold uppercase tracking-[0.14em] text-gray-500">Support</h3>
              <ul className="space-y-2.5 text-sm text-gray-400">
                <li><Link href="/support" className="hover:text-white">Contact support</Link></li>
                <li><Link href="/faq" className="hover:text-white">FAQ</Link></li>
                <li><Link href="/delete-account" className="hover:text-white">Delete account</Link></li>
              </ul>
            </div>
            <div>
              <h3 className="mb-4 text-xs font-semibold uppercase tracking-[0.14em] text-gray-500">Legal</h3>
              <ul className="space-y-2.5 text-sm text-gray-400">
                <li><Link href="/terms" className="hover:text-white">Terms</Link></li>
                <li><Link href="/privacy" className="hover:text-white">Privacy</Link></li>
                <li><Link href="/refunds" className="hover:text-white">Refunds</Link></li>
              </ul>
            </div>
          </div>
          <div className="mt-10 flex flex-col gap-3 border-t border-border pt-6 text-xs text-gray-600 sm:flex-row sm:items-center sm:justify-between">
            <p>&copy; 2026 MTL Ledger. All rights reserved.</p>
            <p className="max-w-xl sm:text-right">
              MTL Ledger records and analyses trades you have already made. It is not a broker,
              it does not place orders, and every trade you take is your own.
            </p>
          </div>
        </div>
      </footer>
    </div>
  )
}
