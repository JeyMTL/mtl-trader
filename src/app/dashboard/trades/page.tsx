'use client'

import { useState, useEffect } from 'react'
import { Search, Trash2, TrendingUp, TrendingDown, Pencil, Download } from 'lucide-react'
import { formatCurrency } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import Link from 'next/link'

interface Trade {
  id: string
  symbol: string
  type: string
  entry_price: number
  exit_price: number
  lot_size: number
  pnl: number
  created_at: string
  close_time: string
  strategy: string
}

export default function TradesPage() {
  const [trades, setTrades] = useState<Trade[]>([])
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function fetchTrades() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        window.location.href = '/auth/login'
        return
      }

      const { data } = await supabase
        .from('trades')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })

      setTrades(data || [])
      setLoading(false)
    }
    fetchTrades()
  }, [])

  const filteredTrades = trades.filter(trade => {
    const matchSearch = trade.symbol.toLowerCase().includes(search.toLowerCase()) ||
                       (trade.strategy || '').toLowerCase().includes(search.toLowerCase())
    const matchFilter = filter === 'all' || 
                       (filter === 'wins' && trade.pnl > 0) ||
                       (filter === 'losses' && trade.pnl < 0)
    return matchSearch && matchFilter
  })

  const totalPnl = filteredTrades.reduce((acc, t) => acc + t.pnl, 0)

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this trade?')) return
    await supabase.from('trades').delete().eq('id', id)
    setTrades(trades.filter(t => t.id !== id))
  }

  const handleExport = () => {
    const escapeCSV = (val: string) => {
      if (val.includes(',') || val.includes('"') || val.includes('\n')) {
        return `"${val.replace(/"/g, '""')}"`
      }
      return val
    }
    const headers = ['Symbol', 'Type', 'Entry', 'Exit', 'Lot Size', 'P&L', 'Strategy', 'Open Time', 'Close Time']
    const rows = filteredTrades.map(t => [
      escapeCSV(t.symbol),
      t.type,
      t.entry_price,
      t.exit_price,
      t.lot_size,
      t.pnl.toFixed(2),
      escapeCSV(t.strategy || ''),
      t.close_time ? new Date(t.close_time).toISOString() : '',
      t.created_at ? new Date(t.created_at).toISOString() : '',
    ])
    const csv = [headers, ...rows].map(r => r.join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `trades_${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white">Trade History</h1>
          <p className="text-gray-400 text-sm mt-1">
            {loading ? 'Loading...' : `${filteredTrades.length} trades • Total P&L: `}
            {!loading && <span className={totalPnl >= 0 ? 'text-success' : 'text-danger'}>{formatCurrency(totalPnl)}</span>}
          </p>
        </div>
        <button
          onClick={handleExport}
          disabled={filteredTrades.length === 0}
          className="flex items-center gap-2 px-4 py-2 bg-surface border border-border rounded-lg text-gray-300 hover:text-white hover:border-primary transition-colors disabled:opacity-50"
        >
          <Download className="w-4 h-4" />
          Export CSV
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500" />
          <input
            type="text"
            placeholder="Search trades..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-surface border border-border rounded-lg pl-10 pr-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
          />
        </div>
        <div className="flex gap-2">
          {['all', 'wins', 'losses'].map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                filter === f
                  ? 'bg-primary text-white'
                  : 'bg-surface border border-border text-gray-400 hover:text-white'
              }`}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Symbol</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Type</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Entry</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Exit</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Lot</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">P&L</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Date</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={8} className="px-4 py-8 text-center text-gray-500">Loading trades...</td>
                </tr>
              ) : filteredTrades.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-4 py-8 text-center text-gray-500">No trades found. Import or add your first trade!</td>
                </tr>
              ) : filteredTrades.map((trade) => (
                <tr key={trade.id} className="border-b border-border last:border-0 hover:bg-surface-light transition-colors">
                  <td className="px-4 py-3 text-sm font-medium text-white">{trade.symbol}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium ${
                      trade.type === 'BUY' 
                        ? 'bg-success/20 text-success' 
                        : 'bg-danger/20 text-danger'
                    }`}>
                      {trade.type === 'BUY' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                      {trade.type}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-300">{trade.entry_price}</td>
                  <td className="px-4 py-3 text-sm text-gray-300">{trade.exit_price}</td>
                  <td className="px-4 py-3 text-sm text-gray-300">{trade.lot_size}</td>
                  <td className={`px-4 py-3 text-sm font-medium ${trade.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                    {trade.pnl >= 0 ? '+' : ''}{formatCurrency(trade.pnl)}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-400">
                    {trade.created_at ? new Date(trade.created_at).toLocaleDateString() : '-'}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Link
                        href={`/dashboard/trades/${trade.id}/edit`}
                        className="text-gray-400 hover:text-primary transition-colors"
                      >
                        <Pencil className="w-4 h-4" />
                      </Link>
                      <button 
                        onClick={() => handleDelete(trade.id)}
                        className="text-gray-400 hover:text-danger transition-colors"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
