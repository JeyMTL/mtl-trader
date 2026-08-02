'use client'

import { useState, useCallback, useEffect } from 'react'
import { Upload, FileText, CheckCircle, AlertCircle, X, Trash2, Clock } from 'lucide-react'
import Papa from 'papaparse'
import { supabase } from '@/lib/supabase'

interface ParsedTrade {
  symbol: string
  type: string
  entry: number
  exit: number
  lot: number
  pnl: number
  commission: number
  swap: number
  date: string
  closeDate: string
  sl: number
  tp: number
}

function parseMT5Date(dateStr: string): string {
  if (!dateStr) return ''
  const cleaned = String(dateStr).trim()
  if (!cleaned || cleaned.toLowerCase().includes('running') || cleaned.toLowerCase().includes('open')) return ''
  if (cleaned.includes('-') || cleaned.includes('T')) return cleaned
  return cleaned.replace(/(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}:\d{2}:\d{2})/, '$1-$2-$3T$4')
}

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

export default function ImportPage() {
  const [file, setFile] = useState<File | null>(null)
  const [parsedData, setParsedData] = useState<ParsedTrade[]>([])
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const [error, setError] = useState('')
  const [userId, setUserId] = useState<string | null>(null)
  const [importCount, setImportCount] = useState(0)
  const [imports, setImports] = useState<ImportRecord[]>([])
  const [deleteLoading, setDeleteLoading] = useState<string | null>(null)

  useEffect(() => {
    setImports(getImports())
    async function getUser() {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) setUserId(user.id)
    }
    getUser()
  }, [])

  const extractTrades = (rows: string[][]): ParsedTrade[] => {
    const trades: ParsedTrade[] = []

    let format = 'mt5'
    if (rows.length > 0) {
      const firstRow = rows[0].map(h => String(h || '').trim().toLowerCase())
      if (firstRow.includes('ticket id') || firstRow.includes('ticket')) {
        format = 'broker'
      }
    }

    const startRow = format === 'broker' ? 1 : (rows[0] && String(rows[0][0] || '').trim() === 'Time' ? 1 : 0)

    for (let idx = startRow; idx < rows.length; idx++) {
      const row = rows[idx]
      if (!row || row.length < 8) continue

      if (format === 'broker') {
        const time = String(row[1] || '').trim()
        if (!time.match(/\d{4}/)) continue
        const symbol = String(row[9] || '').trim()
        const type = String(row[10] || '').trim().toUpperCase()
        const lot = parseFloat(String(row[6] || '0')) || 0
        const entry = parseFloat(String(row[2] || '0')) || 0
        const exit = parseFloat(String(row[4] || '0')) || 0
        const profit = parseFloat(String(row[5] || '0')) || 0
        const commission = parseFloat(String(row[7] || '0')) || 0
        const swap = parseFloat(String(row[8] || '0')) || 0
        const sl = parseFloat(String(row[11] || '0')) || 0
        const tp = parseFloat(String(row[12] || '0')) || 0
        const closeTime = String(row[3] || '').trim()

        if (!symbol || !type) continue
        if (type !== 'BUY' && type !== 'SELL') continue
        const normType = type === 'BUY' ? 'BUY' : 'SELL'
        if (lot <= 0) continue

        trades.push({
          symbol,
          type: normType,
          entry,
          exit,
          lot,
          pnl: profit,
          commission,
          swap,
          date: parseMT5Date(time),
          closeDate: parseMT5Date(closeTime),
          sl,
          tp,
        })
      } else {
        const time = String(row[0] || '').trim()
        if (!time) continue
        if (time === 'Time' || time.startsWith('Total') || time.startsWith('Short') || time.startsWith('Long') || time.startsWith('Initial') || time.startsWith('Trade') || time.startsWith('Name') || time.startsWith('Account') || time.startsWith('Company') || time.startsWith('Date') || time.startsWith('Positions') || !time.match(/\d{4}/)) continue

        const symbol = String(row[2] || '').trim()
        const type = String(row[3] || '').trim().toUpperCase()
        const lot = parseFloat(String(row[4] || '0')) || 0
        const entry = parseFloat(String(row[5] || '0')) || 0
        const sl = parseFloat(String(row[6] || '0')) || 0
        const tp = parseFloat(String(row[7] || '0')) || 0
        const closeTime = String(row[8] || '').trim()
        const exit = parseFloat(String(row[9] || '0')) || 0
        const commission = parseFloat(String(row[10] || '0')) || 0
        const swap = parseFloat(String(row[11] || '0')) || 0
        const profit = parseFloat(String(row[12] || '0')) || 0

        if (!symbol || !type) continue
        if (type !== 'BUY' && type !== 'SELL') continue
        if (lot <= 0) continue

        trades.push({
          symbol,
          type,
          entry,
          exit,
          lot,
          pnl: profit,
          commission,
          swap,
          date: parseMT5Date(time),
          closeDate: parseMT5Date(closeTime),
          sl,
          tp,
        })
      }
    }
    return trades
  }

  const parseCSV = useCallback((file: File) => {
    setLoading(true)
    setError('')

    const reader = new FileReader()
    reader.onload = (e) => {
      const text = e.target?.result as string

      if (!text || text.length === 0) {
        setError('File is empty or could not be read. If this is an Excel file, please export as CSV instead.')
        setLoading(false)
        return
      }

      if (text.charCodeAt(0) === 0x50 && text.charCodeAt(1) === 0x4B) {
        setError('This is an Excel (.xlsx) file. Please export as CSV from MT5 instead. Right-click in History → Export Deals → CSV format.')
        setLoading(false)
        return
      }

      Papa.parse(text, {
        header: false,
        complete: (results) => {
          const rows = results.data as string[][]
          const trades = extractTrades(rows)
          setParsedData(trades)
          setLoading(false)
        },
        error: (parseError: { message: string }) => {
          setError('Error parsing file: ' + parseError.message)
          setLoading(false)
        }
      })
    }
    reader.onerror = () => {
      setError('Failed to read file')
      setLoading(false)
    }
    reader.readAsText(file)
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    const droppedFile = e.dataTransfer.files[0]
    if (droppedFile) {
      setFile(droppedFile)
      parseCSV(droppedFile)
    }
  }, [parseCSV])

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0]
    if (selectedFile) {
      setFile(selectedFile)
      parseCSV(selectedFile)
    }
  }

  const handleImport = async () => {
    if (!userId) {
      setError('You must be logged in to import trades')
      return
    }

    setLoading(true)
    setError('')

    const importTimestamp = new Date().toISOString()
    const batchSize = 100
    let imported = 0

    for (let i = 0; i < parsedData.length; i += batchSize) {
      const batch = parsedData.slice(i, i + batchSize)
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
      })).filter(t => t.lot_size > 0)

      const { error: insertError } = await supabase.from('trades').insert(tradesToInsert)

      if (insertError) {
        setError('Error saving trades: ' + insertError.message)
        setLoading(false)
        return
      }
      imported += batch.length
      setImportCount(imported)
    }

    const newImport: ImportRecord = {
      id: crypto.randomUUID(),
      filename: file?.name || 'Unknown',
      tradeCount: parsedData.length,
      timestamp: importTimestamp,
    }
    const updatedImports = [newImport, ...getImports()]
    saveImports(updatedImports)
    setImports(updatedImports)

    setSuccess(true)
    setLoading(false)
  }

  const reset = () => {
    setFile(null)
    setParsedData([])
    setSuccess(false)
    setError('')
    setImportCount(0)
  }

  const handleDeleteImport = async (imp: ImportRecord) => {
    if (!confirm(`Delete all ${imp.tradeCount} trades from "${imp.filename}"?`)) return
    setDeleteLoading(imp.id)

    const importTime = new Date(imp.timestamp).getTime()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data: trades } = await supabase
      .from('trades')
      .select('id, created_at')
      .eq('user_id', user.id)

    const toDelete = (trades || [])
      .filter(t => {
        if (!t.created_at) return false
        const tTime = new Date(t.created_at).getTime()
        return Math.abs(tTime - importTime) < 60000
      })
      .map(t => t.id)

    if (toDelete.length > 0) {
      await supabase.from('trades').delete().in('id', toDelete)
    }

    const updatedImports = imports.filter(i => i.id !== imp.id)
    saveImports(updatedImports)
    setImports(updatedImports)
    setDeleteLoading(null)
  }

  const handleDeleteAllTrades = async () => {
    if (!confirm('Delete ALL trades? This cannot be undone.')) return
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return
    await supabase.from('trades').delete().eq('user_id', user.id)
    saveImports([])
    setImports([])
  }

  const wins = parsedData.filter(t => t.pnl > 0).length
  const losses = parsedData.filter(t => t.pnl < 0).length
  const totalPnl = parsedData.reduce((acc, t) => acc + t.pnl, 0)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Import Trades</h1>
        <p className="text-gray-400 text-sm mt-1">Upload your MT5 trade history CSV file</p>
      </div>

      {!file ? (
        <div
          onDrop={handleDrop}
          onDragOver={(e) => e.preventDefault()}
          className="border-2 border-dashed border-border hover:border-primary rounded-xl p-12 text-center transition-colors cursor-pointer"
        >
          <input
            type="file"
            accept=".csv"
            onChange={handleFileSelect}
            className="hidden"
            id="file-upload"
          />
          <label htmlFor="file-upload" className="cursor-pointer">
            <Upload className="w-12 h-12 text-gray-500 mx-auto mb-4" />
            <p className="text-lg font-medium text-white mb-2">
              Drag and drop your CSV file here
            </p>
            <p className="text-gray-400 text-sm mb-4">
              or click to browse
            </p>
            <p className="text-gray-500 text-xs">
              Only CSV files are supported. Export from MT5 using History → Export Deals
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
                        <th className="text-left px-4 py-2 text-xs text-gray-400">P&L</th>
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
          <li>4. Right-click → Click &quot;Export Deals&quot;</li>
          <li>5. Choose <span className="text-primary font-semibold">CSV</span> format and save</li>
          <li>6. Upload the CSV file above</li>
        </ol>
        <div className="mt-4 bg-warning/10 border border-warning/30 rounded-lg p-3">
          <p className="text-warning text-xs font-medium">
            Important: Make sure to export as CSV, not as Report (HTML/XLSX). The Report format is a summary and won&apos;t import individual trades.
          </p>
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-white">Import History</h3>
          {imports.length > 0 && (
            <button
              onClick={handleDeleteAllTrades}
              className="flex items-center gap-2 px-3 py-1.5 text-sm border border-danger/50 rounded-lg text-danger hover:bg-danger/10 transition-colors"
            >
              <Trash2 className="w-3.5 h-3.5" />
              Delete All
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
