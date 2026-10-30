'use client'

import { useCallback, useEffect, useState } from 'react'
import { Search, Trash2, TrendingUp, TrendingDown, Pencil, Download, Loader2, ChevronLeft, ChevronRight, Image as ImageIcon, Mic } from 'lucide-react'
import { cn, formatCurrency, formatDuration } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { deleteTradeMedia } from '@/lib/journal-media'
import Link from 'next/link'
import type { TradePageResult, TradeRow } from '@/types/journal'

const PAGE_SIZE = 25
const EXPORT_PAGE_SIZE = 200
const MAX_EXPORT_PAGES = 100

/** Entry → exit clock window, with the time in market when both exist. */
function timeWindow(trade: TradeRow): string {
  const open = trade.open_time ? new Date(trade.open_time) : null
  const close = trade.close_time ? new Date(trade.close_time) : null
  if (!open && !close) return 'No time window'
  const clock = (date: Date) => date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
  const minutes = open && close && close.getTime() >= open.getTime()
    ? Math.round((close.getTime() - open.getTime()) / 60_000)
    : null
  return `${open ? clock(open) : '—'} → ${close ? clock(close) : '—'}${minutes !== null ? ` · ${formatDuration(minutes)}` : ''}`
}

export default function TradesPage() {
  const [trades, setTrades] = useState<TradeRow[]>([])
  const [total, setTotal] = useState(0)
  const [totalPnl, setTotalPnl] = useState(0)
  const [search, setSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(true)
  const [clearLoading, setClearLoading] = useState(false)
  const [exportLoading, setExportLoading] = useState(false)
  const [error, setError] = useState('')

  const applyResult = useCallback((result: TradePageResult | null, message: string | null) => {
    if (!result) {
      setError(message ? 'Could not load trades: ' + message : 'Could not load trades.')
      setLoading(false)
      return
    }
    setTrades(result.trades ?? [])
    setTotal(Number(result.total ?? 0))
    setTotalPnl(Number(result.total_pnl ?? 0))
    setError('')
    setLoading(false)
  }, [])

  const fetchPage = useCallback(async (
    targetPage: number,
    term: string,
    activeFilter: string
  ): Promise<{ result: TradePageResult | null; message: string | null }> => {
    const { data, error: rpcError } = await supabase.rpc('trade_page', {
      p_limit: PAGE_SIZE,
      p_offset: targetPage * PAGE_SIZE,
      p_search: term || null,
      p_filter: activeFilter,
    })
    if (rpcError) return { result: null, message: rpcError.message }
    return { result: data as unknown as TradePageResult, message: null }
  }, [])

  const loadPage = useCallback(async (targetPage: number, term: string, activeFilter: string) => {
    const { result, message } = await fetchPage(targetPage, term, activeFilter)
    applyResult(result, message)
  }, [fetchPage, applyResult])

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(search)
      setPage(0)
    }, 300)
    return () => clearTimeout(timer)
  }, [search])

  useEffect(() => {
    let active = true
    fetchPage(page, debouncedSearch, filter).then(({ result, message }) => {
      if (!active) return
      applyResult(result, message)
    })
    return () => { active = false }
  }, [page, debouncedSearch, filter, fetchPage, applyResult])

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this trade?')) return
    // Storage objects do not cascade with the row, so remove them first.
    await deleteTradeMedia([id])
    const { error: deleteError } = await supabase.from('trades').delete().eq('id', id)
    if (deleteError) {
      setError('Could not delete the trade: ' + deleteError.message)
      return
    }
    const nextPage = trades.length === 1 && page > 0 ? page - 1 : page
    setLoading(true)
    if (nextPage !== page) setPage(nextPage)
    else await loadPage(page, debouncedSearch, filter)
  }

  const handleClearJournal = async () => {
    if (!confirm('Clear every trade in your journal? This cannot be undone.')) return
    setClearLoading(true)
    setError('')
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      setError('You must be logged in to clear the journal.')
      setClearLoading(false)
      return
    }
    const { data: idRows } = await supabase.from('trades').select('id').eq('user_id', user.id)
    await deleteTradeMedia(((idRows ?? []) as Array<{ id: string }>).map((row) => row.id))
    const { error: deleteError } = await supabase.from('trades').delete().eq('user_id', user.id)
    if (deleteError) {
      setError('Could not clear the journal: ' + deleteError.message)
    } else {
      setPage(0)
      await loadPage(0, debouncedSearch, filter)
    }
    setClearLoading(false)
  }

  const handleExport = async () => {
    setExportLoading(true)
    setError('')
    try {
      const rows: TradeRow[] = []
      for (let index = 0; index < MAX_EXPORT_PAGES; index++) {
        const { data, error: rpcError } = await supabase.rpc('trade_page', {
          p_limit: EXPORT_PAGE_SIZE,
          p_offset: index * EXPORT_PAGE_SIZE,
          p_search: debouncedSearch || null,
          p_filter: filter,
        })
        if (rpcError) throw new Error(rpcError.message)
        const result = data as unknown as TradePageResult
        rows.push(...(result?.trades ?? []))
        if (rows.length >= Number(result?.total ?? 0) || (result?.trades ?? []).length === 0) break
      }

      const escapeCSV = (val: string) => {
        if (val.includes(',') || val.includes('"') || val.includes('\n')) {
          return `"${val.replace(/"/g, '""')}"`
        }
        return val
      }
      const headers = ['Symbol', 'Type', 'Entry', 'Exit', 'Lot Size', 'P&L', 'Commission', 'Swap', 'Strategy', 'Open Time', 'Close Time']
      const csvRows = rows.map(t => [
        escapeCSV(t.symbol),
        t.type,
        t.entry_price,
        t.exit_price,
        t.lot_size,
        Number(t.pnl).toFixed(2),
        (Number(t.commission) || 0).toFixed(2),
        (Number(t.swap) || 0).toFixed(2),
        escapeCSV(t.strategy || ''),
        t.open_time ? new Date(t.open_time).toISOString() : '',
        t.close_time ? new Date(t.close_time).toISOString() : '',
      ])
      const csv = [headers, ...csvRows].map(r => r.join(',')).join('\n')
      const blob = new Blob([csv], { type: 'text/csv' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `trades_${new Date().toISOString().slice(0, 10)}.csv`
      a.click()
      URL.revokeObjectURL(url)
    } catch (exportError: unknown) {
      setError('Could not export trades: ' + (exportError instanceof Error ? exportError.message : 'Unknown error'))
    }
    setExportLoading(false)
  }

  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const firstRow = total === 0 ? 0 : page * PAGE_SIZE + 1
  const lastRow = Math.min(total, (page + 1) * PAGE_SIZE)

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white">Trade History</h1>
          <p className="text-gray-400 text-sm mt-1">
            {loading ? 'Loading...' : `${total} trades • Total P&L: `}
            {!loading && <span className={totalPnl >= 0 ? 'text-success' : 'text-danger'}>{formatCurrency(totalPnl)}</span>}
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={handleExport}
            disabled={exportLoading || total === 0}
            className="flex flex-1 lg:flex-none items-center justify-center gap-2 px-4 py-2.5 bg-surface border border-border rounded-xl text-gray-300 active:opacity-70 transition-colors disabled:opacity-50"
          >
            {exportLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
            {exportLoading ? 'Exporting...' : 'Export'}
          </button>
          <button
            onClick={handleClearJournal}
            disabled={clearLoading || total === 0}
            className="flex flex-1 lg:flex-none items-center justify-center gap-2 px-4 py-2.5 border border-danger/50 rounded-xl text-danger active:bg-danger/10 transition-colors disabled:opacity-50"
          >
            {clearLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />}
            {clearLoading ? 'Clearing...' : 'Clear'}
          </button>
        </div>
      </div>

      {error && <p className="bg-danger/10 border border-danger/30 text-danger px-4 py-3 rounded-lg text-sm">{error}</p>}

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500" />
          <input
            type="text"
            placeholder="Search symbol, strategy or tag…"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setLoading(true) }}
            className="w-full bg-surface border border-border rounded-lg pl-10 pr-4 py-2 text-white focus:outline-none focus:border-primary transition-colors"
          />
        </div>
        <div className="flex gap-2">
          {['all', 'wins', 'losses'].map((f) => (
            <button
              key={f}
              onClick={() => { setFilter(f); setPage(0); setLoading(true) }}
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

      {/* Phone: one card per trade. The table is a desktop-only layout. */}
      <div className="space-y-3 lg:hidden">
        {loading ? (
          Array.from({ length: 4 }).map((_, index) => (
            <div key={index} className="h-24 animate-pulse rounded-2xl border border-border bg-surface" />
          ))
        ) : trades.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border p-6 text-center text-sm text-gray-500">
            No trades found. Import or add your first trade.
          </div>
        ) : (
          trades.map((trade) => {
            const pnl = Number(trade.pnl) || 0
            const tradedAt = trade.close_time || trade.open_time || trade.created_at
            return (
              <div key={trade.id} className="tap-card rounded-2xl border border-border bg-surface p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-base font-semibold text-white">{trade.symbol}</span>
                      <span className={cn(
                        'inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[10px] font-semibold',
                        trade.type === 'BUY' ? 'bg-success/15 text-success' : 'bg-danger/15 text-danger'
                      )}>
                        {trade.type === 'BUY' ? <TrendingUp className="h-3 w-3" /> : <TrendingDown className="h-3 w-3" />}
                        {trade.type}
                      </span>
                    </div>
                    <p className="mt-1 truncate text-xs text-gray-500">
                      {tradedAt ? new Date(tradedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '—'}
                      {' · '}{trade.lot_size} lots
                      {' · '}{trade.entry_price} → {trade.exit_price}
                    </p>
                    <p className="num mt-0.5 flex items-center gap-1 truncate text-[11px] text-gray-500">
                      <span className="tabular-nums">{timeWindow(trade)}</span>
                      {(trade.image_count ?? 0) > 0 && (
                        <span className="ml-1 inline-flex items-center gap-0.5 text-primary">
                          <ImageIcon className="h-3 w-3" />{trade.image_count}
                        </span>
                      )}
                      {(trade.audio_count ?? 0) > 0 && (
                        <span className="inline-flex items-center gap-0.5 text-primary">
                          <Mic className="h-3 w-3" />{trade.audio_count}
                        </span>
                      )}
                    </p>
                  </div>
                  <div className={cn(
                    'shrink-0 text-right text-base font-semibold tabular-nums',
                    pnl >= 0 ? 'text-success' : 'text-danger'
                  )}>
                    {pnl >= 0 ? '+' : ''}{formatCurrency(pnl)}
                  </div>
                </div>

                {trade.tags && trade.tags.length > 0 && (
                  <div className="mt-2 flex flex-wrap items-center gap-1">
                    {trade.tags.slice(0, 4).map(tag => (
                      <span key={tag} className="rounded border border-border px-1.5 py-0.5 text-[10px] text-gray-400">
                        {tag}
                      </span>
                    ))}
                    {trade.tags.length > 4 && (
                      <span className="text-[10px] text-gray-500">+{trade.tags.length - 4}</span>
                    )}
                  </div>
                )}

                <div className="mt-3 flex items-center justify-between border-t border-border pt-2">
                  <span className="truncate text-xs text-gray-500">{trade.strategy || 'No strategy'}</span>
                  <div className="flex items-center">
                    <Link
                      href={`/dashboard/trades/${trade.id}/edit`}
                      aria-label={`Edit ${trade.symbol} trade`}
                      className="flex h-9 w-9 items-center justify-center rounded-lg text-gray-400 active:bg-surface-light"
                    >
                      <Pencil className="h-4 w-4" />
                    </Link>
                    <button
                      onClick={() => handleDelete(trade.id)}
                      aria-label={`Delete ${trade.symbol} trade`}
                      className="flex h-9 w-9 items-center justify-center rounded-lg text-gray-400 active:bg-danger/10 active:text-danger"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>

      <div className="hidden lg:block bg-surface border border-border rounded-xl overflow-hidden">
        <div className="table-scroll overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Symbol</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Type</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Entry</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Exit</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Lot</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">P&L</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Costs</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Date</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Window</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Journal</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={11} className="px-4 py-8 text-center text-gray-500">Loading trades...</td>
                </tr>
              ) : trades.length === 0 ? (
                <tr>
                  <td colSpan={11} className="px-4 py-8 text-center text-gray-500">No trades found. Import or add your first trade!</td>
                </tr>
              ) : trades.map((trade) => (
                <tr key={trade.id} className="border-b border-border last:border-0 hover:bg-surface-light transition-colors">
                  <td className="px-4 py-3">
                    <span className="text-sm font-medium text-white">{trade.symbol}</span>
                    {trade.tags && trade.tags.length > 0 && (
                      <span className="mt-1 flex flex-wrap gap-1">
                        {trade.tags.slice(0, 2).map(tag => (
                          <span key={tag} className="rounded border border-border px-1 py-0.5 text-[10px] font-normal text-gray-400">
                            {tag}
                          </span>
                        ))}
                        {trade.tags.length > 2 && (
                          <span className="text-[10px] text-gray-500">+{trade.tags.length - 2}</span>
                        )}
                      </span>
                    )}
                  </td>
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
                  <td className={`px-4 py-3 text-sm font-medium ${Number(trade.pnl) >= 0 ? 'text-success' : 'text-danger'}`}>
                    {Number(trade.pnl) >= 0 ? '+' : ''}{formatCurrency(Number(trade.pnl))}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-400 tabular-nums" title="Commission + swap (already deducted from P&L)">
                    {(trade.commission || trade.swap)
                      ? `${formatCurrency((Number(trade.commission) || 0) + (Number(trade.swap) || 0))}`
                      : '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-400">
                    {trade.close_time || trade.open_time || trade.created_at
                      ? new Date(trade.close_time || trade.open_time || trade.created_at).toLocaleDateString()
                      : '-'}
                  </td>
                  <td className="px-4 py-3 text-xs text-gray-400">
                    <span className="num whitespace-nowrap">{timeWindow(trade)}</span>
                  </td>
                  <td className="px-4 py-3">
                    <span className="flex items-center gap-2 text-gray-400">
                      {(trade.image_count ?? 0) > 0 ? (
                        <span className="inline-flex items-center gap-1 text-xs text-primary">
                          <ImageIcon className="h-3.5 w-3.5" />{trade.image_count}
                        </span>
                      ) : null}
                      {(trade.audio_count ?? 0) > 0 ? (
                        <span className="inline-flex items-center gap-1 text-xs text-primary">
                          <Mic className="h-3.5 w-3.5" />{trade.audio_count}
                        </span>
                      ) : null}
                      {(trade.image_count ?? 0) === 0 && (trade.audio_count ?? 0) === 0 ? (
                        <span className="text-xs text-gray-600">—</span>
                      ) : null}
                    </span>
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

      <div className="flex flex-col items-center justify-between gap-3 text-xs text-gray-400 sm:flex-row sm:text-sm">
        <span>
          {total === 0 ? 'No trades' : `Showing ${firstRow}–${lastRow} of ${total}`}
        </span>
        <div className="flex w-full items-center gap-2 sm:w-auto">
          <button
            onClick={() => { setLoading(true); setPage((current) => Math.max(0, current - 1)) }}
            disabled={page === 0 || loading}
            className="flex flex-1 items-center justify-center gap-1 rounded-xl border border-border bg-surface px-3 py-2.5 hover:text-white disabled:opacity-40 sm:flex-none sm:py-1.5"
          >
            <ChevronLeft className="w-4 h-4" /> Previous
          </button>
          <span className="whitespace-nowrap">Page {page + 1} of {pageCount}</span>
          <button
            onClick={() => { setLoading(true); setPage((current) => Math.min(pageCount - 1, current + 1)) }}
            disabled={page >= pageCount - 1 || loading}
            className="flex flex-1 items-center justify-center gap-1 rounded-xl border border-border bg-surface px-3 py-2.5 hover:text-white disabled:opacity-40 sm:flex-none sm:py-1.5"
          >
            Next <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  )
}
