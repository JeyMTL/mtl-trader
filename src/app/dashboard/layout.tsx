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
  Menu,
  X,
  Plus,
  Shield,
  Calendar,
  RefreshCw
} from 'lucide-react'
import { useState, useEffect } from 'react'
import { cn } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { Logo } from '@/components/logo'

const navigation = [
  { name: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { name: 'Add Trade', href: '/dashboard/trades/new', icon: Plus },
  { name: 'Trades', href: '/dashboard/trades', icon: TrendingUp },
  { name: 'Import', href: '/dashboard/import', icon: Upload },
  { name: 'MT5 Sync', href: '/dashboard/sync', icon: RefreshCw },
  { name: 'Analytics', href: '/dashboard/analytics', icon: BarChart3 },
  { name: 'Calendar', href: '/dashboard/calendar', icon: Calendar },
  { name: 'Settings', href: '/dashboard/settings', icon: Settings },
]

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const pathname = usePathname()
  const router = useRouter()
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [user, setUser] = useState<{ tier: string; status: string; isAdmin: boolean; maxTrades: number; tradesUsed: number; trialEndsAt: string | null } | null>(null)
  const [trialDaysLeft, setTrialDaysLeft] = useState(0)

  useEffect(() => {
    async function loadUser() {
      const { data: { user: authUser } } = await supabase.auth.getUser()
      if (!authUser) {
        router.push('/auth/login')
        return
      }
      let { data } = await supabase
        .from('users')
        .select('subscription_tier, subscription_status, max_trades, trial_ends_at, is_admin')
        .eq('id', authUser.id)
        .single()

      if (!data) {
        data = {
          subscription_tier: 'free',
          subscription_status: 'trial',
          max_trades: -1,
          trial_ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
          is_admin: false,
        }
      }

      // Trades used this month (drives the quota display)
      const startOfMonth = new Date()
      startOfMonth.setDate(1)
      startOfMonth.setHours(0, 0, 0, 0)
      const { count } = await supabase
        .from('trades')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', authUser.id)
        .gte('created_at', startOfMonth.toISOString())

      if (data) {
        setUser({
          tier: data.subscription_tier || 'free',
          status: data.subscription_status || 'trial',
          isAdmin: data.is_admin === true,
          maxTrades: data.max_trades ?? 10,
          tradesUsed: count ?? 0,
          trialEndsAt: data.trial_ends_at,
        })
        if (data.trial_ends_at) {
          setTrialDaysLeft(Math.max(0, Math.ceil((new Date(data.trial_ends_at).getTime() - Date.now()) / (1000 * 60 * 60 * 24))))
        }
      }
    }
    loadUser()
  }, [router])

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/')
  }

  const trialProgress = user?.maxTrades && user.maxTrades > 0
    ? Math.min(100, (user.tradesUsed / user.maxTrades) * 100)
    : 0

  const tradesRemaining = user?.maxTrades === -1 || !user
    ? null
    : Math.max(0, user.maxTrades - user.tradesUsed)

  const isPro = user?.tier === 'pro'
  const isBasic = user?.tier === 'basic'

  return (
    <div className="min-h-screen bg-background flex">
      {/* Mobile sidebar overlay */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}

      {/* Sidebar */}
      <aside className={cn(
        "fixed lg:static inset-y-0 left-0 z-50 w-64 bg-surface border-r border-border transform transition-transform duration-200 ease-in-out",
        sidebarOpen ? "translate-x-0" : "-translate-x-full lg:translate-x-0"
      )}>
        <div className="flex flex-col h-full">
          <div className="flex items-center justify-between h-16 px-4 border-b border-border">
            <Link href="/dashboard" className="flex items-center gap-2">
              <Logo size="sm" />
            </Link>
            <button onClick={() => setSidebarOpen(false)} className="lg:hidden text-gray-400 hover:text-white">
              <X className="w-5 h-5" />
            </button>
          </div>

          <nav className="flex-1 px-3 py-4 space-y-1">
            {navigation.map((item) => {
              const isActive = pathname === item.href
              return (
                <Link
                  key={item.name}
                  href={item.href}
                  onClick={() => setSidebarOpen(false)}
                  className={cn(
                    "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors",
                    isActive
                      ? "nav-active"
                      : "text-gray-400 hover:text-white hover:bg-surface-light"
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
                onClick={() => setSidebarOpen(false)}
                className={cn(
                  "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors",
                  pathname === '/dashboard/admin'
                    ? "nav-active"
                    : "text-gray-400 hover:text-white hover:bg-surface-light"
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
                  {isPro ? 'Pro Plan' : isBasic ? 'Basic Plan' : '30-Day Free Trial'}
                </div>
                <div className="text-sm text-white font-medium">
                  {user.status === 'active' ? (isPro ? 'Unlimited trades' : `${tradesRemaining} / ${user.maxTrades} trades remaining this month`) :
                   user.status === 'trial' ? `${trialDaysLeft} days remaining, unlimited trades` :
                   'Expired'}
                </div>
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
        </div>
      </aside>

      {/* Main content */}
      <div className="flex-1 flex flex-col min-w-0">
        <header className="sticky top-0 z-30 bg-surface/50 backdrop-blur-sm border-b border-border h-16 flex items-center px-4 lg:px-6">
          <button onClick={() => setSidebarOpen(true)} className="lg:hidden text-gray-400 hover:text-white mr-4">
            <Menu className="w-6 h-6" />
          </button>
          <div className="flex-1" />
          <div className="flex items-center gap-4">
            {user && (
              <div className="text-sm text-gray-400">
                {isPro ? 'Unlimited trades' : (
                  <><span className="text-white font-medium">{tradesRemaining}</span> / {user.maxTrades} trades remaining this month</>
                )}
              </div>
            )}
            <Link href="/pricing" className="btn-gradient text-white px-4 py-2 rounded-lg text-sm font-medium">
              Upgrade
            </Link>
          </div>
        </header>

        <main className="flex-1 p-4 lg:p-6 overflow-auto">
          {children}
        </main>
      </div>
    </div>
  )
}
