export function Logo({ size = 'md' }: { size?: 'sm' | 'md' | 'lg' }) {
  const sizes = {
    sm: { box: 'w-7 h-7', icon: 16, text: 'text-base' },
    md: { box: 'w-9 h-9', icon: 20, text: 'text-xl' },
    lg: { box: 'w-12 h-12', icon: 28, text: 'text-2xl' },
  }
  const s = sizes[size]

  return (
    <div className="flex items-center gap-2">
      <div className={`${s.box} rounded-lg flex items-center justify-center`}>
        <svg width={s.icon} height={s.icon} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect width="28" height="28" rx="6" fill="#3B82F6"/>
          <path d="M7 20L11 12L15 15L21 8" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
          <circle cx="21" cy="8" r="2" fill="#22C55E"/>
          <path d="M18 8H21V11" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </div>
      <span className={`font-bold text-white ${s.text}`}>MTL Trader</span>
    </div>
  )
}
