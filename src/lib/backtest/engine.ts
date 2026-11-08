/**
 * The simulation loop.
 *
 * The rules, stated up front because a backtest is only as good as its worst
 * assumption:
 *
 *  - **Decide on the close, fill on the next open.** A signal computed from bar
 *    i cannot be traded at bar i's price; it is queued and filled at i+1's open.
 *  - **Costs on every fill.** Half the spread and the full slippage are applied
 *    against the trader on both entry and exit, and the commission is charged
 *    once per round turn.
 *  - **Pessimistic intrabar order.** If a bar's range touches both the stop and
 *    the target, the stop is assumed to have filled first. Without tick data
 *    there is no way to know the true order, and assuming the better one is how
 *    backtests end up lying.
 *  - **Gaps fill at the open.** A bar that opens beyond the stop exits at the
 *    open, which is worse than the stop, exactly as it would live.
 *  - **Size from risk.** Lots are chosen so a stop-out costs `riskPercent` of
 *    equity, then capped by `maxLeverage`.
 *  - **Close at the end.** A position still open on the last bar is marked out at
 *    that close, so the reported P&L is realised, not paper.
 */

import type { Bar, BacktestConfig, SimulationResult, Trade } from './types'
import type { Signal, StrategyDefinition } from './strategies'

interface OpenPosition {
  side: 'long' | 'short'
  lots: number
  /** Effective fill price, costs included. */
  entryPrice: number
  /** Raw fill price, costs excluded. */
  entryRaw: number
  stopPrice: number
  takeProfitPrice: number
  entryTime: number
  entryIndex: number
  riskAmount: number
}

interface PendingEntry {
  side: 'long' | 'short'
  stopPrice: number
  takeProfitPrice: number
}

const MIN_LOTS = 0.01

/** Rounds down to the 0.01 lot step brokers accept. */
function roundLots(lots: number): number {
  return Math.floor(lots * 100) / 100
}

export function simulate(
  bars: Bar[],
  definition: StrategyDefinition,
  params: Record<string, number>,
  config: BacktestConfig
): SimulationResult {
  if (bars.length < 2) {
    throw new Error('A backtest needs at least two bars.')
  }

  const signals = definition.signals(bars, params)
  const half = Math.max(0, config.costs.spread) / 2
  const slip = Math.max(0, config.costs.slippage)
  const commission = Math.max(0, config.costs.commission)

  // The position lives in an object rather than a bare `let`: it is replaced by
  // the helpers below, and TypeScript cannot track assignments made inside
  // closures, which narrows a plain variable to `never` at the call sites.
  const state: { position: OpenPosition | null } = { position: null }

  let balance = config.initialBalance
  let pendingEntry: PendingEntry | null = null
  let pendingExit = false
  let exposureBars = 0
  let leverageCapped = false
  // Counted rather than guessed at: when a bar spans both levels the engine takes
  // the stop, and how often that happened is the honest size of the error that
  // assumption introduces.
  let ambiguousExits = 0

  const trades: Trade[] = []
  const equity: SimulationResult['equity'] = []

  const openPosition = (
    bar: Bar,
    rawFill: number,
    entry: PendingEntry,
    index: number
  ) => {
    const direction = entry.side === 'long' ? 1 : -1
    const stopDistance = Math.abs(rawFill - entry.stopPrice)
    if (!(stopDistance > 0)) return

    const riskAmount = balance * (config.riskPercent / 100)
    if (!(riskAmount > 0)) return

    let lots = roundLots(riskAmount / (stopDistance * config.contractSize))

    const notionalPerLot = config.contractSize * rawFill
    const maxNotional = balance * config.maxLeverage
    if (notionalPerLot > 0 && lots * notionalPerLot > maxNotional) {
      lots = roundLots(maxNotional / notionalPerLot)
      leverageCapped = true
    }
    if (lots < MIN_LOTS) return

    state.position = {
      side: entry.side,
      lots,
      entryRaw: rawFill,
      entryPrice: rawFill + direction * (half + slip),
      stopPrice: entry.stopPrice,
      takeProfitPrice: entry.takeProfitPrice,
      entryTime: bar.time,
      entryIndex: index,
      riskAmount,
    }
  }

  const closePosition = (
    bar: Bar,
    rawPrice: number,
    index: number,
    reason: Trade['exitReason']
  ) => {
    const position = state.position
    if (!position) return
    const direction = position.side === 'long' ? 1 : -1
    const exitPrice = rawPrice - direction * (half + slip)

    const grossPnl =
      (rawPrice - position.entryRaw) * direction * position.lots * config.contractSize
    const netBeforeCommission =
      (exitPrice - position.entryPrice) * direction * position.lots * config.contractSize
    const pnl = netBeforeCommission - commission
    const costs = Math.abs(grossPnl - netBeforeCommission) + commission

    balance += pnl
    trades.push({
      side: position.side,
      entryTime: position.entryTime,
      exitTime: bar.time,
      entryPrice: position.entryPrice,
      exitPrice,
      stopPrice: position.stopPrice,
      takeProfitPrice: position.takeProfitPrice,
      lots: position.lots,
      grossPnl,
      costs,
      pnl,
      riskAmount: position.riskAmount,
      rMultiple: position.riskAmount > 0 ? pnl / position.riskAmount : 0,
      barsHeld: Math.max(1, index - position.entryIndex),
      exitReason: reason,
    })
    state.position = null
  }

  /** Stop, target and gap handling for the bar that has just opened. */
  const checkExits = (bar: Bar, index: number) => {
    const position = state.position
    if (!position) return
    const { side, stopPrice, takeProfitPrice } = position

    if (side === 'long') {
      if (bar.open <= stopPrice) return closePosition(bar, bar.open, index, 'stop')
      if (bar.open >= takeProfitPrice) return closePosition(bar, bar.open, index, 'target')
      const hitStop = bar.low <= stopPrice
      const hitTarget = bar.high >= takeProfitPrice
      if (hitStop && hitTarget) ambiguousExits += 1
      if (hitStop) return closePosition(bar, stopPrice, index, 'stop')
      if (hitTarget) return closePosition(bar, takeProfitPrice, index, 'target')
    } else {
      if (bar.open >= stopPrice) return closePosition(bar, bar.open, index, 'stop')
      if (bar.open <= takeProfitPrice) return closePosition(bar, bar.open, index, 'target')
      const hitStop = bar.high >= stopPrice
      const hitTarget = bar.low <= takeProfitPrice
      if (hitStop && hitTarget) ambiguousExits += 1
      if (hitStop) return closePosition(bar, stopPrice, index, 'stop')
      if (hitTarget) return closePosition(bar, takeProfitPrice, index, 'target')
    }
  }

  for (let index = 0; index < bars.length; index += 1) {
    const bar = bars[index]
    if (!bar) continue
    const inMarketAtStart = state.position !== null

    // 1. Orders queued at the previous close fill at this open.
    if (state.position && pendingExit) {
      closePosition(bar, bar.open, index, 'signal')
    }
    if (pendingEntry) {
      if (state.position) closePosition(bar, bar.open, index, 'signal')
      openPosition(bar, bar.open, pendingEntry, index)
    }
    pendingExit = false
    pendingEntry = null

    // 2. Stop and target inside this bar.
    checkExits(bar, index)

    // 3. Mark to market before the next decision.
    const open = state.position
    const unrealised = open
      ? (bar.close - open.entryPrice) *
        (open.side === 'long' ? 1 : -1) *
        open.lots *
        config.contractSize
      : 0
    equity.push({ time: bar.time, equity: balance + unrealised, balance })

    if (inMarketAtStart || state.position !== null) exposureBars += 1

    // 4. Decide on this close, for the next open.
    const signal: Signal | null = signals[index] ?? null
    if (!signal) continue

    if (signal.action === 'close') {
      if (state.position) pendingExit = true
      continue
    }

    const side: 'long' | 'short' = signal.action === 'long' ? 'long' : 'short'
    if (state.position && state.position.side === side) continue
    if (
      signal.stopPrice === undefined ||
      signal.takeProfitPrice === undefined ||
      !Number.isFinite(signal.stopPrice) ||
      !Number.isFinite(signal.takeProfitPrice)
    ) {
      continue
    }

    pendingEntry = {
      side,
      stopPrice: signal.stopPrice,
      takeProfitPrice: signal.takeProfitPrice,
    }
  }

  // A position still open at the end is marked out at the last close.
  const last = bars[bars.length - 1]
  if (state.position && last) {
    closePosition(last, last.close, bars.length - 1, 'end')
    const finalPoint = equity[equity.length - 1]
    if (finalPoint) {
      finalPoint.equity = balance
      finalPoint.balance = balance
    }
  }

  return {
    trades,
    equity,
    exposureBars,
    barCount: bars.length,
    from: bars[0]?.time ?? 0,
    to: last?.time ?? 0,
    leverageCapped,
    ambiguousExits,
  }
}
