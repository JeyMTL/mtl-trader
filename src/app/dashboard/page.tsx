'use client'

import { useEffect, useState, useMemo } from 'react'
import { TrendingUp, TrendingDown, BarChart3, DollarSign, Target, AlertTriangle, Plus } from 'lucide-react'
import { formatCurrency } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { XAxis, YAxis, Tooltip, ResponsiveContainer, Area, AreaChart } from 'recharts'

interface Trade {
  id: string
  symbol: string
  type: string
  pnl: number
  entry_price: number
  exit_price: number
  lot_size: number
  created_at: string
  close_time: string
}

interface Deposit {
  amount: number
}

export default function DashboardPage() {
  const [trades, setTrades] = useState<Trade[]>([])
  const [deposits, setDeposits] = useState<Deposit[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function fetchData() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        window.location.href = '/auth/login'
        return
      }

      const [tradesRes, depositsRes] = await Promise.all([
        supabase.from('trades').select('*').eq('user_id', user.id).order('close_time', { ascending: true }),
        supabase.from('deposits').select('amount').eq('user_id', user.id),
      ])

      setTrades(tradesRes.data || [])
      setDeposits(depositsRes.data || [])
      setLoading(false)
    }
    fetchData()
  }, [])

  const totalDeposits = deposits.reduce((acc, d) => acc + d.amount, 0)
  const totalPnl = useMemo(() => trades.reduce((acc, t) => acc + t.pnl, 0), [trades])
  const balance = totalDeposits + totalPnl
  const wins = useMemo(() => trades.filter(t => t.pnl > 0).length, [trades])
  const winRate = trades.length > 0 ? (wins / trades.length) * 100 : 0
  const grossWins = useMemo(() => trades.filter(t => t.pnl > 0).reduce((acc, t) => acc + t.pnl, 0), [trades])
  const grossLosses = useMemo(() => Math.abs(trades.filter(t => t.pnl < 0).reduce((acc, t) => acc + t.pnl, 0)), [trades])
  const profitFactor = grossLosses > 0 ? grossWins / grossLosses : 0

  const { equityData, maxDrawdown } = useMemo(() => {
    const initialBalance = totalDeposits
    const result = trades.reduce<{ data: Array<{ trade: number; balance: number; pnl: number }>; running: number; peak: number; dd: number }>(
      (acc, t, i) => {
        const newRunning = acc.running + t.pnl
        const newPeak = Math.max(acc.peak, newRunning)
        const drawdown = newPeak > 0 ? ((newPeak - newRunning) / newPeak) * 100 : 0
        const newDd = Math.max(acc.dd, drawdown)
        return {
          data: [...acc.data, { trade: i + 1, balance: parseFloat(newRunning.toFixed(2)), pnl: parseFloat(t.pnl.toFixed(2)) }],
          running: newRunning,
          peak: newPeak,
          dd: newDd,
        }
      },
      { data: [], running: initialBalance, peak: initialBalance, dd: 0 }
    )
    return { equityData: result.data, maxDrawdown: result.dd }
  }, [trades, totalDeposits])

  const statCards = [
    { label: 'Account Balance', value: formatCurrency(balance), icon: DollarSign, positive: balance >= 0, tile: 'icon-tile-green' },
    { label: 'Total P&L', value: formatCurrency(totalPnl), icon: TrendingUp, positive: totalPnl >= 0, tile: 'icon-tile-blue' },
    { label: 'Win Rate', value: `${winRate.toFixed(1)}%`, icon: Target, positive: winRate >= 50, tile: 'icon-tile-violet' },
    { label: 'Profit Factor', value: profitFactor.toFixed(2), icon: BarChart3, positive: profitFactor >= 1, tile: 'icon-tile-amber' },
    { label: 'Max Drawdown', value: `${maxDrawdown.toFixed(1)}%`, icon: AlertTriangle, positive: maxDrawdown < 10, tile: 'icon-tile-blue' },
  ]

  const recentTrades = [...trades].sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()).slice(0, 5)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Dashboard</h1>
        <p className="text-gray-400 text-sm mt-1">
          {loading ? 'Loading...' : 'Welcome back! Here\'s your trading overview.'}
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        {statCards.map((stat) => (
          <div key={stat.label} className="card-hover bg-surface border border-border rounded-xl p-4">
            <div className={`icon-tile ${stat.tile} mb-3`}>
              <stat.icon className="w-5 h-5" />
            </div>
            <div className="text-gray-400 text-sm">{stat.label}</div>
            <div className="text-2xl font-bold text-white mt-1">{stat.value}</div>
            <div className={`text-sm mt-1 flex items-center gap-1 ${stat.positive ? 'text-success' : 'text-danger'}`}>
              {stat.positive ? <TrendingUp className="w-4 h-4" /> : <TrendingDown className="w-4 h-4" />}
              {stat.positive ? 'Good' : 'Needs attention'}
            </div>
          </div>
        ))}
      </div>

      <div className="grid lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Equity Curve</h2>
          {equityData.length > 0 ? (
            <ResponsiveContainer width="100%" height={280}>
              <AreaChart data={equityData}>
                <defs>
                  <linearGradient id="equityGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={totalPnl >= 0 ? '#22c55e' : '#ef4444'} stopOpacity={0.3} />
                    <stop offset="95%" stopColor={totalPnl >= 0 ? '#22c55e' : '#ef4444'} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="trade" stroke="#4b5563" tick={{ fontSize: 12 }} />
                <YAxis stroke="#4b5563" tick={{ fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#1f2937', border: '1px solid #1e3a5f', borderRadius: '8px' }}
                  labelStyle={{ color: '#9ca3af' }}
                  formatter={(value) => [formatCurrency(Number(value)), 'Balance']}
                />
                <Area type="monotone" dataKey="balance" stroke={totalPnl >= 0 ? '#22c55e' : '#ef4444'} fill="url(#equityGradient)" strokeWidth={2} />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="h-64 flex items-center justify-center border border-dashed border-border rounded-lg">
              <p className="text-gray-500">Import or add trades to see your equity curve</p>
            </div>
          )}
        </div>

        <div className="bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Recent Trades</h2>
          <div className="space-y-3">
            {recentTrades.length > 0 ? recentTrades.map((trade) => (
              <div key={trade.id} className="flex items-center justify-between py-2 border-b border-border last:border-0">
                <div className="flex items-center gap-3">
                  <div className={`w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold ${
                    trade.type === 'BUY' ? 'bg-success/20 text-success' : 'bg-danger/20 text-danger'
                  }`}>
                    {trade.type === 'BUY' ? 'B' : 'S'}
                  </div>
                  <div>
                    <div className="text-sm font-medium text-white">{trade.symbol}</div>
                    <div className="text-xs text-gray-500">{new Date(trade.created_at).toLocaleDateString()}</div>
                  </div>
                </div>
                <div className={`text-sm font-medium ${trade.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                  {trade.pnl >= 0 ? '+' : ''}{formatCurrency(trade.pnl)}
                </div>
              </div>
            )) : (
              <p className="text-gray-500 text-sm">No trades yet. Import or add your first trade!</p>
            )}
          </div>
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Quick Actions</h2>
        <div className="grid sm:grid-cols-4 gap-4">
          <a href="/dashboard/trades/new" className="card-hover flex items-center gap-3 p-4 bg-surface-light border border-border rounded-lg">
            <div className="icon-tile icon-tile-green">
              <Plus className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-medium text-white">Add Trade</div>
              <div className="text-xs text-gray-400">Manual entry</div>
            </div>
          </a>
          <a href="/dashboard/import" className="card-hover flex items-center gap-3 p-4 bg-surface-light border border-border rounded-lg">
            <div className="icon-tile icon-tile-blue">
              <TrendingUp className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-medium text-white">Import Trades</div>
              <div className="text-xs text-gray-400">Upload MT5 CSV</div>
            </div>
          </a>
          <a href="/dashboard/analytics" className="card-hover flex items-center gap-3 p-4 bg-surface-light border border-border rounded-lg">
            <div className="icon-tile icon-tile-violet">
              <BarChart3 className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-medium text-white">View Analytics</div>
              <div className="text-xs text-gray-400">Deep performance insights</div>
            </div>
          </a>
          <a href="/dashboard/settings" className="card-hover flex items-center gap-3 p-4 bg-surface-light border border-border rounded-lg">
            <div className="icon-tile icon-tile-amber">
              <Target className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-medium text-white">Settings</div>
              <div className="text-xs text-gray-400">Configure your account</div>
            </div>
          </a>
        </div>
      </div>
    </div>
  )
}
