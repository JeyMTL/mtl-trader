/**
 * Keyboard helpers shared by the desk's dialogs.
 *
 * A modal that is only modal for the mouse is not a modal: the page behind it
 * stays in the tab order and a keyboard user ends up typing into the dashboard
 * while a settings sheet is open on top of it. These are the two pieces every
 * dialog needs — the list of things that can hold focus, and where Tab goes
 * next — kept pure so they can be tested without a browser.
 */

export const FOCUSABLE_SELECTOR = [
  'a[href]',
  'area[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'iframe',
  'audio[controls]',
  'video[controls]',
  '[contenteditable="true"]',
  '[tabindex]:not([tabindex="-1"])',
].join(',')

/** Everything inside `root` that can take focus, in document order. */
export function focusableWithin(root: ParentNode): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
    (element) =>
      !element.hasAttribute('disabled') &&
      element.getAttribute('aria-hidden') !== 'true' &&
      // `[hidden]` and a hidden ancestor both remove a control from the tab
      // order. Deliberately not `offsetParent`: a control inside a `position:
      // fixed` dialog legitimately reports no offset parent in some browsers.
      !element.closest('[hidden]')
  )
}

/**
 * The element Tab (or Shift+Tab) should land on.
 *
 * Wraps at both ends, which is what makes the dialog a loop instead of a trap
 * the keyboard can walk out of. `current` may be outside the list — a click on
 * the dialog's own padding, say — and then focus heads to the nearer end.
 */
export function nextFocusTarget(
  items: HTMLElement[],
  current: HTMLElement | null,
  shift: boolean
): HTMLElement | null {
  if (items.length === 0) return null
  const index = current ? items.indexOf(current) : -1
  if (index === -1) return shift ? items[items.length - 1] : items[0]
  const next = shift ? index - 1 : index + 1
  if (next < 0) return items[items.length - 1]
  if (next >= items.length) return items[0]
  return items[next]
}
