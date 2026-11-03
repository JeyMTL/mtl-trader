'use client'

import { useEffect, useRef, useSyncExternalStore } from 'react'
import Link from 'next/link'
import { ArrowRight, Check, RefreshCw, Settings, Upload, X } from 'lucide-react'
import { Logo } from '@/components/logo'

const STORAGE_KEY = 'mtl.onboarding.v1'

/**
 * Tiny external store around the "seen" flag.
 *
 * Reading localStorage in a render-time snapshot keeps the server markup and
 * the first client render identical, without a mount-time setState.
 */
let dismissedCache: boolean | null = null
const listeners = new Set<() => void>()

function readDismissed(): boolean {
  if (dismissedCache === null) {
    try {
      dismissedCache = window.localStorage.getItem(STORAGE_KEY) === 'done'
    } catch {
      dismissedCache = false
    }
  }
  return dismissedCache
}

function markSeen() {
  dismissedCache = true
  try {
    window.localStorage.setItem(STORAGE_KEY, 'done')
  } catch {
    // Storage can be unavailable (private mode); the guide is cosmetic.
  }
  listeners.forEach(listener => listener())
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  const onStorage = (event: StorageEvent) => {
    if (event.key !== STORAGE_KEY) return
    dismissedCache = null
    listener()
  }
  window.addEventListener('storage', onStorage)
  return () => {
    listeners.delete(listener)
    window.removeEventListener('storage', onStorage)
  }
}

/**
 * First-run setup guide: a sheet on phones, a centred dialog on desktop.
 * Shown once to accounts with no trades. Once a trade exists the guide marks
 * itself seen — a working journal does not need onboarding.
 */
export function Onboarding({ hasTrades }: { hasTrades: boolean }) {
  const dismissed = useSyncExternalStore(subscribe, readDismissed, () => true)
  const visible = !dismissed && !hasTrades
  const dialogRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (hasTrades && !dismissed) markSeen()
  }, [hasTrades, dismissed])

  // A dialog should hold focus until it closes, and give it back afterwards.
  useEffect(() => {
    if (!visible) return
    const dialog = dialogRef.current
    if (!dialog) return

    const previouslyFocused = document.activeElement as HTMLElement | null
    const focusable = () =>
      Array.from(
        dialog.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input, textarea, select, [tabindex]:not([tabindex="-1"])'
        )
      ).filter(element => element.offsetParent !== null)

    dialog.focus()

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        markSeen()
        return
      }
      if (event.key !== 'Tab') return
      const items = focusable()
      if (items.length === 0) return
      const first = items[0]
      const last = items[items.length - 1]
      if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }

    document.addEventListener('keydown', onKeyDown)
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    return () => {
      document.removeEventListener('keydown', onKeyDown)
      document.body.style.overflow = previousOverflow
      previouslyFocused?.focus?.()
    }
  }, [visible])

  if (!visible) return null

  const steps = [
    {
      title: 'Bring in your history',
      body: 'Import an MT5 or broker export — XML report, CSV or Excel — and every closed trade lands in the journal.',
      icon: Upload,
    },
    {
      title: 'Set your desk defaults',
      body: 'Timezone, currency and notification windows — summaries and reminders are computed in your local day.',
      icon: Settings,
    },
    {
      title: 'Journal the why',
      body: 'Notes and tags are what the AI review reads. A one-line reason per trade eventually becomes an edge report.',
      icon: RefreshCw,
    },
  ]

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center" role="dialog" aria-modal="true" aria-labelledby="onboarding-title">
      <button
        type="button"
        tabIndex={-1}
        aria-label="Close setup guide"
        onClick={markSeen}
        className="absolute inset-0 h-full w-full bg-black/70 backdrop-blur-sm"
      />

      <div
        ref={dialogRef}
        tabIndex={-1}
        className="sheet-in mobile-sheet relative z-10 w-full max-w-lg rounded-t-3xl border border-border bg-surface p-5 shadow-2xl outline-none sm:rounded-2xl sm:p-7"
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <Logo size="sm" />
            <p className="eyebrow mt-5">Getting started</p>
            <h2 id="onboarding-title" className="mt-1.5 text-xl font-semibold tracking-tight text-white">
              Set the desk up once.
            </h2>
            <p className="mt-1 text-sm text-gray-400">
              Three steps and the journal runs itself from here.
            </p>
          </div>
          <button
            onClick={markSeen}
            aria-label="Close"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-border text-gray-400 active:opacity-60"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <ol className="mt-5 space-y-0 overflow-hidden rounded-xl border border-border">
          {steps.map((step, index) => (
            <li key={step.title} className={index > 0 ? 'flex gap-3 border-t border-border p-3.5' : 'flex gap-3 p-3.5'}>
              <span className="num mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-primary/40 bg-primary/10 text-[11px] font-semibold text-primary">
                {index + 1}
              </span>
              <div className="min-w-0">
                <p className="text-sm font-medium text-white">{step.title}</p>
                <p className="mt-0.5 text-xs leading-relaxed text-gray-500">{step.body}</p>
              </div>
            </li>
          ))}
        </ol>

        <div className="mt-5 flex flex-col gap-2 sm:flex-row">
          <Link href="/dashboard/import" onClick={markSeen} className="btn btn-primary flex-1">
            Import trades
            <ArrowRight className="h-4 w-4" />
          </Link>
          <Link href="/dashboard/trades/new" onClick={markSeen} className="btn btn-secondary flex-1">
            Add one manually
          </Link>
        </div>

        <button
          type="button"
          onClick={markSeen}
          className="mt-3 flex w-full items-center justify-center gap-1.5 py-2 text-xs font-medium text-gray-500 active:opacity-60"
        >
          <Check className="h-3.5 w-3.5" />
          I&apos;ll explore first
        </button>
      </div>
    </div>
  )
}
