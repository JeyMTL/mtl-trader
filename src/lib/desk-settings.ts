/**
 * The web desk's chart settings, and the layouts and templates that carry them.
 *
 * The phone keeps both in SharedPreferences; the desk keeps them here, in this
 * browser. They are viewer preferences, not account data — nothing on the server
 * needs to know that this laptop prefers a dotted crosshair — so localStorage is
 * the honest home until layouts are worth sharing.
 */

export type CrosshairStyle = 'solid' | 'dashed' | 'dotted'

export interface DeskSettings {
  /** Candle colours. The desk used to hardcode a green and a red. */
  bull: string
  bear: string
  /** Decimals every price prints with; null follows the instrument's magnitude. */
  precision: number | null
  crosshairStyle: CrosshairStyle
  crosshairWidth: number
  gradient: boolean
  gradientTo: string
  /** 24-hour axis labels, or 12-hour with AM/PM. */
  clock24: boolean
  /** Weekday in the time-axis labels. */
  weekday: boolean
  /** Logarithmic price axis. */
  logScale: boolean
  /** Countdown to the forming candle's close, under the last price. */
  countdown: boolean
}

export const DESK_SETTINGS_KEY = 'mtl.desk.settings.v1'

export const DEFAULT_SETTINGS: DeskSettings = {
  bull: '#22c55e',
  bear: '#ef4444',
  precision: null,
  crosshairStyle: 'dashed',
  crosshairWidth: 1,
  gradient: false,
  gradientTo: '#0b1220',
  clock24: true,
  weekday: false,
  logScale: false,
  countdown: false,
}

const CROSSHAIR_STYLES: CrosshairStyle[] = ['solid', 'dashed', 'dotted']

function colour(value: unknown, fallback: string): string {
  return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value) ? value : fallback
}

/** Stored settings, with every field validated so a hand-edited value can't paint. */
export function loadSettings(): DeskSettings {
  if (typeof window === 'undefined') return DEFAULT_SETTINGS
  try {
    const raw = window.localStorage.getItem(DESK_SETTINGS_KEY)
    if (!raw) return DEFAULT_SETTINGS
    const parsed: unknown = JSON.parse(raw)
    if (!parsed || typeof parsed !== 'object') return DEFAULT_SETTINGS
    const value = parsed as Record<string, unknown>
    return {
      bull: colour(value.bull, DEFAULT_SETTINGS.bull),
      bear: colour(value.bear, DEFAULT_SETTINGS.bear),
      precision:
        typeof value.precision === 'number' &&
        Number.isInteger(value.precision) &&
        value.precision >= 0 &&
        value.precision <= 8
          ? value.precision
          : null,
      crosshairStyle: CROSSHAIR_STYLES.includes(value.crosshairStyle as CrosshairStyle)
        ? (value.crosshairStyle as CrosshairStyle)
        : DEFAULT_SETTINGS.crosshairStyle,
      crosshairWidth:
        typeof value.crosshairWidth === 'number' && value.crosshairWidth >= 1 && value.crosshairWidth <= 4
          ? value.crosshairWidth
          : DEFAULT_SETTINGS.crosshairWidth,
      gradient: value.gradient === true,
      gradientTo: colour(value.gradientTo, DEFAULT_SETTINGS.gradientTo),
      clock24: value.clock24 !== false,
      weekday: value.weekday === true,
      logScale: value.logScale === true,
      countdown: value.countdown === true,
    }
  } catch {
    return DEFAULT_SETTINGS
  }
}

export function saveSettings(settings: DeskSettings): void {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(DESK_SETTINGS_KEY, JSON.stringify(settings))
  } catch {
    // Preferences are a convenience; failing to store them is not an error.
  }
}

export interface ChartLayout {
  id: string
  name: string
  symbol: string
  interval: string
  settings: DeskSettings
  savedAt: number
}

export const CHART_LAYOUTS_KEY = 'mtl.desk.layouts.v1'

export function loadLayouts(): ChartLayout[] {
  if (typeof window === 'undefined') return []
  try {
    const raw = window.localStorage.getItem(CHART_LAYOUTS_KEY)
    if (!raw) return []
    const parsed: unknown = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    const layouts: ChartLayout[] = []
    for (const entry of parsed) {
      if (!entry || typeof entry !== 'object') continue
      const value = entry as Record<string, unknown>
      if (typeof value.id !== 'string' || typeof value.name !== 'string') continue
      layouts.push({
        id: value.id,
        name: value.name,
        symbol: typeof value.symbol === 'string' ? value.symbol : 'EUR_USD',
        interval: typeof value.interval === 'string' ? value.interval : '1h',
        settings: normaliseSettings(value.settings),
        savedAt: typeof value.savedAt === 'number' ? value.savedAt : 0,
      })
    }
    // Newest first, the way a list of saves is read.
    return layouts.sort((a, b) => b.savedAt - a.savedAt)
  } catch {
    return []
  }
}

/** A layout's settings get the same validation as a stored preference. */
function normaliseSettings(value: unknown): DeskSettings {
  if (!value || typeof value !== 'object') return DEFAULT_SETTINGS
  return {
    ...DEFAULT_SETTINGS,
    ...loadSettingsFromRecord(value as Record<string, unknown>),
  }
}

function loadSettingsFromRecord(
  value: Record<string, unknown>
): Partial<DeskSettings> {
  const settings: Partial<DeskSettings> = {}
  if (typeof value.bull === 'string' && /^#[0-9a-f]{6}$/i.test(value.bull)) settings.bull = value.bull
  if (typeof value.bear === 'string' && /^#[0-9a-f]{6}$/i.test(value.bear)) settings.bear = value.bear
  if (typeof value.precision === 'number' && value.precision >= 0 && value.precision <= 8) {
    settings.precision = Math.round(value.precision)
  }
  if (CROSSHAIR_STYLES.includes(value.crosshairStyle as CrosshairStyle)) {
    settings.crosshairStyle = value.crosshairStyle as CrosshairStyle
  }
  if (typeof value.crosshairWidth === 'number' && value.crosshairWidth >= 1 && value.crosshairWidth <= 4) {
    settings.crosshairWidth = value.crosshairWidth
  }
  if (typeof value.gradient === 'boolean') settings.gradient = value.gradient
  if (typeof value.gradientTo === 'string' && /^#[0-9a-f]{6}$/i.test(value.gradientTo)) {
    settings.gradientTo = value.gradientTo
  }
  if (typeof value.clock24 === 'boolean') settings.clock24 = value.clock24
  if (typeof value.weekday === 'boolean') settings.weekday = value.weekday
  if (typeof value.logScale === 'boolean') settings.logScale = value.logScale
  if (typeof value.countdown === 'boolean') settings.countdown = value.countdown
  return settings
}

export function saveLayouts(layouts: ChartLayout[]): void {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(CHART_LAYOUTS_KEY, JSON.stringify(layouts))
  } catch {
    // Same as settings: losing a layout is not worth breaking a chart over.
  }
}

/** Saves a layout, replacing one with the same name rather than piling up copies. */
export function upsertLayout(layouts: ChartLayout[], layout: ChartLayout): ChartLayout[] {
  const without = layouts.filter((entry) => entry.name.toLowerCase() !== layout.name.toLowerCase())
  const next = [layout, ...without]
  saveLayouts(next)
  return next
}

export function removeLayout(layouts: ChartLayout[], id: string): ChartLayout[] {
  const next = layouts.filter((entry) => entry.id !== id)
  saveLayouts(next)
  return next
}

/**
 * A named set of canvas settings, the phone's `ChartPreset`.
 *
 * A template sits between the defaults and a layout: it carries the paint only —
 * colours, scales, crosshair, background, countdown — and no instrument or
 * interval, so "MTL" can be stamped onto whichever chart is open. That is the
 * whole value of one: a look worth keeping should not drag the market with it.
 */
export interface ChartTemplate {
  name: string
  settings: DeskSettings
}

export const CHART_TEMPLATES_KEY = 'mtl.desk.templates.v1'

/** Enough for a handful of house looks; a longer list is one nobody reads. */
export const MAX_TEMPLATES = 20

/** Matches the phone's name field, so a template renamed on either desk fits. */
export const MAX_TEMPLATE_NAME = 30

function cleanName(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const name = value.trim().slice(0, MAX_TEMPLATE_NAME).trim()
  return name.length > 0 ? name : null
}

export function loadTemplates(): ChartTemplate[] {
  if (typeof window === 'undefined') return []
  try {
    const raw = window.localStorage.getItem(CHART_TEMPLATES_KEY)
    if (!raw) return []
    const parsed: unknown = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    const templates: ChartTemplate[] = []
    for (const entry of parsed) {
      if (!entry || typeof entry !== 'object') continue
      const value = entry as Record<string, unknown>
      const name = cleanName(value.name)
      if (!name) continue
      templates.push({ name, settings: normaliseSettings(value.settings) })
      if (templates.length >= MAX_TEMPLATES) break
    }
    return templates
  } catch {
    return []
  }
}

export function saveTemplates(templates: ChartTemplate[]): void {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(
      CHART_TEMPLATES_KEY,
      JSON.stringify(templates.slice(0, MAX_TEMPLATES))
    )
  } catch {
    // A template that can't be stored is still applied to the open chart.
  }
}

/** Saves under a name, replacing one that reads the same instead of duplicating. */
export function upsertTemplate(
  templates: ChartTemplate[],
  template: ChartTemplate
): ChartTemplate[] {
  // Cleaned here rather than only on load, so the list the dialog shows is the
  // list that will come back on the next visit.
  const name = cleanName(template.name)
  if (!name) return templates
  const saved: ChartTemplate = { name, settings: template.settings }
  const without = templates.filter(
    (entry) => entry.name.toLowerCase() !== name.toLowerCase()
  )
  const next = [saved, ...without].slice(0, MAX_TEMPLATES)
  saveTemplates(next)
  return next
}

export function removeTemplate(templates: ChartTemplate[], name: string): ChartTemplate[] {
  const next = templates.filter((entry) => entry.name !== name)
  saveTemplates(next)
  return next
}
