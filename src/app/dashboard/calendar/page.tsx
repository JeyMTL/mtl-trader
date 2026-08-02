'use client'

import { useEffect, useState, useRef, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import { ChevronLeft, ChevronRight, TrendingUp, TrendingDown, X } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { formatCurrency, cn } from '@/lib/utils'

interface Trade {
  id: string
  symbol: string
  type: string
  entry_price: number
  exit_price: number
  lot_size: number
  pnl: number
  commission: number
  swap: number
  strategy: string
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

export default function CalendarPage() {
  const router = useRouter()
  const [currentMonth, setCurrentMonth] = useState(new Date())
  const [allTrades, setAllTrades] = useState<Trade[]>([])
  const [loaded, setLoaded] = useState(false)
  const [selectedDay, setSelectedDay] = useState<DayData | null>(null)
  const mountedRef = useRef(false)

  useEffect(() => {
    async function loadTrades() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/auth/login')
        return
      }

      const { data: trades } = await supabase
        .from('trades')
        .select('id, symbol, type, entry_price, exit_price, lot_size, pnl, commission, swap, strategy, close_time, created_at, open_time')
        .eq('user_id', user.id)

      const tradeList = trades || []
      setAllTrades(tradeList)

      if (tradeList.length > 0) {
        let latestDate = ''
        for (const trade of tradeList) {
          const timeField = trade.close_time || trade.open_time || trade.created_at
          if (timeField && timeField > latestDate) {
            latestDate = timeField
          }
        }
        if (latestDate && !mountedRef.current) {
          const d = new Date(latestDate)
          setCurrentMonth(new Date(d.getFullYear(), d.getMonth(), 1))
        }
      }

      mountedRef.current = true
      setLoaded(true)
    }
    loadTrades()
  }, [router])

  const year = currentMonth.getFullYear()
  const month = currentMonth.getMonth()
  const firstDay = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const monthName = currentMonth.toLocaleString('default', { month: 'long', year: 'numeric' })

  const dailyData = useMemo(() => {
    const data: Record<string, DayData> = {}
    for (const trade of allTrades) {
      const timeField = trade.close_time || trade.open_time || trade.created_at
      if (!timeField) continue
      const day = timeField.split('T')[0]
      if (!day || !day.match(/^\d{4}-\d{2}-\d{2}$/)) continue
      const tradeDate = new Date(day + 'T00:00:00')
      if (tradeDate.getMonth() !== month || tradeDate.getFullYear() !== year) continue
      const pnl = Number(trade.pnl) || 0
      if (!data[day]) {
        data[day] = { date: day, pnl: 0, trades: 0, wins: 0, losses: 0 }
      }
      data[day].pnl += pnl
      data[day].trades += 1
      if (pnl >= 0) {
        data[day].wins += 1
      } else {
        data[day].losses += 1
      }
    }
    return data
  }, [allTrades, month, year])

  const selectedDayTrades = useMemo(() => {
    if (!selectedDay) return []
    return allTrades.filter((trade) => {
      const timeField = trade.close_time || trade.open_time || trade.created_at
      if (!timeField) return false
      return timeField.split('T')[0] === selectedDay.date
    }).sort((a, b) => {
      const aTime = a.close_time || a.open_time || a.created_at
      const bTime = b.close_time || b.open_time || b.created_at
      return aTime.localeCompare(bTime)
    })
  }, [allTrades, selectedDay])

  const monthlyStats = useMemo(() => {
    return Object.values(dailyData).reduce(
      (acc, d) => ({
        totalPnl: acc.totalPnl + d.pnl,
        totalTrades: acc.totalTrades + d.trades,
        winningDays: acc.winningDays + (d.pnl > 0 ? 1 : 0),
        losingDays: acc.losingDays + (d.pnl < 0 ? 1 : 0),
        tradingDays: acc.tradingDays + (d.trades > 0 ? 1 : 0),
      }),
      { totalPnl: 0, totalTrades: 0, winningDays: 0, losingDays: 0, tradingDays: 0 }
    )
  }, [dailyData])

  const prevMonth = () => {
    setCurrentMonth(new Date(year, month - 1, 1))
    setSelectedDay(null)
  }

  const nextMonth = () => {
    setCurrentMonth(new Date(year, month + 1, 1))
    setSelectedDay(null)
  }

  const days = []
  for (let i = 0; i < firstDay; i++) {
    days.push(null)
  }
  for (let d = 1; d <= daysInMonth; d++) {
    days.push(d)
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Trading Calendar</h1>
          <p className="text-gray-400 text-sm mt-1">Daily P&L overview</p>
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-5 gap-4">
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
        <div className="bg-surface border border-border rounded-xl p-4">
          <div className="text-xs text-gray-400 mb-1">Losing Days</div>
          <div className="text-lg font-bold text-danger">{monthlyStats.losingDays}</div>
        </div>
      </div>

      <div className="bg-surface border border-border rounded-xl p-6">
        <div className="flex items-center justify-between mb-6">
          <button onClick={prevMonth} className="p-2 hover:bg-surface-light rounded-lg transition-colors">
            <ChevronLeft className="w-5 h-5 text-gray-400" />
          </button>
          <h2 className="text-lg font-semibold text-white">{monthName}</h2>
          <button onClick={nextMonth} className="p-2 hover:bg-surface-light rounded-lg transition-colors">
            <ChevronRight className="w-5 h-5 text-gray-400" />
          </button>
        </div>

        <div className="grid grid-cols-7 gap-1 mb-2">
          {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day) => (
            <div key={day} className="text-center text-xs font-medium text-gray-500 py-2">
              {day}
            </div>
          ))}
        </div>

        {!loaded ? (
          <div className="grid grid-cols-7 gap-1">
            {Array.from({ length: 42 }).map((_, i) => (
              <div key={i} className="h-24 rounded-lg bg-surface-light animate-pulse" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-7 gap-1">
            {days.map((day, i) => {
              if (day === null) return <div key={`empty-${i}`} />
              const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
              const dayData = dailyData[dateStr]
              const hasTrades = dayData && dayData.trades > 0
              const isProfit = hasTrades && dayData.pnl > 0
              const isLoss = hasTrades && dayData.pnl < 0
              const isSelected = selectedDay?.date === dateStr

              return (
                <button
                  key={day}
                  onClick={() => hasTrades && setSelectedDay(isSelected ? null : dayData)}
                  className={cn(
                    "h-24 rounded-lg border p-2 text-left transition-all relative",
                    !hasTrades && "border-border/50 bg-surface-light/30",
                    hasTrades && !isProfit && !isLoss && "border-border bg-surface-light",
                    isProfit && "border-success/30 bg-success/5",
                    isLoss && "border-danger/30 bg-danger/5",
                    isSelected && "ring-2 ring-primary",
                    hasTrades && "hover:ring-1 hover:ring-primary/50 cursor-pointer"
                  )}
                >
                  <div className="text-sm text-gray-400">{day}</div>
                  {hasTrades && (
                    <>
                      <div className={cn(
                        "text-xs font-semibold mt-1",
                        isProfit ? "text-success" : isLoss ? "text-danger" : "text-gray-400"
                      )}>
                        {formatCurrency(dayData.pnl)}
                      </div>
                      <div className="text-[10px] text-gray-500 mt-0.5">
                        {dayData.trades} trade{dayData.trades !== 1 ? 's' : ''}
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
        <div className="bg-surface border border-border rounded-xl p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-white">
              {new Date(selectedDay.date + 'T00:00:00').toLocaleDateString('default', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}
            </h3>
            <button onClick={() => setSelectedDay(null)} className="p-1 hover:bg-surface-light rounded-lg transition-colors">
              <X className="w-5 h-5 text-gray-400" />
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
            <div>
              <div className="text-xs text-gray-400">Daily P&L</div>
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
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
