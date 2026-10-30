'use client'

interface TooltipPayloadItem {
  color?: string
  name?: string
  value?: number | string
}

interface ChartTooltipProps {
  active?: boolean
  payload?: TooltipPayloadItem[]
  label?: string | number
  /** Formats numeric values; defaults to a plain number with two decimals. */
  format?: (value: number) => string
}

export function ChartTooltip({ active, payload, label, format }: ChartTooltipProps) {
  if (!active || !payload?.length) return null

  const formatValue = format ?? ((value: number) => value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }))

  return (
    <div className="rounded-lg border border-border bg-surface-strong px-3 py-2 shadow-xl">
      {label !== undefined && (
        <p className="mb-1 text-[10px] font-semibold uppercase tracking-[0.12em] text-gray-500">{String(label)}</p>
      )}
      {payload.map((item, index) => (
        <p key={index} className="num flex items-center gap-2 text-xs text-gray-200">
          <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: item.color }} />
          <span className="text-gray-400">{item.name}</span>
          <span className="ml-auto pl-3 font-semibold text-white">
            {typeof item.value === 'number' ? formatValue(item.value) : item.value}
          </span>
        </p>
      ))}
    </div>
  )
}
