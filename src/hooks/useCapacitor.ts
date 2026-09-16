'use client'

import { useState, useEffect, useCallback } from 'react'
import { isCapacitor } from '@/lib/utils'

interface CapacitorStatus {
  isCapacitor: boolean
  isNative: boolean
  isIOS: boolean
  isAndroid: boolean
  isReady: boolean
}

interface CapacitorPlugins {
  Haptics?: {
    impact: (options: { style: string }) => Promise<void>
    vibrate: (options: { duration: number }) => Promise<void>
  }
  App?: {
    addListener: (event: string, handler: () => void) => { remove: () => void } | null
  }
}

interface CapacitorInstance {
  isNativePlatform?: () => boolean
  getPlatform?: () => string
  isReady?: () => boolean
  Plugins?: CapacitorPlugins
}

function getCapacitor(): CapacitorInstance | null {
  if (typeof window === 'undefined') return null
  return (window as unknown as { Capacitor?: CapacitorInstance }).Capacitor ?? null
}

export function useCapacitor(): CapacitorStatus {
  const [status, setStatus] = useState<CapacitorStatus>({
    isCapacitor: false,
    isNative: false,
    isIOS: false,
    isAndroid: false,
    isReady: false,
  })

  useEffect(() => {
    const checkCapacitor = () => {
      const capacitor = getCapacitor()
      setStatus({
        isCapacitor: !!capacitor,
        isNative: capacitor?.isNativePlatform?.() ?? false,
        isIOS: capacitor?.getPlatform?.() === 'ios',
        isAndroid: capacitor?.getPlatform?.() === 'android',
        isReady: true,
      })
    }

    if (typeof window !== 'undefined') {
      if (isCapacitor()) {
        const capacitor = getCapacitor()
        if (capacitor?.isReady?.()) {
          checkCapacitor()
        } else {
          window.addEventListener('DOMContentLoaded', checkCapacitor)
        }
      } else {
        checkCapacitor()
      }
    }

    return () => {
      if (typeof window !== 'undefined') {
        window.removeEventListener('DOMContentLoaded', checkCapacitor)
      }
    }
  }, [])

  return status
}

// Haptic feedback hook
export function useHaptics() {
  const trigger = useCallback(async (style: 'light' | 'medium' | 'heavy' = 'light') => {
    const capacitor = getCapacitor()
    if (capacitor?.Plugins?.Haptics) {
      try {
        await capacitor.Plugins.Haptics.impact({ style })
      } catch {
        // Haptics not available
      }
    }
  }, [])

  const vibrate = useCallback(async (duration: number = 100) => {
    const capacitor = getCapacitor()
    if (capacitor?.Plugins?.Haptics) {
      try {
        await capacitor.Plugins.Haptics.vibrate({ duration })
      } catch {
        // Fallback to Web Vibration API
        if ('vibrate' in navigator) {
          navigator.vibrate(duration)
        }
      }
    } else if ('vibrate' in navigator) {
      navigator.vibrate(duration)
    }
  }, [])

  return { trigger, vibrate }
}

// Keyboard visibility hook
export function useKeyboard() {
  const [isVisible, setIsVisible] = useState(false)

  useEffect(() => {
    if (typeof window === 'undefined') return

    const handleKeyboardShow = () => setIsVisible(true)
    const handleKeyboardHide = () => setIsVisible(false)

    window.addEventListener('keyboardWillShow', handleKeyboardShow)
    window.addEventListener('keyboardWillHide', handleKeyboardHide)

    return () => {
      window.removeEventListener('keyboardWillShow', handleKeyboardShow)
      window.removeEventListener('keyboardWillHide', handleKeyboardHide)
    }
  }, [])

  return isVisible
}

// App state hook (foreground/background)
export function useAppState() {
  const [isActive, setIsActive] = useState(true)

  useEffect(() => {
    if (typeof window === 'undefined') return

    const handleAppActive = () => setIsActive(true)
    const handleAppInactive = () => setIsActive(false)

    window.addEventListener('appActive', handleAppActive)
    window.addEventListener('appInactive', handleAppInactive)

    // Also handle visibility change for web fallback
    const handleVisibilityChange = () => {
      setIsActive(!document.hidden)
    }
    document.addEventListener('visibilitychange', handleVisibilityChange)

    return () => {
      window.removeEventListener('appActive', handleAppActive)
      window.removeEventListener('appInactive', handleAppInactive)
      document.removeEventListener('visibilitychange', handleVisibilityChange)
    }
  }, [])

  return isActive
}

// Back button hook
export function useBackButton(handler: () => void) {
  useEffect(() => {
    if (typeof window === 'undefined') return

    const capacitor = getCapacitor()
    if (capacitor?.Plugins?.App) {
      const backButtonListener = capacitor.Plugins.App.addListener(
        'backButton',
        handler
      )

      return () => {
        backButtonListener?.remove()
      }
    }
  }, [handler])
}
