'use client'

import { useEffect, useState, use } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Save, TrendingUp, TrendingDown } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { formatCurrency, getPointValue } from '@/lib/utils'

export default function EditTradePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params)
  const router = useRouter()
  const [saving, setSaving] = useState(false)
  const [loading, setLoading] = useState(true)
  const [form, setForm] = useState({
    symbol: '',
    type: 'BUY',
    entry_price: '',
    exit_price: '',
    lot_size: '',
    stop_loss: '',
    take_profit: '',
    commission: '',
    swap: '',
    strategy: '',
    notes: '',
    open_time: '',
    close_time: '',
  })

  useEffect(() => {
    async function fetchTrade() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/auth/login')
        return
      }
      const { data } = await supabase.from('trades').select('*').eq('id', id).eq('user_id', user.id).single()
      if (!data) {
        alert('Trade not found')
        router.push('/dashboard/trades')
        return
      }
      setForm({
        symbol: data.symbol || '',
        type: data.type || 'BUY',
        entry_price: data.entry_price?.toString() || '',
        exit_price: data.exit_price?.toString() || '',
        lot_size: data.lot_size?.toString() || '',
        stop_loss: data.stop_loss?.toString() || '',
        take_profit: data.take_profit?.toString() || '',
        commission: data.commission?.toString() || '',
        swap: data.swap?.toString() || '',
        strategy: data.strategy || '',
        notes: data.notes || '',
        open_time: data.open_time ? new Date(data.open_time).toISOString().slice(0, 16) : '',
        close_time: data.close_time ? new Date(data.close_time).toISOString().slice(0, 16) : '',
      })
      setLoading(false)
    }
    fetchTrade()
  }, [id, router])

  const update = (field: string, value: string) => setForm(prev => ({ ...prev, [field]: value }))

  const pnl = (() => {
    const entry = parseFloat(form.entry_price)
    const exit = parseFloat(form.exit_price)
    const lots = parseFloat(form.lot_size)
    const comm = parseFloat(form.commission || '0')
    const swapVal = parseFloat(form.swap || '0')
    if (isNaN(entry) || isNaN(exit) || isNaN(lots)) return null
    const pointValue = getPointValue(form.symbol || 'EURUSD')
    const raw = form.type === 'BUY'
      ? (exit - entry) * lots * pointValue
      : (entry - exit) * lots * pointValue
    return raw - comm + swapVal
  })()

  const handleSubmit = async () => {
    if (!form.symbol || !form.entry_price || !form.exit_price || !form.lot_size) return
    setSaving(true)

    const { error } = await supabase.from('trades').update({
      symbol: form.symbol.toUpperCase(),
      type: form.type,
      entry_price: parseFloat(form.entry_price),
      exit_price: parseFloat(form.exit_price),
      lot_size: parseFloat(form.lot_size),
      stop_loss: form.stop_loss ? parseFloat(form.stop_loss) : null,
      take_profit: form.take_profit ? parseFloat(form.take_profit) : null,
      pnl: pnl || 0,
      commission: form.commission ? parseFloat(form.commission) : 0,
      swap: form.swap ? parseFloat(form.swap) : 0,
      strategy: form.strategy || null,
      notes: form.notes || null,
      open_time: form.open_time ? new Date(form.open_time).toISOString() : null,
      close_time: form.close_time ? new Date(form.close_time).toISOString() : null,
    }).eq('id', id)

    if (error) {
      alert('Error: ' + error.message)
      setSaving(false)
      return
    }

    router.push('/dashboard/trades')
  }

  if (loading) {
    return (
      <div className="space-y-6 max-w-2xl">
        <p className="text-gray-400">Loading trade...</p>
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <button onClick={() => router.back()} className="flex items-center gap-2 text-gray-400 hover:text-white mb-4 transition-colors">
          <ArrowLeft className="w-4 h-4" />
          Back
        </button>
        <h1 className="text-2xl font-bold text-white">Edit Trade</h1>
        <p className="text-gray-400 text-sm mt-1">Update trade details</p>
      </div>

      <div className="bg-surface border border-border rounded-xl p-6 space-y-6">
        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Symbol *</label>
            <input
              type="text"
              value={form.symbol}
              onChange={(e) => update('symbol', e.target.value)}
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Type *</label>
            <div className="flex gap-2">
              <button
                onClick={() => update('type', 'BUY')}
                className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg font-medium transition-colors ${
                  form.type === 'BUY'
                    ? 'bg-success text-white'
                    : 'bg-surface-light border border-border text-gray-400 hover:text-white'
                }`}
              >
                <TrendingUp className="w-4 h-4" />
                Buy
              </button>
              <button
                onClick={() => update('type', 'SELL')}
                className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg font-medium transition-colors ${
                  form.type === 'SELL'
                    ? 'bg-danger text-white'
                    : 'bg-surface-light border border-border text-gray-400 hover:text-white'
                }`}
              >
                <TrendingDown className="w-4 h-4" />
                Sell
              </button>
            </div>
          </div>
        </div>

        <div className="grid sm:grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Entry Price *</label>
            <input
              type="number"
              step="any"
              value={form.entry_price}
              onChange={(e) => update('entry_price', e.target.value)}
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Exit Price *</label>
            <input
              type="number"
              step="any"
              value={form.exit_price}
              onChange={(e) => update('exit_price', e.target.value)}
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Lot Size *</label>
            <input
              type="number"
              step="any"
              value={form.lot_size}
              onChange={(e) => update('lot_size', e.target.value)}
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
        </div>

        <div className="grid sm:grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Stop Loss</label>
            <input
              type="number"
              step="any"
              value={form.stop_loss}
              onChange={(e) => update('stop_loss', e.target.value)}
              placeholder="Optional"
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Take Profit</label>
            <input
              type="number"
              step="any"
              value={form.take_profit}
              onChange={(e) => update('take_profit', e.target.value)}
              placeholder="Optional"
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Strategy</label>
            <input
              type="text"
              value={form.strategy}
              onChange={(e) => update('strategy', e.target.value)}
              placeholder="e.g. Breakout"
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Commission</label>
            <input
              type="number"
              step="any"
              value={form.commission}
              onChange={(e) => update('commission', e.target.value)}
              placeholder="0.00"
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Swap</label>
            <input
              type="number"
              step="any"
              value={form.swap}
              onChange={(e) => update('swap', e.target.value)}
              placeholder="0.00"
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Open Time</label>
            <input
              type="datetime-local"
              value={form.open_time}
              onChange={(e) => update('open_time', e.target.value)}
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">Close Time</label>
            <input
              type="datetime-local"
              value={form.close_time}
              onChange={(e) => update('close_time', e.target.value)}
              className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">Notes</label>
          <textarea
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
            placeholder="Trade notes..."
            rows={3}
            className="w-full bg-background border border-border rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary transition-colors resize-none"
          />
        </div>

        {pnl !== null && (
          <div className={`flex items-center justify-between p-4 rounded-lg ${pnl >= 0 ? 'bg-success/10 border border-success/30' : 'bg-danger/10 border border-danger/30'}`}>
            <span className="text-gray-300 font-medium">P&L</span>
            <span className={`text-xl font-bold ${pnl >= 0 ? 'text-success' : 'text-danger'}`}>
              {pnl >= 0 ? '+' : ''}{formatCurrency(pnl)}
            </span>
          </div>
        )}

        <div className="flex gap-3">
          <button
            onClick={() => router.back()}
            className="px-6 py-2 border border-border rounded-lg text-gray-400 hover:text-white transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={saving || !form.symbol || !form.entry_price || !form.exit_price || !form.lot_size}
            className="flex items-center gap-2 px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white rounded-lg transition-colors font-medium"
          >
            <Save className="w-4 h-4" />
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  )
}
