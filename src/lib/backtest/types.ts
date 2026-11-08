/**
 * Backtest data model.
 *
 * Every money value is in the instrument's quote currency. The engine does no FX
 * conversion, because a run over EURUSD on a USD account and one on a EUR account
 * are genuinely different bets and silently converting would produce a
 * confident wrong answer. The assumptions list on every result says so.
 */

export interface Bar {
  /** Epoch milliseconds, UTC. */
  time: number
  open: number
  high: number
  low: number
  close: number
  volume?: number
}

export interface CostModel {
  /** Full spread in price units, split half per side. */
  spread: number
  /** Slippage in price units, always applied against the trader. */
  slippage: number
  /** Commission per round-turn trade, in account currency. */
  commission: number
}

export interface BacktestConfig {
  symbol: string
  initialBalance: number
  /** Percent of equity risked between entry and stop. */
  riskPercent: number
  /** Units of the base asset in 1.00 lot: 100000 FX, 100 gold, 1 crypto. */
  contractSize: number
  /** Cap on notional exposure as a multiple of equity. */
  maxLeverage: number
  costs: CostModel
}

export type TradeSide = 'long' | 'short'

export type ExitReason = 'stop' | 'target' | 'signal' | 'end'

export interface Trade {
  side: TradeSide
  entryTime: number
  exitTime: number
  /** Effective fill, spread and slippage already included. */
  entryPrice: number
  /** Effective fill, spread and slippage already included. */
  exitPrice: number
  stopPrice: number
  takeProfitPrice: number
  lots: number
  /** P&L on raw prices, before any cost. */
  grossPnl: number
  /** Spread, slippage and commission actually charged. */
  costs: number
  /** Gross minus costs: what the account moves by. */
  pnl: number
  riskAmount: number
  /** P&L as a multiple of the amount risked at entry. */
  rMultiple: number
  barsHeld: number
  exitReason: ExitReason
}

export interface EquityPoint {
  time: number
  equity: number
  balance: number
}

export interface SimulationResult {
  trades: Trade[]
  equity: EquityPoint[]
  /** Bars during which a position was open. */
  exposureBars: number
  barCount: number
  from: number
  to: number
  /** True when the leverage cap, not the risk size, decided a position's size. */
  leverageCapped: boolean
  /**
   * Trades closed on a bar that touched both the stop and the target. The order
   * is unknowable without tick data, so these are where the stop-first
   * assumption actually changed the result.
   */
  ambiguousExits?: number
}
