'use client'

import { useEffect, useState, useMemo } from 'react'
import { Target, DollarSign, AlertTriangle, Clock } from 'lucide-react'
import { formatCurrency, formatPercent } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell } from 'recharts'

interface Trade {
  symbol: string
  type: string
  pnl: number
  lot_size: number
  entry_price: number
  exit_price: number
  open_time: string
  close_time: string
  strategy: string
}

interface Deposit {
  amount: number
}

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ color: string; name: string; value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-surface-light border border-border rounded-lg p-3 shadow-lg">
      <p className="text-gray-400 text-xs mb-1">{label}</p>
      {payload.map((p: { color: string; name: string; value: number }, i: number) => (
        <p key={i} className="text-sm font-medium" style={{ color: p.color }}>
          {p.name}: {typeof p.value === 'number' ? formatCurrency(p.value) : p.value}
        </p>
      ))}
    </div>
  )
}

export default function AnalyticsPage() {
  const [trades, setTrades] = useState<Trade[]>([])
  const [deposits, setDeposits] = useState<Deposit[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function fetchData() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

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

  const { equityData, maxDrawdown } = useMemo(() => {
    const initialBalance = deposits.reduce((acc: number, d: Deposit) => acc + d.amount, 0)
    const result = trades.reduce<{ data: Array<{ trade: number; balance: number }>; running: number; peak: number; dd: number }>(
      (acc, t, i) => {
        const newRunning = acc.running + t.pnl
        const newPeak = Math.max(acc.peak, newRunning)
        const drawdown = newPeak > 0 ? ((newPeak - newRunning) / newPeak) * 100 : 0
        const newDd = Math.max(acc.dd, drawdown)
        return {
          data: [...acc.data, { trade: i + 1, balance: parseFloat(newRunning.toFixed(2)) }],
          running: newRunning,
          peak: newPeak,
          dd: newDd,
        }
      },
      { data: [], running: initialBalance, peak: initialBalance, dd: 0 }
    )
    return { equityData: result.data, maxDrawdown: result.dd }
  }, [trades, deposits])

  if (loading) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-white">Analytics</h1>
        <p className="text-gray-400">Loading your real trading data...</p>
      </div>
    )
  }

  const totalTrades = trades.length
  const wins = trades.filter(t => t.pnl > 0).length
  const losses = trades.filter(t => t.pnl < 0).length
  const winRate = totalTrades > 0 ? (wins / totalTrades) * 100 : 0
  const totalPnl = trades.reduce((acc, t) => acc + t.pnl, 0)
  const grossWins = trades.filter(t => t.pnl > 0).reduce((acc, t) => acc + t.pnl, 0)
  const grossLosses = Math.abs(trades.filter(t => t.pnl < 0).reduce((acc, t) => acc + t.pnl, 0))
  const profitFactor = grossLosses > 0 ? grossWins / grossLosses : 0
  const avgWin = wins > 0 ? grossWins / wins : 0
  const avgLoss = losses > 0 ? -grossLosses / losses : 0
  const largestWin = trades.length > 0 ? Math.max(...trades.map(t => t.pnl)) : 0
  const largestLoss = trades.length > 0 ? Math.min(...trades.map(t => t.pnl)) : 0
  const expectancy = totalTrades > 0 ? totalPnl / totalTrades : 0

  const symbolStats: Record<string, { trades: number; pnl: number; wins: number }> = {}
  trades.forEach(t => {
    if (!symbolStats[t.symbol]) symbolStats[t.symbol] = { trades: 0, pnl: 0, wins: 0 }
    symbolStats[t.symbol].trades++
    symbolStats[t.symbol].pnl += t.pnl
    if (t.pnl > 0) symbolStats[t.symbol].wins++
  })

  const symbolData = Object.entries(symbolStats)
    .map(([symbol, stats]) => ({
      symbol,
      trades: stats.trades,
      pnl: parseFloat(stats.pnl.toFixed(2)),
      winRate: stats.trades > 0 ? (stats.wins / stats.trades) * 100 : 0,
    }))
    .sort((a, b) => b.pnl - a.pnl)

  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
  const dayStats: Record<string, { wins: number; losses: number; pnl: number }> = {}
  trades.forEach(t => {
    const date = t.open_time ? new Date(t.open_time) : null
    if (!date) return
    const day = dayNames[date.getDay()]
    if (!dayStats[day]) dayStats[day] = { wins: 0, losses: 0, pnl: 0 }
    dayStats[day].pnl += t.pnl
    if (t.pnl > 0) dayStats[day].wins++
    else dayStats[day].losses++
  })

  const dayData = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'].map(day => ({
    day,
    wins: dayStats[day]?.wins || 0,
    losses: dayStats[day]?.losses || 0,
    pnl: parseFloat((dayStats[day]?.pnl || 0).toFixed(2)),
  }))

  const monthlyStats: Record<string, number> = {}
  trades.forEach(t => {
    const date = t.close_time ? new Date(t.close_time) : null
    if (!date) return
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`
    monthlyStats[key] = (monthlyStats[key] || 0) + t.pnl
  })
  const monthlyData = Object.entries(monthlyStats)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([month, pnl]) => ({ month, pnl: parseFloat(pnl.toFixed(2)) }))

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Analytics</h1>
        <p className="text-gray-400 text-sm mt-1">Your real trading performance</p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-6 gap-4">
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <DollarSign className="w-4 h-4" />
            Total P&L
          </div>
          <div className={`text-2xl font-bold ${totalPnl >= 0 ? 'text-success' : 'text-danger'}`}>{formatCurrency(totalPnl)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <Target className="w-4 h-4" />
            Win Rate
          </div>
          <div className="text-2xl font-bold text-white">{formatPercent(winRate)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <DollarSign className="w-4 h-4" />
            Profit Factor
          </div>
          <div className="text-2xl font-bold text-white">{profitFactor.toFixed(2)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <AlertTriangle className="w-4 h-4" />
            Max Drawdown
          </div>
          <div className="text-2xl font-bold text-warning">{maxDrawdown.toFixed(1)}%</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <DollarSign className="w-4 h-4" />
            Expectancy
          </div>
          <div className={`text-2xl font-bold ${expectancy >= 0 ? 'text-success' : 'text-danger'}`}>{formatCurrency(expectancy)}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-2">
            <Clock className="w-4 h-4" />
            Total Trades
          </div>
          <div className="text-2xl font-bold text-white">{totalTrades}</div>
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Equity Curve</h2>
        {equityData.length > 0 ? (
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={equityData}>
              <defs>
                <linearGradient id="eqFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={totalPnl >= 0 ? '#22c55e' : '#ef4444'} stopOpacity={0.3} />
                  <stop offset="95%" stopColor={totalPnl >= 0 ? '#22c55e' : '#ef4444'} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e3a5f" />
              <XAxis dataKey="trade" stroke="#4b5563" tick={{ fontSize: 12 }} />
              <YAxis stroke="#4b5563" tick={{ fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
              <Tooltip content={<CustomTooltip />} />
              <Area type="monotone" dataKey="balance" stroke={totalPnl >= 0 ? '#22c55e' : '#ef4444'} fill="url(#eqFill)" strokeWidth={2} name="Balance" />
            </AreaChart>
          </ResponsiveContainer>
        ) : (
          <p className="text-gray-500 text-sm">No trades to display.</p>
        )}
      </div>

      <div className="grid lg:grid-cols-2 gap-6">
        <div className="bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Performance Summary</h2>
          <div className="space-y-3">
            {[
              { label: 'Total Trades', value: totalTrades },
              { label: 'Wins / Losses', value: `${wins} / ${losses}` },
              { label: 'Avg Win', value: formatCurrency(avgWin), color: 'text-success' },
              { label: 'Avg Loss', value: formatCurrency(avgLoss), color: 'text-danger' },
              { label: 'Largest Win', value: formatCurrency(largestWin), color: 'text-success' },
              { label: 'Largest Loss', value: formatCurrency(largestLoss), color: 'text-danger' },
            ].map((item) => (
              <div key={item.label} className="flex justify-between py-2 border-b border-border last:border-0">
                <span className="text-gray-400">{item.label}</span>
                <span className={`font-medium ${item.color || 'text-white'}`}>{item.value}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">P&L by Day</h2>
          {dayData.some(d => d.wins + d.losses > 0) ? (
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={dayData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1e3a5f" />
                <XAxis dataKey="day" stroke="#4b5563" tick={{ fontSize: 12 }} />
                <YAxis stroke="#4b5563" tick={{ fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
                <Tooltip content={<CustomTooltip />} />
                <Bar dataKey="pnl" name="P&L" radius={[4, 4, 0, 0]}>
                  {dayData.map((entry, index) => (
                    <Cell key={index} fill={entry.pnl >= 0 ? '#22c55e' : '#ef4444'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <p className="text-gray-500 text-sm">No day-of-week data yet.</p>
          )}
        </div>
      </div>

      {monthlyData.length > 0 && (
        <div className="bg-surface border border-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Monthly P&L</h2>
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={monthlyData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e3a5f" />
              <XAxis dataKey="month" stroke="#4b5563" tick={{ fontSize: 12 }} />
              <YAxis stroke="#4b5563" tick={{ fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="pnl" name="P&L" radius={[4, 4, 0, 0]}>
                {monthlyData.map((entry, index) => (
                  <Cell key={index} fill={entry.pnl >= 0 ? '#22c55e' : '#ef4444'} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      <div className="bg-surface border border-border rounded-xl p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Performance by Symbol</h2>
        {symbolData.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Symbol</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Trades</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Win Rate</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">P&L</th>
                </tr>
              </thead>
              <tbody>
                {symbolData.map((item) => (
                  <tr key={item.symbol} className="border-b border-border last:border-0">
                    <td className="px-4 py-3 text-sm font-medium text-white">{item.symbol}</td>
                    <td className="px-4 py-3 text-sm text-gray-300">{item.trades}</td>
                    <td className="px-4 py-3 text-sm text-gray-300">{formatPercent(item.winRate)}</td>
                    <td className={`px-4 py-3 text-sm font-medium ${item.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                      {formatCurrency(item.pnl)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-gray-500 text-sm">No trades imported yet.</p>
        )}
      </div>
    </div>
  )
}
