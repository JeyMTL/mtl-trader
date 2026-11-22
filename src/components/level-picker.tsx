'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CandlestickChart, Loader2, X } from 'lucide-react'
import { chartSymbol } from '@/components/chart-workspace'
import { useChartPalette } from '@/lib/chart-theme'
import { cn, formatPrice } from '@/lib/utils'

/**
 * Pin entry, stop and target straight off a live chart.
 *
 * The phone has carried "Pin levels from chart" into the trade form since the
 * chart existed; the web form only had numeric fields, which meant reading a
 * price off another window and typing it. This is the same gesture here: a
 * candle chart of the trade's own symbol, three markers, and a tap to place the
 * one you are on.
 *
 * It is deliberately its own component rather than the desk chart in a modal.
 * The desk chart owns saved drawings and a workspace toolbar; this needs none of
 * that, and a trader pinning levels for one trade should not be able to delete
 * a level saved last week by accident.
 */

export interface PickedLevels {
  entry: number | null
  stop: number | null
  take: number | null
}

type Marker = 'entry' | 'stop' | 'take'

interface Candle {
  t: number
  o: number
  h: number
  l: number
  c: number
  v: number
}

const MARKERS: { key: Marker; label: string }[] = [
  { key: 'entry', label: 'Entry' },
  { key: 'stop', label: 'Stop' },
  { key: 'take', label: 'Target' },
]

const INTERVALS = ['M5', 'M15', 'H1', 'H4'] as const
type Interval = (typeof INTERVALS)[number]

/** Price decimals that suit the magnitude: 5 for EUR/USD, 3 for gold, 2 for indices. */
export function levelDecimals(price: number): number {
  const magnitude = Math.abs(price)
  if (magnitude >= 100) return 2
  if (magnitude >= 10) return 3
  return 5
}

function priceText(value: number): string {
  return formatPrice(value, levelDecimals(value))
}

interface LevelPickerProps {
  symbol: string
  side: 'BUY' | 'SELL'
  initial: PickedLevels
  onApply: (levels: PickedLevels) => void
  onClose: () => void
}

export function LevelPicker({ symbol, side, initial, onApply, onClose }: LevelPickerProps) {
  const palette = useChartPalette()
  const [interval, setInterval] = useState<Interval>('M15')
  const [candles, setCandles] = useState<Candle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [active, setActive] = useState<Marker>(initial.entry === null ? 'entry' : 'stop')
  const [levels, setLevels] = useState<PickedLevels>(initial)

  const feedSymbol = useMemo(() => chartSymbol(symbol), [symbol])
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const wrapRef = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState({ width: 0, height: 0 })
  const dragging = useRef<Marker | null>(null)

  useEffect(() => {
    let cancelled = false
    const load = async () => {
      try {
        const response = await fetch(
          `/api/market/candles?symbol=${encodeURIComponent(feedSymbol)}&interval=${interval}`,
          { cache: 'no-store' }
        )
        const body = (await response.json()) as { candles?: Candle[]; error?: string }
        if (!response.ok) throw new Error(body.error || 'The chart feed refused this symbol.')
        if (cancelled) return
        setCandles((body.candles ?? []).filter((row) => Number.isFinite(row.c) && row.c > 0))
        setError('')
        setLoading(false)
      } catch (cause) {
        if (cancelled) return
        setCandles([])
        setError(cause instanceof Error ? cause.message : 'The chart feed did not answer.')
        setLoading(false)
      }
    }
    void load()
    return () => {
      cancelled = true
    }
  }, [feedSymbol, interval])

  /** Changing the candle size starts a fresh read, so the spinner belongs there. */
  const changeInterval = (next: Interval) => {
    if (next === interval) return
    setLoading(true)
    setError('')
    setInterval(next)
  }

  // The canvas is sized from its container and redrawn on every change, so a
  // resize or a rotation can never leave a stale chart behind.
  useEffect(() => {
    const element = wrapRef.current
    if (!element) return
    const measure = () => {
      const box = element.getBoundingClientRect()
      setSize({ width: box.width, height: box.height })
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  const bounds = useMemo(() => {
    if (candles.length === 0) return null
    let high = -Infinity
    let low = Infinity
    for (const candle of candles) {
      if (candle.h > high) high = candle.h
      if (candle.l < low) low = candle.l
    }
    for (const value of [levels.entry, levels.stop, levels.take]) {
      if (value === null) continue
      if (value > high) high = value
      if (value < low) low = value
    }
    const pad = (high - low) * 0.08 || high * 0.001 || 1
    return { high: high + pad, low: low - pad }
  }, [candles, levels])

  const priceAt = useCallback(
    (y: number) => {
      if (!bounds || size.height <= 0) return null
      const ratio = 1 - y / size.height
      return bounds.low + (bounds.high - bounds.low) * ratio
    },
    [bounds, size.height]
  )

  const yFor = useCallback(
    (price: number) => {
      if (!bounds) return 0
      const ratio = (price - bounds.low) / (bounds.high - bounds.low)
      return size.height - ratio * size.height
    },
    [bounds, size.height]
  )

  const place = useCallback(
    (marker: Marker, y: number) => {
      const price = priceAt(y)
      if (price === null) return
      setLevels((current) => ({ ...current, [marker]: price }))
    },
    [priceAt]
  )

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas || size.width <= 0 || size.height <= 0) return
    const ratio = window.devicePixelRatio || 1
    canvas.width = Math.round(size.width * ratio)
    canvas.height = Math.round(size.height * ratio)
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
    ctx.clearRect(0, 0, size.width, size.height)

    // Grid: four hairlines, the same weight the desk chart uses.
    ctx.strokeStyle = palette.grid
    ctx.lineWidth = 1
    for (let step = 1; step < 5; step += 1) {
      const y = (size.height / 5) * step
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(size.width, y)
      ctx.stroke()
    }

    if (candles.length > 0 && bounds) {
      const slot = size.width / candles.length
      const body = Math.max(1, Math.min(10, slot * 0.62))
      candles.forEach((candle, index) => {
        const x = slot * index + slot / 2
        const up = candle.c >= candle.o
        ctx.strokeStyle = up ? palette.profit : palette.loss
        ctx.fillStyle = ctx.strokeStyle
        const top = yFor(Math.max(candle.o, candle.c))
        const bottom = yFor(Math.min(candle.o, candle.c))
        ctx.beginPath()
        ctx.moveTo(x, yFor(candle.h))
        ctx.lineTo(x, yFor(candle.l))
        ctx.stroke()
        ctx.fillRect(x - body / 2, top, body, Math.max(1, bottom - top))
      })
    }

    // Pinned levels: a dashed line across, the label in the right gutter.
    const rows: { key: Marker; value: number | null; color: string }[] = [
      { key: 'entry', value: levels.entry, color: palette.brass },
      { key: 'stop', value: levels.stop, color: palette.loss },
      { key: 'take', value: levels.take, color: palette.profit },
    ]
    ctx.font = '600 10px ui-monospace, monospace'
    ctx.textBaseline = 'middle'
    for (const row of rows) {
      if (row.value === null || !bounds) continue
      const y = yFor(row.value)
      ctx.save()
      ctx.setLineDash([4, 3])
      ctx.strokeStyle = row.color
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(size.width, y)
      ctx.stroke()
      ctx.restore()
      const label = `${row.key === 'take' ? 'target' : row.key} ${priceText(row.value)}`
      const width = ctx.measureText(label).width + 10
      ctx.fillStyle = row.color
      ctx.fillRect(size.width - width, y - 8, width, 16)
      ctx.fillStyle = '#0b0d10'
      ctx.fillText(label, size.width - width + 5, y)
    }
  }, [bounds, candles, levels, palette, size, yFor])

  const distance = useMemo(() => {
    const { entry, stop, take } = levels
    if (entry === null || stop === null || take === null) return null
    const risk = Math.abs(entry - stop)
    const reward = Math.abs(take - entry)
    if (risk <= 0) return null
    return { risk, reward, ratio: reward / risk }
  }, [levels])

  const sideMakesSense = useMemo(() => {
    const { entry, stop, take } = levels
    if (entry === null) return true
    if (stop === null && take === null) return true
    // A stop on the wrong side of entry is a typo, not a strategy.
    if (stop !== null && side === 'BUY' && stop > entry) return false
    if (stop !== null && side === 'SELL' && stop < entry) return false
    if (take !== null && side === 'BUY' && take < entry) return false
    if (take !== null && side === 'SELL' && take > entry) return false
    return true
  }, [levels, side])

  const onPointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const box = event.currentTarget.getBoundingClientRect()
    dragging.current = active
    place(active, event.clientY - box.top)
  }

  const onPointerMove = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!dragging.current) return
    const box = event.currentTarget.getBoundingClientRect()
    place(dragging.current, event.clientY - box.top)
  }

  const stopDragging = () => {
    dragging.current = null
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-0 sm:items-center sm:p-6">
      <div className="flex h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-t-2xl border border-border bg-surface sm:h-[80vh] sm:rounded-2xl">
        <div className="flex items-center gap-3 border-b border-border px-4 py-3">
          <CandlestickChart className="h-4 w-4 text-primary" />
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">
              Pin levels · {feedSymbol}
            </p>
            <p className="text-[11px] text-gray-500">
              Tap the chart to place the marker you pick, then drag it to adjust.
            </p>
          </div>
          <div className="ml-auto flex items-center gap-2">
            <select
              value={interval}
              onChange={(event) => changeInterval(event.target.value as Interval)}
              className="rounded-lg border border-border bg-background px-2 py-1 text-xs text-gray-300"
              aria-label="Candle size"
            >
              {INTERVALS.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
            <button
              type="button"
              onClick={onClose}
              aria-label="Close the level picker"
              className="rounded-lg border border-border p-1.5 text-gray-400 hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        <div ref={wrapRef} className="relative min-h-0 flex-1 bg-background">
          {loading && (
            <div className="absolute inset-0 z-10 flex items-center justify-center">
              <Loader2 className="h-6 w-6 animate-spin text-primary" />
            </div>
          )}
          {!loading && error && (
            <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-2 px-6 text-center">
              <p className="text-sm text-gray-300">{error}</p>
              <p className="text-[11px] text-gray-500">
                The picker needs candles for {feedSymbol}. A symbol the feed cannot
                quote cannot be pinned from.
              </p>
            </div>
          )}
          <canvas
            ref={canvasRef}
            className={cn('h-full w-full touch-none', loading || error ? 'opacity-30' : 'cursor-crosshair')}
            style={{ width: size.width || '100%', height: size.height || '100%' }}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={stopDragging}
            onPointerLeave={stopDragging}
          />
        </div>

        <div className="border-t border-border px-4 py-3">
          <div className="flex flex-wrap items-center gap-2">
            {MARKERS.map((marker) => {
              const value = levels[marker.key]
              return (
                <button
                  key={marker.key}
                  type="button"
                  onClick={() => setActive(marker.key)}
                  aria-pressed={active === marker.key}
                  className={cn(
                    'flex items-center gap-2 rounded-lg border px-3 py-1.5 text-xs',
                    active === marker.key
                      ? 'border-primary/60 bg-primary/10 text-white'
                      : 'border-border text-gray-400 hover:text-white'
                  )}
                >
                  <span className={cn('h-2 w-2 rounded-full', {
                    'bg-brass': marker.key === 'entry',
                    'bg-danger': marker.key === 'stop',
                    'bg-success': marker.key === 'take',
                  })} />
                  {marker.label}
                  <span className="font-mono text-[11px] text-gray-300">
                    {value === null ? '—' : priceText(value)}
                  </span>
                </button>
              )
            })}
            <button
              type="button"
              onClick={() => setLevels({ entry: null, stop: null, take: null })}
              className="ml-auto text-[11px] text-gray-500 hover:text-white"
            >
              Clear
            </button>
          </div>

          {distance && (
            <p className="mt-2 text-[11px] text-gray-500">
              Risk {priceText(distance.risk)} · reward {priceText(distance.reward)} ·{' '}
              <span className={distance.ratio >= 1 ? 'text-success' : 'text-danger'}>
                {distance.ratio.toFixed(2)}R
              </span>
            </p>
          )}
          {!sideMakesSense && (
            <p className="mt-2 text-[11px] text-danger">
              A {side === 'BUY' ? 'long' : 'short'} has its {levels.stop !== null ? 'stop' : 'target'} on
              the wrong side of entry. Move it before using these.
            </p>
          )}

          <div className="mt-3 flex items-center gap-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 rounded-lg border border-border px-4 py-2 text-sm text-gray-300 hover:text-white"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={levels.entry === null || !sideMakesSense}
              onClick={() => onApply(levels)}
              className="btn-gradient flex-1 rounded-lg px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              Use these levels
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
