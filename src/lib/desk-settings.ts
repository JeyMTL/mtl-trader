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
  /** What this desk can paint, derived from `style`. */
  settings: DeskSettings
  /**
   * The phone's `ChartStyle.toJson()` object, carried whole.
   *
   * The phone is the older client and the one with the longer settings list, so
   * its keys are the shared vocabulary. Keeping the untouched object means a
   * save made in a browser cannot erase a phone-only setting — a study period,
   * the watermark — that the browser has no control for.
   */
  style: Record<string, unknown>
  /** When the look was last changed, epoch ms. Settles which copy wins. */
  editedAt: number
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

/** The case-insensitive identity of a template, matching the server's `slug`. */
export function templateSlug(name: string): string {
  return name.trim().toLowerCase()
}

/**
 * A phone colour — `Color.toARGB32()`, an unsigned 32-bit int — as `#rrggbb`.
 *
 * Alpha is dropped: a template colour is a fill or a stroke, and every painter
 * on both desks expects an opaque value. Anything that is not a number is
 * ignored rather than guessed at.
 */
function hexFromArgb(value: unknown): string | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null
  const argb = Math.trunc(value) >>> 0
  const rgb = (argb & 0xffffff).toString(16).padStart(6, '0')
  return `#${rgb}`
}

function argbFromHex(hex: string): number {
  return (0xff000000 | parseInt(hex.slice(1), 16)) >>> 0
}

function booleanFrom(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined
}

/**
 * The part of a phone style this desk can paint.
 *
 * Deliberately partial and silent about what it does not know: a template made
 * on the phone carries studies, a chart type and a watermark, none of which have
 * a desk control yet. Mapping only what exists keeps the two sides honest
 * instead of pretending a setting travelled when it did not.
 */
export function settingsFromPhoneStyle(
  style: Record<string, unknown>
): Partial<DeskSettings> {
  const settings: Partial<DeskSettings> = {}
  const bull = hexFromArgb(style.bull)
  if (bull) settings.bull = bull
  const bear = hexFromArgb(style.bear)
  if (bear) settings.bear = bear
  if (
    typeof style.precision === 'number' &&
    Number.isInteger(style.precision) &&
    style.precision >= 0 &&
    style.precision <= 8
  ) {
    settings.precision = style.precision
  }
  if (CROSSHAIR_STYLES.includes(style.crosshairStyle as CrosshairStyle)) {
    settings.crosshairStyle = style.crosshairStyle as CrosshairStyle
  }
  if (
    typeof style.crosshairWidth === 'number' &&
    style.crosshairWidth >= 1 &&
    style.crosshairWidth <= 4
  ) {
    settings.crosshairWidth = style.crosshairWidth
  }
  // The phone signals "no gradient" by leaving `backgroundTo` out altogether.
  const gradientTo = hexFromArgb(style.backgroundTo)
  settings.gradient = gradientTo !== null
  if (gradientTo) settings.gradientTo = gradientTo
  const clock24 = booleanFrom(style.hour24)
  if (clock24 !== undefined) settings.clock24 = clock24
  const weekday = booleanFrom(style.dayOfWeek)
  if (weekday !== undefined) settings.weekday = weekday
  const logScale = booleanFrom(style.logScale)
  if (logScale !== undefined) settings.logScale = logScale
  const countdown = booleanFrom(style.countdown)
  if (countdown !== undefined) settings.countdown = countdown
  return settings
}

/**
 * This desk's settings as a phone style object, laid over `base` so the keys the
 * desk does not own survive a save.
 */
export function phoneStyleFromSettings(
  settings: DeskSettings,
  base: Record<string, unknown> = {}
): Record<string, unknown> {
  const style: Record<string, unknown> = { ...base }
  style.bull = argbFromHex(settings.bull)
  style.bear = argbFromHex(settings.bear)
  if (settings.precision === null) delete style.precision
  else style.precision = settings.precision
  style.crosshairStyle = settings.crosshairStyle
  style.crosshairWidth = settings.crosshairWidth
  style.hour24 = settings.clock24
  style.dayOfWeek = settings.weekday
  style.logScale = settings.logScale
  style.countdown = settings.countdown
  if (settings.gradient) style.backgroundTo = argbFromHex(settings.gradientTo)
  else delete style.backgroundTo
  return style
}

function templateFromStyle(
  name: string,
  style: Record<string, unknown>,
  editedAt: number
): ChartTemplate {
  return {
    name,
    style,
    editedAt,
    settings: { ...DEFAULT_SETTINGS, ...settingsFromPhoneStyle(style) },
  }
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
      const editedAt = typeof value.editedAt === 'number' ? value.editedAt : 0
      if (value.style && typeof value.style === 'object') {
        templates.push(
          templateFromStyle(name, value.style as Record<string, unknown>, editedAt)
        )
      } else if (value.settings && typeof value.settings === 'object') {
        // A template saved by the first version of this feature, before the
        // phone's vocabulary existed: read it, then store it the shared way.
        templates.push(
          templateFromStyle(
            name,
            phoneStyleFromSettings(normaliseSettings(value.settings)),
            editedAt
          )
        )
      } else {
        // A named entry whose payload is unreadable still has a name the trader
        // typed: keep it as a defaults template rather than silently dropping
        // it.
        templates.push(
          templateFromStyle(name, phoneStyleFromSettings(DEFAULT_SETTINGS), editedAt)
        )
      }
      if (templates.length >= MAX_TEMPLATES) break
    }
    return templates
  } catch {
    return []
  }
}

/** Only the shared parts are written: `settings` is derived, never stored. */
export function saveTemplates(templates: ChartTemplate[]): void {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(
      CHART_TEMPLATES_KEY,
      JSON.stringify(
        templates.slice(0, MAX_TEMPLATES).map((template) => ({
          name: template.name,
          style: template.style,
          editedAt: template.editedAt,
        }))
      )
    )
  } catch {
    // A template that can't be stored is still applied to the open chart.
  }
}

/**
 * Saves under a name, replacing one that reads the same instead of duplicating.
 *
 * `style` may be supplied by the caller (a template downloaded from the
 * account); otherwise it is rebuilt from the settings laid over whatever the
 * replaced template already carried, so phone-only keys are not lost.
 */
export function upsertTemplate(
  templates: ChartTemplate[],
  template: { name: string; settings: DeskSettings; style?: Record<string, unknown> }
): ChartTemplate[] {
  // Cleaned here rather than only on load, so the list the dialog shows is the
  // list that will come back on the next visit.
  const name = cleanName(template.name)
  if (!name) return templates
  const slug = templateSlug(name)
  const existing = templates.find((entry) => templateSlug(entry.name) === slug)
  const style =
    template.style ?? phoneStyleFromSettings(template.settings, existing?.style ?? {})
  const saved = templateFromStyle(name, style, Date.now())
  const without = templates.filter((entry) => templateSlug(entry.name) !== slug)
  const next = [saved, ...without].slice(0, MAX_TEMPLATES)
  saveTemplates(next)
  return next
}

/** A template straight from the account, keeping its edit time for the merge. */
export function templateFromCloud(row: {
  name?: unknown
  style?: unknown
  edited_at?: unknown
  editedAt?: unknown
}): ChartTemplate | null {
  const name = cleanName(row.name)
  if (!name) return null
  const style =
    row.style && typeof row.style === 'object'
      ? (row.style as Record<string, unknown>)
      : {}
  const raw = row.editedAt ?? row.edited_at
  const editedAt =
    typeof raw === 'number'
      ? raw
      : typeof raw === 'string'
        ? Date.parse(raw) || 0
        : 0
  return templateFromStyle(name, style, editedAt)
}

/**
 * Local and account templates as one list: same name, later edit wins.
 *
 * Union rather than replace, because a template lives on whichever desk it was
 * made on until the account has it, and losing the local list to a slow or empty
 * fetch would look like the trader's looks were deleted.
 */
export function mergeTemplates(
  local: ChartTemplate[],
  cloud: ChartTemplate[]
): ChartTemplate[] {
  const merged = new Map<string, ChartTemplate>()
  for (const template of [...cloud, ...local]) {
    const key = templateSlug(template.name)
    const existing = merged.get(key)
    if (!existing) {
      merged.set(key, template)
      continue
    }
    // Local is folded in after the cloud copy, and a tie keeps the local one:
    // a save made here with an unstamped time must not be replaced by an older
    // row that happens to share the stamp.
    if (template.editedAt >= existing.editedAt) merged.set(key, template)
  }
  const next = [...merged.values()]
    .sort((a, b) => b.editedAt - a.editedAt)
    .slice(0, MAX_TEMPLATES)
  saveTemplates(next)
  return next
}

export function removeTemplate(templates: ChartTemplate[], name: string): ChartTemplate[] {
  const slug = templateSlug(name)
  const next = templates.filter((entry) => templateSlug(entry.name) !== slug)
  saveTemplates(next)
  return next
}
