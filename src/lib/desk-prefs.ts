/**
 * The desk's own choices, remembered between visits.
 *
 * A chart is a workspace: the instrument you were reading, the candle size, and
 * whether you had alerts filtered are part of where you left off. Re-picking all
 * of it on every reload is the "drag" part of using the web version, so these
 * survive in localStorage — viewer state, not account data, which is why it never
 * needs to leave this browser.
 */

export interface DeskPrefs {
  symbol?: string
  interval?: string
  activeAlertsOnly?: boolean
  vwap?: boolean
  sessions?: boolean
}

export const DESK_PREFS_KEY = 'mtl.desk.v1'

/** Saved preferences, or an empty object when there are none to trust. */
export function loadDeskPrefs(): DeskPrefs {
  if (typeof window === 'undefined') return {}
  try {
    const raw = window.localStorage.getItem(DESK_PREFS_KEY)
    if (!raw) return {}
    const parsed: unknown = JSON.parse(raw)
    if (!parsed || typeof parsed !== 'object') return {}
    const value = parsed as Record<string, unknown>
    const prefs: DeskPrefs = {}
    if (typeof value.symbol === 'string' && value.symbol) prefs.symbol = value.symbol
    if (typeof value.interval === 'string' && value.interval) prefs.interval = value.interval
    if (typeof value.activeAlertsOnly === 'boolean') prefs.activeAlertsOnly = value.activeAlertsOnly
    if (typeof value.vwap === 'boolean') prefs.vwap = value.vwap
    if (typeof value.sessions === 'boolean') prefs.sessions = value.sessions
    return prefs
  } catch {
    // Private mode, a full quota or a corrupt value all read as "nothing saved".
    return {}
  }
}

/** Merges one change into what is stored, so two effects cannot clobber each other. */
export function saveDeskPrefs(patch: DeskPrefs): void {
  if (typeof window === 'undefined') return
  try {
    const next = { ...loadDeskPrefs(), ...patch }
    window.localStorage.setItem(DESK_PREFS_KEY, JSON.stringify(next))
  } catch {
    // Remembering the workspace is a convenience; failing to is not an error.
  }
}
