'use client'

import { useState } from 'react'
import { cn } from '@/lib/utils'

export function initialsOf(
  name: string | null | undefined,
  email: string | null | undefined
): string {
  const source = (name || '').trim() || (email || '').trim()
  if (!source) return 'MT'
  const parts = source.split(/[\s@._-]+/).filter(Boolean)
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase()
  return source.slice(0, 2).toUpperCase()
}

/**
 * Profile picture with a fallback ladder: the picture the user chose, then the
 * picture tied to their email address, then their initials.
 *
 * The initials are the normal path, not an error case — most email accounts
 * have no Gravatar — so the fallback is styled rather than hidden behind a
 * broken-image icon.
 */
export function Avatar({
  email,
  name,
  src,
  size = 36,
  className,
}: {
  email?: string | null
  name?: string | null
  src?: string | null
  size?: number
  className?: string
}) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null)
  const initials = initialsOf(name, email)
  const url =
    src ||
    (email
      ? `/api/avatar?email=${encodeURIComponent(email)}&s=${Math.round(size * 2)}`
      : null)
  const showImage = Boolean(url) && failedUrl !== url

  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-surface-light font-semibold uppercase text-gray-300',
        className
      )}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.36) }}
      aria-label={initials}
    >
      {showImage && url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={url}
          alt=""
          width={size}
          height={size}
          className="h-full w-full object-cover"
          onError={() => setFailedUrl(url)}
        />
      ) : (
        initials
      )}
    </span>
  )
}
