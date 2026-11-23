'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import {
  BarChart3,
  TrendingUp,
  Shield,
  Zap,
  ArrowRight,
  Check,
  CandlestickChart,
  RefreshCw,
  FlaskConical,
  Smartphone,
} from 'lucide-react'
import { PLANS } from '@/lib/plans'
import { formatCurrency } from '@/lib/utils'
import { Logo } from '@/components/logo'
import { GoogleSignInButton } from '@/components/google-signin-button'

const features = [
  {
    icon: CandlestickChart,
    title: 'A real chart desk',
    description:
      'Seconds to daily candles, VWAP and Asia, London and New York levels, drawing tools, saved layouts and templates, and two instruments compared on one screen.',
    tile: 'icon-tile-blue',
  },
  {
    icon: RefreshCw,
    title: 'MT5 auto sync',
    description:
      'Connect your account once and closed trades land here, or import an MT5 report, CSV or XLSX when you would rather do it by hand.',
    tile: 'icon-tile-green',
  },
  {
    icon: Shield,
    title: 'Discipline that holds',
    description:
      'Write your playbook, track prop-firm limits, and set a daily stop whose soft or hard lock the MT5 guard enforces in your terminal.',
    tile: 'icon-tile-amber',
  },
  {
    icon: BarChart3,
    title: 'Analytics that show the pattern',
    description:
      'Win rate, profit factor, expectancy and max drawdown, split by session, symbol, tag and setup, with your best hours and days.',
    tile: 'icon-tile-blue',
  },
  {
    icon: Zap,
    title: 'AI journal summary',
    description:
      'A written summary of the trades you have already logged: how your results broke down by setup, session and day, and what your own notes repeat. It describes your record — it does not rate you or suggest a trade. Fifteen summaries a month on Basic, forty on Pro.',
    tile: 'icon-tile-violet',
  },
  {
    icon: FlaskConical,
    title: 'Backtest and replay',
    description:
      'Pro replays past sessions a candle at a time and tests the entry and exit rules you wrote yourself, reporting win rate, profit factor and drawdown for those rules. A simulation on saved history: nothing connects to a broker and no order is placed.',
    tile: 'icon-tile-amber',
  },
  {
    icon: Smartphone,
    title: 'Phone and web, one account',
    description:
      'The same journal and chart drawings in the browser and the Android app, in 30+ languages, with price alerts pushed to your phone.',
    tile: 'icon-tile-violet',
  },
  {
    icon: TrendingUp,
    title: 'The bigger picture',
    description:
      'Equity curve, P&L calendar, monthly reports and a full account export, so a bad week is visible before it becomes a habit.',
    tile: 'icon-tile-green',
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
      {/* Navigation */}
      <nav className="border-b border-border bg-surface/50 backdrop-blur-sm sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <div className="flex items-center gap-2">
              <Logo size="sm" />
            </div>
            <div className="flex items-center gap-4">
              <Link href="/auth/login" className="text-gray-300 hover:text-white transition-colors">
                Login
              </Link>
              <Link href="/auth/signup" className="bg-primary hover:bg-primary-dark text-white px-4 py-2 rounded-lg transition-colors">
                Get Started Free
              </Link>
            </div>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="py-24 px-4 relative overflow-hidden">
        {/* Ambient background */}
        <div className="absolute inset-0 hero-grid" />
        <div className="hero-blob w-96 h-96 bg-primary top-[-120px] left-[10%]" />
        <div className="hero-blob w-80 h-80 bg-violet-500 top-[-60px] right-[12%]" style={{ animationDelay: '-5s' }} />
        <div className="hero-blob w-72 h-72 bg-primary-light bottom-[-120px] left-[45%]" style={{ animationDelay: '-9s', opacity: 0.22 }} />

        <div className="max-w-7xl mx-auto text-center relative">
          <div className="fade-up">
            <span className="badge-pill mb-8">
              <span className="w-1.5 h-1.5 rounded-full bg-success inline-block" />
              The professional trading journal
            </span>
          </div>
          <h1 className="fade-up-1 text-5xl md:text-7xl font-bold text-white mb-6 tracking-tight">
            Track. Analyze. <span className="text-gradient">Improve.</span>
          </h1>
          <p className="fade-up-2 text-xl text-gray-400 mb-10 max-w-2xl mx-auto">
            A journal that records the trades you take, measures how they performed,
            and keeps the whole history in one place.
          </p>
          <div className="fade-up-3 flex flex-col sm:flex-row gap-4 justify-center">
            <Link href="/auth/signup" className="btn-gradient glow-primary text-white px-8 py-4 rounded-xl text-lg font-semibold flex items-center justify-center gap-2">
              Start Free Trial <ArrowRight className="w-5 h-5" />
            </Link>
            <Link href="#pricing" className="border border-border hover:border-primary text-gray-300 hover:text-white px-8 py-4 rounded-xl text-lg transition-colors">
              View Pricing
            </Link>
          </div>
          <div className="fade-up-3 mt-4 flex justify-center">
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
          <p className="fade-up-3 text-gray-500 mt-5 text-sm">
            No credit card required • Unlimited access for 3 days • Web and Android
          </p>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-4 bg-surface/30">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-3">
              Everything You Need to <span className="text-gradient">Trade Better</span>
            </h2>
            <p className="text-gray-400 max-w-xl mx-auto">
              One place for your trades, your charts, your rules, and the review that ties them together.
            </p>
          </div>
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            {features.map((feature) => (
              <div key={feature.title} className="card-hover bg-surface border border-border rounded-xl p-6">
                <div className={`icon-tile ${feature.tile} mb-5`}>
                  <feature.icon className="w-6 h-6" />
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">{feature.title}</h3>
                <p className="text-gray-400 text-sm leading-relaxed">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Stats Preview */}
      <section className="py-20 px-4">
        <div className="max-w-7xl mx-auto">
          <div className="card-hover bg-surface border border-border rounded-2xl p-8 glow-primary">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
              <div className="text-center">
                <div className="text-3xl md:text-4xl font-bold text-gradient">67.3%</div>
                <div className="text-gray-400 text-sm mt-1">Win Rate</div>
              </div>
              <div className="text-center">
                <div className="text-3xl md:text-4xl font-bold text-gradient">$12,847</div>
                <div className="text-gray-400 text-sm mt-1">Total P&L</div>
              </div>
              <div className="text-center">
                <div className="text-3xl md:text-4xl font-bold text-gradient">2.4</div>
                <div className="text-gray-400 text-sm mt-1">Profit Factor</div>
              </div>
              <div className="text-center">
                <div className="text-3xl md:text-4xl font-bold text-gradient">1:2.8</div>
                <div className="text-gray-400 text-sm mt-1">Avg Risk/Reward</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section id="pricing" className="py-20 px-4 bg-surface/30">
        <div className="max-w-7xl mx-auto">
          <h2 className="text-3xl font-bold text-white text-center mb-4">
            Simple, Transparent Pricing
          </h2>
          <p className="text-gray-400 text-center mb-12">
            Start free, upgrade when you need more
          </p>
          <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            {PLANS.map((plan) => (
              <div
                key={plan.id}
                className={`card-hover bg-surface border rounded-2xl p-8 ${
                  plan.popular ? 'border-primary glow-primary' : 'border-border'
                }`}
              >
                {plan.popular && (
                  <div className="badge-pill mb-3">MOST POPULAR</div>
                )}
                <h3 className="text-2xl font-bold text-white mb-2">{plan.name}</h3>
                <div className="mb-6">
                  <span className="text-4xl font-bold text-white">
                    {plan.price === 0 ? 'Free' : formatCurrency(plan.price)}
                  </span>
                  {plan.price > 0 && <span className="text-gray-400">/month</span>}
                </div>
                <ul className="space-y-3 mb-8">
                  {plan.features.map((feature) => (
                    <li key={feature} className="flex items-center gap-2 text-gray-300 text-sm">
                      <Check className="w-4 h-4 text-success flex-shrink-0" />
                      {feature}
                    </li>
                  ))}
                </ul>
                <Link
                  href="/auth/signup"
                  className={`block w-full text-center py-3 rounded-xl font-semibold transition-colors ${
                    plan.popular
                      ? 'btn-gradient text-white'
                      : 'border border-border hover:border-primary text-gray-300 hover:text-white'
                  }`}
                >
                  {plan.price === 0 ? 'Start Free Trial' : 'Get Started'}
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-4 border-t border-border">
        <div className="max-w-7xl mx-auto flex flex-col items-center justify-between gap-3 text-gray-500 text-sm sm:flex-row">
          <p>
            &copy; 2026 MTL Ledger. All rights reserved.
          </p>
          <p className="max-w-md text-center text-xs text-gray-500 sm:text-left">
            MTL Ledger records and analyses trades you have already made. It is not a broker, it
            does not place orders, and every trade you take is your own.
          </p>
          <nav className="flex flex-wrap items-center justify-center gap-4 text-xs">
            <Link href="/terms" className="hover:text-white transition-colors">Terms</Link>
            <Link href="/privacy" className="hover:text-white transition-colors">Privacy</Link>
            <Link href="/refunds" className="hover:text-white transition-colors">Refunds</Link>
            <Link href="/support" className="hover:text-white transition-colors">Support</Link>
            <a
              href="https://play.google.com/store/apps/details?id=com.mtltrader.app"
              className="hover:text-white transition-colors"
              target="_blank"
              rel="noreferrer"
            >
              Android app
            </a>
          </nav>
        </div>
      </footer>
    </div>
  )
}
