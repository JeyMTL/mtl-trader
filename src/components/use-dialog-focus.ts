'use client'

import { useEffect, useRef } from 'react'

import { focusableWithin, nextFocusTarget } from '@/lib/a11y'

/**
 * Makes a dialog behave like one for the keyboard.
 *
 * On open it focuses the first control (or whatever carries `data-autofocus`:
 * the name field in a save dialog, rather than its Cancel button). Tab and
 * Shift+Tab cycle inside the dialog instead of walking into the page behind it,
 * Escape closes it, and on close focus returns to whatever opened it — so the
 * next Tab continues from the button the trader pressed, not from the top of the
 * document.
 *
 * Returns the ref to attach to the element carrying `role="dialog"`.
 */
export function useDialogFocus<T extends HTMLElement>(onClose: () => void) {
  const ref = useRef<T | null>(null)
  // Kept in a ref so a parent that re-creates its close handler on every render
  // does not tear the trap down and restore focus in the middle of a session.
  const closeRef = useRef(onClose)
  useEffect(() => {
    closeRef.current = onClose
  }, [onClose])

  useEffect(() => {
    const node = ref.current
    if (!node) return
    const previous = document.activeElement as HTMLElement | null

    const preferred = node.querySelector<HTMLElement>('[data-autofocus]')
    const first = preferred ?? focusableWithin(node)[0] ?? node
    // A dialog with no controls still has to hold focus, or the page behind it
    // keeps the keyboard.
    if (first === node) node.tabIndex = -1
    first.focus()

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation()
        closeRef.current()
        return
      }
      if (event.key !== 'Tab') return
      const items = focusableWithin(node)
      const target = nextFocusTarget(
        items,
        document.activeElement as HTMLElement | null,
        event.shiftKey
      )
      if (!target) return
      event.preventDefault()
      target.focus()
    }

    node.addEventListener('keydown', onKeyDown)
    return () => {
      node.removeEventListener('keydown', onKeyDown)
      // The opener can be gone — an object deleted from its own dialog — so the
      // restore is only attempted when it is still on the page.
      if (previous && document.contains(previous)) previous.focus()
    }
  }, [])

  return ref
}
