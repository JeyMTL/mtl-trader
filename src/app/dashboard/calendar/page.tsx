'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { ChevronLeft, ChevronRight, TrendingUp, TrendingDown, X, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { formatCurrency, cn } from '@/lib/utils'
import type { DailyPnlRow } from '@/types/journal'

interface CalendarTrade {
  id: string
  symbol: string
  type: string
  entry_price: number
  exit_price: number
  lot_size: number
  pnl: number
  commission: number | null
  swap: number | null
  strategy: string | null
  close_time: string | null
  created_at: string
  open_time: string | null
}

interface DayData {
  date: string
  pnl: number
  trades: number
  wins: number
  losses: number
}

function pad(value: number) {
  return String(value).padStart(2, '0')
}

export default function CalendarPage() {
  const [currentMonth, setCurrentMonth] = useState<Date | null>(null)
  const [dailyData, setDailyData] = useState<Record<string, DayData>>({})
  const [monthLoading, setMonthLoading] = useState(true)
  const [selectedDay, setSelectedDay] = useState<DayData | null>(null)
  const [selectedDayTrades, setSelectedDayTrades] = useState<CalendarTrade[]>([])
  const [dayLoading, setDayLoading] = useState(false)
  const touchStartX = useRef<number | null>(null)

  // Open on the month of the latest trade without downloading the history.
  useEffect(() => {
    let active = true
    async function loadLatest() {
      const { data } = await supabase.rpc('latest_trade_day')
      if (!active) return
      if (typeof data === 'string' && data) {
        const latest = new Date(`${data}T00:00:00`)
        if (!Number.isNaN(latest.getTime())) {
          setCurrentMonth(new Date(latest.getFullYear(), latest.getMonth(), 1))
          return
        }
      }
      setCurrentMonth(new Date())
    }
    loadLatest()
    return () => { active = false }
  }, [])

  const year = currentMonth?.getFullYear() ?? new Date().getFullYear()
  const month = currentMonth?.getMonth() ?? new Date().getMonth()
  const firstDay = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const monthName = new Date(year, month, 1).toLocaleString('default', { month: 'long', year: 'numeric' })

  useEffect(() => {
    if (!currentMonth) return
    let active = true

    async function loadMonth() {
      setMonthLoading(true)
      const from = `${year}-${pad(month + 1)}-01`
      const to = `${year}-${pad(month + 1)}-${pad(daysInMonth)}`
      const { data, error } = await supabase.rpc('daily_pnl', { p_from: from, p_to: to })
      if (!active) return

      const next: Record<string, DayData> = {}
      if (!error) {
        for (const row of (data as DailyPnlRow[] | null) ?? []) {
          const key = String(row.day).slice(0, 10)
          next[key] = {
            date: key,
            pnl: Number(row.pnl) || 0,
            trades: Number(row.trades) || 0,
            wins: 0,
            losses: 0,
          }
        }
      }
      setDailyData(next)
      setMonthLoading(false)
    }

    loadMonth()
    return () => { active = false }
  }, [currentMonth, year, month, daysInMonth])

  const selectDay = useCallback(async (day: DayData) => {
    if (selectedDay?.date === day.date) {
      setSelectedDay(null)
      setSelectedDayTrades([])
      return
    }

    setSelectedDay(day)
    setSelectedDayTrades([])
    setDayLoading(true)

    const { data } = await supabase.rpc('day_trades', { p_day: day.date })
    const rows = (data as CalendarTrade[] | null) ?? []
    setSelectedDayTrades(rows)
    setSelectedDay({
      ...day,
      wins: rows.filter((trade) => Number(trade.pnl) >= 0).length,
      losses: rows.filter((trade) => Number(trade.pnl) < 0).length,
    })
    setDayLoading(false)
  }, [selectedDay])

  const monthlyStats = Object.values(dailyData).reduce(
    (acc, d) => ({
      totalPnl: acc.totalPnl + d.pnl,
      totalTrades: acc.totalTrades + d.trades,
      winningDays: acc.winningDays + (d.pnl > 0 ? 1 : 0),
      losingDays: acc.losingDays + (d.pnl < 0 ? 1 : 0),
      tradingDays: acc.tradingDays + (d.trades > 0 ? 1 : 0),
    }),
    { totalPnl: 0, totalTrades: 0, winningDays: 0, losingDays: 0, tradingDays: 0 }
  )

  const prevMonth = () => {
    setCurrentMonth(new Date(year, month - 1, 1))
    setSelectedDay(null)
    setSelectedDayTrades([])
  }

  const nextMonth = () => {
    setCurrentMonth(new Date(year, month + 1, 1))
    setSelectedDay(null)
    setSelectedDayTrades([])
  }

  // Swipe left/right to change month, like a native calendar.
  const onTouchStart = (event: React.TouchEvent) => {
    touchStartX.current = event.touches[0]?.clientX ?? null
  }

  const onTouchEnd = (event: React.TouchEvent) => {
    if (touchStartX.current === null) return
    const delta = (event.changedTouches[0]?.clientX ?? 0) - touchStartX.current
    touchStartX.current = null
    if (Math.abs(delta) < 60) return
    if (delta > 0) prevMonth()
    else nextMonth()
  }

  const days: Array<number | null> = []
  for (let i = 0; i < firstDay; i++) {
    days.push(null)
  }
  for (let d = 1; d <= daysInMonth; d++) {
    days.push(d)
  }

  return (
    <div className="space-y-4 lg:space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white lg:text-2xl">Trading Calendar</h1>
          <p className="text-gray-400 text-sm mt-1">Daily P&L overview</p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5 sm:gap-4">
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="text-xs text-gray-400 mb-1">Monthly P&L</div>
          <div className={cn("text-lg font-bold", monthlyStats.totalPnl >= 0 ? "text-success" : "text-danger")}>
            {formatCurrency(monthlyStats.totalPnl)}
          </div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="text-xs text-gray-400 mb-1">Total Trades</div>
          <div className="text-lg font-bold text-white">{monthlyStats.totalTrades}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="text-xs text-gray-400 mb-1">Trading Days</div>
          <div className="text-lg font-bold text-white">{monthlyStats.tradingDays}</div>
        </div>
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="text-xs text-gray-400 mb-1">Winning Days</div>
          <div className="text-lg font-bold text-success">{monthlyStats.winningDays}</div>
        </div>
        <div className="col-span-2 rounded-xl border border-border bg-surface p-4 sm:col-span-1">
          <div className="text-xs text-gray-400 mb-1">Losing Days</div>
          <div className="text-lg font-bold text-danger">{monthlyStats.losingDays}</div>
        </div>
      </div>

      <div
        className="bg-surface border border-border rounded-xl p-3 sm:p-6"
        onTouchStart={onTouchStart}
        onTouchEnd={onTouchEnd}
      >
        <div className="flex flex-wrap items-center justify-between gap-3 mb-4 sm:mb-6">
          <button onClick={prevMonth} className="p-2 hover:bg-surface-light rounded-lg transition-colors">
            <ChevronLeft className="w-5 h-5 text-gray-400" />
          </button>
          <h2 className="text-lg font-semibold text-white">{monthName}</h2>
          <button onClick={nextMonth} className="p-2 hover:bg-surface-light rounded-lg transition-colors">
            <ChevronRight className="w-5 h-5 text-gray-400" />
          </button>
        </div>

        <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-2 mb-4 text-[11px] sm:text-xs text-gray-400">
          <span className="inline-flex items-center gap-1.5"><span className="w-2 h-2 rounded-full bg-success" />Profit</span>
          <span className="inline-flex items-center gap-1.5"><span className="w-2 h-2 rounded-full bg-danger" />Loss</span>
          <span className="inline-flex items-center gap-1.5"><span className="w-2 h-2 rounded-full bg-gray-500" />No trades</span>
        </div>

        <div className="grid grid-cols-7 gap-1 mb-2">
          {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day) => (
            <div key={day} className="text-center text-xs font-medium text-gray-500 py-2">
              {day}
            </div>
          ))}
        </div>

        {monthLoading ? (
          <div className="grid grid-cols-7 gap-1">
            {Array.from({ length: 42 }).map((_, i) => (
              <div key={i} className="h-20 sm:h-24 rounded-lg bg-surface-light animate-pulse" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-7 gap-1">
            {days.map((day, i) => {
              if (day === null) return <div key={`empty-${i}`} />
              const dateStr = `${year}-${pad(month + 1)}-${pad(day)}`
              const dayData = dailyData[dateStr]
              const hasTrades = dayData && dayData.trades > 0
              const isProfit = hasTrades && dayData.pnl > 0
              const isLoss = hasTrades && dayData.pnl < 0
              const isSelected = selectedDay?.date === dateStr

              return (
                <button
                  key={day}
                  onClick={() => dayData && hasTrades && selectDay(dayData)}
                  className={cn(
                    "relative h-16 rounded-lg border p-1 text-left transition-all sm:h-24 sm:p-2",
                    !hasTrades && "border-border/50 bg-surface-light/30",
                    hasTrades && !isProfit && !isLoss && "border-border bg-surface-light",
                    isProfit && "border-success/30 bg-success/5",
                    isLoss && "border-danger/30 bg-danger/5",
                    isSelected && "ring-2 ring-primary",
                    hasTrades && "cursor-pointer active:opacity-70"
                  )}
                >
                  <div className="flex items-center justify-between gap-1">
                    <div className="text-xs sm:text-sm text-gray-400">{day}</div>
                    {hasTrades && <span className={cn("w-1.5 h-1.5 rounded-full", isProfit ? "bg-success" : isLoss ? "bg-danger" : "bg-gray-500")} />}
                  </div>
                  {hasTrades && (
                    <>
                      <div className={cn(
                        "mt-0.5 truncate text-[9px] font-semibold tabular-nums sm:mt-1 sm:text-xs",
                        isProfit ? "text-success" : isLoss ? "text-danger" : "text-gray-400"
                      )} title={`${isProfit ? '+' : ''}${formatCurrency(dayData.pnl)}`}>
                        {isProfit ? '+' : ''}{formatCurrency(dayData.pnl)}
                      </div>
                      <div className="mt-0.5 hidden truncate text-[10px] text-gray-500 sm:block">
                        {dayData.trades} {dayData.trades === 1 ? 'trade' : 'trades'}
                      </div>
                    </>
                  )}
                </button>
              )
            })}
          </div>
        )}
      </div>

      {selectedDay && (
        <>
        <button
          type="button"
          aria-label="Close day details"
          onClick={() => { setSelectedDay(null); setSelectedDayTrades([]) }}
          className="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm lg:hidden"
        />
        <div className="mobile-sheet fixed inset-x-0 bottom-0 z-50 max-h-[85dvh] overflow-y-auto rounded-t-3xl border-t border-border bg-surface p-4 lg:static lg:max-h-none lg:rounded-xl lg:border lg:p-6">
          <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-border lg:hidden" />
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-white">
              {new Date(selectedDay.date + 'T00:00:00').toLocaleDateString('default', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}
            </h3>
            <button
              onClick={() => { setSelectedDay(null); setSelectedDayTrades([]) }}
              className="p-1 hover:bg-surface-light rounded-lg transition-colors"
            >
              <X className="w-5 h-5 text-gray-400" />
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
            <div className="col-span-2 sm:col-span-1">
              <div className="text-xs text-gray-400">Net daily P&amp;L</div>
              <div className={cn("text-xl font-bold", selectedDay.pnl >= 0 ? "text-success" : "text-danger")}>
                {formatCurrency(selectedDay.pnl)}
              </div>
            </div>
            <div>
              <div className="text-xs text-gray-400">Trades</div>
              <div className="text-xl font-bold text-white">{selectedDay.trades}</div>
            </div>
            <div>
              <div className="text-xs text-gray-400">Wins</div>
              <div className="text-xl font-bold text-success">{selectedDay.wins}</div>
            </div>
            <div>
              <div className="text-xs text-gray-400">Losses</div>
              <div className="text-xl font-bold text-danger">{selectedDay.losses}</div>
            </div>
          </div>

          {dayLoading ? (
            <div className="flex items-center gap-2 text-gray-400 text-sm">
              <Loader2 className="w-4 h-4 animate-spin" /> Loading trades...
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-border">
                    <th className="text-left px-3 py-2 text-xs font-medium text-gray-400 uppercase">Time</th>
                    <th className="text-left px-3 py-2 text-xs font-medium text-gray-400 uppercase">Symbol</th>
                    <th className="text-left px-3 py-2 text-xs font-medium text-gray-400 uppercase">Type</th>
                    <th className="text-right px-3 py-2 text-xs font-medium text-gray-400 uppercase">Entry</th>
                    <th className="text-right px-3 py-2 text-xs font-medium text-gray-400 uppercase">Exit</th>
                    <th className="text-right px-3 py-2 text-xs font-medium text-gray-400 uppercase">Lot</th>
                    <th className="text-right px-3 py-2 text-xs font-medium text-gray-400 uppercase">P&L</th>
                    {selectedDayTrades.some((t) => t.strategy) && (
                      <th className="text-left px-3 py-2 text-xs font-medium text-gray-400 uppercase">Strategy</th>
                    )}
                  </tr>
                </thead>
                <tbody>
                  {selectedDayTrades.map((trade) => {
                    const tradePnl = Number(trade.pnl) || 0
                    return (
                      <tr key={trade.id} className="border-b border-border/50 last:border-0 hover:bg-surface-light transition-colors">
                        <td className="px-3 py-2 text-sm text-gray-400">
                          {(trade.close_time || trade.open_time || trade.created_at)?.split('T')[1]?.slice(0, 5) || '-'}
                        </td>
                        <td className="px-3 py-2 text-sm font-medium text-white">{trade.symbol}</td>
                        <td className="px-3 py-2">
                          <span className={cn(
                            "inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full",
                            trade.type === 'BUY' ? "bg-success/10 text-success" : "bg-danger/10 text-danger"
                          )}>
                            {trade.type === 'BUY' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                            {trade.type}
                          </span>
                        </td>
                        <td className="px-3 py-2 text-sm text-gray-300 text-right">{trade.entry_price}</td>
                        <td className="px-3 py-2 text-sm text-gray-300 text-right">{trade.exit_price}</td>
                        <td className="px-3 py-2 text-sm text-gray-300 text-right">{trade.lot_size}</td>
                        <td className={cn("px-3 py-2 text-sm font-medium text-right", tradePnl >= 0 ? "text-success" : "text-danger")}>
                          {tradePnl >= 0 ? '+' : ''}{formatCurrency(tradePnl)}
                        </td>
                        {selectedDayTrades.some((t) => t.strategy) && (
                          <td className="px-3 py-2 text-sm text-gray-400">{trade.strategy || '-'}</td>
                        )}
                      </tr>
                    )
                  })}
                  {selectedDayTrades.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-3 py-6 text-center text-sm text-gray-500">No trades recorded for this day.</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
        </>
      )}
    </div>
  )
}
