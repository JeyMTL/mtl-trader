import { createServerSupabase, requireServerUser } from '@/lib/supabase-server'
import { ChartWorkspace, type ChartDrawingRow } from '@/components/chart-workspace'
import { loadAccount } from '@/lib/plan-guard'
import { hasProTools } from '@/lib/subscription'

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
  // The 5s/10s/15s sizes are Pro (a live trial counts). The page decides once so
  // the first paint does not flash a locked size; the component only draws it.
  const proTimeframes = hasProTools((await loadAccount(user.id)) ?? {})

  let drawings: ChartDrawingRow[] = []
  let tableMissing = false

  if (supabase) {
    const read = (columns: string) =>
      supabase
        .from('chart_drawings')
        .select(columns)
        .eq('user_id', user.id)
        .order('created_at', { ascending: true })

    const first = await read('id, symbol, kind, points, text, style, edited_at')
    let rows = first.data as Record<string, unknown>[] | null
    let readError = first.error
    // The first paint must not depend on a migration: if the style column is
    // not there yet, the chart still opens with the objects it has.
    if (readError && /style/i.test(readError.message ?? '')) {
      const retry = await read('id, symbol, kind, points, text, edited_at')
      rows = retry.data as Record<string, unknown>[] | null
      readError = retry.error
    }

    if (readError) {
      tableMissing = true
    } else {
      drawings = (rows ?? []).map((row) => ({
        id: String(row.id),
        symbol: String(row.symbol),
        kind: String(row.kind),
        points: Array.isArray(row.points)
          ? (row.points as { t: number; p: number }[]).filter(
              (point) => typeof point?.t === 'number' && typeof point?.p === 'number'
            )
          : [],
        text: row.text == null ? null : String(row.text),
        style:
          row.style && typeof row.style === 'object'
            ? (row.style as Record<string, unknown>)
            : {},
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

      <ChartWorkspace
        initialDrawings={drawings}
        defaultSymbol="EUR_USD"
        proTimeframes={proTimeframes}
      />
    </div>
  )
}
