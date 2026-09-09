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
  ticket?: number
}

function normalizeHeader(s: unknown): string {
  return String(s ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
}

function parseNumeric(v: unknown): number {
  if (v === null || v === undefined || v === '') return 0
  const raw = String(v).trim().replace(/[ currency$€£]/gi, '')
  const value = raw.replace(/^\((.*)\)$/, '-$1').replace(/\s/g, '')
  const normalized = value.includes(',') && value.includes('.')
    ? value.lastIndexOf(',') > value.lastIndexOf('.')
      ? value.replace(/\./g, '').replace(',', '.')
      : value.replace(/,/g, '')
    : value.replace(',', '.')
  const n = parseFloat(normalized)
  return isNaN(n) ? 0 : n
}

function parseTicket(v: unknown): number | undefined {
  if (v === null || v === undefined || v === '') return undefined
  const n = parseInt(String(v).replace(/[^0-9]/g, ''), 10)
  return isNaN(n) || n <= 0 ? undefined : n
}

/**
 * Normalize signed costs to the app convention (negative = paid).
 * MT5 reports already store commission/swap as negative numbers. Brokers that
 * export them as positive costs get flipped so P&L math stays consistent.
 */
function normalizeSignedCost(v: number): number {
  return v > 0 ? -v : v
}

function normalizeDate(v: unknown): string {
  if (!v) return ''
  if (v instanceof Date && !isNaN(v.getTime())) return v.toISOString()
  const s = String(v).trim()
  if (!s) return ''
  const lower = s.toLowerCase()
  if (lower.includes('running') || lower.includes('open')) return ''

  // Already ISO-ish: "YYYY-MM-DD HH:MM:SS" or "YYYY-MM-DDTHH:MM:SS"
  const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?/)
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}T${iso[4]}:${iso[5]}:${iso[6] || '00'}`

  // MT5 export: "YYYY.MM.DD HH:MM:SS"
  const mt5 = s.match(/^(\d{4})\.(\d{2})\.(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/)
  if (mt5) return `${mt5[1]}-${mt5[2]}-${mt5[3]}T${mt5[4]}:${mt5[5]}:${mt5[6] || '00'}`

  // US Excel format: "MM/DD/YYYY HH:MM:SS"
  const us = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})[ T](\d{2}):(\d{2})(?::(\d{2}))?/)
  if (us) {
    const month = Number(us[1])
    const day = Number(us[2])
    const year = Number(us[3])
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31 && year >= 1990 && year <= 2100) {
      return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${us[4]}:${us[5]}:${us[6] || '00'}`
    }
  }

  const dateOnly = s.match(/^(\d{4})[.-](\d{2})[.-](\d{2})$/)
  if (dateOnly) return `${dateOnly[1]}-${dateOnly[2]}-${dateOnly[3]}T00:00:00`

  const usDateOnly = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/)
  if (usDateOnly) {
    const month = Number(usDateOnly[1])
    const day = Number(usDateOnly[2])
    const year = Number(usDateOnly[3])
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31 && year >= 1990 && year <= 2100) {
      return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T00:00:00`
    }
  }

  return s
}

/** Detect the delimiter (comma, semicolon, or tab) by counting outside quotes. */
function detectDelimiter(text: string): string {
  const lines = text.split(/\r?\n/).filter(l => l.trim()).slice(0, 20)
  const counts: Record<string, number> = { ',': 0, ';': 0, '\t': 0 }
  for (const line of lines) {
    let inQuotes = false
    for (const ch of line) {
      if (ch === '"') inQuotes = !inQuotes
      else if (!inQuotes && counts[ch] !== undefined) counts[ch]++
    }
  }
  let best = ','
  let bestCount = -1
  for (const [delim, n] of Object.entries(counts)) {
    if (n > bestCount) {
      bestCount = n
      best = delim
    }
  }
  return best
}

/** Read any supported file (xlsx / xls / xml / csv / tsv / txt) into rows of strings. */
async function parseFileToRows(file: File): Promise<string[][]> {
  const buffer = await file.arrayBuffer()
  const bytes = new Uint8Array(buffer)

  const lowerName = file.name.toLowerCase()
  const isZip = bytes.length >= 2 && bytes[0] === 0x50 && bytes[1] === 0x4b
  const isLegacyExcel = bytes.length >= 4 && bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0
  const isXml = bytes.length >= 5 && bytes[0] === 0x3c && bytes[1] === 0x3f && bytes[2] === 0x78 && bytes[3] === 0x6d && bytes[4] === 0x6c // "<?xml"
  const looksLikeXml = isXml || lowerName.endsWith('.xml')

  // Read both modern .xlsx and legacy .xls files, even when the extension is wrong.
  if (isZip || isLegacyExcel || lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
    const XLSX = await import('xlsx')
    const wb = XLSX.read(buffer, { type: 'array', cellDates: true })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' }) as unknown[][]
    return rows.map(row =>
      (row || []).map(v => (v instanceof Date ? v.toISOString() : String(v ?? '').trim()))
    )
  }

  let text = new TextDecoder('utf-8').decode(buffer)
  // Strip UTF-8 BOM (Excel adds one to CSVs; the XML check above catches "<?xml" first)
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1)
  if (!text.trim()) return []

  // MT5 "Report" / "Export Deals" saves XML (SpreadsheetML, "ReportHistory-<account>") or PAMM-style HTML2 markup.
  if (looksLikeXml || /^\s*<\?xml/i.test(text) || /\sxmlns:html2=\"urn:report-component/.test(text)) {
    const parsed = xmlStringToRows(text)
    if (parsed.length > 0) return parsed
    // Fall through to the delimiter path if the markup had no tabular data.
  }

  const delimiter = detectDelimiter(text)
  const parsed = Papa.parse<string[]>(text, {
    header: false,
    delimiter,
    skipEmptyLines: true,
  })
  if (parsed.errors && parsed.errors.length > 0) {
    console.warn('PapaParse warnings:', parsed.errors)
  }
  return parsed.data
}

/** Minimal XML helper: returns the first <tag ...>...</tag> block (or self-closing tag). */
function matchTag(text: string, tag: string, from: number): { attrs: string; inner: string; next: number } | null {
  const open = text.indexOf(`<${tag}`, from)
  if (open === -1) return null
  const attrsEnd = text.indexOf('>', open)
  if (attrsEnd === -1) return null
  const attrs = text.slice(open + tag.length + 1, attrsEnd)
  if (text[attrsEnd - 1] === '/') {
    return { attrs, inner: '', next: attrsEnd + 1 }
  }
  const close = text.indexOf(`</${tag}>`, attrsEnd)
  if (close === -1) return null
  return { attrs, inner: text.slice(attrsEnd + 1, close), next: close + tag.length + 3 }
}

function decodeXmlEntities(s: string): string {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&amp;/g, '&')
}

/**
 * Flatten XML/HTML2 markup into rows of strings. Covers:
 *  - SpreadsheetML 2003 XML (what MT5 writes for its Trade History Report)
 *  - PAMM/investor statement markup (xmlns:html2="urn:report-component)
 * Each top-level row of the first visible table becomes one string[] of cell text.
 */
function xmlStringToRows(text: string): string[][] {
  const unescapeText = (s: string) => decodeXmlEntities(s.replace(/<[^>]*>/g, '')).trim()

  // SpreadsheetML: Worksheet > Table > Row > Cell > Data
  const sheet = matchTag(text, 'Worksheet', 0)
  const table = sheet ? matchTag(sheet.inner, 'Table', 0) : null
  if (table) {
    const rows: string[][] = []
    let rowPos = 0
    for (;;) {
      const row = matchTag(table.inner, 'Row', rowPos)
      if (!row) break
      rowPos = row.next
      const cells: string[] = []
      let cellPos = 0
      let colIndex = 0
      for (;;) {
        const cell = matchTag(row.inner, 'Cell', cellPos)
        if (!cell) break
        cellPos = cell.next
        // Respect ss:Index / ss:MergeDown so columns stay aligned.
        const indexMatch = cell.attrs.match(/ss:Index\s*=\s*"(\d+)"/)
        const mergeDownMatch = cell.attrs.match(/ss:MergeDown\s*=\s*"(\d+)"/)
        const spanMatch = cell.attrs.match(/ss:MergeAcross\s*=\s*"(\d+)"/)
        const targetIndex = indexMatch ? parseInt(indexMatch[1], 10) - 1 : colIndex
        while (cells.length < targetIndex) cells.push('')
        const data = matchTag(cell.inner, 'Data', 0)
        cells.push(data ? unescapeText(data.inner) : '')
        const colSpan = 1 + (spanMatch ? parseInt(spanMatch[1], 10) : 0)
        for (let extra = 1; extra < colSpan; extra++) cells.push('')
        colIndex = cells.length
        if (mergeDownMatch && parseInt(mergeDownMatch[1], 10) > 0) {
          cells.push(cells[cells.length - 1])
        }
      }
      rows.push(cells)
    }
    if (rows.length > 0) return rows
  }

  // Generic/PAMM markup: every top-level <row> of the first table-like block.
  const rowRegex = /<row(?:\s[^>]*)?>([\s\S]*?)<\/row>/gi
  const rows: string[][] = []
  for (const m of text.matchAll(rowRegex)) {
    if (/<\/(tr|h|d|name|value)>/i.test(m[1])) {
      const cells: string[] = []
      const cellRegex = /<(?:[ch]:)?(?:tr|h|d|name|value)(?:\s[^>]*)?>([\s\S]*?)<\/(?:[ch]:)?(?:tr|h|d|name|value)>/gi
      for (const c of m[1].matchAll(cellRegex)) cells.push(unescapeText(c[1]))
      if (cells.length > 0) rows.push(cells)
    }
  }
  return rows
}

interface ColumnMap {
  ticket: number
  openDate: number
  openTime: number
  closeDate: number
  closeTime: number
  symbol: number
  type: number
  lot: number
  entry: number
  exit: number
  sl: number
  tp: number
  profit: number
  profitIsNet: boolean
  commission: number
  swap: number
  direction?: number
  dealVolumeIdx?: number
}

function buildColumnMap(headerRow: string[]): ColumnMap {
  const idx: Record<string, number[]> = {}
  headerRow.forEach((h, i) => {
    const key = normalizeHeader(h)
    if (!key) return
    if (!idx[key]) idx[key] = []
    idx[key].push(i)
  })

  const first = (...keys: string[]) => {
    for (const k of keys) if (idx[k]?.length) return idx[k][0]
    return -1
  }
  const nth = (key: string, n: number) => (idx[key] && idx[key].length > n ? idx[key][n] : -1)

  const openDate = first('date', 'opendate', 'tradedate')
  const openTime = first('time', 'opentime', 'starttime')
  const closeDate = first('closedate', 'exitdate')
  const closeTime = first('closetime', 'time2') !== -1 ? first('closetime', 'time2') : nth('time', 1)
  const entry = first('openprice', 'entryprice', 'priceopen') !== -1
    ? first('openprice', 'entryprice', 'priceopen')
    : nth('price', 0)
  const exit = first('closeprice', 'exitprice', 'priceclose') !== -1
    ? first('closeprice', 'exitprice', 'priceclose')
    : nth('price', 1)
  const profitIsNet = ['netprofit', 'netpl', 'profitloss', 'result', 'gainloss'].some(key => idx[key]?.length)

  // MT5 report Positions rows carry a unique "Position" id — ideal dedup key.
  // (Only the Deals section reuses Position ids across partial fills, and we never parse that section.)
  return {
    ticket: first('ticket', 'ticketid', 'deal', 'dealid', 'position'),
    openDate,
    openTime,
    closeDate,
    closeTime,
    symbol: first('symbol', 'instrument'),
    type: first('type', 'direction'),
    lot: first('volume', 'lots', 'volumelots', 'size'),
    entry,
    exit,
    sl: first('sl', 'stoploss'),
    tp: first('tp', 'takeprofit'),
    profit: first('profit', 'pnl', 'pl', 'netprofit', 'netpl', 'profitloss', 'result', 'gainloss'),
    profitIsNet,
    commission: first('commission', 'commision', 'fee'),
    swap: first('swap', 'swaps'),
    // Deals section: "Type" is buy/sell and "Direction" is in/out; Volume column follows Direction.
    direction: idx['direction']?.length ? idx['direction'][0] : -1,
    dealVolumeIdx: idx['direction']?.length ? idx['direction'][0] + 1 : -1,
  }
}

/**
 * In MT5 reports (Positions + Orders + Deals sections share one sheet), stop at the
 * section markers so Orders/Deals rows are not imported as duplicate trades.
 */
const MT5_SECTION_MARKERS = new Set(['orders', 'deals', 'results'])

function isMt5SectionMarker(row: string[]): boolean {
  const first = String(row[0] || '').trim().toLowerCase()
  if (!MT5_SECTION_MARKERS.has(first)) return false
  const rest = row.slice(1, 6).map(c => String(c || '').trim()).filter(Boolean)
  return rest.length === 0
}

const HEADER_HINTS = ['date', 'closedate', 'exitdate', 'time', 'opentime', 'closetime', 'starttime', 'symbol', 'instrument', 'type', 'direction', 'volume', 'lots', 'price', 'openprice', 'closeprice', 'entryprice', 'exitprice', 'profit', 'pnl', 'pl', 'netprofit', 'netpl', 'profitloss', 'result', 'gainloss', 'commission', 'swap', 'ticket', 'ticketid', 'deal', 'dealid', 'position', 'sl', 'tp']

function findHeaderRow(rows: string[][]): { idx: number; map: ColumnMap | null } {
  for (let i = 0; i < Math.min(rows.length, 60); i++) {
    const row = (rows[i] || []).map(c => String(c ?? '').trim())
    if (row.length < 3) continue
    const set = new Set(row.map(normalizeHeader).filter(Boolean))
    const hits = [...set].filter(h => HEADER_HINTS.some(hint => h.includes(hint))).length
    if (hits >= 3) {
      return { idx: i, map: buildColumnMap(row) }
    }
  }
  return { idx: -1, map: null }
}

function extractTrades(rows: string[][]): ParsedTrade[] {
  const trades: ParsedTrade[] = []
  const { idx: headerRowIdx, map } = findHeaderRow(rows)

  // ---- Header-driven parsing (handles MT5 exports, broker exports, xlsx, xml) ----
  if (headerRowIdx !== -1 && map) {
    const get = (row: unknown[], i: number) => (i >= 0 ? row[i] : undefined)
    const dateTime = (row: unknown[], dateIndex: number, timeIndex: number) => {
      const date = String(get(row, dateIndex) ?? '').trim()
      const time = String(get(row, timeIndex) ?? '').trim()
      if (date && time && date !== time) return `${date} ${time}`
      return time || date
    }
    for (let i = headerRowIdx + 1; i < rows.length; i++) {
      const row = rows[i]
      if (isMt5SectionMarker(row || [])) break // next report section starts — stop here
      if (!row || row.length < 3) continue

      const timeVal = dateTime(row, map.openDate, map.openTime)
      if (!timeVal || !/\d{4}/.test(timeVal)) continue

      const symbol = String(get(row, map.symbol) ?? '').trim().toUpperCase()
      const type = String(get(row, map.type) ?? '').trim().toUpperCase()
      const lot = parseNumeric(get(row, map.lot))
      if (!symbol || (type !== 'BUY' && type !== 'SELL') || lot <= 0) continue

      // Deals-format rows (Direction column): "in" opens, "out" closes — keep one row per trade.
      const directionIdx = map.direction ?? -1
      const dealVolumeIdx = map.dealVolumeIdx ?? -1
      const direction = String(get(row, directionIdx) ?? '').trim().toLowerCase()
      if (direction && direction !== 'out') continue
      const effectiveLot = direction === 'out' && dealVolumeIdx >= 0
        ? parseNumeric(get(row, dealVolumeIdx))
        : lot

      const profit = parseNumeric(get(row, map.profit))
      const commission = normalizeSignedCost(parseNumeric(get(row, map.commission)))
      const swap = normalizeSignedCost(parseNumeric(get(row, map.swap)))

      trades.push({
        symbol,
        type: type as 'BUY' | 'SELL',
        entry: parseNumeric(get(row, map.entry)),
        exit: parseNumeric(get(row, map.exit)),
        lot: effectiveLot,
        pnl: map.profitIsNet ? profit : profit + commission + swap,
        commission,
        swap,
        date: normalizeDate(timeVal),
        closeDate: normalizeDate(dateTime(row, map.closeDate, map.closeTime)),
        sl: parseNumeric(get(row, map.sl)),
        tp: parseNumeric(get(row, map.tp)),
        ticket: parseTicket(get(row, map.ticket)),
      })
    }
    return trades
  }

  // ---- Fallback: positional heuristics for files without a recognizable header ----
  let format: 'mt5' | 'broker' = 'mt5'

  for (let i = 0; i < Math.min(rows.length, 20); i++) {
    const row = rows[i].map(c => String(c || '').trim().toLowerCase())
    if (row[0] === 'time' && row.includes('symbol') && row.includes('type')) {
      format = 'mt5'
      break
    }
    if (row.includes('ticket') || (row[9] && row[9].match(/[a-z]{2,6}/) && row[10] && (row[10] === 'buy' || row[10] === 'sell'))) {
      format = 'broker'
      break
    }
  }

  const startRow = (() => {
    for (let i = 0; i < Math.min(rows.length, 50); i++) {
      const firstCell = String(rows[i][0] || '').trim()
      if (firstCell.match(/^\d{4}[.-]\d{2}[.-]\d{2}/) || firstCell.match(/^\d{1,2}\/\d{1,2}\/\d{4}/)) {
        return i
      }
    }
    return 0
  })()

  for (let i = startRow; i < rows.length; i++) {
    const row = rows[i]
    if (!row || row.length < 8) continue

    if (format === 'broker') {
      const time = String(row[1] || '').trim()
      if (!time || !time.match(/\d{4}/)) continue
      const symbol = String(row[9] || '').trim().toUpperCase()
      const type = String(row[10] || '').trim().toUpperCase()
      const lot = parseFloat(String(row[6] || '0')) || 0
      if (!symbol || (type !== 'BUY' && type !== 'SELL') || lot <= 0) continue
      const commission = normalizeSignedCost(parseNumeric(row[7]))
      const swap = normalizeSignedCost(parseNumeric(row[8]))
      trades.push({
        symbol,
        type: type as 'BUY' | 'SELL',
        entry: parseFloat(String(row[2] || '0')) || 0,
        exit: parseFloat(String(row[4] || '0')) || 0,
        lot,
        pnl: parseNumeric(row[5]) + commission + swap,
        commission,
        swap,
        date: normalizeDate(String(row[1] || '').trim()),
        closeDate: normalizeDate(String(row[3] || '').trim()),
        sl: parseFloat(String(row[11] || '0')) || 0,
        tp: parseFloat(String(row[12] || '0')) || 0,
        ticket: parseTicket(row[0]),
      })
    } else {
      const time = String(row[0] || '').trim()
      if (!time || time.match(/^[a-zA-Z]/) || !time.match(/\d{4}/)) continue
      const symbol = String(row[2] || '').trim().toUpperCase()
      const type = String(row[3] || '').trim().toUpperCase()
      const lot = parseFloat(String(row[4] || '0')) || 0
      if (!symbol || (type !== 'BUY' && type !== 'SELL') || lot <= 0) continue
      const commission = normalizeSignedCost(parseNumeric(row[10]))
      const swap = normalizeSignedCost(parseNumeric(row[11]))
      trades.push({
        symbol,
        type: type as 'BUY' | 'SELL',
        entry: parseFloat(String(row[5] || '0')) || 0,
        exit: parseFloat(String(row[9] || '0')) || 0,
        lot,
        pnl: parseNumeric(row[12]) + commission + swap,
        commission,
        swap,
        date: normalizeDate(time),
        closeDate: normalizeDate(String(row[8] || '').trim()),
        sl: parseFloat(String(row[6] || '0')) || 0,
        tp: parseFloat(String(row[7] || '0')) || 0,
        // MT5 Position is not unique across partial fills, so do not use it as a ticket.
        ticket: undefined,
      })
    }
  }
  return trades
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
    const activeTrial = userRow?.subscription_status === 'trial' &&
      userRow.trial_ends_at && new Date(userRow.trial_ends_at) > new Date()
    const effectiveMaxTrades = activeTrial ? -1 : userRow?.max_trades
    if (effectiveMaxTrades && effectiveMaxTrades !== -1) {
      const { count } = await supabase
        .from('trades')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .gte('created_at', startOfCurrentMonth().toISOString())
      const remaining = Math.max(0, effectiveMaxTrades - (count ?? 0))
      if (remaining === 0) {
        setError(`You have reached your monthly limit of ${effectiveMaxTrades} trades. Upgrade your plan for more.`)
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