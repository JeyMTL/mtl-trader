export interface Trade {
  id: string
  user_id: string
  symbol: string
  type: 'BUY' | 'SELL'
  entry_price: number
  exit_price: number
  lot_size: number
  stop_loss: number
  take_profit: number
  pnl: number
  commission: number
  swap: number
  open_time: string
  close_time: string
  timeframe: string
  strategy: string
  notes: string
  tags: string[]
  created_at: string
}

export interface User {
  id: string
  email: string
  full_name: string
  subscription_tier: 'free' | 'basic' | 'pro'
  subscription_status: 'active' | 'trial' | 'expired' | 'cancelled'
  trial_ends_at: string | null
  trades_remaining: number
  max_trades: number
  created_at: string
}

export interface TradeStats {
  total_trades: number
  win_rate: number
  profit_factor: number
  total_pnl: number
  avg_win: number
  avg_loss: number
  largest_win: number
  largest_loss: number
  avg_rr: number
  max_drawdown: number
  equity_curve: { date: string; equity: number }[]
  win_loss_by_day: { day: string; wins: number; losses: number }[]
  pnl_by_symbol: { symbol: string; pnl: number }[]
}

export interface SubscriptionPlan {
  id: string
  name: string
  price: number
  max_trades: number
  features: string[]
  popular?: boolean
}
