'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { loadDeskPrefs, saveDeskPrefs } from '@/lib/desk-prefs'
import {
  DEFAULT_SETTINGS,
  isLightCanvas,
  loadLayouts,
  loadSettings,
  loadTemplates,
  removeLayout,
  removeTemplate,
  templateSlug,
  saveSettings,
  upsertLayout,
  upsertTemplate,
  type ChartLayout,
  type ChartTemplate,
  type DeskSettings,
} from '@/lib/desk-settings'
import { ChartSettingsDialog } from '@/components/chart-settings-panel'
import { AnalysisHubDialog, ChartLayoutsDialog } from '@/components/chart-desk-dialogs'
import { alignCompare } from '@/lib/chart-compare'
import { mergeCandleTail, parseChartInterval, tailPollMs } from '@/lib/market-candles'
import { isBasicTimeframe, isProTimeframe, isTimeframeOpen } from '@/lib/subscription'
import { sessionWindows } from '@/lib/market-sessions'
import { publicErrorMessage } from '@/lib/errors'
import {
  deleteCloudTemplate,
  pushCloudTemplate,
  syncTemplates,
} from '@/lib/chart-templates-cloud'
import {
  ChartObjectBar,
  ChartObjectList,
  ChartObjectSettings,
  styleColour,
  styleFill,
  visibleOnInterval,
  type DrawingStyle,
} from '@/components/chart-object-panel'

/**
 * The chart desk: candles, pan, zoom and the objects a trader pins to them.
 *
 * Objects are stored in `chart_drawings`, one row each, with the same `kind`
 * names the phone already uses (`ray` for a horizontal level, `trend`, `fib`,
 * `rectangle`) and the same `points` shape — `{ t, p }` epoch milliseconds and
 * price. That is deliberate: the phone's local store and this table can be
 * merged without translating anything.
 *
 * Rendering is a single canvas rather than one DOM node per candle: 700 bars
 * plus a fib ladder is one paint, and panning stays smooth on a laptop.
 */

export interface ChartDrawingRow {
  id: string
  symbol: string
  kind: string
  points: { t: number; p: number }[]
  text: string | null
  /**
   * Colour, weight, dash, fill and the lock/hide flags. The same JSON keys the
   * phone writes into the `style` column, so the two desks agree.
   */
  style: DrawingStyle
  /** When the trader made the edit, epoch milliseconds. Settles conflicts. */
  editedAtMs: number | null
}

interface Candle {
  t: number
  o: number
  h: number
  l: number
  c: number
  v: number
}

interface Point {
  t: number
  p: number
}

type ToolId =
  | 'select'
  | 'ray'
  | 'alert'
  | 'trend'
  | 'fib'
  | 'rectangle'
  | 'measure'
  | 'vline'

/** A horizontal level derived from the candles rather than pinned by hand. */
interface SessionLevel {
  label: string
  side: 'high' | 'low'
  price: number
  colour: string
}

interface VwapPoint {
  /** Index into `candles`, so a pan does not have to rebuild the series. */
  i: number
  p: number
  /** UTC day bucket; the line resets where this changes. */
  day: number
}

const INTERVALS = [
  { key: '5s', label: '5s' },
  { key: '10s', label: '10s' },
  { key: '15s', label: '15s' },
  { key: '30s', label: '30s' },
  { key: '45s', label: '45s' },
  { key: '1m', label: '1m' },
  { key: '5m', label: '5m' },
  { key: '15m', label: '15m' },
  { key: '30m', label: '30m' },
  { key: '1h', label: '1h' },
  { key: '4h', label: '4h' },
  { key: '1d', label: '1D' },
] as const

const TOOLS: { id: ToolId; label: string; hint: string }[] = [
  { id: 'select', label: 'Select', hint: 'Drag objects, pan the chart' },
  { id: 'ray', label: 'Level', hint: 'Tap a price to pin a level' },
  {
    id: 'alert',
    label: 'Alert',
    hint: 'Tap a price to be told when it is reached',
  },
  { id: 'trend', label: 'Trend', hint: 'Two points' },
  { id: 'fib', label: 'Fib', hint: 'Two points, retracement ladder' },
  { id: 'rectangle', label: 'Zone', hint: 'Two corners' },
  { id: 'vline', label: 'Vertical', hint: 'Tap a time to mark it' },
  { id: 'measure', label: 'Measure', hint: 'Two points, shows the move' },
]

const SYMBOLS = ['EUR_USD', 'GBP_USD', 'USD_JPY', 'XAU_USD', 'US30', 'NAS100']

const AXIS = 64
/** The time gutter under the plot. Reserved, so labels no longer sit on bars. */
const TIME_AXIS = 24
const FIB_LEVELS = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
/** Violet: distinct from the bars, the VWAP amber and the session lines. */
const COMPARE_COLOUR = '#a78bfa'

interface View {
  /** Index of the first visible candle. */
  start: number
  /** How many candles fit across the plot. */
  span: number
}

export function ChartWorkspace({
  initialDrawings,
  defaultSymbol,
  proTimeframes = false,
  paidTimeframes = false,
}: {
  initialDrawings: ChartDrawingRow[]
  defaultSymbol: string
  /**
   * Whether the 5s, 10s and 15s candle sizes are open to this account (Pro or a
   * live trial).
   */
  proTimeframes?: boolean
  /**
   * Whether 30s and 45s are open (Basic, Pro, or a live trial). The free chart
   * runs from a minute up. Each size is listed either way so the upgrade is
   * visible where it is felt; a locked one explains itself instead of moving
   * the chart silently.
   */
  paidTimeframes?: boolean
}) {
  const [symbol, setSymbolInput] = useState(defaultSymbol)
  const [symbolDraft, setSymbolDraft] = useState(defaultSymbol)
  const [interval, setIntervalKey] = useState<string>('1h')
  const [lockedSize, setLockedSize] = useState<{ label: string; tier: 'basic' | 'pro' } | null>(
    null
  )

  // A saved layout or desk preference can name a size this account cannot use
  // any more. Falling back to the smallest size the plan actually serves keeps
  // the chart drawing rather than polling a feed the plan does not include.
  useEffect(() => {
    if (isTimeframeOpen(interval, { pro: proTimeframes, paid: paidTimeframes })) return
    setIntervalKey(paidTimeframes ? '30s' : '1m')
  }, [paidTimeframes, proTimeframes, interval])
  const [candles, setCandles] = useState<Candle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [drawings, setDrawings] = useState<ChartDrawingRow[]>(initialDrawings)
  const [tool, setTool] = useState<ToolId>('select')
  /**
   * Hide alert lines that have already fired. The rows are kept — a level that
   * was reached is still the record of a level — this only decides what the
   * desk draws, the same choice Settings offers on the phone.
   */
  const [activeAlertsOnly, setActiveAlertsOnly] = useState(false)
  const [pending, setPending] = useState<Point | null>(null)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [view, setView] = useState<View>({ start: 0, span: 120 })
  const [hover, setHover] = useState<{ x: number; y: number } | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  /** The object whose settings dialog is open, by id. */
  const [settingsId, setSettingsId] = useState<string | null>(null)
  const [showVwap, setShowVwap] = useState(false)
  const [showSessions, setShowSessions] = useState(false)

  /** The second instrument drawn on this axis, and its own candle series. */
  const [compareSymbol, setCompareSymbol] = useState<string | null>(null)
  const [compareCandles, setCompareCandles] = useState<Candle[]>([])
  const [compareError, setCompareError] = useState<string | null>(null)
  const [compareOpen, setCompareOpen] = useState(false)
  const [compareDraft, setCompareDraft] = useState('')
  /**
   * The chart on the whole viewport, the way the phone's immersive toggle
   * leaves it. The desk inside the dashboard shell is a 62vh block with a
   * sidebar and two headers around it; analysis on a laptop wants the candles.
   */
  const [expanded, setExpanded] = useState(false)
  /**
   * Whether the stored settings have been read yet.
   *
   * The save effect below runs on mount, before the deferred restore lands. Left
   * unguarded it wrote the defaults over the trader's saved look, so every
   * reload quietly reset the desk.
   */
  const settingsRestored = useRef(false)
  /** The desk's own frame, which is the element handed to the browser when the
   * address bar is asked to go away. */
  const frameRef = useRef<HTMLDivElement | null>(null)

  /** What the canvas paints: colours, decimals, crosshair, clock, log axis. */
  const [settings, setSettings] = useState<DeskSettings>(DEFAULT_SETTINGS)
  const [layouts, setLayouts] = useState<ChartLayout[]>([])
  const [templates, setTemplates] = useState<ChartTemplate[]>([])
  const [activeLayoutId, setActiveLayoutId] = useState<string | null>(null)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [layoutsOpen, setLayoutsOpen] = useState(false)
  const [hubOpen, setHubOpen] = useState(false)
  /** Index of the newest candle replay may paint; null is the live chart. */
  const [replayCut, setReplayCut] = useState<number | null>(null)
  const [replayPlaying, setReplayPlaying] = useState(false)
  /** A clock for the bar-close countdown; null when the countdown is off. */
  const [now, setNow] = useState<number | null>(null)

  // Restoring the workspace happens after mount, not in the initial state: the
  // server renders this component too, and reading localStorage while rendering
  // would hand React two different first frames.
  useEffect(() => {
    let cancelled = false
    // Deferred by a tick: the server rendered this frame with the default
    // instrument, and applying storage during the same paint would hand React a
    // different tree than the HTML it just hydrated.
    const restore = window.setTimeout(() => {
      const prefs = loadDeskPrefs()
      if (prefs.symbol) {
        setSymbolInput(prefs.symbol)
        setSymbolDraft(prefs.symbol)
      }
      if (prefs.interval) setIntervalKey(prefs.interval)
      if (typeof prefs.activeAlertsOnly === 'boolean') setActiveAlertsOnly(prefs.activeAlertsOnly)
      if (typeof prefs.vwap === 'boolean') setShowVwap(prefs.vwap)
      if (typeof prefs.sessions === 'boolean') setShowSessions(prefs.sessions)
    }, 0)
    const restoreSettings = window.setTimeout(() => {
      setSettings(loadSettings())
      setLayouts(loadLayouts())
      setTemplates(loadTemplates())
      settingsRestored.current = true
    }, 0)
    // Templates are shared with the phone, so the account's copy is pulled once
    // and merged; whatever the account has not seen is pushed back up there.
    const pullTemplates = window.setTimeout(() => {
      void syncTemplates(loadTemplates()).then((result) => {
        if (cancelled) return
        setTemplates(result.templates)
        if (result.error) setNotice(result.error)
      })
    }, 0)
    return () => {
      cancelled = true
      window.clearTimeout(restore)
      window.clearTimeout(restoreSettings)
      window.clearTimeout(pullTemplates)
    }
  }, [])

  // Settings are the trader's own; they are written the moment they change —
  // but only once the stored ones are in, or the first frame would save the
  // defaults over them.
  useEffect(() => {
    if (!settingsRestored.current) return
    saveSettings(settings)
  }, [settings])

  // The countdown is the only thing on this chart that needs a clock, so it is
  // the only thing that asks for a timer.
  useEffect(() => {
    if (!settings.countdown) return
    // The first tick lands one interval later, which keeps this an effect that
    // subscribes to a clock rather than one that sets state while running.
    const tick = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(tick)
  }, [settings.countdown])

  // One effect for the lot: every one of these is a workspace choice, and each
  // change is merged into what is already stored.
  useEffect(() => {
    saveDeskPrefs({
      symbol,
      interval,
      activeAlertsOnly,
      vwap: showVwap,
      sessions: showSessions,
    })
  }, [symbol, interval, activeAlertsOnly, showVwap, showSessions])

  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const boxRef = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState({ width: 900, height: 520 })
  /**
   * Vertical stretch of the price scale, the same idea as the phone's
   * `_priceZoom`: 1 fits the visible candles, smaller zooms in on the range.
   * Dragging the price gutter changes it.
   */
  const [priceZoom, setPriceZoom] = useState(1)

  useEffect(() => {
    if (!replayPlaying) return
    const id = window.setInterval(() => {
      setReplayCut((cut) => {
        if (cut === null) return null
        return cut >= candles.length - 1 ? cut : cut + 1
      })
    }, 900)
    return () => window.clearInterval(id)
  }, [replayPlaying, candles.length])

  /** Pointer state for a pan or an object drag that is in progress. */
  /** Writes in flight. The poll stands aside while one is running, so a read
   * that left before the write cannot land on top of it and undo it on screen. */
  const pendingWrites = useRef(0)

  const drag = useRef<{
    mode: 'pan' | 'object'
    id?: string
    originX: number
    originY: number
    start: View
    points?: Point[]
  } | null>(null)

  /** A drag that started on one of the axis gutters: it zooms that axis. */
  const axisDrag = useRef<{
    axis: 'price' | 'time'
    startX: number
    startY: number
    baseZoom: number
    baseSpan: number
    baseStart: number
  } | null>(null)

  const visible = useMemo(() => {
    if (candles.length === 0) return []
    const from = Math.max(0, Math.floor(view.start))
    const to = Math.min(candles.length, Math.ceil(view.start + view.span) + 1)
    return candles.slice(from, to)
  }, [candles, view])

  const compareSeries = useMemo(
    () =>
      compareSymbol && compareCandles.length > 0
        ? alignCompare(candles, compareCandles)
        : null,
    [candles, compareCandles, compareSymbol]
  )

  const priceRange = useMemo(() => {
    if (visible.length === 0) return { min: 0, max: 1 }
    let min = Infinity
    let max = -Infinity
    for (const candle of visible) {
      if (candle.l < min) min = candle.l
      if (candle.h > max) max = candle.h
    }
    // The compare line shares the axis, so its range counts too; a line drawn
    // off the top of the plot would be a line the trader cannot see.
    if (compareSeries) {
      const from = Math.max(0, Math.floor(view.start))
      const to = Math.min(candles.length, Math.ceil(view.start + view.span) + 1)
      for (let index = from; index < to; index += 1) {
        const point = compareSeries.points[index]
        if (!point) continue
        if (point.p < min) min = point.p
        if (point.p > max) max = point.p
      }
    }
    // A little air above and below, so a level at the extreme is still grabbable.
    const pad = (max - min) * 0.08 || 0.0004
    min -= pad
    max += pad
    // The trader's vertical stretch, around the middle of the range: the candles
    // keep their centre while the axis stretches, which is what makes a drag on
    // the price gutter feel like the chart rather than the page is moving.
    if (priceZoom !== 1) {
      const mid = (min + max) / 2
      const half = ((max - min) / 2) * priceZoom
      min = mid - half
      max = mid + half
    }
    return { min, max }
  }, [candles.length, compareSeries, priceZoom, view, visible])

  /** Percent move of the compare instrument across what is on screen. */
  const compareChange = useMemo(() => {
    if (!compareSeries) return null
    const from = Math.max(0, Math.floor(view.start))
    const to = Math.min(candles.length, Math.ceil(view.start + view.span) + 1) - 1
    const first = compareSeries.points[from]
    const last = compareSeries.points[to]
    if (!first || !last || first.p <= 0) return null
    return last.p / first.p - 1
  }, [candles.length, compareSeries, view])

  const plotW = Math.max(60, size.width - AXIS)
  /** Decimals on every price: the trader's override, else the instrument's. */
  const decimals = useCallback(
    (price: number) => settings.precision ?? pricePrecision(price),
    [settings.precision]
  )
  const plotH = Math.max(60, size.height - TIME_AXIS)

  const xForIndex = useCallback(
    (index: number) => ((index + 0.5 - view.start) / view.span) * plotW,
    [plotW, view]
  )
  // A log axis is only defined for positive prices; a range that touches zero
  // falls back to linear rather than painting NaN.
  const logAxis = settings.logScale && priceRange.min > 0
  const yForPrice = useCallback(
    (price: number) => {
      if (!logAxis) {
        return plotH - ((price - priceRange.min) / (priceRange.max - priceRange.min)) * plotH
      }
      const low = Math.log(priceRange.min)
      const high = Math.log(priceRange.max)
      const value = Math.log(Math.max(price, Number.MIN_VALUE))
      return plotH - ((value - low) / (high - low)) * plotH
    },
    [logAxis, plotH, priceRange]
  )
  const priceForY = useCallback(
    (y: number) => {
      if (!logAxis) {
        return priceRange.min + ((plotH - y) / plotH) * (priceRange.max - priceRange.min)
      }
      const low = Math.log(priceRange.min)
      const high = Math.log(priceRange.max)
      return Math.exp(low + ((plotH - y) / plotH) * (high - low))
    },
    [logAxis, plotH, priceRange]
  )
  const indexForTime = useCallback(
    (ms: number) => {
      if (candles.length === 0) return 0
      const step = candles.length > 1 ? candles[1].t - candles[0].t : 60_000
      let guess = (ms - candles[0].t) / step
      if (guess <= 0) return 0
      if (guess >= candles.length - 1) return candles.length - 1
      guess = Math.round(guess)
      // Reconciled against the real timestamps, because a daily series skips
      // weekends and a fixed step would drift.
      while (guess > 0 && candles[guess].t > ms) guess -= 1
      while (guess < candles.length - 1 && candles[guess + 1].t <= ms) guess += 1
      return guess
    },
    [candles]
  )

  const timeForIndex = useCallback(
    (index: number) => {
      if (candles.length === 0) return Date.now()
      const clamped = Math.min(candles.length - 1, Math.max(0, Math.round(index)))
      return candles[clamped].t
    },
    [candles]
  )

  // The browser can leave fullscreen without asking — Escape, the phone's back
  // gesture, a system dialog. When it does, the desk's expanded layout goes with
  // it, so the two modes can never disagree about what is on screen.
  useEffect(() => {
    const onChange = () => {
      if (!document.fullscreenElement) setExpanded(false)
    }
    document.addEventListener('fullscreenchange', onChange)
    return () => document.removeEventListener('fullscreenchange', onChange)
  }, [])

  /**
   * Full screen, twice over: the desk fills the viewport in CSS, and the browser
   * is asked to drop its own chrome on top of that.
   *
   * The CSS half is the one that always works. `requestFullscreen` is refused on
   * iPhone Safari for anything but a video, can be blocked by an embedding
   * iframe, and is gone in older browsers — every one of those falls back to the
   * overlay rather than doing nothing, which is why the two are not a choice.
   */
  const toggleFullScreen = () => {
    if (expanded) {
      setExpanded(false)
      if (document.fullscreenElement) {
        void document.exitFullscreen().catch(() => {
          // Exiting is best-effort too: the overlay is already gone.
        })
      }
      return
    }
    setExpanded(true)
    const frame = frameRef.current
    if (!document.fullscreenEnabled || !frame?.requestFullscreen) return
    void frame.requestFullscreen().catch(() => {
      // A refused request leaves the expanded overlay doing the job.
    })
  }

  // Full screen is a mode, so it owns the page while it is on: the dashboard
  // behind it must not scroll under the canvas, and Escape has to give the
  // screen back even when the canvas is not the focused element.
  useEffect(() => {
    if (!expanded) return
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      setExpanded(false)
      // The browser usually takes Escape for itself; when it hands the key to
      // the page instead, the chrome goes with the overlay.
      if (document.fullscreenElement) {
        void document.exitFullscreen().catch(() => {})
      }
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', onKey)
    }
  }, [expanded])

  // ---------------------------------------------------------------- loading
  useEffect(() => {
    let cancelled = false
    async function load() {
      setLoading(true)
      setError(null)
      try {
        const response = await fetch(
          `/api/market/candles?symbol=${encodeURIComponent(chartSymbol(symbol))}&interval=${interval}`,
          { cache: 'no-store' }
        )
        const body = await response.json()
        if (!response.ok) {
          throw new Error(body?.error || `The chart feed answered ${response.status}.`)
        }
        if (cancelled) return
        const next: Candle[] = Array.isArray(body.candles) ? body.candles : []
        setCandles(next)
        const span = Math.min(160, Math.max(40, Math.floor(next.length * 0.45)))
        setView({ start: Math.max(0, next.length - span), span })
        setPending(null)
        // A new instrument or candle size has its own range; keeping a stretch
        // from the last chart would open it somewhere nobody asked for.
        setPriceZoom(1)
      } catch (caught) {
        if (!cancelled) {
          setCandles([])
          setError(publicErrorMessage(caught, 'Could not load candles. Please try again.'))
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => {
      cancelled = true
    }
  }, [symbol, interval])

  // The compare series is loaded on its own: a second instrument that fails to
  // answer must never take the main chart down with it.
  useEffect(() => {
    const clean = compareSymbol
    // Nothing to fetch while there is no compare instrument; the candles are
    // cleared where the overlay is removed, not by running an effect to say so.
    if (!clean) return
    let cancelled = false
    async function load(target: string) {
      try {
        const response = await fetch(
          `/api/market/candles?symbol=${encodeURIComponent(target)}&interval=${interval}`,
          { cache: 'no-store' }
        )
        const body = await response.json()
        if (!response.ok) {
          throw new Error(body?.error || `The compare feed answered ${response.status}.`)
        }
        if (cancelled) return
        setCompareCandles(Array.isArray(body.candles) ? body.candles : [])
        setCompareError(null)
      } catch (caught) {
        if (cancelled) return
        setCompareCandles([])
        setCompareError(
          publicErrorMessage(caught, 'Could not load the compare instrument. Please try again.')
        )
      }
    }
    void load(clean)
    return () => {
      cancelled = true
    }
  }, [compareSymbol, interval])

  // -------------------------------------------------------------- live tail
  /**
   * Keeps the newest candles moving.
   *
   * The desk used to load candles once per symbol and then sit still, so a
   * one-minute chart could be minutes behind the broker until the trader
   * switched timeframes. The tail is refetched while the tab is visible, merged
   * by open time so history does not jump under the pointer, and left alone
   * during replay: replay is a historical window and must not walk forward.
   */
  useEffect(() => {
    if (replayCut !== null) return
    const intervalKey = parseChartInterval(interval) ?? '1m'
    const compare = compareSymbol
    let cancelled = false

    async function tick() {
      // A hidden tab has nobody looking at it; focus catches up immediately.
      if (document.visibilityState !== 'visible') return
      try {
        const response = await fetch(
          `/api/market/candles?symbol=${encodeURIComponent(chartSymbol(symbol))}&interval=${interval}&tail=1`,
          { cache: 'no-store' }
        )
        if (!response.ok) return
        const body = await response.json()
        const next: Candle[] = Array.isArray(body?.candles) ? body.candles : []
        if (cancelled || next.length === 0) return
        setCandles((current) => mergeCandleTail(current, next))
      } catch {
        // Keep the last good chart; the next tick retries.
      }

      if (!compare) return
      try {
        const response = await fetch(
          `/api/market/candles?symbol=${encodeURIComponent(compare)}&interval=${interval}&tail=1`,
          { cache: 'no-store' }
        )
        if (!response.ok) return
        const body = await response.json()
        const next: Candle[] = Array.isArray(body?.candles) ? body.candles : []
        if (cancelled || next.length === 0) return
        setCompareCandles((current) => mergeCandleTail(current, next))
      } catch {
        // A failed overlay refresh keeps the last overlay.
      }
    }

    const timer = window.setInterval(() => void tick(), tailPollMs(intervalKey))
    const onWake = () => void tick()
    document.addEventListener('visibilitychange', onWake)
    window.addEventListener('focus', onWake)
    return () => {
      cancelled = true
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onWake)
      window.removeEventListener('focus', onWake)
    }
  }, [symbol, interval, compareSymbol, replayCut])

  const symbolDrawings = useMemo(
    () => drawings.filter((row) => row.symbol === chartSymbol(symbol)),
    [drawings, symbol]
  )

  /** The object the strip below the tools acts on. */
  const selectedRow = useMemo(
    () => symbolDrawings.find((row) => row.id === selectedId) ?? null,
    [symbolDrawings, selectedId]
  )
  const settingsRow = useMemo(
    () => symbolDrawings.find((row) => row.id === settingsId) ?? null,
    [settingsId, symbolDrawings]
  )

  /**
   * Session VWAP: typical price weighted by tick volume, reset at each UTC day.
   * A vendor that reports no volume falls back to a plain average of the typical
   * price rather than drawing a flat line at zero.
   */
  const vwap = useMemo<VwapPoint[]>(() => {
    if (!showVwap || candles.length === 0) return []
    const out: VwapPoint[] = []
    let day = -1
    let weighted = 0
    let volume = 0
    let sum = 0
    let count = 0
    for (let index = 0; index < candles.length; index += 1) {
      const candle = candles[index]
      const bucket = Math.floor(candle.t / 86_400_000)
      if (bucket !== day) {
        day = bucket
        weighted = 0
        volume = 0
        sum = 0
        count = 0
      }
      const typical = (candle.h + candle.l + candle.c) / 3
      sum += typical
      count += 1
      if (candle.v > 0) {
        weighted += typical * candle.v
        volume += candle.v
      }
      out.push({ i: index, p: volume > 0 ? weighted / volume : sum / count, day })
    }
    return out
  }, [candles, showVwap])

  /**
   * Asia / London / New York high and low for the most recent session.
   *
   * The windows come from `market-sessions`, which defines them in each city's
   * own zone, so daylight saving is applied and the levels are identical for a
   * viewer in Lusaka and one in New York. London and New York deliberately
   * overlap; that overlap is the point of the levels.
   */
  const sessionLevels = useMemo<SessionLevel[]>(() => {
    if (!showSessions || candles.length === 0) return []
    const levels: SessionLevel[] = []
    for (const window of sessionWindows(candles[candles.length - 1].t)) {
      let high = -Infinity
      let low = Infinity
      for (const candle of candles) {
        if (candle.t < window.from || candle.t >= window.to) continue
        if (candle.h > high) high = candle.h
        if (candle.l < low) low = candle.l
      }
      if (!Number.isFinite(high) || !Number.isFinite(low)) continue
      levels.push({ label: window.name, side: 'high', price: high, colour: window.colour })
      levels.push({ label: window.name, side: 'low', price: low, colour: window.colour })
    }
    return levels
  }, [candles, showSessions])

  // ------------------------------------------------------- layouts and replay
  /** Opens a saved layout: its instrument, interval and paint settings. */
  const openLayout = (layout: ChartLayout) => {
    setSettings(layout.settings)
    setSymbolInput(layout.symbol)
    setSymbolDraft(layout.symbol)
    setIntervalKey(layout.interval)
    setActiveLayoutId(layout.id)
    setLayoutsOpen(false)
    setHubOpen(false)
  }

  const saveCurrentLayout = (name: string) => {
    const layout: ChartLayout = {
      id: `layout-${Date.now()}`,
      name,
      symbol: chartSymbol(symbol),
      interval,
      settings,
      savedAt: Date.now(),
    }
    setLayouts(upsertLayout(layouts, layout))
    setActiveLayoutId(layout.id)
  }

  const deleteLayout = (id: string) => {
    setLayouts(removeLayout(layouts, id))
    if (activeLayoutId === id) setActiveLayoutId(null)
  }

  /** Templates carry the paint only, so saving one never touches instrument or interval. */
  const saveTemplate = (name: string) => {
    const next = upsertTemplate(templates, { name, settings })
    setTemplates(next)
    const saved = next.find((entry) => templateSlug(entry.name) === templateSlug(name))
    if (!saved) return
    void pushCloudTemplate(saved).then((failure) => {
      if (failure) setNotice(failure)
    })
  }

  const deleteTemplate = (name: string) => {
    setTemplates(removeTemplate(templates, name))
    void deleteCloudTemplate(name).then((failure) => {
      if (failure) setNotice(failure)
    })
  }

  /** Adds a compare instrument; the one already charted would be a flat line. */
  const addCompare = (raw: string) => {
    const next = chartSymbol(raw)
    if (!next) return
    if (next === chartSymbol(symbol)) {
      setCompareError('Compare needs a different instrument.')
      return
    }
    setCompareSymbol(next)
    setCompareDraft(next)
    setCompareOpen(false)
    setCompareError(null)
  }

  const removeCompare = () => {
    setCompareSymbol(null)
    setCompareCandles([])
    setCompareError(null)
    setCompareDraft('')
    setCompareOpen(false)
  }

  const newLayout = () => {
    setSettings({ ...DEFAULT_SETTINGS })
    setActiveLayoutId(null)
    setHubOpen(false)
  }

  const startReplay = () => {
    if (candles.length < 20) return
    // Sixty bars back is enough to see the setup that led to now without
    // making the trader walk through a session by hand.
    setReplayCut(Math.max(1, candles.length - 60))
    setReplayPlaying(false)
  }

  const stopReplay = () => {
    setReplayCut(null)
    setReplayPlaying(false)
  }

  const stepReplay = () =>
    setReplayCut((cut) => Math.min(candles.length - 1, (cut ?? candles.length - 1) + 1))

  const activeAlertCount = symbolDrawings.filter((row) => row.style?.al && !row.style?.fd).length

  // ------------------------------------------------------------------ paint
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ratio = window.devicePixelRatio || 1
    canvas.width = Math.round(size.width * ratio)
    canvas.height = Math.round(size.height * ratio)
    const context = canvas.getContext('2d')
    if (!context) return
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
    context.clearRect(0, 0, size.width, size.height)
    if (settings.gradient) {
      const gradient = context.createLinearGradient(0, 0, 0, size.height)
      gradient.addColorStop(0, settings.background)
      gradient.addColorStop(1, settings.gradientTo)
      context.fillStyle = gradient
      context.fillRect(0, 0, size.width, size.height)
    }

    // The two axis gutters first: a panel each, so the labels have somewhere to
    // live that is not on top of the candles. `axisInk` is deliberately brighter
    // than the old #6b7280, which was under 4.5:1 on this canvas.
    const lightCanvas = isLightCanvas(settings)
    const axisInk = lightCanvas ? '#334155' : '#9aa4b2'
    const gridInk = lightCanvas ? 'rgba(15, 23, 42, 0.12)' : 'rgba(148, 163, 184, 0.12)'
    const crosshairInk = lightCanvas ? 'rgba(15, 23, 42, 0.5)' : 'rgba(226, 232, 240, 0.45)'
    const axisPanel = lightCanvas ? 'rgba(15, 23, 42, 0.05)' : 'rgba(148, 163, 184, 0.07)'
    context.fillStyle = axisPanel
    context.fillRect(plotW, 0, AXIS, plotH)
    context.fillRect(0, plotH, size.width, TIME_AXIS)
    context.strokeStyle = gridInk
    context.beginPath()
    context.moveTo(plotW + 0.5, 0)
    context.lineTo(plotW + 0.5, size.height)
    context.moveTo(0, plotH + 0.5)
    context.lineTo(size.width, plotH + 0.5)
    context.stroke()

    // Grid and axes. The price labels are pixel-density ticks on a 1-2-2.5-5
    // ladder: four fixed gridlines left fat empty bands on a tall chart and a
    // crowded smear on a short one, and neither reads as a price.
    context.font = '10px ui-sans-serif, system-ui, sans-serif'
    context.fillStyle = axisInk
    context.strokeStyle = gridInk
    context.lineWidth = 1
    // Replay paints up to the bar the trader has walked to, and no further: the
    // candles after it exist but are not history yet.
    const lastPaintable = replayCut === null ? candles.length - 1 : Math.min(replayCut, candles.length - 1)
    const liveShown = candles[lastPaintable]
    const liveY = liveShown ? yForPrice(liveShown.c) : null
    let previousPriceY: number | null = null
    for (const price of priceAxisTicks(priceForY(plotH), priceForY(0), plotH, decimals(priceForY(0)))) {
      const y = yForPrice(price)
      if (y < 0 || y > plotH) continue
      // A pill in the gutter wins the space under it: the live price and the
      // crosshair price are the two numbers the trader is actually reading.
      if (liveY !== null && Math.abs(liveY - y) < 18) continue
      if (hover && Math.abs(hover.y - y) < 18) continue
      if (previousPriceY !== null && Math.abs(previousPriceY - y) < 32) continue
      previousPriceY = y
      context.beginPath()
      context.moveTo(0, y)
      context.lineTo(plotW, y)
      context.stroke()
      context.fillStyle = axisInk
      context.fillText(
        price.toFixed(decimals(price)),
        plotW + 6,
        // 12, not 3: 10px digits drawn at the top gridline would be cut in half
        // by the gutter's own edge.
        Math.min(plotH - 4, Math.max(12, y + 3))
      )
    }
    // Time labels work the same way across the plot: a calendar step wide enough
    // to clear the last label, with day, month and year boundaries in heavier
    // type rather than a repeated date on every tick.
    let previousTimeX: number | null = null
    for (const marker of timeAxisTicks(
      timeForIndex(view.start),
      timeForIndex(view.start + view.span),
      plotW,
      settings.clock24 !== false
    )) {
      const x = xForIndex(indexForTime(marker.ms))
      if (x < 0 || x > plotW) continue
      if (previousTimeX !== null && x - previousTimeX < 28) continue
      previousTimeX = x
      context.beginPath()
      context.moveTo(x, 0)
      context.lineTo(x, plotH)
      context.stroke()
      context.font = marker.major
        ? '600 10px ui-sans-serif, system-ui, sans-serif'
        : '10px ui-sans-serif, system-ui, sans-serif'
      context.fillStyle = axisInk
      const labelWidth = context.measureText(marker.label).width
      // Centred under its own tick and kept inside the plot, so the first and
      // last labels do not hang off the gutter.
      const labelX = Math.max(2, Math.min(x - labelWidth / 2, plotW - labelWidth - 2))
      context.fillText(marker.label, labelX, plotH + 15)
    }
    context.font = '10px ui-sans-serif, system-ui, sans-serif'

    // Candles.
    const bodyW = Math.max(1.5, (plotW / view.span) * 0.65)
    for (let index = Math.floor(view.start); index <= Math.min(view.start + view.span, lastPaintable); index += 1) {
      const candle = candles[index]
      if (!candle) continue
      const x = xForIndex(index)
      if (x < -bodyW || x > plotW + bodyW) continue
      const colour = candle.c >= candle.o ? settings.bull : settings.bear
      context.strokeStyle = colour
      context.fillStyle = colour
      context.beginPath()
      context.moveTo(x, yForPrice(candle.h))
      context.lineTo(x, yForPrice(candle.l))
      context.stroke()
      const open = yForPrice(candle.o)
      const close = yForPrice(candle.c)
      const top = Math.min(open, close)
      const height = Math.max(1, Math.abs(close - open))
      context.fillRect(x - bodyW / 2, top, bodyW, height)
    }

    // The compare instrument, in the main axis's own units. Broken where the
    // compare series has no bar, so a holiday does not paint as a flat stretch.
    if (compareSeries) {
      context.strokeStyle = COMPARE_COLOUR
      context.lineWidth = 1.6
      context.setLineDash([])
      context.beginPath()
      let drawing = false
      const from = Math.max(0, Math.floor(view.start) - 1)
      const to = Math.min(lastPaintable, Math.ceil(view.start + view.span) + 1)
      for (let index = from; index <= to; index += 1) {
        const point = compareSeries.points[index]
        if (!point || point.stale) {
          drawing = false
          continue
        }
        const x = xForIndex(index)
        const y = yForPrice(point.p)
        if (drawing) context.lineTo(x, y)
        else {
          context.moveTo(x, y)
          drawing = true
        }
      }
      context.stroke()
      context.lineWidth = 1
    }

    // Computed levels sit under the objects: they are reference, not edits.
    if (sessionLevels.length > 0) {
      for (const level of sessionLevels) {
        const y = yForPrice(level.price)
        if (y < -2 || y > plotH + 2) continue
        context.strokeStyle = level.colour
        context.lineWidth = 1
        context.setLineDash([2, 4])
        context.beginPath()
        context.moveTo(0, y)
        context.lineTo(plotW, y)
        context.stroke()
        context.setLineDash([])
        context.fillStyle = level.colour
        context.fillText(
          `${level.label} ${level.side === 'high' ? 'H' : 'L'} ${level.price.toFixed(decimals(level.price))}`,
          6,
          y - 3
        )
      }
    }

    if (vwap.length > 0) {
      context.strokeStyle = '#f59e0b'
      context.lineWidth = 1.4
      context.setLineDash([])
      context.beginPath()
      let day = -1
      for (const point of vwap) {
        if (point.i < view.start - 1 || point.i > view.start + view.span + 1) continue
        const x = xForIndex(point.i)
        const y = yForPrice(point.p)
        if (point.day !== day) {
          // A new session starts a new line, so the reset is not drawn as a jump.
          context.moveTo(x, y)
          day = point.day
        } else {
          context.lineTo(x, y)
        }
      }
      context.stroke()
    }

    // Objects. Paint order is the trader's: a higher `z` sits on top, and the
    // list order decides when nobody has moved one. Everything an object owns is
    // clipped to the candle pane, so a wide label or a stray handle can no
    // longer sit on top of the price or time axis.
    const axisTags: Array<{ y: number; text: string; colour: string }> = []
    context.save()
    context.beginPath()
    context.rect(0, 0, plotW, plotH)
    context.clip()
    const orderedObjects = [...symbolDrawings].sort(
      (a, b) => (a.style?.z ?? 0) - (b.style?.z ?? 0)
    )
    for (const row of orderedObjects) {
      const points = row.points ?? []
      if (points.length === 0) continue
      // A hidden object keeps its row and stops being painted, which is how a
      // trader clears the chart without throwing the idea away.
      if (row.style?.hd) continue
      // An object the trader only wants on other candle sizes is not drawn here.
      if (!visibleOnInterval(row.style, interval)) continue
      // A fired alert is kept as the record of a level that was reached; the
      // filter is about what the trader still wants to see.
      const firedAlert = Boolean(row.style?.al && row.style?.fd)
      if (firedAlert && activeAlertsOnly) continue
      // One viewport test per object, before anything of it is painted. When it
      // fails the geometry, its label, its measurements and its handles are all
      // skipped together: pinning an off-screen label to the chart edge is
      // exactly what used to leave text floating after a pan.
      const anchors = points.map((point) => ({
        x: xForIndex(indexForTime(point.t)),
        y: yForPrice(point.p),
      }))
      const minX = Math.min(...anchors.map((anchor) => anchor.x))
      const maxX = Math.max(...anchors.map((anchor) => anchor.x))
      const minY = Math.min(...anchors.map((anchor) => anchor.y))
      const maxY = Math.max(...anchors.map((anchor) => anchor.y))
      if (!objectInPane({ minX, maxX, minY, maxY }, row.kind, plotW, plotH)) continue
      const selected = row.id === selectedId
      const colour = styleColour(row.style, selected)
      context.strokeStyle = colour
      context.fillStyle = styleFill(row.style, colour, selected)
      context.lineWidth = row.style?.w ?? (selected ? 2 : 1.2)
      context.setLineDash(
        row.style?.dt ? [1.5, 3.5] : row.style?.d ? [5, 4] : []
      )

      if (row.kind === 'text') {
        // A label pinned on the phone has to read here too: the words are the
        // object, and a dot with no text would be a bug with a shadow.
        const at = anchors[0]
        const words = row.text ?? ''
        if (words) {
          context.font = '600 11px ui-sans-serif, system-ui, sans-serif'
          const width = context.measureText(words).width + 10
          context.fillRect(at.x, at.y - 16, width, 16)
          context.strokeRect(at.x, at.y - 16, width, 16)
          context.fillStyle = colour
          context.setLineDash([])
          context.fillText(words, at.x + 5, at.y - 4)
          context.font = '11px ui-sans-serif, system-ui, sans-serif'
        }
        if (selected) {
          context.fillStyle = colour
          context.beginPath()
          context.arc(at.x, at.y, 3.5, 0, Math.PI * 2)
          context.fill()
        }
        continue
      }

      if (row.kind === 'ray') {
        const y = yForPrice(points[0].p)
        // A fired line keeps its colour but loses its weight, so the live
        // alerts are what the eye lands on.
        const alpha = context.globalAlpha
        if (firedAlert) context.globalAlpha = 0.5
        context.beginPath()
        context.moveTo(0, y)
        context.lineTo(plotW, y)
        context.stroke()
        context.globalAlpha = alpha
        if (row.style?.al) {
          // The same left-edge mark the phone draws: hollow while the alert is
          // waiting, solid once it has fired.
          context.setLineDash([])
          if (firedAlert) {
            context.fillRect(0, y - 3.5, 4, 7)
          } else {
            context.strokeRect(0, y - 3.5, 4, 7)
          }
        }
        context.setLineDash([])
        // The price tag belongs in the gutter, which is outside the clip, so it
        // is collected here and painted once the plot is unclipped.
        axisTags.push({ y, text: points[0].p.toFixed(decimals(points[0].p)), colour })
        continue
      }

      if (row.kind === 'vline') {
        const x = xForIndex(indexForTime(points[0].t))
        if (x >= -1 && x <= plotW + 1) {
          context.beginPath()
          context.moveTo(x, 0)
          context.lineTo(x, plotH)
          context.stroke()
          context.setLineDash([])
        }
        continue
      }

      if (points.length < 2) continue
      const a = anchors[0]
      const b = anchors[1]

      if (row.kind === 'measure') {
        const delta = points[1].p - points[0].p
        const change = points[0].p === 0 ? 0 : (delta / points[0].p) * 100
        const step = candles.length > 1 ? candles[1].t - candles[0].t : 60_000
        const bars = Math.round(Math.abs(points[1].t - points[0].t) / step)
        const left = Math.min(a.x, b.x)
        const top = Math.min(a.y, b.y)
        context.fillRect(left, top, Math.abs(b.x - a.x), Math.abs(b.y - a.y))
        context.beginPath()
        context.moveTo(a.x, a.y)
        context.lineTo(b.x, b.y)
        context.stroke()
        const label =
          `${delta >= 0 ? '+' : ''}${delta.toFixed(decimals(delta || points[0].p))}` +
          `  ${change >= 0 ? '+' : ''}${change.toFixed(2)}%  ${bars} bars`
        context.fillStyle = '#0b1220'
        const width = context.measureText(label).width + 10
        const captionY = Math.max(2, top - 20)
        const captionX = left + 4
        // Only when the caption's own corner is inside the pane: a measure that
        // has been panned almost out of sight must not hang its numbers on the
        // chart edge.
        if (captionX >= 0 && captionX + width <= plotW) {
          context.fillRect(captionX, captionY, width, 16)
          context.fillStyle = selected ? '#bfdbfe' : '#cbd5e1'
          context.fillText(label, captionX + 5, captionY + 12)
        }
        continue
      }

      if (row.kind === 'rectangle') {
        context.fillRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
        context.strokeRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
      } else if (row.kind === 'fib') {
        const left = Math.min(a.x, b.x)
        const right = Math.max(a.x, b.x)
        for (const ratio of FIB_LEVELS) {
          const price = points[1].p + (points[0].p - points[1].p) * ratio
          const y = yForPrice(price)
          context.globalAlpha = ratio === 0 || ratio === 0.5 || ratio === 1 ? 1 : 0.6
          context.beginPath()
          context.moveTo(left, y)
          context.lineTo(right, y)
          context.stroke()
          context.globalAlpha = 1
          context.fillStyle = colour
          // Kept inside the pane even when the right anchor is panned past it: a
          // Fib that is still visible keeps its percentages, one that is not
          // never reaches this code.
          const percent = `${Math.round(ratio * 100)}%`
          const percentWidth = context.measureText(percent).width
          context.fillText(percent, Math.max(2, Math.min(right + 4, plotW - percentWidth - 2)), y - 2)
        }
      } else {
        context.beginPath()
        context.moveTo(a.x, a.y)
        context.lineTo(b.x, b.y)
        context.stroke()
      }

      // A label on the shape or line itself, above its highest anchor: the
      // note belongs to the object, not to a corner of the chart.
      if (row.text && row.kind !== 'text') {
        const top = a.y <= b.y ? a : b
        context.setLineDash([])
        context.fillStyle = colour
        context.font = '600 10.5px ui-sans-serif, system-ui, sans-serif'
        context.fillText(row.text, top.x + 4, top.y - 6)
        context.font = '11px ui-sans-serif, system-ui, sans-serif'
      }

      if (selected) {
        context.fillStyle = colour
        for (const point of [a, b]) {
          context.beginPath()
          context.arc(point.x, point.y, 3.5, 0, Math.PI * 2)
          context.fill()
        }
      }
    }

    // The half-placed object.
    if (pending) {
      const x = xForIndex(indexForTime(pending.t))
      const y = yForPrice(pending.p)
      context.strokeStyle = '#60a5fa'
      context.setLineDash([3, 3])
      context.beginPath()
      context.arc(x, y, 5, 0, Math.PI * 2)
      context.stroke()
      context.setLineDash([])
    }
    context.restore()

    // Price tags for horizontal lines go back into the gutter, which the clip
    // above deliberately excludes so the axis keeps owning its own numbers.
    context.setLineDash([])
    context.font = '10px ui-sans-serif, system-ui, sans-serif'
    for (const tag of axisTags) {
      const tagWidth = context.measureText(tag.text).width + 8
      context.fillStyle = tag.colour
      context.fillRect(plotW + 2, tag.y - 8, tagWidth, 16)
      context.fillStyle = '#0b1220'
      context.fillText(tag.text, plotW + 6, tag.y + 4)
    }

    // The last price, with the countdown under it when the trader asked for
    // one: how long the forming bar still has to run.
    const lastShown = candles[lastPaintable]
    if (lastShown) {
      const y = yForPrice(lastShown.c)
      if (y >= 0 && y <= plotH) {
        const colour = lastShown.c >= lastShown.o ? settings.bull : settings.bear
        context.strokeStyle = colour
        context.lineWidth = 1
        context.setLineDash([4, 3])
        context.beginPath()
        context.moveTo(0, y)
        context.lineTo(plotW, y)
        context.stroke()
        context.setLineDash([])
        context.fillStyle = colour
        const tag = lastShown.c.toFixed(decimals(lastShown.c))
        const tagWidth = context.measureText(tag).width + 10
        context.fillRect(plotW + 2, y - 8, tagWidth, 16)
        context.fillStyle = '#0b1220'
        context.fillText(tag, plotW + 6, y + 4)
        if (settings.countdown && now !== null) {
          const closeAt = lastShown.t + intervalMs(interval)
          const left = Math.max(0, Math.round((closeAt - now) / 1000))
          const clock = `${String(Math.floor(left / 60)).padStart(2, '0')}:${String(left % 60).padStart(2, '0')}`
          context.fillStyle = '#94a3b8'
          context.fillText(clock, plotW + 4, y + 20)
        }
      }
    }

    // Crosshair.
    if (hover) {
      context.strokeStyle = crosshairInk
      context.lineWidth = settings.crosshairWidth
      context.setLineDash(
        settings.crosshairStyle === 'solid'
          ? []
          : settings.crosshairStyle === 'dotted'
            ? [1, 3]
            : [5, 4]
      )
      context.beginPath()
      context.moveTo(hover.x, 0)
      context.lineTo(hover.x, plotH)
      context.moveTo(0, hover.y)
      context.lineTo(plotW, hover.y)
      context.stroke()
      context.setLineDash([])
      context.lineWidth = 1

      const index = Math.round(view.start + (hover.x / plotW) * view.span)
      const candle = candles[Math.min(candles.length - 1, Math.max(0, index))]
      if (candle) {
        const tag =
          tickLabel(candle.t, interval, settings) + '  ·  ' + candle.c.toFixed(decimals(candle.c))
        context.fillStyle = lightCanvas ? 'rgba(248, 250, 252, 0.95)' : 'rgba(15, 23, 42, 0.92)'
        const width = context.measureText(tag).width + 12
        context.fillRect(
          Math.min(hover.x + 8, plotW - width - 2),
          Math.max(2, hover.y - 26),
          width,
          18
        )
        context.fillStyle = lightCanvas ? '#0f172a' : '#e2e8f0'
        context.fillText(
          tag,
          Math.min(hover.x + 14, plotW - width + 4),
          Math.max(14, hover.y - 13)
        )
      }

      // The price under the pointer, printed in its own gutter the way the phone
      // prints it: the floating tag can land on a candle, this cannot.
      const hoverPrice = priceForY(hover.y)
      const priceBadge = hoverPrice.toFixed(decimals(hoverPrice))
      const badgeWidth = Math.min(AXIS - 4, context.measureText(priceBadge).width + 10)
      context.fillStyle = lightCanvas ? 'rgba(15, 23, 42, 0.9)' : 'rgba(148, 163, 184, 0.9)'
      context.fillRect(plotW + 2, hover.y - 8, badgeWidth, 16)
      context.fillStyle = lightCanvas ? '#f8fafc' : '#0b1220'
      context.fillText(priceBadge, plotW + 6, hover.y + 4)
    }
  }, [
    activeAlertsOnly,
    candles,
    compareSeries,
    decimals,
    hover,
    interval,
    now,
    pending,
    replayCut,
    settings,
    plotH,
    plotW,
    priceForY,
    selectedId,
    size,
    symbolDrawings,
    view,
    xForIndex,
    yForPrice,
    indexForTime,
    timeForIndex,
    sessionLevels,
    showSessions,
    showVwap,
    vwap,
  ])

  // ------------------------------------------------------------- persistence
  const addDrawing = useCallback(
    async (kind: string, points: Point[], style: DrawingStyle = {}, text: string | null = null) => {
      const clean = chartSymbol(symbol)
      const editedAtMs = Date.now()
      const optimistic: ChartDrawingRow = {
        id: `local-${editedAtMs}`,
        symbol: clean,
        kind,
        points,
        text,
        style,
        editedAtMs,
      }
      setDrawings((current) => [...current, optimistic])
      setSelectedId(optimistic.id)
      pendingWrites.current += 1
      try {
        const { data, error: writeError } = await supabase
          .from('chart_drawings')
          .insert({
            symbol: clean,
            kind,
            points,
            text,
            // Only sent when there is something to say: a project that has not
            // applied the style migration still draws its objects.
            ...(Object.keys(style).length > 0 ? { style } : {}),
            edited_at: new Date(editedAtMs).toISOString(),
          })
          .select('id')
          .single()
        if (writeError) {
          setDrawings((current) => current.filter((row) => row.id !== optimistic.id))
          setNotice(
            'Could not save that object. If this is a new deployment, apply ' +
              'supabase/migrations/20261124_chart_analysis.sql.'
          )
          return
        }
        setDrawings((current) =>
          current.map((row) =>
            row.id === optimistic.id
              ? { ...row, id: String(data.id), editedAtMs }
              : row
          )
        )
        setSelectedId(String(data.id))
      } finally {
        pendingWrites.current -= 1
      }
    },
    [symbol]
  )

  /**
   * Writes one object: where it sits, how it looks, what it says.
   *
   * One path for all three, because they are one row and one edit time — a
   * restyle that reused the drag path, or the other way round, is how the two
   * start disagreeing about which version the table holds.
   */
  const persistObject = useCallback(
    async (
      id: string,
      patch: { points?: Point[]; style?: DrawingStyle; text?: string | null }
    ) => {
      // Stamped here, at the moment of the change: this is when the trader
      // moved or restyled it, not when the request reached the server.
      const editedAtMs = Date.now()
      setDrawings((current) =>
        current.map((row) => (row.id === id ? { ...row, ...patch, editedAtMs } : row))
      )
      if (id.startsWith('local-')) return
      pendingWrites.current += 1
      try {
        const { error: writeError } = await supabase
          .from('chart_drawings')
          .update({
            ...(patch.points ? { points: patch.points } : {}),
            ...(patch.style ? { style: patch.style } : {}),
            ...(patch.text === undefined ? {} : { text: patch.text }),
            edited_at: new Date(editedAtMs).toISOString(),
          })
          .eq('id', id)
        if (writeError) {
          // A missing `style` column is a named state with a named fix, not a
          // connection problem, and saying so saves the trader a dead end.
          setNotice(
            /style/i.test(writeError.message)
              ? 'The look was applied here but could not be saved: apply ' +
                'supabase/migrations/20261126_chart_drawing_style.sql.'
              : 'Could not save that change. Check your connection.'
          )
        }
      } finally {
        pendingWrites.current -= 1
      }
    },
    []
  )

  const persistPoints = useCallback(
    async (id: string, points: Point[]) => persistObject(id, { points }),
    [persistObject]
  )

  /**
   * Copies an object, nudged a touch so the copy is visible beside the original
   * instead of exactly under it. Style and label travel with it; lock and hide
   * do not, because a copy that cannot be grabbed looks like the clone failed.
   */
  const cloneObject = useCallback(
    (row: ChartDrawingRow) => {
      const base = candles[candles.length - 1]?.c ?? row.points[0]?.p ?? 0
      const nudge = Math.max(Math.abs(base) * 0.0006, 1e-6)
      const style: DrawingStyle = { ...row.style }
      delete style.lk
      delete style.hd
      void addDrawing(
        row.kind,
        row.points.map((point) => ({ t: point.t, p: point.p + nudge })),
        style,
        row.text
      )
    },
    [addDrawing, candles]
  )

  /** Restyles one object without touching its geometry. */
  const restyleObject = useCallback(
    (id: string, patch: Partial<DrawingStyle>) => {
      const row = drawings.find((item) => item.id === id)
      if (!row) return
      const style: DrawingStyle = { ...row.style, ...patch }
      for (const key of Object.keys(patch) as (keyof DrawingStyle)[]) {
        if (patch[key] === undefined) delete style[key]
      }
      void persistObject(id, { style })
    },
    [drawings, persistObject]
  )

  const removeDrawing = useCallback(async (id: string) => {
    setDrawings((current) => current.filter((row) => row.id !== id))
    setSelectedId(null)
    if (id.startsWith('local-')) return
    pendingWrites.current += 1
    try {
      const { error: writeError } = await supabase.from('chart_drawings').delete().eq('id', id)
      if (writeError) setNotice('Could not delete that object. Check your connection.')
    } finally {
      pendingWrites.current -= 1
    }
  }, [])

  const clearAll = useCallback(async () => {
    const clean = chartSymbol(symbol)
    setDrawings((current) => current.filter((row) => row.symbol !== clean))
    setSelectedId(null)
    pendingWrites.current += 1
    try {
      const { error: writeError } = await supabase
        .from('chart_drawings')
        .delete()
        .eq('symbol', clean)
      if (writeError) setNotice('Could not clear the objects. Check your connection.')
    } finally {
      pendingWrites.current -= 1
    }
  }, [symbol])

  /**
   * Re-reads this symbol's saved objects and folds them in.
   *
   * The phone writes to the same table, so without this a level pinned there
   * only appeared after a page reload. Reads are skipped while a write is in
   * flight or a finger is dragging: those states are newer than anything the
   * table can answer with, and applying them would move the object backwards.
   */
  const pullDrawings = useCallback(async () => {
    if (pendingWrites.current > 0 || drag.current) return
    const clean = chartSymbol(symbol)
    const read = (columns: string) =>
      supabase
        .from('chart_drawings')
        .select(columns)
        .eq('symbol', clean)
        .order('created_at', { ascending: true })
    const first = await read('id, symbol, kind, points, text, style, edited_at')
    let data = first.data as Record<string, unknown>[] | null
    let readError = first.error
    // A project that has not applied the style migration yet still charts its
    // objects: the read falls back to the columns that have always been there.
    if (readError && /style/i.test(readError.message)) {
      const retry = await read('id, symbol, kind, points, text, edited_at')
      data = retry.data as Record<string, unknown>[] | null
      readError = retry.error
    }
    if (readError || !data) return
    const rows: ChartDrawingRow[] = data.map((row) => ({
      id: String(row.id),
      symbol: String(row.symbol),
      kind: String(row.kind),
      points: Array.isArray(row.points)
        ? (row.points as { t: number; p: number }[]).filter(
            (point) => typeof point?.t === 'number' && typeof point?.p === 'number'
          )
        : [],
      text: row.text == null ? null : String(row.text),
      style:
        row.style && typeof row.style === 'object'
          ? (row.style as DrawingStyle)
          : {},
      editedAtMs: row.edited_at ? Date.parse(String(row.edited_at)) : null,
    }))
    setDrawings((current) => mergeSymbolDrawings(current, rows, clean))
    setSelectedId((selected) =>
      selected && !rows.some((row) => row.id === selected) ? null : selected
    )
  }, [symbol])

  useEffect(() => {
    const tick = () => {
      // A hidden tab has nobody looking at it; catching up on focus is enough.
      if (document.visibilityState === 'visible') void pullDrawings()
    }
    // Scheduled rather than called inline: the effect body must not set state
    // synchronously, and the read is asynchronous anyway.
    const first = window.setTimeout(tick, 0)
    const timer = window.setInterval(tick, 10_000)
    document.addEventListener('visibilitychange', tick)
    window.addEventListener('focus', tick)
    return () => {
      window.clearTimeout(first)
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', tick)
      window.removeEventListener('focus', tick)
    }
  }, [activeAlertsOnly, pullDrawings])

  const undo = useCallback(() => {
    const last = symbolDrawings[symbolDrawings.length - 1]
    if (last) removeDrawing(last.id)
  }, [removeDrawing, symbolDrawings])

  // ------------------------------------------------------------- interaction
  const localPoint = (event: React.PointerEvent | React.MouseEvent) => {
    const rect = boxRef.current?.getBoundingClientRect()
    return {
      x: (event.clientX - (rect?.left ?? 0)) / 1,
      y: (event.clientY - (rect?.top ?? 0)) / 1,
    }
  }

  /** Nearest object within 14 px of the pointer, else null. */
  const hitTest = useCallback(
    (x: number, y: number): ChartDrawingRow | null => {
      let best: ChartDrawingRow | null = null
      let bestDistance = 14
      for (const row of symbolDrawings) {
        const points = row.points ?? []
        if (points.length === 0) continue
        // A hidden object cannot be grabbed: it is not on the chart, so a
        // pointer over that patch of candles is not over anything.
        if (row.style?.hd) continue
        if (row.style?.al && row.style?.fd && activeAlertsOnly) continue
        if (row.kind === 'ray') {
          const distance = Math.abs(yForPrice(points[0].p) - y)
          if (distance < bestDistance) {
            bestDistance = distance
            best = row
          }
          continue
        }
        if (row.kind === 'vline') {
          const distance = Math.abs(xForIndex(indexForTime(points[0].t)) - x)
          if (distance < bestDistance) {
            bestDistance = distance
            best = row
          }
          continue
        }
        if (points.length < 2) continue
        const left = Math.min(
          xForIndex(indexForTime(points[0].t)),
          xForIndex(indexForTime(points[1].t))
        )
        const right = Math.max(
          xForIndex(indexForTime(points[0].t)),
          xForIndex(indexForTime(points[1].t))
        )
        const top = Math.min(yForPrice(points[0].p), yForPrice(points[1].p))
        const bottom = Math.max(yForPrice(points[0].p), yForPrice(points[1].p))
        const dx = x < left ? left - x : x > right ? x - right : 0
        const dy = y < top ? top - y : y > bottom ? y - bottom : 0
        const distance = Math.hypot(dx, dy)
        if (distance < bestDistance) {
          bestDistance = distance
          best = row
        }
      }
      return best
    },
    [activeAlertsOnly, indexForTime, symbolDrawings, xForIndex, yForPrice]
  )

  const onPointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const { x, y } = localPoint(event)
    // The gutters are controls, not dead margins: a vertical drag stretches the
    // price scale and a horizontal drag stretches the time axis, exactly as the
    // same strips behave on the phone and in a desktop terminal.
    if (x > plotW || y > plotH) {
      event.currentTarget.setPointerCapture(event.pointerId)
      axisDrag.current = {
        axis: x > plotW ? 'price' : 'time',
        startX: x,
        startY: y,
        baseZoom: priceZoom,
        baseSpan: view.span,
        baseStart: view.start,
      }
      return
    }
    event.currentTarget.setPointerCapture(event.pointerId)

    if (tool === 'select') {
      const hit = hitTest(x, y)
      if (hit) {
        setSelectedId(hit.id)
        // A locked object still selects, so its settings can be opened and it
        // can be unlocked; it just refuses to move.
        if (hit.style?.lk) return
        drag.current = {
          mode: 'object',
          id: hit.id,
          originX: x,
          originY: y,
          start: view,
          points: hit.points.map((point) => ({ ...point })),
        }
        return
      }
      setSelectedId(null)
      drag.current = { mode: 'pan', originX: x, originY: y, start: view }
      return
    }

    if (tool === 'vline') {
      void addDrawing('vline', [
        { t: timeForIndex(view.start + (x / plotW) * view.span), p: priceForY(y) },
      ])
      return
    }

    if (tool === 'alert') {
      const price = priceForY(y)
      // Above the market is waiting for a rise, below for a fall, so the line
      // takes the up or down colour the phone uses for the same choice.
      const last = candles.length > 0 ? candles[candles.length - 1].c : price
      const colour = price < last ? 0xffef4444 : 0xff22c55e
      void addDrawing(
        'ray',
        [{ t: timeForIndex(view.start + (x / plotW) * view.span), p: price }],
        { al: true, c: colour }
      )
      return
    }

    if (tool === 'ray') {
      const price = priceForY(y)
      void addDrawing('ray', [{ t: timeForIndex(view.start + (x / plotW) * view.span), p: price }])
      return
    }

    const point: Point = {
      t: timeForIndex(view.start + (x / plotW) * view.span),
      p: priceForY(y),
    }
    if (!pending) {
      setPending(point)
      return
    }
    void addDrawing(tool, [pending, point])
    setPending(null)
  }

  const onPointerMove = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const { x, y } = localPoint(event)
    setHover(x <= plotW ? { x: Math.min(x, plotW), y: Math.min(y, plotH) } : null)

    const zoomDrag = axisDrag.current
    if (zoomDrag) {
      if (zoomDrag.axis === 'price') {
        // Up stretches the range around its middle (bars look bigger), down
        // compresses it. Clamped like the phone, so a fling cannot invert it.
        const factor = Math.exp(((y - zoomDrag.startY) / plotH) * 2.5)
        setPriceZoom(Math.min(8, Math.max(0.2, zoomDrag.baseZoom * factor)))
      } else {
        // Right widens the bars, left packs them, with the newest bar held in
        // place so the live edge does not walk out from under the trader.
        const factor = Math.exp((-1 * (x - zoomDrag.startX) / plotW) * 2.5)
        const span = Math.max(12, Math.min(candles.length, zoomDrag.baseSpan * factor))
        const rightEdge = zoomDrag.baseStart + zoomDrag.baseSpan
        const start = Math.max(0, Math.min(candles.length - span, rightEdge - span))
        setView({ start, span })
      }
      return
    }

    const active = drag.current
    if (!active) {
      // A pointer over a gutter says what it can do before it is pressed.
      event.currentTarget.style.cursor =
        x > plotW ? 'ns-resize' : y > plotH ? 'ew-resize' : tool === 'select' ? 'crosshair' : 'copy'
      return
    }

    if (active.mode === 'pan') {
      const barsMoved = ((x - active.originX) / plotW) * active.start.span
      const start = Math.max(
        -active.start.span * 0.2,
        Math.min(candles.length - active.start.span * 0.2, active.start.start - barsMoved)
      )
      setView({ start, span: active.start.span })
      return
    }

    if (!active.id || !active.points) return
    const priceDelta = priceForY(active.originY) - priceForY(y)
    const msPerBar =
      candles.length > 1 ? candles[1].t - candles[0].t : 60_000
    const barsMoved = ((x - active.originX) / plotW) * active.start.span
    const timeDelta = Math.round(barsMoved * msPerBar)
    const moved = active.points.map((point) => ({
      t: point.t + timeDelta,
      p: point.p + priceDelta,
    }))
    setDrawings((current) =>
      current.map((row) => (row.id === active.id ? { ...row, points: moved } : row))
    )
  }

  const onPointerUp = (event: React.PointerEvent<HTMLCanvasElement>) => {
    axisDrag.current = null
    const active = drag.current
    drag.current = null
    if (active?.mode === 'object' && active.id) {
      const row = drawings.find((item) => item.id === active.id)
      if (row) void persistPoints(active.id, row.points)
    }
    try {
      event.currentTarget.releasePointerCapture(event.pointerId)
    } catch {
      // The capture is already gone (pointer cancelled); nothing to release.
    }
  }

  const onWheel = (event: React.WheelEvent<HTMLCanvasElement>) => {
    if (candles.length === 0) return
    event.preventDefault()
    const { x } = localPoint(event)
    const anchorIndex = view.start + (x / plotW) * view.span
    const factor = event.deltaY > 0 ? 1.12 : 0.89
    const span = Math.min(candles.length, Math.max(12, view.span * factor))
    const ratio = x / plotW
    const start = Math.max(
      0,
      Math.min(candles.length - span, anchorIndex - span * ratio)
    )
    setView({ start, span })
  }

  // A box that follows the container, so the canvas is never stretched.
  useEffect(() => {
    const element = boxRef.current
    if (!element) return
    const observer = new ResizeObserver((entries) => {
      const box = entries[0]?.contentRect
      if (box) setSize({ width: box.width, height: box.height })
    })
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Delete' || event.key === 'Backspace') {
        if (selectedId) {
          event.preventDefault()
          void removeDrawing(selectedId)
        }
      }
      if (event.key === 'Escape') setPending(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [removeDrawing, selectedId])

  const lastPrice = candles.length > 0 ? candles[candles.length - 1].c : null

  /** The candle under the pointer, for the screen-reader line. */
  const hoverCandle =
    hover && candles.length > 0
      ? candles[
          Math.min(
            candles.length - 1,
            Math.max(0, Math.round(view.start + (hover.x / plotW) * view.span))
          )
        ]
      : null
  const activeTool = TOOLS.find((item) => item.id === tool)

  return (
    <div
      ref={frameRef}
      className={
        expanded
          ? 'fixed inset-0 z-[45] flex flex-col gap-2 overflow-y-auto bg-background p-3'
          : 'space-y-3'
      }
    >
      {/* The desk has a lot of controls between the top of the page and the
          candles. A keyboard user should not have to walk all of them to pan. */}
      <a
        href="#chart-canvas"
        className="sr-only focus:not-sr-only focus:absolute focus:left-3 focus:top-3 focus:z-50 focus:rounded-lg focus:border focus:border-primary focus:bg-surface focus:px-3 focus:py-2 focus:text-xs focus:font-semibold focus:text-white"
      >
        Skip to chart
      </a>

      <div className="flex flex-wrap items-center gap-2">
        <form
          onSubmit={(event) => {              event.preventDefault()
            const next = chartSymbol(symbolDraft)
            if (!next) return
            // The compare overlay is the same instrument now, which is a flat
            // line at the anchor: drop it rather than draw a lie.
            if (next === compareSymbol) removeCompare()
            setSymbolInput(next)
          }}
          className="flex items-center gap-2"
        >
          <input
            value={symbolDraft}
            onChange={(event) => setSymbolDraft(event.target.value)}
            aria-label="Symbol"
            spellCheck={false}
            className="min-h-11 w-28 rounded-lg border border-border bg-surface px-3 py-1.5 text-sm font-semibold uppercase tracking-wide text-white outline-none focus:border-primary"
          />
        </form>
        <div className="flex items-center gap-1">
          {SYMBOLS.slice(0, 4).map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => {
                setSymbolDraft(item)
                setSymbolInput(item)
              }}
              className={`min-h-11 min-w-11 rounded-md px-2.5 py-1 text-[11px] font-semibold ${
                symbol === item
                  ? 'bg-primary/20 text-primary'
                  : 'text-gray-500 hover:text-gray-300'
              }`}
            >
              {item.replace('_', '/')}
            </button>
          ))}
        </div>
        <div className="ml-auto flex min-w-0 max-w-full items-center gap-1 overflow-x-auto rounded-lg border border-border bg-surface p-0.5">
          {INTERVALS.map((item) => {
            const locked = !isTimeframeOpen(item.key, {
              pro: proTimeframes,
              paid: paidTimeframes,
            })
            const tier = isProTimeframe(item.key) ? 'pro' : 'basic'
            return (
              <button
                key={item.key}
                type="button"
                onClick={() =>
                  locked ? setLockedSize({ label: item.label, tier }) : setIntervalKey(item.key)
                }
                title={locked ? `${tier === 'pro' ? 'Pro' : 'Basic'} candle size` : undefined}
                className={`min-h-11 min-w-11 rounded-md px-2.5 py-1 text-[11px] font-semibold ${
                  interval === item.key
                    ? 'bg-surface-light text-white'
                    : locked
                      ? 'text-gray-600'
                      : 'text-gray-500 hover:text-gray-300'
                }`}
              >
                {item.label}
                {locked && (
                  <span className="ml-0.5 align-super text-[8px] text-primary">
                    {tier === 'pro' ? 'Pro' : 'Basic'}
                  </span>
                )}
              </button>
            )
          })}
        </div>
      </div>

      {lockedSize && (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border border-primary/30 bg-primary/10 px-3 py-2 text-[11px] text-primary">
          <span>
            {lockedSize.tier === 'pro'
              ? `${lockedSize.label} candles are part of Pro. Basic charts run from 30s up.`
              : `${lockedSize.label} candles are part of Basic. Free charts run from 1m up.`}
          </span>
          <a href="/pricing" className="font-semibold underline">
            Upgrade
          </a>
          <button
            type="button"
            onClick={() => setLockedSize(null)}
            className="ml-auto text-primary/70 hover:text-primary"
          >
            Dismiss
          </button>
        </div>
      )}

      <div className="flex flex-wrap items-center gap-1.5">
        {TOOLS.map((item) => (
          <button
            key={item.id}
            type="button"
            title={item.hint}
            onClick={() => {
              setTool(item.id)
              setPending(null)
            }}
            className={`min-h-11 rounded-lg border px-3 py-1.5 text-xs font-semibold ${
              tool === item.id
                ? 'border-primary bg-primary/15 text-primary'
                : 'border-border bg-surface text-gray-400 hover:text-white'
            }`}
          >
            {item.label}
          </button>
        ))}
        <div className="ml-auto flex flex-wrap items-center justify-end gap-1.5">
          <button
            type="button"
            title="Hide alert lines that have already fired"
            aria-pressed={activeAlertsOnly}
            onClick={() => setActiveAlertsOnly((current) => !current)}
            className={`min-h-11 rounded-lg border px-3 py-1.5 text-xs font-semibold ${
              activeAlertsOnly
                ? 'border-primary bg-primary/15 text-primary'
                : 'border-border bg-surface text-gray-400 hover:text-white'
            }`}
          >
            Active alerts
          </button>
          <button
            type="button"
            title={
              expanded
                ? 'Back to the dashboard'
                : 'Give the chart the whole screen, without the browser chrome'
            }
            aria-pressed={expanded}
            onClick={toggleFullScreen}
            className={`min-h-11 rounded-lg border px-3 py-1.5 text-xs font-semibold ${
              expanded
                ? 'border-primary bg-primary/15 text-primary'
                : 'border-border bg-surface text-gray-400 hover:text-white'
            }`}
          >
            {expanded ? 'Exit full screen' : 'Full screen'}
          </button>
          <button
            type="button"
            onClick={() => setSettingsOpen(true)}
            className="min-h-11 rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-gray-400 hover:text-white"
          >
            Settings
          </button>
          <button
            type="button"
            onClick={() => setHubOpen(true)}
            className="min-h-11 rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-gray-400 hover:text-white"
          >
            Hub
          </button>
          {replayCut !== null ? (
            <span className="flex items-center gap-1 rounded-lg border border-primary/50 bg-primary/10 px-1.5 py-0.5">
              <button
                type="button"
                onClick={() => setReplayPlaying((playing) => !playing)}
                className="grid min-h-11 min-w-11 place-items-center rounded px-2 text-[11px] font-bold text-primary"
                aria-label={replayPlaying ? 'Pause replay' : 'Play replay'}
              >
                {replayPlaying ? 'Pause' : 'Play'}
              </button>
              <button
                type="button"
                onClick={stepReplay}
                className="grid min-h-11 min-w-11 place-items-center rounded px-2 text-[11px] font-bold text-primary"
                aria-label="Next bar"
              >
                Step
              </button>
              <button
                type="button"
                onClick={stopReplay}
                className="grid min-h-11 min-w-11 place-items-center rounded px-2 text-[11px] font-bold text-primary"
                aria-label="Stop replay"
              >
                Stop
              </button>
              <span className="pr-1 text-[10px] text-primary/80">
                {replayCut + 1}/{candles.length}
              </span>
            </span>
          ) : (
            <button
              type="button"
              onClick={startReplay}
              disabled={candles.length < 20}
              className="min-h-11 rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-gray-400 hover:text-white disabled:opacity-40"
            >
              Replay
            </button>
          )}
          <button
            type="button"
            onClick={undo}
            disabled={symbolDrawings.length === 0}
            className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-gray-400 hover:text-white disabled:opacity-40"
          >
            Undo
          </button>
          <button
            type="button"
            onClick={() => void clearAll()}
            disabled={symbolDrawings.length === 0}
            className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-gray-400 hover:text-white disabled:opacity-40"
          >
            Clear
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        <span className="text-[10px] font-semibold uppercase tracking-wider text-gray-500">
          Overlays
        </span>
        <button
          type="button"
          title="Overlay a second instrument, scaled to this one"
          aria-pressed={compareSymbol !== null}
          aria-expanded={compareOpen}
          onClick={() => {
            setCompareOpen((open) => !open)
            setCompareError(null)
          }}            className={`min-h-11 rounded-lg border px-2.5 py-1 text-[11px] font-semibold ${
            compareSymbol
              ? 'border-violet-400/60 bg-violet-400/10 text-violet-300'
              : 'border-border bg-surface text-gray-500 hover:text-gray-300'
          }`}
        >
          Compare
        </button>
        {compareSymbol && (
          <span className="flex min-h-11 items-center gap-1.5 rounded-lg border border-violet-400/40 bg-violet-400/10 px-2 text-[10px] font-semibold tabular-nums">
            <span
              aria-hidden
              className="h-1.5 w-1.5 rounded-full"
              style={{ background: COMPARE_COLOUR }}
            />
            <span className="text-violet-200">{compareSymbol.replace('_', '/')}</span>
            {compareChange !== null && (
              <span className={compareChange >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                {compareChange >= 0 ? '+' : ''}
                {(compareChange * 100).toFixed(2)}%
              </span>
            )}
            {compareError && <span className="text-rose-400">no feed</span>}
            <button
              type="button"
              aria-label={`Remove compare ${compareSymbol}`}
              onClick={removeCompare}
              className="grid h-11 w-11 place-items-center rounded text-violet-300/70 hover:text-white"
            >
              ×
            </button>
          </span>
        )}
        <button
          type="button"
          title="Session VWAP, reset each UTC day"
          onClick={() => setShowVwap((value) => !value)}            className={`min-h-11 rounded-lg border px-2.5 py-1 text-[11px] font-semibold ${
            showVwap
              ? 'border-amber-400/60 bg-amber-400/10 text-amber-300'
              : 'border-border bg-surface text-gray-500 hover:text-gray-300'
          }`}
        >
          VWAP
        </button>
        <button
          type="button"
          title="Asia, London and New York high and low for the latest session day"
          onClick={() => setShowSessions((value) => !value)}            className={`min-h-11 rounded-lg border px-2.5 py-1 text-[11px] font-semibold ${
            showSessions
              ? 'border-sky-400/60 bg-sky-400/10 text-sky-300'
              : 'border-border bg-surface text-gray-500 hover:text-gray-300'
          }`}
        >
          Sessions
        </button>
        {showVwap && vwap.length > 0 && (
          <span className="text-[10px] font-semibold tabular-nums text-amber-400">
            VWAP {vwap[vwap.length - 1].p.toFixed(pricePrecision(vwap[vwap.length - 1].p))}
          </span>
        )}
      </div>

      {compareOpen && (
        <form
          onSubmit={(event) => {
            event.preventDefault()
            addCompare(compareDraft)
          }}
          className="flex flex-wrap items-center gap-1.5 rounded-lg border border-border bg-surface px-2 py-1.5"
        >
          <input
            value={compareDraft}
            onChange={(event) => setCompareDraft(event.target.value)}
            aria-label="Compare symbol"
            placeholder="XAU_USD"
            spellCheck={false}
            className="min-h-11 w-24 rounded-md border border-border bg-surface-light px-2 py-1 text-[11px] font-semibold uppercase tracking-wide text-white outline-none focus:border-primary"
          />
          <button
            type="submit"
            className="min-h-11 rounded-md bg-primary px-3 text-[11px] font-bold text-black"
          >
            Overlay
          </button>
          {SYMBOLS.filter((item) => item !== chartSymbol(symbol))
            .slice(0, 4)
            .map((item) => (
              <button
                key={item}
                type="button"
                onClick={() => addCompare(item)}
                className="min-h-11 rounded-md border border-border px-3 text-[11px] font-semibold text-gray-400 hover:text-white"
              >
                {item.replace('_', '/')}
              </button>
            ))}
          <button
            type="button"
            onClick={() => {
              setCompareOpen(false)
              setCompareError(null)
            }}
            className="ml-auto min-h-11 rounded-md px-2 text-[11px] font-semibold text-gray-500 hover:text-white"
          >
            Cancel
          </button>
          {compareError && (
            <span role="alert" className="w-full text-[10px] text-rose-400">
              {compareError}
            </span>
          )}
        </form>
      )}

      {/* The object strip sits directly above the canvas, where the eye
          already is: selecting something must not push the tools it was drawn
          with out from under the pointer. */}
      {selectedRow && (
        <ChartObjectBar
          row={selectedRow}
          onStyle={(patch) => restyleObject(selectedRow.id, patch)}
          onClone={() => cloneObject(selectedRow)}
          onDelete={() => void removeDrawing(selectedRow.id)}
          onOpenSettings={() => setSettingsId(selectedRow.id)}
        />
      )}

      <ChartObjectList
        rows={symbolDrawings}
        selectedId={selectedId}
        interval={interval}
        onSelect={(id) => setSelectedId(id)}
        onDelete={(id) => void removeDrawing(id)}
        formatPrice={(price) => price.toFixed(decimals(price))}
        formatTime={(ms) => tickLabel(ms, interval, settings)}
      />

      <p id="chart-live" aria-live="polite" className="sr-only">
        {hoverCandle
          ? `${tickLabel(hoverCandle.t, interval, settings)} open ${hoverCandle.o.toFixed(decimals(hoverCandle.o))}, high ${hoverCandle.h.toFixed(decimals(hoverCandle.h))}, low ${hoverCandle.l.toFixed(decimals(hoverCandle.l))}, close ${hoverCandle.c.toFixed(decimals(hoverCandle.c))}`
          : `${symbolDrawings.length} saved object${symbolDrawings.length === 1 ? '' : 's'} on ${symbol}`}
        {replayCut === null ? '' : `. Replay paused at bar ${replayCut + 1} of ${candles.length}`}
        {compareSymbol && compareChange !== null
          ? `. ${compareSymbol} is ${compareChange >= 0 ? 'up' : 'down'} ${Math.abs(
              compareChange * 100
            ).toFixed(2)} percent across this view, drawn in violet against ${symbol}.`
          : ''}
      </p>

      <div
        ref={boxRef}
        className={`relative w-full overflow-hidden rounded-xl border border-border ${
          expanded
            ? 'h-[calc(100vh-20rem)] min-h-[320px] shrink-0'
            : 'h-[62vh] min-h-[380px]'
        }`}
        style={{ background: settings.background }}
      >
        <canvas
          ref={canvasRef}
          id="chart-canvas"
          role="img"
          tabIndex={0}
          // The canvas fills its box instead of pinning the measured size: an
          // inline 900px width is a min-content width, and on a phone it made
          // the whole desk 934px wide rather than letting it shrink.
          className="block h-full w-full outline-none focus-visible:outline-2 focus-visible:outline-offset-[-3px] focus-visible:outline-primary"
          aria-label={`${symbol} ${interval} chart with ${symbolDrawings.length} saved object${
            symbolDrawings.length === 1 ? '' : 's'
          }${compareSymbol ? `, compared with ${compareSymbol}` : ''}. Arrow keys pan, plus and minus zoom.`}
          aria-describedby="chart-live"
          style={{ touchAction: 'none', cursor: tool === 'select' ? 'crosshair' : 'copy' }}
          onKeyDown={(event) => {
            // A canvas has no focusable parts, so the keyboard model lives on
            // the canvas itself: the same keys a trader reaches for in any
            // charting app, without a mouse.
            const step = event.shiftKey ? 0.25 : 0.1
            if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
              event.preventDefault()
              setView((current) => ({
                ...current,
                start: Math.max(0, current.start + (event.key === 'ArrowLeft' ? -current.span : current.span) * step),
              }))
              return
            }
            if (event.key === '+' || event.key === '=' || event.key === '-') {
              event.preventDefault()
              setView((current) => {
                const zoomed = event.key === '-' ? current.span * 1.15 : current.span / 1.15
                const span = Math.max(12, Math.min(candles.length, zoomed))
                return { start: Math.min(current.start, Math.max(0, candles.length - span)), span }
              })
              return
            }
            if (event.key === 'Escape') {
              setSelectedId(null)
              setSettingsOpen(false)
              setLayoutsOpen(false)
              setHubOpen(false)
              setCompareOpen(false)
            }
          }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerLeave={() => {
            setHover(null)
            drag.current = null
          }}
          onWheel={onWheel}
        />

        {loading && (
          <div className="absolute inset-0 grid place-items-center bg-[#0b1220]/70 text-xs text-gray-400">
            Loading {symbol.replace('_', '/')}…
          </div>
        )}
        {!loading && error && (
          <div className="absolute inset-0 grid place-items-center px-6 text-center text-xs text-gray-300">
            {error}
          </div>
        )}
        {!loading && !error && candles.length === 0 && (
          <div className="absolute inset-0 grid place-items-center text-xs text-gray-400">
            No candles came back for {symbol.replace('_', '/')}.
          </div>
        )}

        {lastPrice !== null && (
          <div className="pointer-events-none absolute right-2 top-2 rounded-md bg-[#0b1220]/80 px-2 py-1 text-[11px] font-semibold tabular-nums text-gray-300">
            {lastPrice.toFixed(pricePrecision(lastPrice))}
          </div>
        )}
      </div>

      <p className="text-[11px] leading-relaxed text-gray-500">
        {activeTool?.hint}.{' '}
        {tool === 'select'
          ? 'Drag an object to move it, press Delete to remove the selected one, scroll to zoom.'
          : 'Tap once (or twice for two-point tools) to place it.'}{' '}
        {symbolDrawings.length} object{symbolDrawings.length === 1 ? '' : 's'} saved on{' '}
        {symbol.replace('_', '/')}. Vertical marks a time, Measure reports the move in
        points, percent and bars. Both overlays are computed from the candles and
        never touch your saved objects.
      </p>

      {settingsRow && (
        <ChartObjectSettings
          row={settingsRow}
          onClose={() => setSettingsId(null)}
          onClone={() => {
            cloneObject(settingsRow)
            setSettingsId(null)
          }}
          onDelete={() => {
            void removeDrawing(settingsRow.id)
            setSettingsId(null)
          }}
          onSave={(next) => {
            void persistObject(settingsRow.id, next)
            setSettingsId(null)
          }}
        />
      )}

      {notice && (
        <div className="flex items-start justify-between gap-3 rounded-lg border border-border bg-surface px-3 py-2 text-[11px] text-gray-300">
          <span>{notice}</span>
          <button type="button" onClick={() => setNotice(null)} className="text-gray-500 hover:text-white">
            Dismiss
          </button>
        </div>
      )}

      {settingsOpen && (
        <ChartSettingsDialog
          settings={settings}
          onChange={setSettings}
          onClose={() => setSettingsOpen(false)}
          activeAlertsOnly={activeAlertsOnly}
          onActiveAlertsOnly={setActiveAlertsOnly}
          templates={templates}
          onSaveTemplate={saveTemplate}
          onDeleteTemplate={deleteTemplate}
        />
      )}

      {layoutsOpen && (
        <ChartLayoutsDialog
          layouts={layouts}
          currentSymbol={chartSymbol(symbol)}
          currentInterval={interval}
          onOpen={openLayout}
          onSave={(name) => {
            saveCurrentLayout(name)
            setLayoutsOpen(false)
          }}
          onDelete={deleteLayout}
          onClose={() => setLayoutsOpen(false)}
        />
      )}

      {hubOpen && (
        <AnalysisHubDialog
          activeLayoutName={layouts.find((layout) => layout.id === activeLayoutId)?.name ?? null}
          onOpenLayouts={() => {
            setHubOpen(false)
            setLayoutsOpen(true)
          }}
          onOpenSettings={() => {
            setHubOpen(false)
            setSettingsOpen(true)
          }}
          onSaveLayout={() => {
            setHubOpen(false)
            setLayoutsOpen(true)
          }}
          onNewLayout={newLayout}
          onToggleReplay={() => {
            if (replayCut === null) startReplay()
            else stopReplay()
            setHubOpen(false)
          }}
          replaying={replayCut !== null}
          objectCount={symbolDrawings.length}
          alertCount={activeAlertCount}
          onClose={() => setHubOpen(false)}
        />
      )}
    </div>
  )
}

/**
 * Folds a fresh read of one symbol's rows into the list on screen.
 *
 * Every other symbol is left untouched, and an optimistic `local-` row is kept
 * until its insert returns a real id — otherwise a poll landing mid-write would
 * blink the object the trader just placed out of existence and back again.
 */
export function mergeSymbolDrawings(
  current: ChartDrawingRow[],
  incoming: ChartDrawingRow[],
  symbol: string
): ChartDrawingRow[] {
  const local = new Map(
    current.filter((row) => row.symbol === symbol).map((row) => [row.id, row])
  )
  const merged = incoming.map((row) => {
    const mine = local.get(row.id)
    if (!mine) return row
    // Same row, two versions: the later edit stays on screen. A local version
    // that is newer than the read has not been pushed yet; it will be, and the
    // other device adopts it by this same rule.
    return (mine.editedAtMs ?? 0) > (row.editedAtMs ?? 0) ? mine : row
  })
  return [
    ...current.filter((row) => row.symbol !== symbol),
    ...merged,
    ...current.filter((row) => row.symbol === symbol && row.id.startsWith('local-')),
  ]
}

/**
 * One canonical symbol for both the candle request and the saved objects.
 *
 * The phone's instrument list says `EURUSD`; the vendor and this desk say
 * `EUR_USD`. Without a single spelling the same pair would carry two sets of
 * levels that never meet. Indices keep their short names, as they do on the
 * phone.
 */
export function chartSymbol(raw: string): string {
  const cleaned = raw.trim().toUpperCase().replace(/[/\s-]+/g, '_')
  if (cleaned.includes('_')) return cleaned
  for (const quote of ['USD', 'EUR', 'JPY', 'GBP', 'AUD', 'CHF', 'CAD', 'NZD']) {
    if (cleaned.length > quote.length && cleaned.endsWith(quote)) {
      return `${cleaned.slice(0, cleaned.length - quote.length)}_${quote}`
    }
  }
  return cleaned
}

/** Price decimals that suit the magnitude: 5 for EUR/USD, 2 for gold, 1 for indices. */
/** Milliseconds in one candle of this interval, for the bar-close countdown. */
function intervalMs(interval: string): number {
  const table: Record<string, number> = {
    '5m': 5 * 60_000,
    '15m': 15 * 60_000,
    '30m': 30 * 60_000,
    '1h': 60 * 60_000,
    '4h': 4 * 60 * 60_000,
    '1d': 24 * 60 * 60_000,
  }
  return table[interval] ?? 60 * 60_000
}

/**
 * A price step a trader reads as round: 1, 2, 2.5 or 5 times a power of ten.
 *
 * Dividing the visible range by a fixed tick count invents steps like 37.4,
 * which round to 37 and then either collide or leave a gap depending on where
 * the range starts. The ladder snaps to the numbers people actually quote.
 */
export function niceStep(raw: number): number {
  if (!Number.isFinite(raw) || raw <= 0) return 0
  const magnitude = 10 ** Math.floor(Math.log10(raw))
  const normalised = raw / magnitude
  const ladder = [1, 2, 2.5, 5, 10]
  const pick = ladder.find((candidate) => normalised <= candidate * (1 + 1e-9)) ?? 10
  return pick * magnitude
}

/**
 * Price levels for the axis, spaced by the plot's own height.
 *
 * Four fixed gridlines left fat empty bands on a tall chart and a crowded smear
 * on a short one. The count now follows the pixel height and the step comes
 * from the ladder, floored at the instrument's precision so two labels can never
 * print the same number.
 */
export function priceAxisTicks(
  min: number,
  max: number,
  plotHeightPx: number,
  precision: number,
  preferredSpacingPx = 44
): number[] {
  if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min || plotHeightPx <= 0) return []
  const range = max - min
  // Three is the floor: two labels read as "top" and "bottom" and nothing else.
  const target = Math.max(3, Math.floor(plotHeightPx / preferredSpacingPx))
  const digits = Math.max(0, Math.min(8, precision))
  const minTick = 10 ** -digits
  // 32px between label centres is the hard collision guard.
  const step = Math.max(niceStep(range / (target - 1)), (32 * range) / plotHeightPx, minTick)
  const first = Math.ceil(min / step - 1e-9) * step
  const ticks: number[] = []
  for (let value = first; value <= max + 1e-9 && ticks.length < 64; value += step) {
    // Repeated addition drifts: 3595.738 arrives as 3595.7380000000003.
    ticks.push(Number(value.toFixed(digits + 2)))
  }
  return ticks
}

export interface TimeAxisTick {
  ms: number
  major: boolean
  label: string
}

interface TimeStep {
  unit: 'minute' | 'day' | 'week' | 'month' | 'year'
  count: number
}

const MINUTE_MS = 60_000
const DAY_MS = 24 * 60 * MINUTE_MS

const TIME_LADDER: TimeStep[] = [
  { unit: 'minute', count: 1 },
  { unit: 'minute', count: 5 },
  { unit: 'minute', count: 15 },
  { unit: 'minute', count: 30 },
  { unit: 'minute', count: 60 },
  { unit: 'minute', count: 120 },
  { unit: 'minute', count: 240 },
  { unit: 'minute', count: 360 },
  { unit: 'minute', count: 720 },
  { unit: 'day', count: 1 },
  { unit: 'day', count: 3 },
  { unit: 'week', count: 1 },
  // Two weeks is not in the textbook ladder, but jumping 7d -> 1M leaves a
  // hundred-day view with three labels and a lot of empty axis.
  { unit: 'week', count: 2 },
  { unit: 'month', count: 1 },
  { unit: 'month', count: 3 },
  { unit: 'year', count: 1 },
]

function stepMilliseconds(step: TimeStep): number {
  switch (step.unit) {
    case 'minute':
      return step.count * MINUTE_MS
    case 'day':
      return step.count * DAY_MS
    case 'week':
      return step.count * 7 * DAY_MS
    case 'month':
      return step.count * 30 * DAY_MS
    case 'year':
      return step.count * 365 * DAY_MS
  }
}

/** First tick at or after `ms`, on the UTC boundary the step names. */
function snapUp(ms: number, step: TimeStep): number {
  if (step.unit === 'minute') {
    const size = stepMilliseconds(step)
    return Math.ceil(ms / size) * size
  }
  if (step.unit === 'day') {
    const size = stepMilliseconds(step)
    return Math.ceil(ms / size) * size
  }
  if (step.unit === 'week') {
    const dayStart = Math.floor(ms / DAY_MS) * DAY_MS
    // Monday first, so a week tick lands on a week rather than on the epoch.
    const weekday = new Date(dayStart).getUTCDay()
    let candidate = dayStart + ((8 - weekday) % 7) * DAY_MS
    if (candidate < ms) candidate += 7 * DAY_MS
    return candidate
  }
  const date = new Date(ms)
  if (step.unit === 'month') {
    const year = date.getUTCFullYear()
    const month = date.getUTCMonth()
    const aligned = month - (month % step.count)
    const candidate = Date.UTC(year, aligned, 1)
    if (candidate >= ms) return candidate
    let next = aligned + step.count
    let nextYear = year
    while (next >= 12) {
      next -= 12
      nextYear += 1
    }
    return Date.UTC(nextYear, next, 1)
  }
  const candidate = Date.UTC(date.getUTCFullYear(), 0, 1)
  return candidate >= ms ? candidate : Date.UTC(date.getUTCFullYear() + 1, 0, 1)
}

function advance(ms: number, step: TimeStep): number {
  if (step.unit === 'month' || step.unit === 'year') {
    const date = new Date(ms)
    const months = step.unit === 'year' ? step.count * 12 : step.count
    return Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, 1)
  }
  return ms + stepMilliseconds(step)
}

function clockLabel(ms: number, clock24: boolean): string {
  const date = new Date(ms)
  const hours = date.getUTCHours()
  const minutes = String(date.getUTCMinutes()).padStart(2, '0')
  if (clock24) return `${String(hours).padStart(2, '0')}:${minutes}`
  const hour12 = hours % 12 === 0 ? 12 : hours % 12
  return `${hour12}:${minutes} ${hours >= 12 ? 'PM' : 'AM'}`
}

function dayLabel(ms: number): string {
  const date = new Date(ms)
  return `${date.getUTCDate()} ${date.toLocaleString('en-GB', { month: 'short', timeZone: 'UTC' })}`
}

function monthLabel(ms: number): string {
  return new Date(ms).toLocaleString('en-GB', { month: 'short', timeZone: 'UTC' })
}

/**
 * Time labels snapped to the calendar, wide enough never to collide.
 *
 * Labelling every Nth bar drifts: the same setting produced `03:47` mid-session
 * and collided at two zoom levels either side of it. Ticks now land on real
 * clock and calendar boundaries, and the first tick of a new day, month or year
 * is flagged so the axis can render it in heavier type instead of repeating a
 * date on every label.
 */
export function timeAxisTicks(
  startMs: number,
  endMs: number,
  plotWidthPx: number,
  clock24 = true,
  minSpacingPx = 95
): TimeAxisTick[] {
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs || plotWidthPx <= 0) {
    return []
  }
  const span = endMs - startMs
  const step =
    TIME_LADDER.find(
      (candidate) => (stepMilliseconds(candidate) / span) * plotWidthPx >= minSpacingPx
    ) ?? TIME_LADDER[TIME_LADDER.length - 1]

  const ticks: TimeAxisTick[] = []
  let ms = snapUp(startMs, step)
  for (let guard = 0; guard < 200 && ms <= endMs; guard += 1) {
    const date = new Date(ms)
    const previous = ticks.length > 0 ? new Date(ticks[ticks.length - 1].ms) : null
    const newYear = previous !== null && previous.getUTCFullYear() !== date.getUTCFullYear()
    const newMonth = previous !== null && previous.getUTCMonth() !== date.getUTCMonth()
    const newDay = previous !== null && previous.getUTCDate() !== date.getUTCDate()
    const major = newYear || newMonth || (step.unit === 'minute' && newDay)

    let label: string
    if (step.unit === 'year') {
      label = String(date.getUTCFullYear())
    } else if (step.unit === 'month') {
      label = newYear ? String(date.getUTCFullYear()) : monthLabel(ms)
    } else if (step.unit === 'day' || step.unit === 'week') {
      label = newYear ? String(date.getUTCFullYear()) : newMonth ? monthLabel(ms) : dayLabel(ms)
    } else {
      label = newYear
        ? String(date.getUTCFullYear())
        : newMonth
          ? monthLabel(ms)
          : newDay
            ? dayLabel(ms)
            : clockLabel(ms, clock24)
    }

    ticks.push({ ms, major, label })
    ms = advance(ms, step)
  }
  return ticks
}

/**
 * Whether an object's pixel bounds touch the candle pane at all.
 *
 * One decision per object, taken before any of it is painted, so a panned-away
 * object takes its geometry, labels, measurements and handles with it. A
 * horizontal line is decided by its price, a vertical one by its time, and the
 * rest by their bounding box: a segment that crosses the pane has a box that
 * overlaps it even when neither anchor is on screen.
 */
export function objectInPane(
  bounds: { minX: number; maxX: number; minY: number; maxY: number },
  kind: string,
  plotWidth: number,
  plotHeight: number
): boolean {
  const spansPrices = bounds.minY <= plotHeight && bounds.maxY >= 0
  const spansTimes = bounds.minX <= plotWidth && bounds.maxX >= 0
  if (kind === 'ray') return spansPrices
  if (kind === 'vline') return spansTimes
  if (kind === 'text') {
    // The words hang above and to the right of the anchor.
    return spansTimes && bounds.maxY >= 0 && bounds.minY - 16 <= plotHeight
  }
  return spansPrices && spansTimes
}

function pricePrecision(price: number): number {
  const magnitude = Math.abs(price)
  if (magnitude >= 1000) return 1
  if (magnitude >= 100) return 2
  if (magnitude >= 10) return 3
  return 5
}

function tickLabel(
  ms: number,
  interval: string,
  settings?: { clock24: boolean; weekday: boolean }
): string {
  const date = new Date(ms)
  const weekday = settings?.weekday
    ? `${date.toLocaleString('en-GB', { weekday: 'short', timeZone: 'UTC' })} `
    : ''
  const daily = interval === '1d'
  if (daily) {
    return `${weekday}${date.getUTCDate()} ${date.toLocaleString('en-GB', { month: 'short', timeZone: 'UTC' })}`
  }
  const hours = settings?.clock24 === false
    ? String(date.getUTCHours() % 12 === 0 ? 12 : date.getUTCHours() % 12)
    : String(date.getUTCHours()).padStart(2, '0')
  const minutes = String(date.getUTCMinutes()).padStart(2, '0')
  const suffix = settings?.clock24 === false ? (date.getUTCHours() >= 12 ? ' PM' : ' AM') : ''
  return `${weekday}${date.getUTCDate()}/${date.getUTCMonth() + 1} ${hours}:${minutes}${suffix}`
}
