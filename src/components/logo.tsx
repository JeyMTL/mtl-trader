export function Logo({ size = 'md' }: { size?: 'sm' | 'md' | 'lg' }) {
  const sizes = {
    sm: { box: 'w-7 h-7', icon: 16, text: 'text-base' },
    md: { box: 'w-9 h-9', icon: 20, text: 'text-xl' },
    lg: { box: 'w-12 h-12', icon: 28, text: 'text-2xl' },
  }
  const s = sizes[size]

  return (
    <div className="flex items-center gap-2">
      <div className={`${s.box} rounded-[7px] flex items-center justify-center`}>
        <svg width={s.icon} height={s.icon} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect width="28" height="28" rx="7" fill="var(--primary)" />
          {/* Ascending equity line, drawn in ink so it reads on the brass tile */}
          <path
            d="M6.5 19.5L11 13.5L14.5 16.5L21 8.5"
            stroke="var(--ink)"
            strokeWidth="2.1"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <path d="M18.4 8.5H21V11.1" stroke="var(--ink)" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M6.5 22.5H21.5" stroke="var(--ink)" strokeOpacity="0.28" strokeWidth="1" strokeLinecap="round" />
        </svg>
      </div>
      <span className={`font-semibold tracking-tight text-foreground ${s.text}`}>MTL Trader</span>
    </div>
  )
}
