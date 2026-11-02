'use client'

import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { Search } from 'lucide-react'
import {
  searchMt5Brokers,
  serverGroups,
  type Mt5Broker,
} from '@/lib/mt5-brokers'
import BrokerMark from '@/components/broker-mark'

/**
 * Broker field with the MT5 directory behind it.
 *
 * Typing filters the directory in place — no request, the list is small — and
 * the field still accepts anything the customer types, because a broker that is
 * missing from the directory is still a valid MT5 broker. Picking an entry is a
 * shortcut, not a requirement.
 */

interface BrokerPickerProps {
  value: string
  onChange: (value: string) => void
  onSelect?: (broker: Mt5Broker) => void
  label?: string
  placeholder?: string
  autoComplete?: string
}

export default function BrokerPicker({
  value,
  onChange,
  onSelect,
  label = 'Broker',
  placeholder = 'Search e.g. IC Markets, Exness, XM',
  autoComplete = 'organization',
}: BrokerPickerProps) {
  const listId = useId()
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const matches = useMemo(() => searchMt5Brokers(value, 40), [value])

  useEffect(
    () => () => {
      if (closeTimer.current) clearTimeout(closeTimer.current)
    },
    []
  )

  const choose = (broker: Mt5Broker) => {
    onChange(broker.name)
    onSelect?.(broker)
    setActive(0)
    setOpen(false)
  }

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Escape') {
      setOpen(false)
      return
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      if (!open) {
        setOpen(true)
        return
      }
      setActive((current) => {
        const next = event.key === 'ArrowDown' ? current + 1 : current - 1
        return Math.min(Math.max(next, 0), Math.max(matches.length - 1, 0))
      })
      return
    }
    if (event.key === 'Enter' && open && matches[active]) {
      event.preventDefault()
      choose(matches[active])
    }
  }

  return (
    <div>
      <label className="block text-sm font-medium text-gray-400 mb-2" htmlFor={`${listId}-input`}>
        {label}
      </label>
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
        <input
          id={`${listId}-input`}
          type="text"
          role="combobox"
          aria-expanded={open}
          aria-controls={listId}
          aria-autocomplete="list"
          aria-activedescendant={open && matches[active] ? `${listId}-${active}` : undefined}
          value={value}
          onChange={(event) => {
            onChange(event.target.value)
            setActive(0)
            setOpen(true)
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => {
            closeTimer.current = setTimeout(() => setOpen(false), 120)
          }}
          onKeyDown={onKeyDown}
          placeholder={placeholder}
          autoComplete={autoComplete}
          className="w-full bg-background border border-border rounded-lg pl-9 pr-4 py-2.5 text-white placeholder-gray-500 focus:outline-none focus:border-primary"
        />

        {open && (
          <ul
            id={listId}
            role="listbox"
            className="absolute z-30 mt-1 max-h-72 w-full overflow-y-auto rounded-lg border border-border bg-surface shadow-2xl"
          >
            {matches.length === 0 && (
              <li className="px-4 py-3 text-xs text-gray-500">
                No broker matches “{value}”. MT5 brokers missing from this list are
                still accepted — type the name exactly as MT5 shows it.
              </li>
            )}
            {matches.map((broker, index) => (
              <li key={broker.name} id={`${listId}-${index}`} role="option" aria-selected={index === active}>
                <button
                  type="button"
                  onMouseDown={(event) => event.preventDefault()}
                  onMouseEnter={() => setActive(index)}
                  onClick={() => choose(broker)}
                  className={`flex w-full items-center justify-between gap-3 px-4 py-2 text-left text-sm transition-colors ${
                    index === active ? 'bg-surface-light text-white' : 'text-gray-300'
                  }`}
                >
                  <span className="flex min-w-0 items-center gap-2">
                    <BrokerMark name={broker.name} />
                    <span className="truncate">{broker.name}</span>
                  </span>
                  {broker.servers[0] && (
                    <span className="flex-shrink-0 text-xs text-gray-500">{broker.servers[0]}</span>
                  )}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

/**
 * One-tap servers for the chosen broker, narrowed by what is already typed in
 * the server field and split into demo and live.
 *
 * The split is the point: a customer testing the app needs the demo server, and
 * a single alphabetical row of `ICMarketsSC-Live01…Live12` buries it. Renders
 * nothing for a broker we have no servers for, and never restricts what can be
 * typed.
 */
export function ServerSuggestions({
  broker,
  query,
  onPick,
}: {
  broker: string
  query?: string
  onPick: (server: string) => void
}) {
  const groups = useMemo(() => serverGroups(broker, query ?? ''), [broker, query])
  const rows: { label: string; servers: string[] }[] = [
    { label: 'Demo', servers: groups.demo },
    { label: 'Live', servers: groups.live },
  ]

  if (groups.demo.length === 0 && groups.live.length === 0) return null

  return (
    <div className="mt-2 space-y-1.5">
      {rows.map(({ label, servers }) =>
        servers.length === 0 ? null : (
          <div key={label} className="flex flex-wrap items-center gap-1.5">
            <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-500">
              {label}
            </span>
            {servers.map((server) => (
              <button
                key={server}
                type="button"
                onClick={() => onPick(server)}
                className="rounded-md border border-border bg-surface-light px-2 py-1 text-xs text-gray-300 hover:border-primary/50 hover:text-white transition-colors"
              >
                {server}
              </button>
            ))}
          </div>
        )
      )}
    </div>
  )
}
