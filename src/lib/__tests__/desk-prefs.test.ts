// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest'

import {
  DESK_PREFS_KEY,
  loadDeskPrefs,
  saveDeskPrefs,
} from '@/lib/desk-prefs'

describe('desk preferences', () => {
  beforeEach(() => window.localStorage.clear())

  it('remembers the workspace between visits', () => {
    saveDeskPrefs({
      symbol: 'XAU_USD',
      interval: '15m',
      activeAlertsOnly: true,
      vwap: false,
      sessions: true,
    })
    expect(loadDeskPrefs()).toEqual({
      symbol: 'XAU_USD',
      interval: '15m',
      activeAlertsOnly: true,
      vwap: false,
      sessions: true,
    })
  })

  it('merges one change instead of overwriting the rest', () => {
    saveDeskPrefs({ symbol: 'EUR_USD', interval: '1h' })
    saveDeskPrefs({ activeAlertsOnly: true })
    expect(loadDeskPrefs()).toEqual({
      symbol: 'EUR_USD',
      interval: '1h',
      activeAlertsOnly: true,
    })
  })

  it('reads a corrupt or foreign value as nothing saved', () => {
    window.localStorage.setItem(DESK_PREFS_KEY, 'not json')
    expect(loadDeskPrefs()).toEqual({})

    window.localStorage.setItem(DESK_PREFS_KEY, '{"symbol":42,"interval":""}')
    expect(loadDeskPrefs()).toEqual({})
  })

  it('drops keys it does not own', () => {
    window.localStorage.setItem(
      DESK_PREFS_KEY,
      JSON.stringify({ symbol: 'US30', theme: 'light' })
    )
    expect(loadDeskPrefs()).toEqual({ symbol: 'US30' })
  })
})
