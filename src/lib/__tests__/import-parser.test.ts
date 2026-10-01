import { describe, it, expect } from 'vitest'
import {
  extractTrades,
  parseNumeric,
  parseTicket,
  normalizeSignedCost,
  normalizeDate,
  detectDelimiter,
  xmlStringToRows,
  parseFileToRows,
} from '@/lib/import-parser'

// Raw MT5 "Positions" table headers: two Time columns and two Price columns.
const MT5_HEADER = 'Time,Position,Symbol,Type,Volume,Price,S / L,T / P,Time,Price,Commission,Swap,Profit'

describe('parseNumeric', () => {
  it('handles plain, signed, parenthesised and thousands formats', () => {
    expect(parseNumeric('1.79')).toBe(1.79)
    expect(parseNumeric('-1.79')).toBe(-1.79)
    expect(parseNumeric('(1.23)')).toBe(-1.23)
    expect(parseNumeric('1,234.56')).toBe(1234.56)
    expect(parseNumeric('1.234,56')).toBe(1234.56)
    expect(parseNumeric('$2.50')).toBe(2.5)
    expect(parseNumeric('')).toBe(0)
    expect(parseNumeric(undefined)).toBe(0)
  })
})

describe('parseTicket', () => {
  it('keeps positive integers and rejects junk', () => {
    expect(parseTicket('511797401')).toBe(511797401)
    expect(parseTicket('0')).toBeUndefined()
    expect(parseTicket('')).toBeUndefined()
    expect(parseTicket('undefined')).toBeUndefined()
  })
})

describe('normalizeSignedCost', () => {
  it('flips positive costs to negative, keeps negatives', () => {
    expect(normalizeSignedCost(2.5)).toBe(-2.5)
    expect(normalizeSignedCost(-2.5)).toBe(-2.5)
    expect(normalizeSignedCost(0)).toBe(0)
  })
})

describe('normalizeDate', () => {
  it('normalises MT5, ISO and US formats', () => {
    expect(normalizeDate('2026.02.10 12:30:03')).toBe('2026-02-10T12:30:03')
    expect(normalizeDate('2026-02-10 12:30:03')).toBe('2026-02-10T12:30:03')
    expect(normalizeDate('02/10/2026 12:30:03')).toBe('2026-02-10T12:30:03')
    expect(normalizeDate('2026.02.10')).toBe('2026-02-10T00:00:00')
  })

  it('drops open/running rows', () => {
    expect(normalizeDate('running')).toBe('')
    expect(normalizeDate('open')).toBe('')
  })
})

describe('detectDelimiter', () => {
  it('detects comma, semicolon and tab', () => {
    expect(detectDelimiter('a,b,c\n1,2,3')).toBe(',')
    expect(detectDelimiter('a;b;c\n1;2;3')).toBe(';')
    expect(detectDelimiter('a\tb\tc\n1\t2\t3')).toBe('\t')
  })
})

describe('extractTrades — MT5 positions CSV', () => {
  const rows = [
    MT5_HEADER.split(','),
    '2026.02.10 12:30:03,511797401,GBPUSDm,sell,0.01,1.36788,1.36967,1.36574,2026.02.10 14:30:13,1.36967,0,0,-1.79'.split(','),
    '2026.02.20 13:02:39,516564448,XAUUSDm,buy,0.01,5026.157,5026.236,,2026.02.20 13:08:28,5026.236,0,0,0.08'.split(','),
    // Orders section header — parsing must stop here.
    'Orders,undefined,undefined,undefined,undefined,undefined,,,undefined,undefined,0,0,undefined'.split(','),
    '2026.02.10 11:13:04,511761805,GBPUSDm,buy,0.01,1.36967,,,2026.02.10 11:13:04,1.36967,0,0,undefined'.split(','),
  ]

  const trades = extractTrades(rows)

  it('parses only the Positions trades and stops at the Orders section', () => {
    expect(trades).toHaveLength(2)
  })

  it('maps every core field from the first trade', () => {
    expect(trades[0]).toMatchObject({
      symbol: 'GBPUSDM',
      type: 'SELL',
      lot: 0.01,
      entry: 1.36788,
      exit: 1.36967,
      pnl: -1.79,
      commission: 0,
      swap: 0,
      date: '2026-02-10T12:30:03',
      closeDate: '2026-02-10T14:30:13',
      ticket: 511797401,
    })
  })

  it('keeps the second trade’s values', () => {
    expect(trades[1].symbol).toBe('XAUUSDM')
    expect(trades[1].pnl).toBeCloseTo(0.08, 6)
  })

  it('dedups by the MT5 Position ticket', () => {
    expect(trades.map(t => t.ticket)).toEqual([511797401, 516564448])
  })
})

describe('extractTrades — costs and P&L composition', () => {
  it('adds signed costs into net P&L and flips positive broker costs', () => {
    const rows = [
      MT5_HEADER.split(','),
      '2026.03.01 10:00:00,600000001,EURUSDm,buy,0.10,1.10000,1.09000,1.11000,2026.03.01 11:00:00,1.10500,2.50,-1.25,50.00'.split(','),
    ]
    const [trade] = extractTrades(rows)
    expect(trade.commission).toBe(-2.5)
    expect(trade.swap).toBe(-1.25)
    expect(trade.pnl).toBeCloseTo(46.25, 6)
  })

  it('trusts a broker "Net Profit" column without re-adding costs', () => {
    const rows = [
      ['Time', 'Symbol', 'Type', 'Volume', 'Price', 'Price', 'Net Profit', 'Commission', 'Swap'],
      ['2026.03.01 10:00:00', 'EURUSDm', 'buy', '0.10', '1.10000', '1.10500', '46.25', '2.50', '-1.25'],
    ]
    const [trade] = extractTrades(rows)
    expect(trade.pnl).toBeCloseTo(46.25, 6)
  })
})

describe('xmlStringToRows + extractTrades — SpreadsheetML report', () => {
  const header = ['Time', 'Position', 'Symbol', 'Type', 'Volume', 'Price', 'S / L', 'T / P', 'Time', 'Price', 'Commission', 'Swap', 'Profit']
  const data = ['2026.02.10 12:30:03', '511797401', 'GBPUSDm', 'sell', '0.01', '1.36788', '1.36967', '', '2026.02.10 14:30:13', '1.36967', '0', '0', '-1.79']
  const cell = (v: string) => `<Cell><Data ss:Type="String">${v}</Data></Cell>`
  const xml = `<?xml version="1.0"?>
<Workbook xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Worksheet ss:Name="Report"><Table>
<Row>${header.map(cell).join('')}</Row>
<Row>${data.map(cell).join('')}</Row>
</Table></Worksheet></Workbook>`

  it('flattens SpreadsheetML into rows', () => {
    const rows = xmlStringToRows(xml)
    expect(rows).toHaveLength(2)
    expect(rows[0]).toHaveLength(13)
    expect(rows[1][2]).toBe('GBPUSDm')
  })

  it('parses the flattened rows into a trade', () => {
    const trades = extractTrades(xmlStringToRows(xml))
    expect(trades).toHaveLength(1)
    expect(trades[0]).toMatchObject({ symbol: 'GBPUSDM', type: 'SELL', ticket: 511797401, pnl: -1.79 })
  })
})

describe('parseFileToRows — CSV entry point', () => {
  it('reads a semicolon-separated CSV via the real File path', async () => {
    const csv = [MT5_HEADER.replace(/,/g, ';'), '2026.02.10 12:30:03;511797401;GBPUSDm;sell;0.01;1.36788;1.36967;;2026.02.10 14:30:13;1.36967;0;0;-1.79'].join('\n')
    const file = new File([csv], 'trades.csv', { type: 'text/csv' })
    const rows = await parseFileToRows(file)
    const trades = extractTrades(rows)
    expect(trades).toHaveLength(1)
    expect(trades[0].pnl).toBe(-1.79)
  })
})
