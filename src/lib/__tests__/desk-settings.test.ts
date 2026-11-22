// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest'

import {
  CHART_LAYOUTS_KEY,
  CHART_TEMPLATES_KEY,
  DEFAULT_SETTINGS,
  DESK_SETTINGS_KEY,
  isLightCanvas,
  MAX_TEMPLATES,
  MAX_TEMPLATE_NAME,
  loadLayouts,
  loadSettings,
  loadTemplates,
  removeLayout,
  removeTemplate,
  mergeTemplates,
  saveSettings,
  templateFromCloud,
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
      background: '#101820',
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
    expect(loaded.background).toBe('#101820')
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

  it('knows when the canvas is light enough to flip its chrome', () => {
    expect(isLightCanvas(DEFAULT_SETTINGS)).toBe(false)
    expect(isLightCanvas({ ...DEFAULT_SETTINGS, background: '#e2e8f0' })).toBe(true)
    // A gradient is judged by both stops, so a light top over a dark bottom
    // still counts as light only when the average is.
    expect(
      isLightCanvas({ ...DEFAULT_SETTINGS, background: '#ffffff', gradient: true, gradientTo: '#000000' })
    ).toBe(false)
    expect(
      isLightCanvas({ ...DEFAULT_SETTINGS, background: '#ffffff', gradient: true, gradientTo: '#e2e8f0' })
    ).toBe(true)
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

  it('reads a phone template through the shared keys', () => {
    const [fromPhone] = mergeTemplates(
      [],
      [
        templateFromCloud({
          name: 'MTL',
          style: {
            background: 0xff0e1016,
            bull: 0xff26a69a,
            bear: 0xfff23645,
            precision: 3,
            crosshairStyle: 'dotted',
            crosshairWidth: 2,
            backgroundTo: 0xff101820,
            hour24: false,
            dayOfWeek: true,
            logScale: true,
            countdown: true,
            // A phone-only setting the desk has no control for.
            studies: ['ema', 'rsi'],
          },
          edited_at: '2026-11-22T18:00:00.000Z',
        })!
      ]
    )
    expect(fromPhone.settings.background).toBe('#0e1016')
    expect(fromPhone.settings.bull).toBe('#26a69a')
    expect(fromPhone.settings.bear).toBe('#f23645')
    expect(fromPhone.settings.precision).toBe(3)
    expect(fromPhone.settings.crosshairStyle).toBe('dotted')
    expect(fromPhone.settings.crosshairWidth).toBe(2)
    expect(fromPhone.settings.gradient).toBe(true)
    expect(fromPhone.settings.gradientTo).toBe('#101820')
    expect(fromPhone.settings.clock24).toBe(false)
    expect(fromPhone.settings.weekday).toBe(true)
    expect(fromPhone.editedAt).toBe(Date.parse('2026-11-22T18:00:00.000Z'))
    // The desk keeps what it cannot draw, so a save here cannot erase it.
    expect(fromPhone.style.studies).toEqual(['ema', 'rsi'])
  })

  it('writes a desk template in the phone’s vocabulary without losing other keys', () => {
    upsertTemplate(
      upsertTemplate([], {
        name: 'MTL',
        settings: { ...DEFAULT_SETTINGS, countdown: true },
        style: { studies: ['ema'], preset: 'ink' },
      }),
      // Saving the same name from the desk keeps the phone-only keys.
      {
        name: 'mtl',
        settings: { ...DEFAULT_SETTINGS, bull: '#4c9aff', gradient: true, gradientTo: '#0b1220' },
      }
    )
    const [saved] = loadTemplates()
    expect(saved.name).toBe('mtl')
    expect(saved.style.studies).toEqual(['ema'])
    expect(saved.style.preset).toBe('ink')
    expect(saved.style.bull).toBe(0xff4c9aff)
    expect(saved.style.backgroundTo).toBe(0xff0b1220)
    expect(saved.settings.bull).toBe('#4c9aff')
  })

  it('merges the account and the browser by name, later edit winning', () => {
    const cloud = [
      templateFromCloud({ name: 'MTL', style: { countdown: true }, edited_at: 2_000 })!,
      templateFromCloud({ name: 'Night', style: { logScale: true }, edited_at: 1_000 })!,
    ]
    const local = [
      // Same name, edited later here: the local look stands.
      { ...templateFromCloud({ name: 'mtl', style: { countdown: false }, edited_at: 3_000 })! },
      // Present only here, so it joins the list.
      { ...templateFromCloud({ name: 'Dawn', style: { weekday: true }, edited_at: 500 })! },
    ]
    const merged = mergeTemplates(local, cloud)
    expect(merged.map((entry) => entry.name)).toEqual(['mtl', 'Night', 'Dawn'])
    expect(merged[0].settings.countdown).toBe(false)
    expect(merged[1].settings.logScale).toBe(true)
    expect(loadTemplates()).toHaveLength(3)

    // The account's copy is newer for that name, so it wins.
    const newerCloud = [templateFromCloud({ name: 'MTL', style: { countdown: true }, edited_at: 9_000 })!]
    const afterPull = mergeTemplates(local, newerCloud)
    expect(afterPull[0].settings.countdown).toBe(true)
  })

  it('reads a template saved by the first version of the feature', () => {
    window.localStorage.setItem(
      CHART_TEMPLATES_KEY,
      JSON.stringify([{ name: 'Old', settings: { ...DEFAULT_SETTINGS, weekday: true } }])
    )
    const [legacy] = loadTemplates()
    expect(legacy.name).toBe('Old')
    expect(legacy.settings.weekday).toBe(true)
    expect(legacy.style.dayOfWeek).toBe(true)
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
