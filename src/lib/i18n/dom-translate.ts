import { DEFAULT_LOCALE, LOCALE_COOKIE, languageFor } from './languages'

export type WebMessages = Record<string, string>

const SKIP_SELECTOR =
  'script, style, code, pre, textarea, [contenteditable="true"], [data-no-translate]'

const TEXT_ATTRIBUTES = ['placeholder', 'title', 'aria-label', 'alt'] as const

function normalize(value: string): string {
  return value.replace(/\s+/g, ' ').trim()
}

function hasLetters(value: string): boolean {
  return /[A-Za-z\u00c0-\u024f\u0370-\u03ff\u0400-\u04ff\u0590-\u05ff\u0600-\u06ff\u0900-\u097f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/.test(
    value
  )
}

function translatedValue(value: string, messages: WebMessages): string | null {
  const normalized = normalize(value)
  if (!normalized || !hasLetters(normalized)) return null
  const translated = messages[normalized]
  return translated && translated !== normalized ? translated : null
}

function translateTextNode(node: Text, messages: WebMessages): void {
  const parent = node.parentElement
  if (!parent || parent.closest(SKIP_SELECTOR)) return

  const value = node.nodeValue
  if (!value) return
  const translated = translatedValue(value, messages)
  if (!translated) return

  const leading = value.match(/^\s*/)?.[0] ?? ''
  const trailing = value.match(/\s*$/)?.[0] ?? ''
  node.nodeValue = `${leading}${translated}${trailing}`
}

function translateElementAttributes(element: Element, messages: WebMessages): void {
  if (element.closest(SKIP_SELECTOR)) return
  for (const attribute of TEXT_ATTRIBUTES) {
    const value = element.getAttribute(attribute)
    if (!value) continue
    const translated = translatedValue(value, messages)
    if (translated) element.setAttribute(attribute, translated)
  }
}

export function translateTree(root: ParentNode, messages: WebMessages): void {
  const walker = document.createTreeWalker(root as Node, NodeFilter.SHOW_TEXT)
  let node = walker.nextNode()
  while (node) {
    translateTextNode(node as Text, messages)
    node = walker.nextNode()
  }

  if (root instanceof Element && root.closest(SKIP_SELECTOR)) return
  root.querySelectorAll?.(TEXT_ATTRIBUTES.map((attribute) => `[${attribute}]`).join(','))
    .forEach((element) => translateElementAttributes(element, messages))
}

function translateDocumentChrome(messages: WebMessages): void {
  const title = document.title
  const translatedTitle = translatedValue(title, messages)
  if (translatedTitle) document.title = translatedTitle

  const description = document.querySelector('meta[name="description"]')
  const content = description?.getAttribute('content')
  if (description && content) {
    const translated = translatedValue(content, messages)
    if (translated) description.setAttribute('content', translated)
  }
}

/**
 * Applies a dictionary to text that is already in the DOM and keeps watching
 * for React re-renders and client-side navigation. This is intentionally a
 * compatibility layer: the web app was written in English long before it had a
 * message catalog, so this translates the rendered copy without a risky
 * rewrite of every screen.
 */
export function startDomTranslation(
  messages: WebMessages,
  locale: string
): () => void {
  translateTree(document.body, messages)
  translateDocumentChrome(messages)
  document.documentElement.lang = locale
  document.documentElement.dir = languageFor(locale)?.rtl ? 'rtl' : 'ltr'

  let frame = 0
  const pendingText = new Set<Text>()
  const pendingElements = new Set<Element>()
  const pendingTrees = new Set<Element>()

  const flush = () => {
    frame = 0
    for (const node of pendingText) translateTextNode(node, messages)
    for (const element of pendingElements) translateElementAttributes(element, messages)
    for (const element of pendingTrees) translateTree(element, messages)
    pendingText.clear()
    pendingElements.clear()
    pendingTrees.clear()
    translateDocumentChrome(messages)
  }

  const schedule = () => {
    if (frame) return
    frame = requestAnimationFrame(flush)
  }

  const bodyObserver = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === 'characterData' && mutation.target instanceof Text) {
        pendingText.add(mutation.target)
      } else if (mutation.type === 'attributes' && mutation.target instanceof Element) {
        pendingElements.add(mutation.target)
      } else if (mutation.type === 'childList') {
        mutation.addedNodes.forEach((node) => {
          if (node instanceof Text) pendingText.add(node)
          else if (node instanceof Element) pendingTrees.add(node)
        })
      }
    }
    schedule()
  })

  bodyObserver.observe(document.body, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: [...TEXT_ATTRIBUTES],
  })

  const headObserver = new MutationObserver(schedule)
  headObserver.observe(document.head, {
    subtree: true,
    childList: true,
    characterData: true,
  })

  return () => {
    bodyObserver.disconnect()
    headObserver.disconnect()
    if (frame) cancelAnimationFrame(frame)
  }
}

export function readLocaleCookie(): string {
  if (typeof document === 'undefined') return DEFAULT_LOCALE
  const match = document.cookie.match(
    new RegExp(`(?:^|; )${LOCALE_COOKIE}=([^;]+)`)
  )
  const code = match ? decodeURIComponent(match[1]) : DEFAULT_LOCALE
  return languageFor(code) ? code : DEFAULT_LOCALE
}

export function writeLocaleCookie(code: string): void {
  if (typeof document === 'undefined') return
  document.cookie = `${LOCALE_COOKIE}=${encodeURIComponent(code)}; path=/; max-age=31536000; samesite=lax`
}

export function markTranslationReady(): void {
  document.documentElement.removeAttribute('data-i18n-pending')
  document.documentElement.setAttribute('data-i18n-ready', '1')
}
