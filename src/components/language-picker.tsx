'use client'

import { useSyncExternalStore } from 'react'
import { Globe } from 'lucide-react'

import { readLocaleCookie, writeLocaleCookie } from '@/lib/i18n/dom-translate'
import { WEB_LANGUAGES, languageFor } from '@/lib/i18n/languages'
import { cn } from '@/lib/utils'

const subscribe = () => () => {}

interface LanguagePickerProps {
  className?: string
}

export function LanguagePicker({ className }: LanguagePickerProps) {
  // A language switch reloads the page, so this store only needs to reflect the
  // cookie after hydration; no in-place subscription is required.
  const locale = useSyncExternalStore(subscribe, readLocaleCookie, () => 'en')

  const current = languageFor(locale)

  const change = (code: string) => {
    writeLocaleCookie(code)
    // Reload so the translation layer applies the new pack before paint.
    window.location.reload()
  }

  return (
    <label
      data-no-translate
      className={cn(
        'inline-flex items-center gap-2 rounded-lg border border-border bg-surface/90 px-2.5 py-1.5 text-xs text-gray-300 shadow-sm backdrop-blur-sm',
        className
      )}
    >
      <Globe className="h-3.5 w-3.5 shrink-0 text-gray-500" aria-hidden="true" />
      <span className="sr-only">Language</span>
      <select
        value={locale}
        onChange={(event) => change(event.target.value)}
        className="max-w-[9.5rem] cursor-pointer bg-transparent pr-1 text-xs text-gray-300 outline-none"
        aria-label="Language"
      >
        {WEB_LANGUAGES.map((language) => (
          <option key={language.code} value={language.code} className="bg-surface text-white">
            {language.nativeName}
          </option>
        ))}
      </select>
      <span className="sr-only">{current?.englishName ?? 'English'}</span>
    </label>
  )
}
