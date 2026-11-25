import languages from './languages.json'

export interface WebLanguage {
  code: string
  nativeName: string
  englishName: string
  rtl: boolean
}

export const WEB_LANGUAGES = languages as WebLanguage[]
export const DEFAULT_LOCALE = 'en'
export const LOCALE_COOKIE = 'mtl_locale'

export function languageFor(code: string | null | undefined): WebLanguage | null {
  if (!code) return null
  return WEB_LANGUAGES.find((language) => language.code === code) ?? null
}

export function isTranslatedLocale(code: string | null | undefined): boolean {
  return Boolean(code && code !== DEFAULT_LOCALE && languageFor(code))
}
