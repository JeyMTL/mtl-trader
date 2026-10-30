'use client'

import { useTheme } from '@/lib/theme'

/**
 * Chart tokens shared by every Recharts view.
 *
 * Keeping these in one place is what makes dashboard and analytics look like one
 * instrument: same hairline grid, muted axes, profit/loss pair, tooltip surface.
 * Two palettes because mint-on-white and mint-on-graphite need different values.
 */

export interface ChartPalette {
  profit: string
  loss: string
  brass: string
  axis: string
  grid: string
}

export const DARK_CHART: ChartPalette = {
  profit: '#45d29a',
  loss: '#f26b78',
  brass: '#d5a44e',
  axis: '#6b7280',
  grid: 'rgba(255, 255, 255, 0.07)',
}

export const LIGHT_CHART: ChartPalette = {
  profit: '#0f7a52',
  loss: '#b32634',
  brass: '#8a6520',
  axis: '#6b7280',
  grid: 'rgba(0, 0, 0, 0.08)',
}

export function chartPalette(theme: 'dark' | 'light'): ChartPalette {
  return theme === 'light' ? LIGHT_CHART : DARK_CHART
}

/** Theme-aware palette for chart components. */
export function useChartPalette(): ChartPalette {
  const { theme } = useTheme()
  return chartPalette(theme)
}

export function axisProps(palette: ChartPalette) {
  return {
    stroke: palette.axis,
    tick: { fontSize: 11, fill: palette.axis },
    tickLine: false,
    axisLine: false,
  }
}

export function gridProps(palette: ChartPalette) {
  return {
    stroke: palette.grid,
    vertical: false,
  }
}
