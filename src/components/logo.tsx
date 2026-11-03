import Image from 'next/image'

/**
 * The MTL monogram, as generated for the launcher and the store listing by
 * `scripts/make-app-icons.mjs`. Rendering the same file here means the tab
 * icon, the PWA icon and the in-app mark can never drift apart.
 */
export function Logo({ size = 'md' }: { size?: 'sm' | 'md' | 'lg' }) {
  const sizes = {
    sm: { box: 28, text: 'text-base' },
    md: { box: 36, text: 'text-xl' },
    lg: { box: 48, text: 'text-2xl' },
  }
  const s = sizes[size]

  return (
    <div className="flex items-center gap-2">
      <Image
        src="/icon-192.png"
        alt=""
        width={s.box}
        height={s.box}
        className="rounded-[7px] shrink-0"
      />
      <span className={`font-semibold tracking-tight text-foreground ${s.text}`}>MTL Trader</span>
    </div>
  )
}
