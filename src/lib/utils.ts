import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
  }).format(value)
}

export function formatNumber(value: number, decimals: number = 2): string {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value)
}

export function formatPercent(value: number): string {
  return `${value.toFixed(1)}%`
}

export function getPointValue(symbol: string): number {
  const s = symbol.toUpperCase().replace(/[^A-Z]/g, '')
  if (s.endsWith('JPY')) return 1000
  if (s.startsWith('XAU') || s.startsWith('GOLD')) return 100
  if (s.startsWith('XAG') || s.startsWith('SILVER')) return 5000
  if (s.startsWith('BTC') || s.startsWith('ETH') || s.startsWith('DOGE') || s.startsWith('SOL') || s.startsWith('ADA') || s.startsWith('XRP') || s.startsWith('DOT') || s.startsWith('AVAX') || s.startsWith('LINK')) return 1
  if (s.startsWith('US30') || s.startsWith('DJ30') || s.startsWith('NAS100') || s.startsWith('NASDAQ') || s.startsWith('SPX500') || s.startsWith('SP500') || s.startsWith('US100') || s.startsWith('DAX') || s.startsWith('DAX40') || s.startsWith('FTSE') || s.startsWith('UK100') || s.startsWith('JP225') || s.startsWith('NIKKEI')) return 1
  if (s.startsWith('USOIL') || s.startsWith('WTI') || s.startsWith('BRN') || s.startsWith('BRENT') || s.startsWith('NATGAS') || s.startsWith('NGAS')) return 1000
  return 100000
}

export function calculatePnL(trade: {
  type: string
  symbol?: string
  entry_price: number
  exit_price: number
  lot_size: number
  commission?: number
  swap?: number
}): number {
  const pointValue = getPointValue(trade.symbol || 'EURUSD')
  let pnl: number
  if (trade.type === 'BUY') {
    pnl = (trade.exit_price - trade.entry_price) * trade.lot_size * pointValue
  } else {
    pnl = (trade.entry_price - trade.exit_price) * trade.lot_size * pointValue
  }
  pnl -= (trade.commission || 0)
  pnl += (trade.swap || 0)
  return pnl
}
