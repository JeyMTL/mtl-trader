'use client'

import { useState, useCallback, useEffect } from 'react'
import { Upload, FileText, CheckCircle, AlertCircle, X, Trash2, Clock } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { extractTrades, parseFileToRows, type ParsedTrade } from '@/lib/import-parser'
import { effectiveMaxTrades, monthlyRemaining, UNLIMITED } from '@/lib/subscription'

interface ImportRecord {
  id: string
  filename: string
  tradeCount: number
  timestamp: string
}

function getImports(): ImportRecord[] {
  if (typeof window === 'undefined') return []
  try {
    return JSON.parse(localStorage.getItem('mtl_imports') || '[]')
  } catch {
    return []
  }
}

function saveImports(imports: ImportRecord[]) {
  localStorage.setItem('mtl_imports', JSON.stringify(imports))
}

function startOfCurrentMonth(): Date {
  const d = new Date()
  d.setDate(1)
  d.setHours(0, 0, 0, 0)
  return d
}

export default function ImportPage() {
  const [file, setFile] = useState<File | null>(null)
  const [parsedData, setParsedData] = useState<ParsedTrade[]>([])
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [userId, setUserId] = useState<string | null>(null)
  const [importCount, setImportCount] = useState(0)
  const [imports, setImports] = useState<ImportRecord[]>(() => getImports())
  const [deleteLoading, setDeleteLoading] = useState<string | null>(null)

  useEffect(() => {
    async function getUser() {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) setUserId(user.id)
    }
    getUser()
  }, [])

  const parseFile = useCallback(async (selectedFile: File) => {
    setLoading(true)
    setError('')
    setNotice('')
    try {
      const rows = await parseFileToRows(selectedFile)
      if (!rows || rows.length === 0) {
        setError('No readable data found in this file. If it came from Excel, try "Save As → CSV UTF-8" or export from MT5 as CSV.')
        setLoading(false)
        return
      }
      const trades = extractTrades(rows)
      setParsedData(trades)
      if (trades.length === 0) {
        setError('No trades could be detected in this file. Make sure it contains an MT5 or broker trade history export.')
      }
    } catch (e) {
      console.error(e)
      setError('Could not read this file. Please try exporting it as a CSV from Excel or MT5.')
    }
    setLoading(false)
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    const droppedFile = e.dataTransfer.files[0]
    if (droppedFile) {
      setFile(droppedFile)
      parseFile(droppedFile)
    }
  }, [parseFile])

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0]
    if (selectedFile) {
      setFile(selectedFile)
      parseFile(selectedFile)
    }
  }

  const handleImport = async () => {
    if (!userId) {
      setError('You must be logged in to import trades')
      return
    }
    if (parsedData.length === 0) return

    setLoading(true)
    setError('')
    setNotice('')

    const { data: { session } } = await supabase.auth.getSession()
    if (!session) {
      setError('Your session has expired. Please log in again.')
      setLoading(false)
      return
    }

    // Repair accounts created before the unlimited 30-day trial change.
    await fetch('/api/trial/activate', {
      method: 'POST',
      headers: { Authorization: `Bearer ${session.access_token}` },
    })

    // Monthly quota pre-check (server enforces this too)
    const { data: userRow } = await supabase
      .from('users')
      .select('max_trades, subscription_status, trial_ends_at')
      .eq('id', userId)
      .single()

    let toImport = parsedData
    const effectiveMax = effectiveMaxTrades(userRow ?? {})
    if (effectiveMax !== UNLIMITED) {
      const { count } = await supabase
        .from('trades')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .gte('created_at', startOfCurrentMonth().toISOString())
      const remaining = monthlyRemaining(userRow ?? {}, count ?? 0)
      if (remaining === 0) {
        setError(`You have reached your monthly limit of ${effectiveMax} trades. Upgrade your plan for more.`)
        setLoading(false)
        return
      }
      if (remaining < parsedData.length) {
        toImport = parsedData.slice(0, remaining)
        setNotice(`Monthly limit: importing ${remaining} of ${parsedData.length} trades. Upgrade your plan to import the rest.`)
      }
    }

    const importId = crypto.randomUUID()
    const importTimestamp = new Date().toISOString()
    const batchSize = 100
    let imported = 0
    let skipped = 0

    const tickets = toImport
      .map(trade => trade.ticket)
      .filter((ticket): ticket is number => ticket !== undefined)
    const existingTickets = new Set<number>()
    if (tickets.length > 0) {
      const { data: existingTrades, error: existingError } = await supabase
        .from('trades')
        .select('ticket')
        .eq('user_id', userId)
        .in('ticket', tickets)
      if (existingError) {
        setError('Could not check for duplicate trades: ' + existingError.message)
        setLoading(false)
        return
      }
      existingTrades?.forEach(trade => {
        if (trade.ticket !== null) existingTickets.add(trade.ticket)
      })
    }

    const importedTickets = new Set<number>()
    const newTrades = toImport.filter(trade => {
      if (!trade.ticket) return true
      if (existingTickets.has(trade.ticket) || importedTickets.has(trade.ticket)) return false
      importedTickets.add(trade.ticket)
      return true
    })
    skipped = toImport.length - newTrades.length
    if (newTrades.length === 0) {
      setImportCount(0)
      setSuccess(true)
      setNotice(`All ${skipped} trades were skipped because they are already in your journal.`)
      setLoading(false)
      return
    }

    for (let i = 0; i < newTrades.length; i += batchSize) {
      const batch = newTrades.slice(i, i + batchSize)
      const tradesToInsert = batch.map((trade) => ({
        user_id: userId,
        symbol: trade.symbol,
        type: trade.type,
        entry_price: trade.entry || 0,
        exit_price: trade.exit || 0,
        lot_size: trade.lot || 0.01,
        stop_loss: trade.sl || null,
        take_profit: trade.tp || null,
        pnl: trade.pnl || 0,
        commission: trade.commission || 0,
        swap: trade.swap || 0,
        open_time: trade.date || null,
        close_time: trade.closeDate || null,
        ticket: trade.ticket ?? null,
        import_id: importId,
      })).filter(t => t.lot_size > 0)

      const { error: insertError } = await supabase
        .from('trades')
        .insert(tradesToInsert)

      if (insertError) {
        setError('Error saving trades: ' + insertError.message)
        setLoading(false)
        return
      }
      imported += tradesToInsert.length
      setImportCount(imported)
    }

    const newImport: ImportRecord = {
      id: importId,
      filename: file?.name || 'Unknown',
      tradeCount: imported,
      timestamp: importTimestamp,
    }
    const updatedImports = [newImport, ...getImports()]
    saveImports(updatedImports)
    setImports(updatedImports)

    setSuccess(true)
    if (skipped > 0) {
      setNotice(`${imported} new trades imported. ${skipped} duplicate trades were skipped because they are already in your journal.`)
    }
    setLoading(false)
  }

  const reset = () => {
    setFile(null)
    setParsedData([])
    setSuccess(false)
    setError('')
    setNotice('')
    setImportCount(0)
  }

  const handleDeleteImport = async (imp: ImportRecord) => {
    if (!confirm(`Delete all ${imp.tradeCount} trades from "${imp.filename}"?`)) return
    setDeleteLoading(imp.id)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    await supabase.from('trades').delete().eq('user_id', user.id).eq('import_id', imp.id)

    const updatedImports = imports.filter(i => i.id !== imp.id)
    saveImports(updatedImports)
    setImports(updatedImports)
    setDeleteLoading(null)
  }

  const handleDeleteAllTrades = async () => {
    if (!confirm('Delete ALL trades? This cannot be undone.')) return
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return
    setDeleteLoading('all')
    const { error: deleteError } = await supabase.from('trades').delete().eq('user_id', user.id)
    if (deleteError) {
      setError('Could not clear the journal: ' + deleteError.message)
      setDeleteLoading(null)
      return
    }
    saveImports([])
    setImports([])
    setDeleteLoading(null)
  }

  const wins = parsedData.filter(t => t.pnl > 0).length
  const losses = parsedData.filter(t => t.pnl < 0).length
  const totalPnl = parsedData.reduce((acc, t) => acc + t.pnl, 0)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Import Trades</h1>
        <p className="text-gray-400 text-sm mt-1">Upload your MT5 or broker trade history — XML report, CSV, or Excel (.xlsx)</p>
      </div>

      {!file ? (
        <div
          onDrop={handleDrop}
          onDragOver={(e) => e.preventDefault()}
          className="border-2 border-dashed border-border hover:border-primary rounded-xl p-12 text-center transition-colors cursor-pointer"
        >
          <input
            type="file"
            accept=".csv,.xlsx,.xls,.xml,.tsv,.txt"
            onChange={handleFileSelect}
            className="hidden"
            id="file-upload"
          />
          <label htmlFor="file-upload" className="cursor-pointer">
            <Upload className="w-12 h-12 text-gray-500 mx-auto mb-4" />
            <p className="text-lg font-medium text-white mb-2">
              Drag and drop your file here
            </p>
            <p className="text-gray-400 text-sm mb-4">
              or click to browse
            </p>
            <p className="text-gray-500 text-xs">
              Works with MT5 XML reports (ReportHistory files), MT5 CSV exports, broker CSVs, Excel .xlsx files, and Excel-saved-as-CSV — even tab- or semicolon-separated files
            </p>
          </label>
        </div>
      ) : success ? (
        <div className="bg-surface border border-border rounded-xl p-8 text-center">
          <CheckCircle className="w-16 h-16 text-success mx-auto mb-4" />
          <h2 className="text-xl font-bold text-white mb-2">Import Successful!</h2>
          <p className="text-gray-400 mb-6">
            {importCount} trades have been imported to your journal.
          </p>
          {notice && (
            <p className="text-warning bg-warning/10 border border-warning/30 rounded-lg px-4 py-2 text-sm mb-6 max-w-md mx-auto">
              {notice}
            </p>
          )}
          <div className="flex gap-3 justify-center">
            <button
              onClick={reset}
              className="px-6 py-2 bg-surface-light border border-border rounded-lg text-white hover:border-primary transition-colors"
            >
              Import More
            </button>
            <a
              href="/dashboard/trades"
              className="px-6 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors"
            >
              View Trades
            </a>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          {error && (
            <div className="bg-danger/10 border border-danger/30 text-danger px-4 py-3 rounded-lg flex items-center gap-2">
              <AlertCircle className="w-5 h-5 flex-shrink-0" />
              <span className="text-sm">{error}</span>
              <button onClick={() => setError('')} className="ml-auto">
                <X className="w-4 h-4" />
              </button>
            </div>
          )}

          <div className="bg-surface border border-border rounded-xl p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <FileText className="w-8 h-8 text-primary" />
                <div>
                  <p className="text-sm font-medium text-white">{file.name}</p>
                  <p className="text-xs text-gray-400">
                    {parsedData.length > 0
                      ? `${parsedData.length} trades found • ${wins} wins, ${losses} losses • P&L: $${totalPnl.toFixed(2)}`
                      : loading ? 'Parsing file...' : '0 trades found'}
                  </p>
                </div>
              </div>
              <button onClick={reset} className="text-gray-400 hover:text-white">
                <X className="w-5 h-5" />
              </button>
            </div>
          </div>

          {parsedData.length > 0 && (
            <>
              <div className="bg-surface border border-border rounded-xl overflow-hidden">
                <div className="p-4 border-b border-border">
                  <h3 className="text-sm font-medium text-white">Preview (first 5 trades)</h3>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border">
                        <th className="text-left px-4 py-2 text-xs text-gray-400">Symbol</th>
                        <th className="text-left px-4 py-2 text-xs text-gray-400">Type</th>
                        <th className="text-left px-4 py-2 text-xs text-gray-400">Volume</th>
                        <th className="text-left px-4 py-2 text-xs text-gray-400">Entry</th>
                        <th className="text-left px-4 py-2 text-xs text-gray-400">Exit</th>
                        <th className="text-left px-4 py-2 text-xs text-gray-400">Costs</th>
                        <th className="text-left px-4 py-2 text-xs text-gray-400">P&L (net)</th>
                      </tr>
                    </thead>
                    <tbody>
                      {parsedData.slice(0, 5).map((trade, i) => (
                        <tr key={i} className="border-b border-border last:border-0">
                          <td className="px-4 py-2 text-white">{trade.symbol}</td>
                          <td className="px-4 py-2">
                            <span className={trade.type === 'BUY' ? 'text-success' : 'text-danger'}>
                              {trade.type}
                            </span>
                          </td>
                          <td className="px-4 py-2 text-gray-300">{trade.lot}</td>
                          <td className="px-4 py-2 text-gray-300">{trade.entry}</td>
                          <td className="px-4 py-2 text-gray-300">{trade.exit}</td>
                          <td className="px-4 py-2 text-gray-400" title="Commission + swap (already deducted from net P&L)">
                            {(trade.commission || trade.swap) ? (trade.commission + trade.swap).toFixed(2) : '—'}
                          </td>
                          <td className={`px-4 py-2 font-medium ${trade.pnl >= 0 ? 'text-success' : 'text-danger'}`}>
                            ${trade.pnl.toFixed(2)}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={reset}
                  className="px-6 py-2 bg-surface-light border border-border rounded-lg text-white hover:border-primary transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleImport}
                  disabled={loading}
                  className="px-6 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg transition-colors disabled:opacity-50"
                >
                  {loading ? `Importing... ${importCount}/${parsedData.length}` : `Import ${parsedData.length} Trades`}
                </button>
              </div>
            </>
          )}
        </div>
      )}

      <div className="bg-surface border border-border rounded-xl p-6">
        <h3 className="text-lg font-semibold text-white mb-4">How to Export from MT5</h3>
        <ol className="space-y-2 text-sm text-gray-400">
          <li>1. Open MetaTrader 5 → Go to &quot;History&quot; tab (bottom)</li>
          <li>2. Right-click → Select &quot;All History&quot;</li>
          <li>3. Select all trades (Ctrl+A)</li>
          <li>4. Right-click → Click &quot;Report&quot; (or &quot;Export Deals&quot;)</li>
          <li>5. MT5 saves the Trade History Report as an <span className="text-primary font-semibold">XML / Excel file</span> named like <span className="text-primary font-semibold">ReportHistory-1234567</span> — upload it directly, no conversion needed</li>
          <li>6. We also read plain <span className="text-primary font-semibold">CSV</span> and <span className="text-primary font-semibold">.xlsx</span> exports automatically</li>
        </ol>
        <div className="mt-4 bg-warning/10 border border-warning/30 rounded-lg p-3">
          <p className="text-warning text-xs font-medium">
            Tip: If MT5 only offers the Report format (HTML/XLSX), upload the XLSX directly — we parse it for you. Avoid the HTML summary report.
          </p>
          <p className="text-gray-400 text-xs mt-2">
            P&L is stored <span className="text-white font-medium">net</span>: MT5 Profit + Commission + Swap. MT5&apos;s report lists these in separate columns, so a trade&apos;s P&L here differs from MT5&apos;s Profit column by its costs — totals still match MT5&apos;s Total Net Profit.
          </p>
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-white">Import History</h3>
          {imports.length > 0 && (
            <button
              onClick={handleDeleteAllTrades}
              disabled={deleteLoading === 'all'}
              className="flex items-center gap-2 px-3 py-1.5 text-sm border border-danger/50 rounded-lg text-danger hover:bg-danger/10 transition-colors"
            >
              <Trash2 className="w-3.5 h-3.5" />
              {deleteLoading === 'all' ? 'Clearing...' : 'Clear Journal'}
            </button>
          )}
        </div>
        {imports.length === 0 ? (
          <p className="text-gray-500 text-sm">No imports yet.</p>
        ) : (
          <div className="space-y-2">
            {imports.map((imp) => (
              <div key={imp.id} className="flex items-center justify-between py-3 px-4 bg-surface-light rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center">
                    <Clock className="w-4 h-4 text-primary" />
                  </div>
                  <div>
                    <p className="text-sm font-medium text-white">{imp.filename}</p>
                    <p className="text-xs text-gray-400">
                      {imp.tradeCount} trades • {new Date(imp.timestamp).toLocaleDateString()} {new Date(imp.timestamp).toLocaleTimeString()}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => handleDeleteImport(imp)}
                  disabled={deleteLoading === imp.id}
                  className="text-gray-500 hover:text-danger transition-colors disabled:opacity-50"
                >
                  {deleteLoading === imp.id ? (
                    <div className="w-4 h-4 border-2 border-danger border-t-transparent rounded-full animate-spin" />
                  ) : (
                    <Trash2 className="w-4 h-4" />
                  )}
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
