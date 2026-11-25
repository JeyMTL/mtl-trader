// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'

import { startDomTranslation } from '@/lib/i18n/dom-translate'

afterEach(() => {
  document.body.innerHTML = ''
  document.documentElement.lang = 'en'
  document.documentElement.dir = 'ltr'
})

describe('startDomTranslation', () => {
  it('translates text and text attributes', () => {
    document.body.innerHTML = `
      <h1>Settings</h1>
      <p>  Save  </p>
      <input placeholder="Search symbol" aria-label="Search" />
    `
    const stop = startDomTranslation(
      {
        Settings: 'Paramètres',
        Save: 'Enregistrer',
        'Search symbol': 'Rechercher un symbole',
        Search: 'Rechercher',
      },
      'fr'
    )
    stop()

    expect(document.querySelector('h1')?.textContent).toBe('Paramètres')
    expect(document.querySelector('p')?.textContent).toBe('  Enregistrer  ')
    expect(document.querySelector('input')?.getAttribute('placeholder')).toBe(
      'Rechercher un symbole'
    )
    expect(document.querySelector('input')?.getAttribute('aria-label')).toBe('Rechercher')
    expect(document.documentElement.lang).toBe('fr')
  })

  it('does not translate code, user content or marked regions', () => {
    document.body.innerHTML = `
      <code>Save</code>
      <textarea>Save</textarea>
      <div data-no-translate>Save</div>
      <p contenteditable="true">Save</p>
    `
    const stop = startDomTranslation({ Save: 'Enregistrer' }, 'fr')
    stop()

    expect(document.querySelector('code')?.textContent).toBe('Save')
    expect(document.querySelector('textarea')?.textContent).toBe('Save')
    expect(document.querySelector('[data-no-translate]')?.textContent).toBe('Save')
    expect(document.querySelector('[contenteditable]')?.textContent).toBe('Save')
  })

  it('sets RTL direction for an RTL locale', () => {
    document.body.textContent = 'Settings'
    const stop = startDomTranslation({ Settings: 'الإعدادات' }, 'ar')
    stop()
    expect(document.documentElement.dir).toBe('rtl')
  })
})
