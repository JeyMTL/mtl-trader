'use client'

import { useMemo, useState } from 'react'
import { CandlestickChart, Copy, Lock, SlidersHorizontal, Trash2, Unlock } from 'lucide-react'

import { useDialogFocus } from '@/components/use-dialog-focus'

/**
 * The look of one saved chart object.
 *
 * The keys are the phone's own (`DrawingLook.toJson`): `c` is an ARGB int, `w`
 * a stroke width, `d` dashed, `f` fill percent, `lk` locked, `hd` hidden. One
 * table, one vocabulary — an object styled on the phone is the same object here
 * without a translation layer to get out of step.
 */
export interface DrawingStyle {
  c?: number
  w?: number
  d?: boolean
  /** Dotted stroke. Exclusive with `d`, the way the sheet treats one choice. */
  dt?: boolean
  f?: number
  lk?: boolean
  hd?: boolean
  /** An alert line: the same level, but it tells you when price reaches it. */
  al?: boolean
  /** Set once that alert has been delivered. Kept so the level is not lost. */
  fd?: boolean
  /**
   * Intervals this object is drawn on, e.g. ['15m','1h']. Absent means every
   * interval, which is what an object drawn before this key existed means.
   */
  iv?: string[]
  /** Paint order: higher sits on top. The phone uses list order instead. */
  z?: number
}

export const INTERVAL_OPTIONS = ['5m', '15m', '30m', '1h', '4h', '1d'] as const

/** True when an object belongs on this interval. */
export function visibleOnInterval(style: DrawingStyle | undefined, interval: string): boolean {
  if (!style?.iv || style.iv.length === 0) return true
  return style.iv.includes(interval)
}

export interface ObjectRow {
  id: string
  kind: string
  points: { t: number; p: number }[]
  text: string | null
  style?: DrawingStyle
}

/** The colours the phone offers, in the same order, so the two match. */
export const OBJECT_PALETTE = [
  '#45d29a',
  '#26a69a',
  '#4c9aff',
  '#d5a44e',
  '#f0b90b',
  '#ab7df6',
  '#f26b78',
  '#ef5350',
  '#98a1b0',
  '#edf0f5',
  '#131722',
] as const

const KIND_NAMES: Record<string, string> = {
  ray: 'Level',
  trend: 'Trend line',
  fib: 'Fib retracement',
  rectangle: 'Zone',
  vline: 'Vertical line',
  measure: 'Measure',
  text: 'Text',
  ellipse: 'Ellipse',
  brush: 'Brush',
  arrowUp: 'Arrow up',
  arrowDown: 'Arrow down',
  fibExtension: 'Fib extension',
}

/** True for the kinds that paint a body, and so have a fill to make solid. */
export function hasFill(kind: string): boolean {
  return ['rectangle', 'ellipse', 'fib', 'fibExtension', 'measure', 'text'].includes(kind)
}

export function objectName(kind: string, style?: DrawingStyle): string {
  // A level and an alert line are the same object on the chart; only the flag
  // separates them, so the name has to read the flag.
  if (kind === 'ray' && style?.al) {
    return style.fd ? 'Alert line — fired' : 'Alert line'
  }
  return KIND_NAMES[kind] ?? kind
}

/** True when the object is a level that announces itself. */
export function isAlertLine(kind: string, style?: DrawingStyle): boolean {
  return kind === 'ray' && Boolean(style?.al)
}

/**
 * Where an object sits, in words.
 *
 * The canvas says none of this out loud — it is pixels — so the object list is
 * the only place a screen reader can learn that the third level is 1.08450
 * rather than 1.08500. Formatting is injected so the desk's own precision and
 * clock apply, and so the text can be asserted in a test without a browser.
 */
export function objectSummary(
  row: ObjectRow,
  formatPrice: (price: number) => string,
  formatTime: (ms: number) => string
): string {
  const points = row.points
  if (points.length === 0) return 'No anchors'
  if (row.kind === 'ray') return formatPrice(points[0].p)
  if (row.kind === 'vline') return formatTime(points[0].t)

  const prices = points.map((point) => point.p)
  const times = points.map((point) => point.t)
  const low = Math.min(...prices)
  const high = Math.max(...prices)
  const from = Math.min(...times)
  const to = Math.max(...times)
  const level = low === high ? formatPrice(low) : `${formatPrice(low)} to ${formatPrice(high)}`
  // Two anchors are a span in time whatever the prices do, so the times are
  // always given as a range: a flat zone still covers a stretch of the chart.
  return `${level}, ${formatTime(from)} to ${formatTime(to)}`
}

/** The states worth saying out loud about an object on this chart. */
export function objectState(style: DrawingStyle | undefined, interval: string): string[] {
  const states: string[] = []
  if (!style) return states
  if (style.al) states.push(style.fd ? 'alert fired' : 'alert armed')
  if (style.lk) states.push('locked')
  if (style.hd) states.push('hidden')
  if (!visibleOnInterval(style, interval)) states.push(`not drawn on ${interval}`)
  return states
}

/** An ARGB int from the phone as a CSS colour, with a fallback per state. */
export function styleColour(style: DrawingStyle | undefined, selected: boolean): string {
  if (typeof style?.c === 'number') {
    return `#${(style.c & 0xffffff).toString(16).padStart(6, '0')}`
  }
  return selected ? '#60a5fa' : '#94a3b8'
}

/** Fill alpha as a canvas `rgba` string: the trader's percent, or the quiet default. */
export function styleFill(style: DrawingStyle | undefined, colour: string, selected: boolean): string {
  const percent = typeof style?.f === 'number' ? style.f : selected ? 12 : 8
  const hex = colour.replace('#', '')
  const value = Number.parseInt(hex, 16)
  const r = (value >> 16) & 0xff
  const g = (value >> 8) & 0xff
  const b = value & 0xff
  return `rgba(${r}, ${g}, ${b}, ${Math.min(1, Math.max(0, percent / 100))})`
}

/** A `datetime-local` value for an epoch time, in the browser's own zone. */
function inputTime(ms: number): string {
  const date = new Date(ms)
  if (Number.isNaN(date.getTime())) return ''
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
    .toISOString()
    .slice(0, 16)
}

/**
 * The strip that appears when an object is selected.
 *
 * Colour, weight and dash are one tap each because that is the loop a trader
 * actually repeats — redraw a zone, make it quieter, move on. Everything else
 * (exact levels, the label, clone, remove) lives one step away in the settings
 * dialog, which is where TradingView puts it too.
 */
export function ChartObjectBar({
  row,
  onStyle,
  onClone,
  onDelete,
  onOpenSettings,
}: {
  row: ObjectRow
  onStyle: (patch: Partial<DrawingStyle>) => void
  onClone: () => void
  onDelete: () => void
  onOpenSettings: () => void
}) {
  const [coloursOpen, setColoursOpen] = useState(false)
  const style = row.style ?? {}
  const colour = styleColour(style, true)
  const width = style.w ?? 2
  const fillable = hasFill(row.kind)

  return (
    <div className="relative flex flex-wrap items-center gap-1.5 rounded-xl border border-primary/40 bg-surface px-2 py-1.5">
      <button
        type="button"
        onClick={onOpenSettings}
        className="flex min-h-11 items-center gap-1.5 rounded-md px-2 py-1 text-xs font-semibold text-white hover:bg-surface-light"
        title="Style, coordinates and the label"
      >
        <CandlestickChart className="h-3.5 w-3.5 text-primary" />
        {objectName(row.kind, row.style)}
        <SlidersHorizontal className="h-3 w-3 text-gray-500" />
      </button>

      <span className="mx-1 h-4 w-px bg-border" />

      <button
        type="button"
        onClick={() => setColoursOpen((open) => !open)}
        title="Colour"
        aria-label="Colour"
        className="grid h-11 w-11 place-items-center rounded-md border border-border"
      >
        <span className="h-3.5 w-3.5 rounded-full" style={{ backgroundColor: colour }} />
      </button>

      <div className="flex items-center rounded-md border border-border">
        <button
          type="button"
          onClick={() => onStyle({ w: Math.max(1, width - 1) })}
          className="grid min-h-11 min-w-11 place-items-center px-2 text-xs text-gray-400 hover:text-white"
          aria-label="Thinner line"
        >
          −
        </button>
        <span className="min-w-[34px] text-center text-[11px] font-semibold tabular-nums text-gray-300">
          {width}px
        </span>
        <button
          type="button"
          onClick={() => onStyle({ w: Math.min(4, width + 1) })}
          className="grid min-h-11 min-w-11 place-items-center px-2 text-xs text-gray-400 hover:text-white"
          aria-label="Thicker line"
        >
          +
        </button>
      </div>

      <button
        type="button"
        onClick={() => onStyle({ d: !style.d, ...(style.d ? {} : { dt: false }) })}
        title="Dashed line"
        aria-pressed={Boolean(style.d)}
        className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
          style.d
            ? 'border-primary/60 bg-primary/10 text-primary'
            : 'border-border text-gray-400 hover:text-white'
        }`}
      >
        Dashed
      </button>

      <button
        type="button"
        onClick={() => onStyle({ dt: !style.dt, ...(style.dt ? {} : { d: false }) })}
        title="Dotted line"
        aria-pressed={Boolean(style.dt)}
        className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
          style.dt
            ? 'border-primary/60 bg-primary/10 text-primary'
            : 'border-border text-gray-400 hover:text-white'
        }`}
      >
        Dotted
      </button>

      {fillable && (
        <label className="flex min-h-11 items-center gap-1.5 rounded-md border border-border px-2 text-[11px] text-gray-400">
          Fill
          <input
            type="range"
            min={0}
            max={60}
            value={typeof style.f === 'number' ? style.f : 6}
            onChange={(event) => onStyle({ f: Number(event.target.value) })}
            className="h-6 w-20 accent-sky-400"
            aria-label="Fill opacity"
          />
          <span className="w-7 text-right tabular-nums text-gray-300">
            {typeof style.f === 'number' ? style.f : 6}%
          </span>
        </label>
      )}

      <button
        type="button"
        onClick={() => onStyle({ lk: !style.lk })}
        title={style.lk ? 'Unlock' : 'Lock'}
        aria-label={style.lk ? 'Unlock object' : 'Lock object'}
        aria-pressed={Boolean(style.lk)}
        className={`grid h-11 w-11 place-items-center rounded-md border ${
          style.lk ? 'border-primary/60 bg-primary/10 text-primary' : 'border-border text-gray-400 hover:text-white'
        }`}
      >
        {style.lk ? <Lock className="h-3.5 w-3.5" /> : <Unlock className="h-3.5 w-3.5" />}
      </button>

      <button
        type="button"
        onClick={() => onStyle({ hd: !style.hd })}
        title={style.hd ? 'Show' : 'Hide'}
        aria-pressed={Boolean(style.hd)}
        className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
          style.hd ? 'border-primary/60 bg-primary/10 text-primary' : 'border-border text-gray-400 hover:text-white'
        }`}
      >
        {style.hd ? 'Hidden' : 'Hide'}
      </button>

      <div className="ml-auto flex items-center gap-1">
        <button
          type="button"
          onClick={onClone}
          title="Clone"
          aria-label="Clone object"
          className="grid h-11 w-11 place-items-center rounded-md border border-border text-gray-400 hover:text-white"
        >
          <Copy className="h-3.5 w-3.5" />
        </button>
        <button
          type="button"
          onClick={onDelete}
          title="Remove"
          aria-label="Remove object"
          className="grid h-11 w-11 place-items-center rounded-md border border-danger/40 text-danger hover:bg-danger/10"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>

      {coloursOpen && (
        <div className="absolute left-0 top-full z-20 mt-1 w-56 rounded-xl border border-border bg-surface p-2 shadow-xl">
          <div className="grid grid-cols-4 gap-1.5">
            {OBJECT_PALETTE.map((swatch) => (
              <button
                key={swatch}
                type="button"
                aria-label={`Colour ${swatch}`}
                onClick={() => {
                  onStyle({ c: (0xff000000 | Number.parseInt(swatch.slice(1), 16)) >>> 0 })
                  setColoursOpen(false)
                }}
                className={`grid h-11 w-11 place-items-center rounded-full border ${
                  colour.toLowerCase() === swatch ? 'border-white' : 'border-border'
                }`}
              >
                <span
                  aria-hidden
                  className="h-6 w-6 rounded-full"
                  style={{ backgroundColor: swatch }}
                />
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={() => {
              onStyle({ c: undefined })
              setColoursOpen(false)
            }}
            className="mt-2 min-h-11 w-full rounded-md border border-border px-3 py-1 text-[11px] font-semibold text-gray-400 hover:text-white"
          >
            Chart colour
          </button>
        </div>
      )}
    </div>
  )
}

/**
 * Every object on this instrument, as a list you can read and act on.
 *
 * A canvas is one image to a screen reader: the candles, the levels and the
 * zones are all the same `role="img"`. This is the mirror of that image in
 * text — name, position and state — with a select button per row so the chart
 * can be driven from the keyboard instead of only from the pointer.
 */
export function ChartObjectList({
  rows,
  selectedId,
  interval,
  onSelect,
  onDelete,
  formatPrice,
  formatTime,
}: {
  rows: ObjectRow[]
  selectedId: string | null
  interval: string
  onSelect: (id: string) => void
  onDelete: (id: string) => void
  formatPrice: (price: number) => string
  formatTime: (ms: number) => string
}) {
  const [open, setOpen] = useState(false)
  return (
    <section
      aria-label="Objects on this chart"
      className="rounded-xl border border-border bg-surface"
    >
      <div className="flex items-center gap-2 px-2 py-1">
        <h2 className="flex-1 text-[11px] font-bold uppercase tracking-wider text-gray-400">
          Objects
        </h2>
        <span aria-hidden className="text-[11px] tabular-nums text-gray-500">
          {rows.length}
        </span>
        <button
          type="button"
          aria-expanded={open}
          aria-controls="chart-object-list"
          onClick={() => setOpen((value) => !value)}
          className="min-h-11 rounded-lg border border-border px-3 text-[11px] font-semibold text-gray-400 hover:text-white"
        >
          {open ? 'Hide list' : rows.length === 0 ? 'Show list' : `Show list (${rows.length})`}
        </button>
      </div>

      {open && (
        <div className="border-t border-border px-2 py-1">
          {rows.length === 0 ? (
            <p className="py-2 text-[11px] leading-relaxed text-gray-500">
              Nothing is pinned to this chart yet. Pick a tool above the canvas and
              press a price to add one.
            </p>
          ) : (
            <ul id="chart-object-list" className="divide-y divide-border/60">
              {rows.map((row) => {
                const states = objectState(row.style, interval)
                const summary = objectSummary(row, formatPrice, formatTime)
                const name = objectName(row.kind, row.style)
                const label = row.text ? `${name}, ${row.text}` : name
                return (
                  <li key={row.id} className="flex items-center gap-1">
                    <button
                      type="button"
                      aria-pressed={row.id === selectedId}
                      onClick={() => onSelect(row.id)}
                      className={`min-h-11 min-w-0 flex-1 rounded-lg px-2 py-1 text-left hover:bg-surface-light ${
                        row.id === selectedId ? 'text-white' : 'text-gray-300'
                      }`}
                    >
                      <span className="block truncate text-xs font-semibold">{label}</span>
                      <span className="block truncate text-[11px] tabular-nums text-gray-500">
                        {summary}
                        {states.length > 0 ? ` — ${states.join(', ')}` : ''}
                      </span>
                    </button>
                    <button
                      type="button"
                      aria-label={`Remove ${label}`}
                      onClick={() => onDelete(row.id)}
                      className="grid h-11 w-11 shrink-0 place-items-center rounded-lg text-gray-500 hover:bg-surface-light hover:text-danger"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      )}
    </section>
  )
}

/**
 * The object's own settings, on the web.
 *
 * Same two tabs as the phone, same draft-first rule: nothing is written until
 * Apply, so a half-finished edit can be abandoned by closing the dialog.
 */
export function ChartObjectSettings({
  row,
  onSave,
  onClose,
  onClone,
  onDelete,
}: {
  row: ObjectRow
  onSave: (next: { points: { t: number; p: number }[]; style: DrawingStyle; text: string | null }) => void
  onClose: () => void
  onClone: () => void
  onDelete: () => void
}) {
  const dialogRef = useDialogFocus<HTMLDivElement>(onClose)
  const [tab, setTab] = useState<'style' | 'coordinates' | 'visibility' | 'text'>('style')
  const [style, setStyle] = useState<DrawingStyle>({ ...(row.style ?? {}) })
  const [points, setPoints] = useState(row.points.map((point) => ({ ...point })))
  const [text, setText] = useState(row.text ?? '')

  const label = useMemo(
    () => objectName(row.kind, row.style),
    [row.kind, row.style]
  )
  const singleAnchor = row.kind === 'ray' || row.kind === 'vline'

  const patchStyle = (patch: Partial<DrawingStyle>) =>
    setStyle((current) => {
      const next = { ...current, ...patch }
      for (const key of Object.keys(patch) as (keyof DrawingStyle)[]) {
        if (patch[key] === undefined) delete next[key]
      }
      return next
    })

  const save = () =>
    onSave({
      points: points.filter((point) => Number.isFinite(point.t) && Number.isFinite(point.p)),
      style,
      // Any object can carry a label: a zone reads better with "supply" on it
      // than with a colour nobody remembers choosing.
      text: text.trim() || null,
    })

  return (
    <div
      ref={dialogRef}
      className="fixed inset-0 z-50 grid place-items-center bg-black/60 p-4"
      role="dialog"
      aria-modal="true"
      aria-label={`${label} settings`}
    >
      <div className="flex max-h-[86vh] w-full max-w-lg flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl">
        <div className="flex items-center justify-between border-b border-border px-4 py-2.5">
          <p className="text-sm font-bold text-white">{label}</p>
          <button
            type="button"
            onClick={onClose}
            className="min-h-11 rounded-lg px-3 text-xs font-semibold text-gray-400 hover:text-white"
          >
            Close
          </button>
        </div>

        <div className="flex items-center gap-1 border-b border-border px-2">
          {(['style', 'coordinates', 'visibility', 'text'] as const).map((value) => (
            <button
              key={value}
              type="button"
              onClick={() => setTab(value as 'style' | 'coordinates' | 'visibility' | 'text')}
              className={`min-h-11 border-b-2 px-3 py-2 text-xs font-semibold capitalize ${
                tab === value ? 'border-primary text-white' : 'border-transparent text-gray-500 hover:text-gray-300'
              }`}
            >
              {value}
            </button>
          ))}
        </div>

        <div className="flex-1 space-y-4 overflow-y-auto px-4 py-3">
          {tab === 'style' && (
            <>
              <section className="space-y-2">
                <p className="text-[11px] font-bold text-gray-400">Line</p>
                <div className="flex flex-wrap gap-1.5">
                  {OBJECT_PALETTE.map((swatch) => (
                    <button
                      key={swatch}
                      type="button"
                      aria-label={`Colour ${swatch}`}
                      onClick={() => patchStyle({ c: (0xff000000 | Number.parseInt(swatch.slice(1), 16)) >>> 0 })}
                      className={`grid h-11 w-11 place-items-center rounded-full border ${
                        styleColour(style, false).toLowerCase() === swatch ? 'border-white' : 'border-border'
                      }`}
                    >
                      <span
                        aria-hidden
                        className="h-6 w-6 rounded-full"
                        style={{ backgroundColor: swatch }}
                      />
                    </button>
                  ))}
                  <button
                    type="button"
                    onClick={() => patchStyle({ c: undefined })}
                    className="min-h-11 rounded-md border border-border px-3 text-[11px] font-semibold text-gray-400 hover:text-white"
                  >
                    Chart colour
                  </button>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-[11px] text-gray-400">Width</span>
                  {[1, 2, 3, 4].map((value) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => patchStyle({ w: value })}
                      className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
                        style.w === value ? 'border-primary bg-primary/15 text-primary' : 'border-border text-gray-400'
                      }`}
                    >
                      {value}px
                    </button>
                  ))}
                  <span className="ml-2 text-[11px] text-gray-400">Style</span>
                  <button
                    type="button"
                    onClick={() => patchStyle({ d: false, dt: false })}
                    className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
                      !style.d && !style.dt ? 'border-primary bg-primary/15 text-primary' : 'border-border text-gray-400'
                    }`}
                  >
                    Solid
                  </button>
                  <button
                    type="button"
                    onClick={() => patchStyle({ d: true, dt: false })}
                    className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
                      style.d ? 'border-primary bg-primary/15 text-primary' : 'border-border text-gray-400'
                    }`}
                  >
                    Dashed
                  </button>
                  <button
                    type="button"
                    onClick={() => patchStyle({ dt: true, d: false })}
                    className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
                      style.dt ? 'border-primary bg-primary/15 text-primary' : 'border-border text-gray-400'
                    }`}
                  >
                    Dotted
                  </button>
                </div>
              </section>

              {hasFill(row.kind) && (
                <section className="space-y-1">
                  <p className="text-[11px] font-bold text-gray-400">Fill</p>
                  <div className="flex items-center gap-2">
                    <input
                      type="range"
                      min={0}
                      max={60}
                      value={typeof style.f === 'number' ? style.f : 6}
                      onChange={(event) => patchStyle({ f: Number(event.target.value) })}
                      className="h-6 flex-1 accent-sky-400"
                      aria-label="Fill opacity"
                    />
                    <span className="w-9 text-right text-[11px] tabular-nums text-gray-300">
                      {typeof style.f === 'number' ? style.f : 6}%
                    </span>
                  </div>
                </section>
              )}

              <section className="space-y-2">
                <p className="text-[11px] font-bold text-gray-400">Object</p>
                <label className="flex min-h-11 items-center justify-between text-xs text-gray-300">
                  Lock, so a pan cannot move it
                  <input
                    type="checkbox"
                    checked={Boolean(style.lk)}
                    onChange={(event) => patchStyle({ lk: event.target.checked })}
                    className="h-4 w-4 accent-sky-400"
                  />
                </label>
                <label className="flex min-h-11 items-center justify-between text-xs text-gray-300">
                  Hide, keeping it in the list
                  <input
                    type="checkbox"
                    checked={Boolean(style.hd)}
                    onChange={(event) => patchStyle({ hd: event.target.checked })}
                    className="h-4 w-4 accent-sky-400"
                  />
                </label>
                <div className="flex items-center gap-2 pt-1">
                  <span className="flex-1 text-[11px] text-gray-400">Order</span>
                  <button
                    type="button"
                    onClick={() => patchStyle({ z: (style.z ?? 0) + 1 })}
                    className="min-h-11 rounded-md border border-border px-3 py-1 text-[11px] font-semibold text-gray-300 hover:text-white"
                  >
                    Bring forward
                  </button>
                  <button
                    type="button"
                    onClick={() => patchStyle({ z: (style.z ?? 0) - 1 })}
                    className="min-h-11 rounded-md border border-border px-3 py-1 text-[11px] font-semibold text-gray-300 hover:text-white"
                  >
                    Send back
                  </button>
                </div>
              </section>

              <div className="flex items-center gap-2 border-t border-border pt-3">
                <button
                  type="button"
                  onClick={onClone}
                  className="min-h-11 flex-1 rounded-lg border border-border px-3 py-2 text-xs font-semibold text-gray-300 hover:text-white"
                >
                  Clone
                </button>
                <button
                  type="button"
                  onClick={onDelete}
                  className="min-h-11 flex-1 rounded-lg border border-danger/40 px-3 py-2 text-xs font-semibold text-danger hover:bg-danger/10"
                >
                  Remove
                </button>
              </div>
            </>
          )}

          {tab === 'visibility' && (
            <div className="space-y-2">
              <p className="text-[11px] font-bold text-gray-400">Show on intervals</p>
              <div className="flex flex-wrap gap-1.5">
                {INTERVAL_OPTIONS.map((option) => {
                  const list = style.iv ?? []
                  const on = list.length === 0 || list.includes(option)
                  return (
                    <button
                      key={option}
                      type="button"
                      aria-pressed={on}
                      onClick={() => {
                        const next = list.length === 0
                          ? INTERVAL_OPTIONS.filter((entry) => entry !== option)
                          : list.includes(option)
                            ? list.filter((entry) => entry !== option)
                            : [...list, option]
                        // Every interval ticked is the same as no list at all.
                        patchStyle({ iv: next.length === INTERVAL_OPTIONS.length ? undefined : next })
                      }}
                      className={`min-h-11 rounded-md border px-3 py-1 text-[11px] font-semibold ${
                        on ? 'border-primary bg-primary/15 text-primary' : 'border-border text-gray-400'
                      }`}
                    >
                      {option}
                    </button>
                  )
                })}
              </div>
              <p className="text-[11px] leading-relaxed text-gray-500">
                An object hidden here is kept and still syncs; it simply is not
                drawn on that candle size. With nothing ticked it shows everywhere.
              </p>
            </div>
          )}

          {tab === 'coordinates' && (
            <div className="space-y-2">
              <p className="text-[11px] font-bold text-gray-400">
                {singleAnchor ? 'Anchor' : 'Anchors'}
              </p>
              {points.map((point, index) => (
                <div key={index} className="flex items-center gap-2">
                  <span className="w-6 text-[11px] font-bold text-gray-500">#{index + 1}</span>
                  {row.kind !== 'ray' && (
                    <input
                      type="datetime-local"
                      value={inputTime(point.t)}
                      onChange={(event) => {
                        const ms = new Date(event.target.value).getTime()
                        if (Number.isNaN(ms)) return
                        setPoints((current) =>
                          current.map((item, at) => (at === index ? { ...item, t: ms } : item))
                        )
                      }}
                      aria-label={`Anchor ${index + 1} time`}
                      className="min-h-11 flex-1 rounded-md border border-border bg-surface-light px-2 py-1 text-[11px] text-gray-200"
                    />
                  )}
                  {row.kind !== 'vline' && (
                    <input
                      type="number"
                      step="any"
                      value={point.p}
                      onChange={(event) => {
                        const value = Number(event.target.value)
                        if (!Number.isFinite(value)) return
                        setPoints((current) =>
                          current.map((item, at) => (at === index ? { ...item, p: value } : item))
                        )
                      }}
                      aria-label={`Anchor ${index + 1} price`}
                      className="min-h-11 w-28 rounded-md border border-border bg-surface-light px-2 py-1 text-right text-[11px] tabular-nums text-gray-200"
                    />
                  )}
                </div>
              ))}
              <p className="pt-1 text-[10.5px] leading-relaxed text-gray-500">
                Times are entered in your own zone. A ray is the same price on every candle
                size; a vertical line only has a time.
              </p>
            </div>
          )}

          {tab === 'text' && (
            <div className="space-y-2">
              <p className="text-[11px] font-bold text-gray-400">Label</p>
              <textarea
                value={text}
                onChange={(event) => setText(event.target.value)}
                rows={3}
                maxLength={200}
                className="w-full rounded-md border border-border bg-surface-light px-2 py-1.5 text-xs text-gray-200 outline-none focus:border-primary"
                placeholder="What this mark is saying"
              />
            </div>
          )}
        </div>

        <div className="flex items-center gap-2 border-t border-border px-4 py-2.5">
          <button
            type="button"
            onClick={onClose}
            className="min-h-11 flex-1 rounded-lg border border-border px-3 py-2 text-xs font-semibold text-gray-400 hover:text-white"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={save}
            className="min-h-11 flex-[2] rounded-lg bg-primary px-3 py-2 text-xs font-bold text-black hover:bg-primary-light"
          >
            Ok
          </button>
        </div>
      </div>
    </div>
  )
}
