'use client'

import Link from 'next/link'
import { BarChart3, TrendingUp, Shield, Zap, ArrowRight, Check } from 'lucide-react'
import { PLANS } from '@/lib/plans'
import { formatCurrency } from '@/lib/utils'
import { Logo } from '@/components/logo'

const features = [
  {
    icon: BarChart3,
    title: 'Advanced Analytics',
    description: 'Deep insights into your trading performance with win rate, profit factor, and risk/reward analysis.',
    tile: 'icon-tile-blue',
  },
  {
    icon: TrendingUp,
    title: 'Equity Curve',
    description: 'Visualize your account growth over time with beautiful interactive charts.',
    tile: 'icon-tile-green',
  },
  {
    icon: Shield,
    title: 'Risk Management',
    description: 'Track drawdowns, position sizes, and risk per trade to protect your capital.',
    tile: 'icon-tile-amber',
  },
  {
    icon: Zap,
    title: 'MT5 Integration',
    description: 'Import trades directly from MetaTrader 5 with CSV upload or real-time sync.',
    tile: 'icon-tile-violet',
  },
]

export default function HomePage() {
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
            The professional trading journal that helps you identify patterns,
            eliminate mistakes, and maximize your trading edge.
          </p>
          <div className="fade-up-3 flex flex-col sm:flex-row gap-4 justify-center">
            <Link href="/auth/signup" className="btn-gradient glow-primary text-white px-8 py-4 rounded-xl text-lg font-semibold flex items-center justify-center gap-2">
              Start Free Trial <ArrowRight className="w-5 h-5" />
            </Link>
            <Link href="#pricing" className="border border-border hover:border-primary text-gray-300 hover:text-white px-8 py-4 rounded-xl text-lg transition-colors">
              View Pricing
            </Link>
          </div>
          <p className="fade-up-3 text-gray-500 mt-5 text-sm">No credit card required • Unlimited access for 30 days</p>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-4 bg-surface/30">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-3">
              Everything You Need to <span className="text-gradient">Trade Better</span>
            </h2>
            <p className="text-gray-400 max-w-xl mx-auto">One place for your trades, analytics, and growth.</p>
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
        <div className="max-w-7xl mx-auto text-center text-gray-500 text-sm">
          <p>&copy; 2026 MTL Trader. All rights reserved.</p>
        </div>
      </footer>
    </div>
  )
}
