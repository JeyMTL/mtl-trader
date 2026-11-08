'use client'

import { createContext, useContext, useEffect, useState } from 'react'

/**
 * The three appearances. `dark` is the default and matches the icon's black
 * ground; `blue` is the cool alternative — navy surfaces with an ice accent.
 */
export type Theme = 'dark' | 'light' | 'blue'

/** Offered in Settings, in the order they appear there. */
export const THEMES: { id: Theme; label: string }[] = [
  { id: 'dark', label: 'Dark' },
  { id: 'light', label: 'Light' },
  { id: 'blue', label: 'Blue' },
]

/** The saved theme, or the dark default. An unknown stored value — an older
 *  build's collection, or a hand-edited key — falls back rather than leaving
 *  the page unstyled. */
function storedTheme(): Theme {
  if (typeof window === 'undefined') return 'dark'
  try {
    const saved = window.localStorage.getItem('theme')
    return THEMES.some((entry) => entry.id === saved) ? (saved as Theme) : 'dark'
  } catch {
    return 'dark'
  }
}

const ThemeContext = createContext<{
  theme: Theme
  setTheme: (theme: Theme) => void
}>({ theme: 'dark', setTheme: () => {} })

export function useTheme() {
  return useContext(ThemeContext)
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(storedTheme)

  useEffect(() => {
    const root = document.documentElement
    // Both flags are written on every change, so switching out of one theme
    // never leaves its class behind on the root element.
    root.classList.toggle('light', theme === 'light')
    root.classList.toggle('blue', theme === 'blue')
    localStorage.setItem('theme', theme)
  }, [theme])

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}
