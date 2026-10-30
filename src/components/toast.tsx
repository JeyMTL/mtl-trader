'use client'

import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react'
import { AlertTriangle, CheckCircle2, Info, X } from 'lucide-react'

type ToastTone = 'success' | 'error' | 'info'

interface ToastItem {
  id: number
  message: string
  tone: ToastTone
}

interface ToastApi {
  toast: (message: string, options?: { tone?: ToastTone }) => void
}

const ToastContext = createContext<ToastApi>({ toast: () => {} })

export function useToast() {
  return useContext(ToastContext)
}

const ICONS = {
  success: CheckCircle2,
  error: AlertTriangle,
  info: Info,
} as const

/**
 * In-app notifications.
 *
 * These replace `window.alert`: they do not block the page, keep the product's
 * visual language, stack politely and are announced to screen readers.
 */
export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([])
  const nextId = useRef(1)
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>())

  const dismiss = useCallback((id: number) => {
    const timer = timers.current.get(id)
    if (timer) {
      clearTimeout(timer)
      timers.current.delete(id)
    }
    setToasts(current => current.filter(item => item.id !== id))
  }, [])

  const toast = useCallback((message: string, options: { tone?: ToastTone } = {}) => {
    const id = nextId.current++
    const tone = options.tone ?? 'info'
    setToasts(current => [...current.slice(-2), { id, message, tone }])
    // Errors stay long enough to be read and acted on.
    const timer = setTimeout(() => dismiss(id), tone === 'error' ? 8000 : 5000)
    timers.current.set(id, timer)
  }, [dismiss])

  useEffect(() => {
    const activeTimers = timers.current
    return () => {
      activeTimers.forEach(timer => clearTimeout(timer))
      activeTimers.clear()
    }
  }, [])

  return (
    <ToastContext.Provider value={{ toast }}>
      {children}
      <div className="toast-stack" role="region" aria-label="Notifications" aria-live="polite">
        {toasts.map(item => {
          const Icon = ICONS[item.tone]
          return (
            <div key={item.id} className={`toast toast-${item.tone}`}>
              <Icon className="toast-icon" aria-hidden="true" />
              <p className="toast-message">{item.message}</p>
              <button
                type="button"
                onClick={() => dismiss(item.id)}
                aria-label="Dismiss notification"
                className="toast-close"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          )
        })}
      </div>
    </ToastContext.Provider>
  )
}
