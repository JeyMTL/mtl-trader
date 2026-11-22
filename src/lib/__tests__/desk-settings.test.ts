// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest'

import {
  CHART_LAYOUTS_KEY,
  CHART_TEMPLATES_KEY,
  DEFAULT_SETTINGS,
  DESK_SETTINGS_KEY,
  MAX_TEMPLATES,
  MAX_TEMPLATE_NAME,
  loadLayouts,
  loadSettings,
  loadTemplates,
  removeLayout,
  removeTemplate,
  saveSettings,
  upsertLayout,
  upsertTemplate,
  type ChartLayout,
  type ChartTemplate,
} from '@/lib/desk-settings'

function layout(overrides: Partial<ChartLayout> = {}): ChartLayout {
  return {
    id: 'l1',
    name: 'JeyMTL',
    symbol: 'EUR_USD',
    interval: '15m',
    settings: { ...DEFAULT_SETTINGS, bull: '#26a69a' },
    savedAt: 1_763_000_000_000,
    ...overrides,
  }
}

describe('desk settings', () => {
  beforeEach(() => window.localStorage.clear())

  it('starts from defaults and round-trips what the trader chose', () => {
    expect(loadSettings()).toEqual(DEFAULT_SETTINGS)

    saveSettings({
      ...DEFAULT_SETTINGS,
      bear: '#f23645',
      precision: 3,
      crosshairStyle: 'dotted',
      crosshairWidth: 2,
      gradient: true,
      clock24: false,
      weekday: true,
      logScale: true,
      countdown: true,
    })
    const loaded = loadSettings()
    expect(loaded.bear).toBe('#f23645')
    expect(loaded.precision).toBe(3)
    expect(loaded.crosshairStyle).toBe('dotted')
    expect(loaded.crosshairWidth).toBe(2)
    expect(loaded.gradient).toBe(true)
    expect(loaded.clock24).toBe(false)
    expect(loaded.weekday).toBe(true)
    expect(loaded.logScale).toBe(true)
    expect(loaded.countdown).toBe(true)
  })

  it('refuses values that would paint something unreadable', () => {
    window.localStorage.setItem(
      DESK_SETTINGS_KEY,
      JSON.stringify({
        bull: 'red',
        precision: 40,
        crosshairStyle: 'wavy',
        crosshairWidth: 90,
        gradientTo: 'nope',
      })
    )
    const loaded = loadSettings()
    expect(loaded.bull).toBe(DEFAULT_SETTINGS.bull)
    expect(loaded.precision).toBeNull()
    expect(loaded.crosshairStyle).toBe(DEFAULT_SETTINGS.crosshairStyle)
    expect(loaded.crosshairWidth).toBe(1)
    expect(loaded.gradientTo).toBe(DEFAULT_SETTINGS.gradientTo)
  })

  it('reads a corrupt settings blob as defaults', () => {
    window.localStorage.setItem(DESK_SETTINGS_KEY, '{')
    expect(loadSettings()).toEqual(DEFAULT_SETTINGS)
  })
})

describe('chart layouts', () => {
  beforeEach(() => window.localStorage.clear())

  it('saves, lists newest first, and drops a layout', () => {
    let layouts = upsertLayout([], layout({ id: 'a', name: 'first', savedAt: 1 }))
    layouts = upsertLayout(layouts, layout({ id: 'b', name: 'second', savedAt: 2 }))

    expect(loadLayouts().map((entry) => entry.name)).toEqual(['second', 'first'])

    layouts = removeLayout(layouts, 'b')
    expect(loadLayouts().map((entry) => entry.name)).toEqual(['first'])
  })

  it('saving the same name replaces it instead of piling up copies', () => {
    let layouts = upsertLayout([], layout({ id: 'a', symbol: 'EUR_USD' }))
    layouts = upsertLayout([], layout({ id: 'b', symbol: 'XAU_USD' }))
    // Same name, so the second save overwrites the first.
    layouts = upsertLayout(layouts, layout({ id: 'b', symbol: 'XAU_USD' }))
    expect(layouts).toHaveLength(1)
    expect(layouts[0].symbol).toBe('XAU_USD')
  })

  it('keeps the settings a layout was saved with', () => {
    upsertLayout([], layout({ settings: { ...DEFAULT_SETTINGS, bear: '#f23645', logScale: true } }))
    const [saved] = loadLayouts()
    expect(saved.settings.bear).toBe('#f23645')
    expect(saved.settings.logScale).toBe(true)
  })

  it('survives a corrupt library', () => {
    window.localStorage.setItem(CHART_LAYOUTS_KEY, 'not json')
    expect(loadLayouts()).toEqual([])
    window.localStorage.setItem(CHART_LAYOUTS_KEY, '[{"nope":1},{"id":"a","name":"ok"}]')
    expect(loadLayouts().map((entry) => entry.name)).toEqual(['ok'])
  })

  it('keeps a template as paint only, with the name it was given', () => {
    expect(loadTemplates()).toEqual([])
    upsertTemplate([], { name: ' MTL ', settings: { ...DEFAULT_SETTINGS, bull: '#26a69a', logScale: true } })

    const [saved] = loadTemplates()
    expect(saved.name).toBe('MTL')
    expect(saved.settings.bull).toBe('#26a69a')
    expect(saved.settings.logScale).toBe(true)
    // No instrument or interval on a template: it is stamped onto the open chart.
    expect(saved).not.toHaveProperty('symbol')
    expect(saved).not.toHaveProperty('interval')
  })

  it('replaces a template saved under the same name, ignoring case', () => {
    let templates = upsertTemplate([], { name: 'MTL', settings: { ...DEFAULT_SETTINGS, bear: '#f23645' } })
    templates = upsertTemplate(templates, { name: 'mtl', settings: { ...DEFAULT_SETTINGS, bear: '#ef4444' } })
    expect(templates).toHaveLength(1)
    expect(templates[0].name).toBe('mtl')
    expect(loadTemplates()[0].settings.bear).toBe('#ef4444')

    templates = removeTemplate(templates, 'mtl')
    expect(loadTemplates()).toEqual([])
  })

  it('caps the template list and trims absurd names', () => {
    let templates: ChartTemplate[] = []
    for (let index = 0; index < MAX_TEMPLATES + 5; index += 1) {
      templates = upsertTemplate(templates, { name: `t${index}`, settings: DEFAULT_SETTINGS })
    }
    expect(templates).toHaveLength(MAX_TEMPLATES)
    expect(loadTemplates()).toHaveLength(MAX_TEMPLATES)

    const long = `  ${'x'.repeat(MAX_TEMPLATE_NAME + 10)}  `
    const [saved] = upsertTemplate([], { name: long, settings: DEFAULT_SETTINGS })
    expect(saved.name).toHaveLength(MAX_TEMPLATE_NAME)
  })

  it('drops template entries that are not templates', () => {
    window.localStorage.setItem(CHART_TEMPLATES_KEY, 'not json')
    expect(loadTemplates()).toEqual([])
    window.localStorage.setItem(
      CHART_TEMPLATES_KEY,
      JSON.stringify([{ name: '   ' }, { name: 'ok', settings: 'nope' }])
    )
    const [only] = loadTemplates()
    expect(only.name).toBe('ok')
    // A broken settings payload falls back to the defaults rather than throwing.
    expect(only.settings).toEqual(DEFAULT_SETTINGS)
  })
})
