import { createServerSupabase, requireServerUser } from '@/lib/supabase-server'
import { ChartWorkspace, type ChartDrawingRow } from '@/components/chart-workspace'

/**
 * Web chart desk.
 *
 * The objects are read here, on the server, so the first paint already has the
 * levels on it — the client only writes. A deployment that has not applied
 * `20261124_chart_analysis.sql` still gets a working chart: the read fails
 * quietly, the page says which migration is missing, and nothing claims the
 * trader's saved levels are gone.
 */

export const dynamic = 'force-dynamic'

export default async function ChartPage() {
  const user = await requireServerUser()
  const supabase = await createServerSupabase()

  let drawings: ChartDrawingRow[] = []
  let tableMissing = false

  if (supabase) {
    const { data, error } = await supabase
      .from('chart_drawings')
      .select('id, symbol, kind, points, text, edited_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: true })

    if (error) {
      tableMissing = true
    } else {
      drawings = (data ?? []).map((row) => ({
        id: String(row.id),
        symbol: String(row.symbol),
        kind: String(row.kind),
        points: Array.isArray(row.points)
          ? (row.points as { t: number; p: number }[]).filter(
              (point) => typeof point?.t === 'number' && typeof point?.p === 'number'
            )
          : [],
        text: row.text == null ? null : String(row.text),
        editedAtMs: row.edited_at ? Date.parse(String(row.edited_at)) : null,
      }))
    }
  }

  return (
    <div className="mx-auto w-full max-w-6xl space-y-3 px-3 py-3 lg:px-6">
      <div>
        <h1 className="text-lg font-bold tracking-tight text-white">Chart</h1>
        <p className="text-[11px] leading-relaxed text-gray-500">
          Live candles, the same feed the phone uses. Pin levels, trends, fib
          retracements and zones, mark a time with a vertical line, measure a move
          — all saved to your account. Session VWAP and the Asia, London and New
          York ranges are computed from the candles themselves.
        </p>
      </div>

      {tableMissing && (
        <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-[11px] text-amber-200">
          Chart drawings are not available on this database yet. Apply{' '}
          <code className="font-mono">supabase/migrations/20261124_chart_analysis.sql</code>{' '}
          to save objects.
        </div>
      )}

      <ChartWorkspace initialDrawings={drawings} defaultSymbol="EUR_USD" />
    </div>
  )
}
