'use client'

import { brokerInitials, brokerMarkColor } from '@/lib/broker-mark'

/**
 * The square monogram shown next to a broker in the picker. Decorative: the
 * broker's name is the label, so the mark is hidden from screen readers.
 */
export default function BrokerMark({
  name,
  size = 24,
}: {
  name: string
  size?: number
}) {
  return (
    <span
      aria-hidden="true"
      className="flex flex-shrink-0 items-center justify-center rounded-md font-semibold text-white"
      style={{
        width: size,
        height: size,
        backgroundColor: brokerMarkColor(name),
        fontSize: Math.round(size * 0.42),
      }}
    >
      {brokerInitials(name)}
    </span>
  )
}
