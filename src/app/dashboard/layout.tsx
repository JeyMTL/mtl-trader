'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import {
  LayoutDashboard,
  TrendingUp,
  BarChart3,
  Settings,
  LogOut,
  Upload,
  Plus,
  Shield,
  Calendar,
  RefreshCw,
  MoreHorizontal,
  ChevronRight,
  ChevronLeft,
  X,
  FlaskConical,
  BookOpenCheck,
  Lock,
} from 'lucide-react'
import { useState, useEffect, useCallback } from 'react'
import { cn } from '@/lib/utils'
import { HelpCircle } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { effectiveMaxTrades } from '@/lib/subscription'
import { MT5_SYNC_ENABLED } from '@/lib/features'
import { Logo } from '@/components/logo'
import { Avatar } from '@/components/avatar'
import { useBackButton, useHaptics } from '@/hooks/useCapacitor'

const navigation = [
  { name: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { name: 'Add Trade', href: '/dashboard/trades/new', icon: Plus },
  { name: 'Trades', href: '/dashboard/trades', icon: TrendingUp },
  { name: 'Import', href: '/dashboard/import', icon: Upload },
  { name: 'MT5 Sync', href: '/dashboard/sync', icon: RefreshCw },
  { name: 'Analytics', href: '/dashboard/analytics', icon: BarChart3 },
  { name: 'Backtest', href: '/dashboard/backtest', icon: FlaskConical },
  { name: 'Rules', href: '/dashboard/playbook', icon: BookOpenCheck },
  { name: 'Calendar', href: '/dashboard/calendar', icon: Calendar },
  { name: 'Settings', href: '/dashboard/settings', icon: Settings },
  { name: 'Support', href: '/support', icon: HelpCircle },
]

/** Destinations the server withholds from Basic accounts (see `plan-guard`). */
const PRO_ONLY_HREFS = ['/dashboard/backtest']

/** Everything that does not fit in five bottom tabs lives in the sheet. */
const moreNavigation = [
  { name: 'Calendar', href: '/dashboard/calendar', icon: Calendar },
  { name: 'Import trades', href: '/dashboard/import', icon: Upload },
  { name: 'MT5 auto sync', href: '/dashboard/sync', icon: RefreshCw },
  { name: 'Backtest', href: '/dashboard/backtest', icon: FlaskConical },
  { name: 'Rules', href: '/dashboard/playbook', icon: BookOpenCheck },
  { name: 'Settings', href: '/dashboard/settings', icon: Settings },
  { name: 'Support', href: '/support', icon: HelpCircle },
]

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const pathname = usePathname()
  const router = useRouter()
  const { trigger } = useHaptics()
  const [sheetOpen, setSheetOpen] = useState(false)
  const [authChecked, setAuthChecked] = useState(false)
  const [user, setUser] = useState<{
    tier: string
    status: string
    isAdmin: boolean
    maxTrades: number
    tradesUsed: number
    trialEndsAt: string | null
    fullName: string | null
    email: string | null
    avatarUrl: string | null
  } | null>(null)
  const [trialDaysLeft, setTrialDaysLeft] = useState(0)

  useEffect(() => {
    async function loadUser() {
      const { data: { user: authUser } } = await supabase.auth.getUser()
      if (!authUser || !authUser.email_confirmed_at) {
        if (authUser) await supabase.auth.signOut()
        router.push('/auth/login')
        return
      }
      let { data } = await supabase
        .from('users')
        .select('full_name, email, subscription_tier, subscription_status, max_trades, trial_ends_at, current_period_end, cancel_at_period_end, is_admin')
        .eq('id', authUser.id)
        .single()

      if (!data) {
        // No profile row: report "no plan" instead of inventing a trial the
        // database does not know about. A fabricated trial would show days left
        // that `enforce_trade_quota` has never agreed to.
        data = {
          full_name: null,
          email: authUser.email ?? null,
          subscription_tier: 'free',
          subscription_status: 'expired',
          max_trades: 0,
          trial_ends_at: null,
          current_period_end: null,
          cancel_at_period_end: false,
          is_admin: false,
        }
      }

      // Counted by the same definition of "this month" as the insert trigger,
      // so the meter cannot promise room the database will refuse.
      const { data: monthCount } = await supabase.rpc('month_trade_count')
      const count = typeof monthCount === 'number' ? monthCount : Number(monthCount ?? 0)

      setUser({
        tier: data.subscription_tier || 'free',
        status: data.subscription_status || 'trial',
        isAdmin: data.is_admin === true,
        maxTrades: effectiveMaxTrades(data),
        tradesUsed: count,
        trialEndsAt: data.trial_ends_at,
        fullName: data.full_name ?? null,
        email: data.email ?? authUser.email ?? null,
        // Google sign-in puts the profile photo in the auth metadata; an email
        // account has none, so the Avatar falls through to Gravatar/initials.
        avatarUrl:
          (authUser.user_metadata?.avatar_url as string | undefined) ??
          (authUser.user_metadata?.picture as string | undefined) ??
          null,
      })
      if (data.trial_ends_at) {
        setTrialDaysLeft(Math.max(0, Math.ceil((new Date(data.trial_ends_at).getTime() - Date.now()) / (1000 * 60 * 60 * 24))))
      }
      setAuthChecked(true)
    }
    loadUser()
  }, [router])

  const openSheet = useCallback(() => {
    trigger('light')
    setSheetOpen(true)
  }, [trigger])

  // Tapping the tab you are already on scrolls to the top, like a native app.
  const handleTabClick = (active: boolean) => {
    trigger('light')
    if (active && typeof window !== 'undefined') {
      window.scrollTo({ top: 0, behavior: 'smooth' })
    }
  }

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/')
  }

  const handleBackButton = useCallback(() => {
    if (sheetOpen) {
      setSheetOpen(false)
    } else {
      router.back()
    }
  }, [sheetOpen, router])

  useBackButton(handleBackButton)

  if (!authChecked) {
    return <div className="min-h-dvh bg-background" />
  }

  const trialProgress = user?.maxTrades && user.maxTrades > 0
    ? Math.min(100, (user.tradesUsed / user.maxTrades) * 100)
    : 0

  const tradesRemaining = user?.maxTrades === -1 || !user
    ? null
    : Math.max(0, user.maxTrades - user.tradesUsed)

  const isPro = user?.tier === 'pro'
  const isBasic = user?.tier === 'basic'

  // The backtester is Pro, and a live trial counts. Hiding the entry beats a
  // nav item that answers 402: the server still refuses a direct URL, so this is
  // presentation, not enforcement. Autosync is available from Basic.
  const proTools = isPro || user?.status === 'trial'
  // MT5 sync is built but not sold while the hosted agent has no funding behind
  // it, so its entry point is filtered out rather than deleted: the route, the
  // credentials store and the supervisor stay, and `MT5_SYNC_ENABLED` brings the
  // link back in one line. See `src/lib/features.ts`.
  const hiddenHrefs = MT5_SYNC_ENABLED ? [] : ['/dashboard/sync']
  const isVisible = (href: string) =>
    (proTools || !PRO_ONLY_HREFS.includes(href)) && !hiddenHrefs.includes(href)
  const visibleNavigation = navigation.filter((item) => isVisible(item.href))
  const visibleMoreNavigation = moreNavigation.filter((item) => isVisible(item.href))

  // `maxTrades` is already the effective allowance, so zero means the period or
  // trial has ended. That covers a lapsed trial and a lapsed paid period without
  // guessing from the stored status label, which may still say `pro`.
  const readOnly = user ? user.maxTrades === 0 : false

  const planLabel = !user
    ? ''
    : user.status === 'active'
      ? (isPro ? 'Pro' : isBasic ? 'Basic' : 'Paid')
      : user.status === 'trial'
        ? `${trialDaysLeft}d trial`
        : 'Free'

  const isActive = (href: string) => {
    if (href === '/dashboard') return pathname === '/dashboard'
    // The Add screen is its own tab, so it must not light up "Trades".
    if (href === '/dashboard/trades') {
      return pathname.startsWith('/dashboard/trades') && !pathname.startsWith('/dashboard/trades/new')
    }
    return pathname === href || pathname.startsWith(href + '/')
  }

  // Inner screens get a native back affordance; tab roots show the brand.
  const subRouteTitles: Record<string, string> = {
    '/dashboard/trades/new': 'Add trade',
    '/dashboard/import': 'Import trades',
    '/dashboard/calendar': 'Calendar',
    '/dashboard/settings': 'Settings',
    '/dashboard/payment': 'Payment',
    '/dashboard/admin': 'Admin',
    '/dashboard/playbook': 'Rules',
  }
  const subRouteTitle = pathname.startsWith('/dashboard/trades/') && pathname.endsWith('/edit')
    ? 'Edit trade'
    : subRouteTitles[pathname]

  const tabClass = (active: boolean) =>
    cn(
      'flex h-full flex-col items-center justify-center gap-1 text-[10px] font-medium transition-colors active:opacity-60',
      active ? 'text-primary' : 'text-gray-500'
    )

  return (
    <div className="min-h-dvh bg-background">
      {/* Desktop sidebar */}
      <aside className="hidden lg:flex lg:fixed lg:inset-y-0 lg:left-0 lg:z-30 lg:w-64 lg:flex-col bg-surface border-r border-border">
        <div className="flex items-center justify-between h-16 px-4 border-b border-border">
          <Link href="/dashboard" className="flex items-center gap-2">
            <Logo size="sm" />
          </Link>
        </div>

        <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
          {visibleNavigation.map((item) => {
            const active = pathname === item.href
            return (
              <Link
                key={item.name}
                href={item.href}
                className={cn(
                  'flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors',
                  active
                    ? 'nav-active'
                    : 'text-gray-400 hover:text-white hover:bg-surface-light'
                )}
              >
                <item.icon className="w-5 h-5" />
                {item.name}
              </Link>
            )
          })}
          {user?.isAdmin && (
            <Link
              href="/dashboard/admin"
              className={cn(
                'flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors',
                pathname === '/dashboard/admin'
                  ? 'nav-active'
                  : 'text-gray-400 hover:text-white hover:bg-surface-light'
              )}
            >
              <Shield className="w-5 h-5" />
              Admin
            </Link>
          )}
        </nav>

        <div className="p-3 border-t border-border">
          {user && (
            <div className="bg-surface-light rounded-lg p-3 mb-3">
              <div className="text-xs text-gray-400">
                {isPro
                  ? 'Pro Plan'
                  : isBasic
                    ? 'Basic Plan'
                    : user.status === 'trial'
                      ? '14-Day Free Trial'
                      : 'Free plan'}
              </div>
              <div className="text-sm text-white font-medium">
                {user.status === 'active' ? (isPro ? 'Unlimited trades' : `${tradesRemaining} / ${user.maxTrades} trades remaining this month`) :
                 user.status === 'trial' ? `${trialDaysLeft} days remaining, unlimited trades` :
                 'Read-only — journal safe'}
              </div>
              {!proTools && (
                <Link href="/pricing" className="mt-2 block text-xs font-semibold text-primary hover:underline">
                  Unlock the backtester →
                </Link>
              )}
              {!isPro && user.status !== 'trial' && (
                <div className="w-full bg-background rounded-full h-2 mt-2">
                  <div className="bg-primary h-2 rounded-full" style={{ width: `${trialProgress}%` }} />
                </div>
              )}
            </div>
          )}
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium text-gray-400 hover:text-white hover:bg-surface-light transition-colors"
          >
            <LogOut className="w-5 h-5" />
            Logout
          </button>
        </div>
      </aside>

      <div className="lg:pl-64 min-h-dvh flex flex-col">
        {/* Desktop header */}
        <header className="hidden lg:flex sticky top-0 z-30 bg-surface/50 backdrop-blur-sm border-b border-border min-h-16 items-center px-6 py-2">
          <div className="flex-1" />
          <div className="flex items-center gap-4 min-w-0">
            {user && (
              <div className="text-sm text-gray-400 truncate">
                {isPro ? 'Unlimited trades' : user.maxTrades === 0 ? (
                  'Read-only — journal safe'
                ) : (
                  <><span className="text-white font-medium">{tradesRemaining}</span> / {user.maxTrades} trades remaining this month</>
                )}
              </div>
            )}
            <Link href="/pricing" className="btn-gradient text-white px-4 py-2 rounded-lg text-sm font-medium whitespace-nowrap">
              Upgrade
            </Link>
          </div>
        </header>

        <main className="flex-1 px-4 lg:p-6 mobile-main">
          {/* The end of a period must read as a pause, not a loss: the trigger
              refuses new trades, it never deletes anything. */}
          {readOnly && (
            <div className="mb-4 flex flex-col gap-3 rounded-xl border border-primary/40 bg-primary/10 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex items-start gap-2.5">
                <Lock className="mt-0.5 h-4 w-4 shrink-0 text-primary-light" />
                <p className="text-sm leading-relaxed text-primary-light">
                  <span className="font-semibold text-white">Your trial has ended.</span>{' '}
                  Nothing was deleted — your journal, photos and analytics are still here and
                  readable. Choose a plan to log new trades.
                </p>
              </div>
              <Link
                href="/pricing"
                className="btn btn-primary shrink-0 self-start px-3 py-1.5 text-xs sm:self-auto"
              >
                Choose a plan
              </Link>
            </div>
          )}
          {children}
        </main>
      </div>

      {/* Mobile top bar */}
      <header className="mobile-appbar lg:hidden fixed inset-x-0 top-0 z-40 border-b border-border bg-surface/85 backdrop-blur-xl">
        <div className="flex h-14 items-center justify-between gap-2 px-4">
          {subRouteTitle ? (
            <div className="flex min-w-0 items-center gap-1">
              <button
                type="button"
                onClick={() => { trigger('light'); router.back() }}
                aria-label="Go back"
                className="-ml-2 flex h-9 items-center gap-0.5 rounded-lg pl-1 pr-2 text-primary active:opacity-60"
              >
                <ChevronLeft className="h-6 w-6" />
              </button>
              <span className="truncate text-base font-semibold text-white">{subRouteTitle}</span>
            </div>
          ) : (
            <Link href="/dashboard" className="flex items-center gap-2 active:opacity-60" onClick={() => trigger('light')}>
              <Logo size="sm" />
            </Link>
          )}
          <div className="flex shrink-0 items-center gap-2">
            <span className="rounded-full border border-border bg-surface-light px-2.5 py-1 text-[11px] font-medium text-gray-300">
              {planLabel}
            </span>
            <button
              type="button"
              onClick={openSheet}
              aria-label="Open menu"
              className="flex items-center justify-center rounded-full active:scale-95 transition-transform"
            >
              <Avatar
                email={user?.email}
                name={user?.fullName}
                src={user?.avatarUrl}
                size={36}
              />
            </button>
          </div>
        </div>
      </header>

      {/* Mobile bottom tab bar */}
      <nav className="mobile-tabbar lg:hidden fixed inset-x-0 bottom-0 z-40 border-t border-border bg-surface/90 backdrop-blur-xl">
        <div className="grid h-14 grid-cols-5 items-end px-1">
          <Link href="/dashboard" className={tabClass(pathname === '/dashboard')} onClick={() => handleTabClick(pathname === '/dashboard')}>
            <LayoutDashboard className="h-5 w-5" />
            Home
          </Link>
          <Link href="/dashboard/trades" className={tabClass(isActive('/dashboard/trades'))} onClick={() => handleTabClick(isActive('/dashboard/trades'))}>
            <TrendingUp className="h-5 w-5" />
            Trades
          </Link>
          <Link
            href="/dashboard/trades/new"
            aria-label="Add trade"
            onClick={() => trigger('medium')}
            className="flex justify-center active:opacity-80"
          >
            <span className="btn-gradient -mt-6 flex h-12 w-12 items-center justify-center rounded-2xl text-white ring-4 ring-background">
              <Plus className="h-6 w-6" />
            </span>
          </Link>
          <Link href="/dashboard/analytics" className={tabClass(isActive('/dashboard/analytics'))} onClick={() => handleTabClick(isActive('/dashboard/analytics'))}>
            <BarChart3 className="h-5 w-5" />
            Analytics
          </Link>
          <button type="button" onClick={openSheet} className={tabClass(sheetOpen)}>
            <MoreHorizontal className="h-5 w-5" />
            More
          </button>
        </div>
      </nav>

      {/* Mobile More sheet */}
      {sheetOpen && (
        <div className="lg:hidden fixed inset-0 z-50" role="dialog" aria-modal="true" aria-label="More options">
          <button
            type="button"
            aria-label="Close menu"
            className="absolute inset-0 h-full w-full bg-black/60 backdrop-blur-sm"
            onClick={() => setSheetOpen(false)}
          />

          <div className="sheet-in mobile-sheet absolute inset-x-0 bottom-0 max-h-[85dvh] overflow-y-auto rounded-t-3xl border-t border-border bg-surface px-4 pt-3">
            <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />

            <div className="mb-4 flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-base font-semibold text-white">
                  {user?.fullName || user?.email || 'Your account'}
                </p>
                <p className="text-xs text-gray-500">
                  {isPro ? 'Pro plan' : isBasic ? 'Basic plan' : user?.status === 'trial' ? 'Free trial' : 'Free plan'}
                  {user?.status === 'trial' && trialDaysLeft > 0 ? ` · ${trialDaysLeft} days left` : ''}
                </p>
              </div>
              <button
                onClick={() => setSheetOpen(false)}
                aria-label="Close"
                className="flex h-9 w-9 items-center justify-center rounded-full bg-surface-light text-gray-400 active:scale-95 transition-transform"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {user && (
              <div className="mb-4 rounded-2xl border border-border bg-surface-light p-3">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-xs text-gray-400">
                    {user.status === 'active'
                      ? (isPro ? 'Unlimited trades' : `${tradesRemaining} of ${user.maxTrades} trades left this month`)
                      : user.status === 'trial'
                        ? 'Unlimited trades during the trial'
                        : 'No active plan'}
                  </span>
                  <Link
                    href="/pricing"
                    onClick={() => setSheetOpen(false)}
                    className="text-xs font-semibold text-primary active:opacity-60"
                  >
                    {isPro ? 'Manage' : 'Upgrade'}
                  </Link>
                </div>
                {!proTools && (
                  <p className="mt-2 text-[11px] text-gray-500">
                    The backtester and replay are Pro features.
                  </p>
                )}
                {!isPro && user.status !== 'trial' && (
                  <div className="mt-2 h-1.5 w-full rounded-full bg-background">
                    <div className="h-1.5 rounded-full bg-primary" style={{ width: `${trialProgress}%` }} />
                  </div>
                )}
              </div>
            )}

            <div className="overflow-hidden rounded-2xl border border-border bg-surface-light">
              {visibleMoreNavigation.map((item, index) => (
                <Link
                  key={item.name}
                  href={item.href}
                  onClick={() => setSheetOpen(false)}
                  className={cn(
                    'flex items-center gap-3 px-4 py-3.5 text-sm font-medium text-white active:bg-surface',
                    index > 0 && 'border-t border-border'
                  )}
                >
                  <item.icon className="h-5 w-5 text-gray-400" />
                  <span className="flex-1">{item.name}</span>
                  <ChevronRight className="h-4 w-4 text-gray-500" />
                </Link>
              ))}
              {user?.isAdmin && (
                <Link
                  href="/dashboard/admin"
                  onClick={() => setSheetOpen(false)}
                  className="flex items-center gap-3 border-t border-border px-4 py-3.5 text-sm font-medium text-white active:bg-surface"
                >
                  <Shield className="h-5 w-5 text-gray-400" />
                  <span className="flex-1">Admin</span>
                  <ChevronRight className="h-4 w-4 text-gray-500" />
                </Link>
              )}
            </div>

            <button
              type="button"
              onClick={handleLogout}
              className="mt-4 flex w-full items-center justify-center gap-2 rounded-2xl border border-danger/40 px-4 py-3 text-sm font-semibold text-danger active:bg-danger/10"
            >
              <LogOut className="h-4 w-4" />
              Log out
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
