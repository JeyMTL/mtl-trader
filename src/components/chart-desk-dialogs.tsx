'use client'

import { useMemo, useState } from 'react'
import {
  BellRing,
  CandlestickChart,
  LayoutTemplate,
  Play,
  Plus,
  Save,
  Search,
  Settings2,
  Trash2,
  X,
} from 'lucide-react'

import type { ChartLayout } from '@/lib/desk-settings'
import { useDialogFocus } from '@/components/use-dialog-focus'

/**
 * The desk's layouts library and analysis hub: the two surfaces the phone has
 * had for a while and the web desk did not. They are deliberately small — a list
 * you can search and reopen, and a hub that says what the desk can do — because a
 * second full-sized app inside a page is how a chart stops being a chart.
 */

export function ChartLayoutsDialog({
  layouts,
  currentSymbol,
  currentInterval,
  onOpen,
  onSave,
  onDelete,
  onClose,
}: {
  layouts: ChartLayout[]
  currentSymbol: string
  currentInterval: string
  onOpen: (layout: ChartLayout) => void
  onSave: (name: string) => void
  onDelete: (id: string) => void
  onClose: () => void
}) {
  const dialogRef = useDialogFocus<HTMLDivElement>(onClose)
  const [query, setQuery] = useState('')
  const [name, setName] = useState('')
  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase()
    if (!needle) return layouts
    return layouts.filter(
      (layout) =>
        layout.name.toLowerCase().includes(needle) ||
        layout.symbol.toLowerCase().includes(needle)
    )
  }, [layouts, query])

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-3"
      role="presentation"
      onClick={onClose}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label="Layouts"
        className="flex max-h-[85vh] w-full max-w-md flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-border px-3 py-2">
          <h2 className="flex-1 text-sm font-bold text-white">Layouts</h2>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="grid h-11 w-11 place-items-center rounded-md text-gray-400 hover:bg-surface-light hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="px-3 py-2">
          <label className="flex items-center gap-2 rounded-lg border border-border bg-surface-light px-2 py-1.5">
            <Search className="h-3.5 w-3.5 text-gray-500" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search layouts"
              aria-label="Search layouts"
              className="min-h-11 w-full bg-transparent text-xs text-white outline-none placeholder:text-gray-500"
            />
          </label>
        </div>

        <div className="flex-1 overflow-y-auto px-3">
          <p className="pb-1 text-[10px] font-bold uppercase tracking-wider text-gray-500">
            Layout name
          </p>
          {visible.length === 0 && (
            <p className="py-4 text-center text-[11px] text-gray-500">
              {layouts.length === 0
                ? 'No saved layouts yet. Save this chart to start one.'
                : 'Nothing matches that search.'}
            </p>
          )}
          <ul>
            {visible.map((layout) => (
              <li key={layout.id} className="flex items-center gap-2 border-b border-border/60 last:border-b-0">
                <button
                  type="button"
                  onClick={() => onOpen(layout)}
                  className="min-h-11 min-w-0 flex-1 py-2 text-left"
                >
                  <span className="block truncate text-xs font-semibold text-white">{layout.name}</span>
                  <span className="block text-[10px] text-gray-500">
                    {layout.symbol}, {layout.interval} (
                    {new Date(layout.savedAt).toLocaleString(undefined, {
                      day: '2-digit',
                      month: 'short',
                      year: 'numeric',
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                    )
                  </span>
                </button>
                <button
                  type="button"
                  aria-label={`Delete ${layout.name}`}
                  onClick={() => onDelete(layout.id)}
                  className="grid h-11 w-11 place-items-center rounded-md text-gray-500 hover:bg-surface-light hover:text-danger"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div className="border-t border-border px-3 py-2">
          <div className="flex items-center gap-2">
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={`Layout name (${currentSymbol}, ${currentInterval})`}
              aria-label="New layout name"
              className="min-h-11 min-w-0 flex-1 rounded-lg border border-border bg-surface-light px-2 py-1.5 text-xs text-white outline-none placeholder:text-gray-500"
            />
            <button
              type="button"
              onClick={() => {
                const trimmed = name.trim()
                if (!trimmed) return
                onSave(trimmed)
                setName('')
              }}
              className="min-h-11 shrink-0 rounded-lg bg-primary px-4 text-xs font-bold text-black"
            >
              Save
            </button>
          </div>
          <p className="mt-1 text-[10px] text-gray-500">
            A layout stores this browser&apos;s colours, scales and interval for the
            instrument it was saved on. Levels stay where they live — on the
            account, per symbol.
          </p>
        </div>
      </div>
    </div>
  )
}

export function AnalysisHubDialog({
  activeLayoutName,
  onOpenLayouts,
  onOpenSettings,
  onSaveLayout,
  onNewLayout,
  onToggleReplay,
  replaying,
  objectCount,
  alertCount,
  onClose,
}: {
  activeLayoutName: string | null
  onOpenLayouts: () => void
  onOpenSettings: () => void
  onSaveLayout: () => void
  onNewLayout: () => void
  onToggleReplay: () => void
  replaying: boolean
  objectCount: number
  alertCount: number
  onClose: () => void
}) {
  const dialogRef = useDialogFocus<HTMLDivElement>(onClose)
  const cards = [
    {
      label: 'Layouts',
      hint: activeLayoutName ? `Active: ${activeLayoutName}` : 'None saved',
      icon: LayoutTemplate,
      onClick: onOpenLayouts,
    },
    { label: 'Chart settings', hint: 'Bars, scales, canvas', icon: Settings2, onClick: onOpenSettings },
    { label: 'Save layout', hint: 'Keep this workspace', icon: Save, onClick: onSaveLayout },
    { label: 'New layout', hint: 'Back to the defaults', icon: Plus, onClick: onNewLayout },
    {
      label: replaying ? 'Stop replay' : 'Bar replay',
      hint: 'Walk the bars forward',
      icon: Play,
      onClick: onToggleReplay,
    },
    {
      label: 'Alert lines',
      hint: alertCount === 0 ? 'None on this chart' : `${alertCount} on this chart`,
      icon: BellRing,
      onClick: onOpenSettings,
    },
  ]

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-3"
      role="presentation"
      onClick={onClose}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label="Analysis hub"
        className="w-full max-w-lg rounded-2xl border border-border bg-surface p-3 shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-2 flex items-center gap-2">
          <CandlestickChart className="h-4 w-4 text-primary" />
          <h2 className="flex-1 text-sm font-bold text-white">Analysis hub</h2>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="grid h-11 w-11 place-items-center rounded-md text-gray-400 hover:bg-surface-light hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {cards.map((card) => (
            <button
              key={card.label}
              type="button"
              onClick={card.onClick}
              className="min-h-11 rounded-xl border border-border bg-surface-light/40 p-2 text-left hover:border-primary/50"
            >
              <card.icon className="mb-1 h-4 w-4 text-primary" />
              <span className="block text-[11px] font-bold text-white">{card.label}</span>
              <span className="block text-[10px] leading-tight text-gray-500">{card.hint}</span>
            </button>
          ))}
        </div>

        <p className="mt-2 text-[10px] leading-relaxed text-gray-500">
          {objectCount === 0
            ? 'No objects on this chart yet: pick a tool above the canvas and tap the price you mean.'
            : `${objectCount} object${objectCount === 1 ? '' : 's'} on this instrument, saved to your account and visible on the phone.`}
        </p>
      </div>
    </div>
  )
}
