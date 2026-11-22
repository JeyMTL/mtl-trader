'use client'

import { useState } from 'react'
import { ArrowLeft, X } from 'lucide-react'

import { useDialogFocus } from '@/components/use-dialog-focus'
import {
  DEFAULT_SETTINGS,
  MAX_TEMPLATE_NAME,
  type ChartTemplate,
  type CrosshairStyle,
  type DeskSettings,
} from '@/lib/desk-settings'

/**
 * The desk's chart settings, as a dialog with the same sections the phone's
 * Settings sheet uses: Symbol, Scales and lines, Canvas, Alerts.
 *
 * Every control here changes something the canvas actually paints. The phone
 * gained a settings page at a time and it is easy to add a switch that reads
 * well and does nothing; a dialog is only worth having if the paint obeys it.
 */

const SECTIONS = [
  { id: 'symbol', label: 'Symbol', hint: 'Bars and decimals' },
  { id: 'scales', label: 'Scales and lines', hint: 'Axis and clock' },
  { id: 'canvas', label: 'Canvas', hint: 'Background and crosshair' },
  { id: 'alerts', label: 'Alerts', hint: 'Lines that fire' },
] as const

type SectionId = (typeof SECTIONS)[number]['id']

const CROSSHAIR_STYLES: { id: CrosshairStyle; label: string }[] = [
  { id: 'solid', label: 'Solid' },
  { id: 'dashed', label: 'Dashed' },
  { id: 'dotted', label: 'Dotted' },
]

const SWATCHES = ['#22c55e', '#26a69a', '#4c9aff', '#f0b90b', '#ef4444', '#f23645', '#ab7df6', '#e2e8f0']

function Row({
  label,
  hint,
  children,
}: {
  label: string
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-border/60 py-2.5 last:border-b-0">
      <div className="min-w-0">
        <p className="text-xs font-semibold text-white">{label}</p>
        {hint && <p className="mt-0.5 text-[11px] leading-snug text-gray-500">{hint}</p>}
      </div>
      <div className="flex shrink-0 items-center gap-2">{children}</div>
    </div>
  )
}

function Toggle({
  checked,
  onChange,
  label,
}: {
  checked: boolean
  onChange: (next: boolean) => void
  label: string
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className="grid h-11 w-11 place-items-center"
    >
      {/* The switch is 36×20, but the thing you press is 44×44: a toggle you
          can see and miss is not a control. */}
      <span
        className={`relative block h-5 w-9 rounded-full border transition ${
          checked ? 'border-primary bg-primary/40' : 'border-border bg-surface-light'
        }`}
      >
        <span
          className={`absolute top-0.5 h-3.5 w-3.5 rounded-full bg-white transition-all ${
            checked ? 'left-[18px]' : 'left-0.5'
          }`}
        />
      </span>
    </button>
  )
}

export function ChartSettingsDialog({
  settings,
  onChange,
  onClose,
  activeAlertsOnly,
  onActiveAlertsOnly,
  templates,
  onSaveTemplate,
  onDeleteTemplate,
}: {
  settings: DeskSettings
  onChange: (next: DeskSettings) => void
  onClose: () => void
  activeAlertsOnly: boolean
  onActiveAlertsOnly: (next: boolean) => void
  templates: ChartTemplate[]
  onSaveTemplate: (name: string) => void
  onDeleteTemplate: (name: string) => void
}) {
  const dialogRef = useDialogFocus<HTMLDivElement>(onClose)
  const [section, setSection] = useState<SectionId | null>(null)
  const [templatesOpen, setTemplatesOpen] = useState(false)
  const [templateName, setTemplateName] = useState('')
  const patch = (next: Partial<DeskSettings>) => onChange({ ...settings, ...next })

  /** Applies a template and returns to the section list, the way the phone does. */
  const applyTemplate = (template: ChartTemplate) => {
    onChange({ ...template.settings })
    setTemplatesOpen(false)
  }

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
        aria-label="Chart settings"
        className="flex max-h-[85vh] w-full max-w-md flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-border px-3 py-2">
          {(section || templatesOpen) && (
            <button
              type="button"
              aria-label="Back"
              onClick={() => {
                setSection(null)
                setTemplatesOpen(false)
              }}
              className="grid h-11 w-11 place-items-center rounded-md text-gray-400 hover:bg-surface-light hover:text-white"
            >
              <ArrowLeft className="h-4 w-4" />
            </button>
          )}
          <h2 className="flex-1 text-sm font-bold text-white">
            {templatesOpen
              ? 'Templates'
              : section
                ? SECTIONS.find((item) => item.id === section)?.label
                : 'Chart settings'}
          </h2>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="grid h-11 w-11 place-items-center rounded-md text-gray-400 hover:bg-surface-light hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-3 py-1">
          {templatesOpen && (
            <div className="py-1">
              <button
                type="button"
                onClick={() => {
                  onChange({ ...DEFAULT_SETTINGS })
                  setTemplatesOpen(false)
                }}
                className="flex min-h-11 w-full items-center justify-between rounded-lg px-2 py-2.5 text-left hover:bg-surface-light"
              >
                <span>
                  <span className="block text-xs font-semibold text-white">Apply defaults</span>
                  <span className="block text-[11px] text-gray-500">
                    Back to the desk&apos;s own palette
                  </span>
                </span>
              </button>

              <div className="mt-1 flex items-center gap-2 border-y border-border/60 py-2">
                <input
                  value={templateName}
                  onChange={(event) => setTemplateName(event.target.value)}
                  placeholder="Template name"
                  aria-label="Template name"
                  maxLength={MAX_TEMPLATE_NAME}
                  onKeyDown={(event) => {
                    if (event.key !== 'Enter') return
                    const name = templateName.trim()
                    if (!name) return
                    onSaveTemplate(name)
                    setTemplateName('')
                  }}
                  className="min-h-11 min-w-0 flex-1 rounded-lg border border-border bg-surface-light px-2 py-1.5 text-xs text-white outline-none placeholder:text-gray-500"
                />
                <button
                  type="button"
                  disabled={templateName.trim().length === 0}
                  onClick={() => {
                    const name = templateName.trim()
                    if (!name) return
                    onSaveTemplate(name)
                    setTemplateName('')
                  }}
                  className="min-h-11 shrink-0 rounded-lg bg-primary px-4 text-xs font-bold text-black disabled:opacity-40"
                >
                  Save
                </button>
              </div>
              <p className="py-1 text-[10px] leading-relaxed text-gray-500">
                A template keeps this chart&apos;s colours, scales and crosshair, not
                the instrument. Saved in this browser, like layouts.
              </p>

              {templates.length === 0 ? (
                <p className="py-3 text-center text-[11px] text-gray-500">
                  No templates yet. Name one above to keep the look you are using.
                </p>
              ) : (
                <ul>
                  {templates.map((template) => (
                    <li
                      key={template.name}
                      className="flex items-center gap-2 border-b border-border/60 last:border-b-0"
                    >
                      <button
                        type="button"
                        onClick={() => applyTemplate(template)}
                        className="flex min-h-11 min-w-0 flex-1 items-center gap-2 py-2 text-left"
                      >
                        <span className="flex shrink-0" aria-hidden>
                          <span
                            className="h-3 w-1.5 rounded-l-sm"
                            style={{ background: template.settings.bull }}
                          />
                          <span
                            className="h-3 w-1.5 rounded-r-sm"
                            style={{ background: template.settings.bear }}
                          />
                        </span>
                        <span className="min-w-0">
                          <span className="block truncate text-xs font-semibold text-white">
                            {template.name}
                          </span>
                          <span className="block text-[10px] text-gray-500">
                            {template.settings.logScale ? 'Log' : 'Linear'}
                            {' · '}
                            {template.settings.gradient ? 'Gradient' : 'Flat'}
                            {' · '}
                            {template.settings.precision === null
                              ? 'Auto dp'
                              : `${template.settings.precision} dp`}
                            {' · '}
                            {template.settings.crosshairStyle} crosshair
                          </span>
                        </span>
                      </button>
                      <button
                        type="button"
                        aria-label={`Delete template ${template.name}`}
                        onClick={() => onDeleteTemplate(template.name)}
                        className="min-h-11 shrink-0 rounded-md border border-border px-3 text-[10px] font-semibold text-gray-400 hover:border-danger/50 hover:text-danger"
                      >
                        Delete
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}

          {!templatesOpen && !section && (
            <ul className="py-1">
              {SECTIONS.map((item) => (
                <li key={item.id}>
                  <button
                    type="button"
                    onClick={() => setSection(item.id)}
                    className="flex min-h-11 w-full items-center justify-between rounded-lg px-2 py-2.5 text-left hover:bg-surface-light"
                  >
                    <span>
                      <span className="block text-xs font-semibold text-white">{item.label}</span>
                      <span className="block text-[11px] text-gray-500">{item.hint}</span>
                    </span>
                    <span className="text-[11px] text-gray-500">
                      {item.id === 'symbol' && (settings.precision === null ? 'Auto' : `${settings.precision} dp`)}
                      {item.id === 'scales' && (settings.logScale ? 'Log' : 'Linear')}
                      {item.id === 'canvas' && (settings.gradient ? 'Gradient' : 'Flat')}
                      {item.id === 'alerts' && `${activeAlertsOnly ? 'Active only' : 'All lines'}`}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          {section === 'symbol' && (
            <div className="py-1">
              <Row label="Up bars" hint="Candles that close above the previous one.">
                <input
                  type="color"
                  aria-label="Up bar colour"
                  value={settings.bull}
                  onChange={(event) => patch({ bull: event.target.value })}
                  className="h-11 w-14 cursor-pointer rounded border border-border bg-transparent"
                />
              </Row>
              <Row label="Down bars">
                <input
                  type="color"
                  aria-label="Down bar colour"
                  value={settings.bear}
                  onChange={(event) => patch({ bear: event.target.value })}
                  className="h-11 w-14 cursor-pointer rounded border border-border bg-transparent"
                />
              </Row>
              <div className="flex flex-wrap gap-1 py-2">
                {SWATCHES.map((colour) => (
                  <button
                    key={`up-${colour}`}
                    type="button"
                    aria-label={`Set up bars to ${colour}`}
                    onClick={() => patch({ bull: colour })}
                    className="grid h-11 w-11 place-items-center rounded-full border border-white/20"
                  >
                    <span
                      aria-hidden
                      className="h-6 w-6 rounded-full"
                      style={{ background: colour }}
                    />
                  </button>
                ))}
              </div>
              <Row
                label="Precision"
                hint="Decimals on every price. Auto follows the instrument's magnitude."
              >
                <select
                  aria-label="Price precision"
                  value={settings.precision ?? 'auto'}
                  onChange={(event) =>
                    patch({
                      precision: event.target.value === 'auto' ? null : Number(event.target.value),
                    })
                  }
                  className="min-h-11 rounded-md border border-border bg-surface-light px-2 py-1 text-[11px] text-white"
                >
                  <option value="auto">Auto</option>
                  {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((places) => (
                    <option key={places} value={places}>
                      {places}
                    </option>
                  ))}
                </select>
              </Row>
            </div>
          )}

          {section === 'scales' && (
            <div className="py-1">
              <Row label="Logarithmic axis" hint="Equal percentage moves take equal room.">
                <Toggle
                  label="Logarithmic axis"
                  checked={settings.logScale}
                  onChange={(logScale) => patch({ logScale })}
                />
              </Row>
              <Row label="24-hour clock" hint="Off prints 11:50 PM instead of 23:50.">
                <Toggle
                  label="24-hour clock"
                  checked={settings.clock24}
                  onChange={(clock24) => patch({ clock24 })}
                />
              </Row>
              <Row label="Day of week on labels">
                <Toggle
                  label="Day of week on labels"
                  checked={settings.weekday}
                  onChange={(weekday) => patch({ weekday })}
                />
              </Row>
              <Row label="Countdown to bar close" hint="Under the last price.">
                <Toggle
                  label="Countdown to bar close"
                  checked={settings.countdown}
                  onChange={(countdown) => patch({ countdown })}
                />
              </Row>
            </div>
          )}

          {section === 'canvas' && (
            <div className="py-1">
              <Row
                label="Background"
                hint="Behind the candles, and the top of the gradient when it is on."
              >
                <input
                  type="color"
                  aria-label="Chart background colour"
                  value={settings.background}
                  onChange={(event) => patch({ background: event.target.value })}
                  className="h-11 w-14 cursor-pointer rounded border border-border bg-transparent"
                />
              </Row>
              <div className="flex flex-wrap gap-1 py-2">
                {SWATCHES.map((colour) => (
                  <button
                    key={`bg-${colour}`}
                    type="button"
                    aria-label={`Set background to ${colour}`}
                    aria-pressed={settings.background.toLowerCase() === colour}
                    onClick={() => patch({ background: colour })}
                    className={`grid h-11 w-11 place-items-center rounded-full border ${
                      settings.background.toLowerCase() === colour ? 'border-white' : 'border-white/20'
                    }`}
                  >
                    <span
                      aria-hidden
                      className="h-6 w-6 rounded-full"
                      style={{ background: colour }}
                    />
                  </button>
                ))}
              </div>
              <Row label="Gradient background">
                <Toggle
                  label="Gradient background"
                  checked={settings.gradient}
                  onChange={(gradient) => patch({ gradient })}
                />
              </Row>
              {settings.gradient && (
                <Row label="Bottom colour" hint="The gradient runs from the background to this.">
                  <input
                    type="color"
                    aria-label="Gradient bottom colour"
                    value={settings.gradientTo}
                    onChange={(event) => patch({ gradientTo: event.target.value })}
                    className="h-11 w-14 cursor-pointer rounded border border-border bg-transparent"
                  />
                </Row>
              )}
              <Row label="Crosshair style">
                <div className="flex gap-1">
                  {CROSSHAIR_STYLES.map((option) => (
                    <button
                      key={option.id}
                      type="button"
                      aria-pressed={settings.crosshairStyle === option.id}
                      onClick={() => patch({ crosshairStyle: option.id })}
                      className={`min-h-11 rounded-md border px-3 text-[11px] font-semibold ${
                        settings.crosshairStyle === option.id
                          ? 'border-primary bg-primary/15 text-primary'
                          : 'border-border bg-surface-light text-gray-400'
                      }`}
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
              </Row>
              <Row label="Crosshair thickness">
                <div className="flex gap-1">
                  {[1, 2, 3, 4].map((width) => (
                    <button
                      key={width}
                      type="button"
                      aria-pressed={settings.crosshairWidth === width}
                      onClick={() => patch({ crosshairWidth: width })}
                      className={`min-h-11 min-w-11 rounded-md border px-2 text-[11px] font-semibold ${
                        settings.crosshairWidth === width
                          ? 'border-primary bg-primary/15 text-primary'
                          : 'border-border bg-surface-light text-gray-400'
                      }`}
                    >
                      {width}
                    </button>
                  ))}
                </div>
              </Row>
            </div>
          )}

          {section === 'alerts' && (
            <div className="py-1">
              <Row
                label="Only active alerts"
                hint="Lines that have already fired are kept but taken off the chart."
              >
                <Toggle
                  label="Only active alerts"
                  checked={activeAlertsOnly}
                  onChange={onActiveAlertsOnly}
                />
              </Row>
              <p className="py-2 text-[11px] leading-relaxed text-gray-500">
                Alert colours come from the level&apos;s own colour: the Alert tool
                paints one above the market in the up colour and one below in the
                down colour.
              </p>
            </div>
          )}
        </div>

        <div className="flex items-center justify-between border-t border-border px-3 py-2">
          <div className="flex items-center gap-3">
            {!templatesOpen && (
              <button
                type="button"
                onClick={() => {
                  setSection(null)
                  setTemplatesOpen(true)
                }}
                className="min-h-11 px-1 text-[11px] font-semibold text-gray-400 hover:text-white"
              >
                Templates
              </button>
            )}
            <button
              type="button"
              onClick={() => onChange({ ...DEFAULT_SETTINGS })}
              className="min-h-11 px-1 text-[11px] font-semibold text-gray-400 hover:text-white"
            >
              Reset
            </button>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="min-h-11 rounded-lg bg-primary px-4 text-xs font-bold text-black"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  )
}
