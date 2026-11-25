'use client'

import { useEffect, useState, useSyncExternalStore } from 'react'
import { usePathname } from 'next/navigation'

import {
  markTranslationReady,
  readLocaleCookie,
  startDomTranslation,
  writeLocaleCookie,
  type WebMessages,
} from '@/lib/i18n/dom-translate'
import { languageFor } from '@/lib/i18n/languages'
import { LanguagePicker } from '@/components/language-picker'

const LEGAL_PATHS = ['/privacy', '/terms', '/refunds', '/delete-account', '/support', '/faq']
const subscribe = () => () => {}

function isLegalPath(pathname: string) {
  return LEGAL_PATHS.some((path) => pathname === path || pathname.startsWith(`${path}/`))
}

/**
 * Loads the selected web pack and applies it to the rendered app. The string
 * catalog is source-derived, so screens keep their normal React code and the
 * layer only substitutes the rendered copy.
 */
export function TranslationLayer() {
  const pathname = usePathname()
  const locale = useSyncExternalStore(subscribe, readLocaleCookie, () => 'en')
  const [partial, setPartial] = useState(false)
  const legalNotice = locale !== 'en' && isLegalPath(pathname)

  useEffect(() => {
    // `?lang=fr` makes a translated view shareable and is also the easiest way
    // to verify a pack without a settings screen.
    const params = new URLSearchParams(window.location.search)
    const requested = params.get('lang')
    if (requested && languageFor(requested) && requested !== readLocaleCookie()) {
      writeLocaleCookie(requested)
      params.delete('lang')
      const query = params.toString()
      window.location.replace(
        `${window.location.pathname}${query ? `?${query}` : ''}${window.location.hash}`
      )
      return
    }

    const code = readLocaleCookie()
    if (code === 'en') {
      markTranslationReady()
      return
    }

    const controller = new AbortController()
    let stop: (() => void) | undefined
    let settled = false
    const finish = () => {
      if (settled) return
      settled = true
      markTranslationReady()
    }
    // A missing pack must not leave the page hidden forever.
    const timeout = window.setTimeout(finish, 6000)

    void (async () => {
      try {
        const [response, manifestResponse] = await Promise.all([
          fetch(`/locales/web/${code}.json`, {
            signal: controller.signal,
            cache: 'force-cache',
          }),
          fetch('/locales/web/manifest.json', {
            signal: controller.signal,
            cache: 'force-cache',
          }).catch(() => null),
        ])
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const messages = (await response.json()) as WebMessages
        if (controller.signal.aborted) return
        if (manifestResponse?.ok) {
          const manifest = (await manifestResponse.json()) as {
            packs?: { code: string; complete?: boolean }[]
          }
          const info = manifest.packs?.find((pack) => pack.code === code)
          setPartial(Boolean(info && !info.complete))
        }
        stop = startDomTranslation(messages, code)
      } catch {
        // An unreadable pack keeps the English copy rather than a blank screen.
      } finally {
        window.clearTimeout(timeout)
        finish()
      }
    })()

    return () => {
      controller.abort()
      window.clearTimeout(timeout)
      stop?.()
    }
  }, [])

  const showFloatingPicker = pathname !== '/' && !pathname.startsWith('/dashboard')
  const showLandingMobilePicker = pathname === '/'

  return (
    <>
      {partial && (
        <div className="fixed bottom-16 left-4 right-4 z-[60] rounded-lg border border-warning/40 bg-surface/95 px-3 py-2 text-xs leading-relaxed text-gray-300 shadow-lg backdrop-blur-sm sm:left-auto sm:max-w-sm">
          This language is still being translated. Some text remains in English.
        </div>
      )}
      {legalNotice && (
        <div className={`fixed left-4 right-4 z-[60] rounded-lg border border-warning/40 bg-surface/95 px-3 py-2 text-xs leading-relaxed text-gray-300 shadow-lg backdrop-blur-sm sm:left-auto sm:max-w-sm ${partial ? 'bottom-28' : 'bottom-16'}`}>
          This is a machine translation. The English version is authoritative.
        </div>
      )}
      {showFloatingPicker && (
        <div className="fixed bottom-4 right-4 z-[60]">
          <LanguagePicker />
        </div>
      )}
      {showLandingMobilePicker && (
        <div className="fixed bottom-4 right-4 z-[60] sm:hidden">
          <LanguagePicker />
        </div>
      )}
    </>
  )
}
