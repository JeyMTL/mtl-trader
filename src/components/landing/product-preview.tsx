const candles = [
  { o: 1.0808, h: 1.0819, l: 1.0802, c: 1.0815 },
  { o: 1.0815, h: 1.0823, l: 1.0809, c: 1.0812 },
  { o: 1.0812, h: 1.0827, l: 1.0808, c: 1.0824 },
  { o: 1.0824, h: 1.0833, l: 1.0818, c: 1.0830 },
  { o: 1.0830, h: 1.0836, l: 1.0821, c: 1.0825 },
  { o: 1.0825, h: 1.0841, l: 1.0822, c: 1.0838 },
  { o: 1.0838, h: 1.0848, l: 1.0831, c: 1.0844 },
  { o: 1.0844, h: 1.0850, l: 1.0835, c: 1.0839 },
  { o: 1.0839, h: 1.0851, l: 1.0836, c: 1.0848 },
  { o: 1.0848, h: 1.0859, l: 1.0842, c: 1.0855 },
  { o: 1.0855, h: 1.0862, l: 1.0847, c: 1.0849 },
  { o: 1.0849, h: 1.0853, l: 1.0839, c: 1.0841 },
  { o: 1.0841, h: 1.0846, l: 1.0829, c: 1.0833 },
  { o: 1.0833, h: 1.0842, l: 1.0828, c: 1.0839 },
  { o: 1.0839, h: 1.0845, l: 1.0826, c: 1.0828 },
  { o: 1.0828, h: 1.0834, l: 1.0817, c: 1.0820 },
  { o: 1.0820, h: 1.0825, l: 1.0809, c: 1.0813 },
  { o: 1.0813, h: 1.0827, l: 1.0810, c: 1.0822 },
  { o: 1.0822, h: 1.0835, l: 1.0818, c: 1.0830 },
  { o: 1.0830, h: 1.0843, l: 1.0825, c: 1.0838 },
  { o: 1.0838, h: 1.0850, l: 1.0832, c: 1.0846 },
  { o: 1.0846, h: 1.0855, l: 1.0840, c: 1.0851 },
  { o: 1.0851, h: 1.0857, l: 1.0842, c: 1.0844 },
  { o: 1.0844, h: 1.0849, l: 1.0833, c: 1.0836 },
  { o: 1.0836, h: 1.0847, l: 1.0831, c: 1.0842 },
  { o: 1.0842, h: 1.0852, l: 1.0837, c: 1.0848 },
]

const MIN = 1.0792
const MAX = 1.087
const TOP = 30
const HEIGHT = 228
const X0 = 38
const STEP = 25

function yFor(price: number) {
  return TOP + ((MAX - price) / (MAX - MIN)) * HEIGHT
}

function vwapPoints() {
  let sum = 0
  return candles
    .map((candle, index) => {
      sum += candle.c
      const x = X0 + index * STEP
      return `${x},${yFor(sum / (index + 1))}`
    })
    .join(' ')
}

const equityPath =
  'M0 42 L18 39 L36 41 L54 34 L72 36 L90 29 L108 31 L126 24 L144 27 L162 20 L180 22 L198 14 L216 16 L234 9 L252 11 L270 5'

const calendarDays = [
  null, null, 2, -1, 4, 0, 3, 5, -2, 1, 0, 4, -3, 2, 6, 1, -1, 3, 5, -2, 2, 4, 0, 3, -3, 5, 2, null,
]

export function ProductPreview() {
  return (
    <div className="mx-auto max-w-6xl px-4">
      <div className="rounded-2xl border border-border bg-surface/80 p-2 shadow-2xl shadow-black/40">
        <div className="overflow-hidden rounded-xl border border-border/70 bg-background">
          <div className="flex items-center justify-between border-b border-border px-4 py-2.5">
            <div className="flex items-center gap-1.5" aria-hidden="true">
              <span className="h-2.5 w-2.5 rounded-full bg-danger/70" />
              <span className="h-2.5 w-2.5 rounded-full bg-warning/70" />
              <span className="h-2.5 w-2.5 rounded-full bg-success/70" />
            </div>
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <span className="font-medium text-white">EURUSD</span>
              <span className="rounded border border-border px-1.5 py-0.5 text-[10px]">15m</span>
              <span className="hidden text-success sm:inline">+0.42%</span>
            </div>
            <div className="hidden items-center gap-3 text-[11px] text-gray-500 sm:flex">
              <span className="text-white">Market</span>
              <span>Journal</span>
              <span>Analytics</span>
            </div>
          </div>

          <div className="grid lg:grid-cols-[1fr_250px]">
            <div className="border-b border-border p-3 sm:p-4 lg:border-b-0 lg:border-r">
              <div className="mb-2 flex items-center justify-between text-[10px] text-gray-500">
                <span>Live market chart · EURUSD</span>
                <span className="hidden sm:inline">Journal synced</span>
              </div>
              <svg
                viewBox="0 0 760 300"
                className="h-auto w-full"
                role="img"
                aria-label="Illustrative market chart with price levels and candles"
              >
                <rect x={X0} y={TOP} width={224 - X0} height={HEIGHT} className="fill-sky-400/5" />
                <rect x={224} y={TOP} width={464 - 224} height={HEIGHT} className="fill-primary/5" />
                <rect x={464} y={TOP} width={680 - 464} height={HEIGHT} className="fill-violet-400/5" />

                <text x={X0 + 6} y={20} className="fill-sky-300/60 text-[9px]">ASIA</text>
                <text x={232} y={20} className="fill-primary-light/70 text-[9px]">LONDON</text>
                <text x={472} y={20} className="fill-violet-300/60 text-[9px]">NEW YORK</text>

                {[0.25, 0.5, 0.75].map((share) => (
                  <line
                    key={share}
                    x1={X0}
                    x2={680}
                    y1={TOP + HEIGHT * share}
                    y2={TOP + HEIGHT * share}
                    className="stroke-border"
                    strokeWidth="1"
                  />
                ))}

                <line
                  x1={X0}
                  x2={680}
                  y1={yFor(1.086)}
                  y2={yFor(1.086)}
                  className="stroke-sky-400/70"
                  strokeDasharray="5 5"
                />
                <rect x={688} y={yFor(1.086) - 9} width={62} height={18} rx={4} className="fill-sky-400/15" />
                <text x={695} y={yFor(1.086) + 3} className="fill-sky-200 text-[9px]">1.08600</text>

                <line
                  x1={X0}
                  x2={680}
                  y1={yFor(1.0812)}
                  y2={yFor(1.0812)}
                  className="stroke-amber-400/70"
                  strokeDasharray="5 5"
                />
                <rect x={688} y={yFor(1.0812) - 9} width={62} height={18} rx={4} className="fill-amber-400/15" />
                <text x={695} y={yFor(1.0812) + 3} className="fill-amber-200 text-[9px]">1.08120</text>

                {candles.map((candle, index) => {
                  const x = X0 + index * STEP
                  const up = candle.c >= candle.o
                  const bodyTop = yFor(Math.max(candle.o, candle.c))
                  const bodyHeight = Math.max(1.5, Math.abs(yFor(candle.o) - yFor(candle.c)))
                  return (
                    <g key={index}>
                      <line
                        x1={x}
                        x2={x}
                        y1={yFor(candle.h)}
                        y2={yFor(candle.l)}
                        className={up ? 'stroke-emerald-400' : 'stroke-rose-400'}
                        strokeWidth="1"
                      />
                      <rect
                        x={x - 3.5}
                        y={bodyTop}
                        width="7"
                        height={bodyHeight}
                        rx="1"
                        className={up ? 'fill-emerald-400' : 'fill-rose-400'}
                      />
                    </g>
                  )
                })}

                <polyline
                  points={vwapPoints()}
                  fill="none"
                  className="stroke-amber-300/80"
                  strokeWidth="1.5"
                  strokeDasharray="3 3"
                />

                <line
                  x1={X0 + 21 * STEP}
                  x2={X0 + 21 * STEP}
                  y1={TOP}
                  y2={TOP + HEIGHT}
                  className="stroke-gray-500/50"
                  strokeWidth="1"
                  strokeDasharray="2 3"
                />
                <circle cx={X0 + 21 * STEP} cy={yFor(1.0851)} r="3" className="fill-white" />

                <text x={X0} y={288} className="fill-gray-500 text-[9px]">09:00</text>
                <text x={X0 + 7 * STEP} y={288} className="fill-gray-500 text-[9px]">11:00</text>
                <text x={X0 + 14 * STEP} y={288} className="fill-gray-500 text-[9px]">13:00</text>
                <text x={X0 + 21 * STEP} y={288} className="fill-gray-500 text-[9px]">15:00</text>
              </svg>
            </div>

            <aside className="p-4 sm:p-5">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-[10px] uppercase tracking-[0.14em] text-gray-500">Today</p>
                  <p className="mt-1 text-2xl font-semibold tabular-nums text-success">+$248.50</p>
                </div>
                <span className="rounded-full border border-border px-2 py-1 text-[10px] text-gray-400">
                  6 trades
                </span>
              </div>

              <div className="mt-4 rounded-lg border border-border bg-surface-light/40 p-3">
                <div className="mb-2 flex items-center justify-between text-[10px]">
                  <span className="text-gray-400">Equity</span>
                  <span className="tabular-nums text-success">+2.4%</span>
                </div>
                <svg viewBox="0 0 270 46" className="h-12 w-full" aria-hidden="true">
                  <defs>
                    <linearGradient id="equityFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="var(--success)" stopOpacity="0.24" />
                      <stop offset="100%" stopColor="var(--success)" stopOpacity="0" />
                    </linearGradient>
                  </defs>
                  <path d={`${equityPath} L270 46 L0 46 Z`} fill="url(#equityFill)" />
                  <path d={equityPath} fill="none" className="stroke-success" strokeWidth="1.6" />
                </svg>
              </div>

              <dl className="mt-4 grid grid-cols-2 gap-2 text-[10px]">
                {[
                  ['Win rate', '67%'],
                  ['Profit factor', '1.9'],
                  ['Avg R', '1.6R'],
                  ['Max DD', '2.1%'],
                ].map(([label, value]) => (
                  <div key={label} className="rounded-lg border border-border bg-surface/60 px-2.5 py-2">
                    <dt className="text-gray-500">{label}</dt>
                    <dd className="mt-0.5 text-sm font-medium tabular-nums text-white">{value}</dd>
                  </div>
                ))}
              </dl>

              <div className="mt-4">
                <div className="mb-2 flex items-center justify-between text-[10px]">
                  <span className="text-gray-400">November</span>
                  <span className="tabular-nums text-success">+$1,284</span>
                </div>
                <div className="grid grid-cols-7 gap-1">
                  {calendarDays.map((pnl, index) => (
                    <div
                      key={index}
                      className={`aspect-square rounded-[3px] ${
                        pnl === null
                          ? 'bg-transparent'
                          : pnl > 0
                            ? 'bg-success/20'
                            : pnl < 0
                              ? 'bg-danger/20'
                              : 'bg-surface-light'
                      }`}
                    />
                  ))}
                </div>
              </div>
            </aside>
          </div>
        </div>
      </div>
      <p className="mt-3 text-center text-xs text-gray-600">
        Example workspace. Market view, analytics and journal share one account.
      </p>
    </div>
  )
}
