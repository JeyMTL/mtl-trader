import Papa from 'papaparse'

/**
 * Trade-import parsing, extracted from the import page so it can be unit tested.
 * Handles MT5 report XML (SpreadsheetML), MT5/broker CSV, .xlsx, and
 * Excel-saved-as-CSV, including delimiter sniffing and signed-cost normalisation.
 */

export interface ParsedTrade {
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

export function normalizeHeader(s: unknown): string {
  return String(s ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
}

export function parseNumeric(v: unknown): number {
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

export function parseTicket(v: unknown): number | undefined {
  if (v === null || v === undefined || v === '') return undefined
  const n = parseInt(String(v).replace(/[^0-9]/g, ''), 10)
  return isNaN(n) || n <= 0 ? undefined : n
}

/**
 * Normalize signed costs to the app convention (negative = paid).
 * MT5 reports already store commission/swap as negative numbers. Brokers that
 * export them as positive costs get flipped so P&L math stays consistent.
 */
export function normalizeSignedCost(v: number): number {
  return v > 0 ? -v : v
}

export function normalizeDate(v: unknown): string {
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
export function detectDelimiter(text: string): string {
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
export async function parseFileToRows(file: File): Promise<string[][]> {
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
export function xmlStringToRows(text: string): string[][] {
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

export function buildColumnMap(headerRow: string[]): ColumnMap {
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
  // A section title row has no other real cells. Some exports and the repo's own
  // sample serialise those blanks as the literal string "undefined", so treat
  // both as empty when deciding whether this is a section boundary.
  const rest = row.slice(1, 6)
    .map(c => String(c ?? '').trim().toLowerCase())
    .filter(c => c && c !== 'undefined')
  return rest.length === 0
}

const HEADER_HINTS = ['date', 'closedate', 'exitdate', 'time', 'opentime', 'closetime', 'starttime', 'symbol', 'instrument', 'type', 'direction', 'volume', 'lots', 'price', 'openprice', 'closeprice', 'entryprice', 'exitprice', 'profit', 'pnl', 'pl', 'netprofit', 'netpl', 'profitloss', 'result', 'gainloss', 'commission', 'swap', 'ticket', 'ticketid', 'deal', 'dealid', 'position', 'sl', 'tp']

export function findHeaderRow(rows: string[][]): { idx: number; map: ColumnMap | null } {
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

export function extractTrades(rows: string[][]): ParsedTrade[] {
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
