# Backtest

A rule-based backtest over your own MT5 bar data, with the assumptions printed on
every result.

## What it is

You export a history range from MetaTrader (or any CSV with date, open, high, low,
close), pick a strategy and a cost model, and the server simulates the rules bar
by bar. The result is reproducible: the same file and the same parameters produce
the same trades, every time.

The engine is at `src/lib/backtest/`, is pure TypeScript with no I/O, and is
unit-tested for the rules that matter (next-open fills, costs, sizing, the
pessimistic intrabar order, gap fills).

## What it is not

- **Not a predictor.** A good equity curve on historical bars says the rules
  survived that data; it says nothing about the next month.
- **Not tick-accurate.** Bars cannot tell you whether the stop or the target was
  touched first. The engine assumes the stop did, every time.
- **Not multi-symbol.** One file is one instrument. Portfolio effects are not
  modelled.
- **Not FX-converted.** P&L is in the data's quote currency.

## The rules, exactly

1. A signal is decided on a bar's **close** and filled at the **next bar's open**.
2. Half the spread and the full slippage are applied against you on entry and on
   exit; commission is charged once per round turn.
3. If a bar's range covers both the stop and the target, the **stop** is assumed
   to have filled first.
4. A bar that opens beyond the stop fills at the open — worse than the stop, as
   it would live.
5. Size is chosen so a stop-out costs `riskPercent` of equity, then capped by the
   leverage limit.
6. A position still open on the final bar is closed at that close, so reported
   P&L is realised.
7. Bar timestamps are read as UTC. If your broker's server clock is offset, set
   the offset — session-based results depend on it.

## Splitting the range

Every run also simulates two independent windows (70/30 by default) from the same
starting balance. That is the honest version of "does it hold up out of sample?":
the second window starts flat and knows nothing the first window produced.

A backtest with fewer than ~30 trades is noise. The report says so rather than
letting a 100% win rate on four trades look like an edge.

## Exporting from MT5

1. Open the chart for the instrument and timeframe you want.
2. `Ctrl+A` to select all bars (or scroll back to load the range first).
3. `Ctrl+C`, then paste into a text file — MT5 copies tab-separated rows with a
   `<DATE> <TIME> <OPEN> <HIGH> <LOW> <CLOSE> …` header.
4. Upload that file.

Limits: 60,000 bars and 4 MB per run (Vercel caps a function body at ~4.5 MB).
60,000 M1 bars is about six weeks of FX data; for a year, use M5 or H1.

## What about my journal, notes and screenshots?

The report shows a **journal comparison** for the same symbol and window: your
real closed trades, their net P&L, win rate and a breakdown by the strategy field
you typed on each trade. That is arithmetic over trades that already happened —
useful context, but not a simulation.

Notes and screenshots cannot drive the engine. A screenshot is pixels and a note
is prose; neither carries a price series, so there is nothing to replay. They
already feed the AI review (`src/lib/ai/review.ts`), which reads them
qualitatively — that is the right home for unstructured evidence.

The strategy field is a label, not a rule set. To test it, describe the rules in
the strategy parameters here and keep the same name in the run and on your
trades, so the two panels line up. The same label is grouped on the analytics
page under **Performance by Strategy** (`strategy_stats`, migration
`20261107_strategy_stats.sql`), matched on the exact trimmed text — "SMA cross"
and "sma cross" are two rows, and blank labels group as *Untagged*.

## Suggesting the rules from a trade

The form has a **Suggest rules from a trade** panel. Pick a journal entry and
`POST /api/backtest/suggest` reads that one trade's notes and up to two of its
screenshots, and returns the closest strategy from the menu with parameters
already clamped into their allowed ranges.

This is the honest use of a screenshot: the model reads the chart's structure —
trend or range, rejection, candle size — and translates the trader's own words
into rules. It does not replay the image. The suggestion is a starting point to
run, not a result to trust; the out-of-sample window is where you find out.

What the model cannot do:

- Name a strategy that does not exist — an unknown id is rejected, not simulated.
- Leave a parameter outside its range — every value is clamped by
  `normalizeParams`, and missing ones take the declared default.
- Pretend to have seen a photo it could not read — images over 4 MB, or in a
  format the provider rejects (HEIC), are skipped and counted, never sent as a
  broken part.

The panel refuses an entry with neither notes nor a screenshot, because the model
would be guessing from the symbol alone. Limits: 5 suggestions per 10 minutes per
user, and the provider must be configured (`GEMINI_API_KEY` or
`ANTHROPIC_API_KEY`); without it the panel says so instead of failing silently.

## Storage

Saved runs live in `public.backtests` (migration `20261106_backtests.sql`) with
RLS scoped to the owner and **no** insert/update policy: runs are written by
`POST /api/backtest` only, so a stored result cannot be edited after the fact.
Each row keeps the strategy parameters, cost model, data window, metrics, split
metrics, equity curve, trades and assumptions.

## Adding a strategy

1. Add a `StrategyDefinition` in `src/lib/backtest/strategies.ts` — an id, a
   description, parameter specs with ranges, and a `signals()` function returning
   absolute stop and target levels.
2. Register it in `STRATEGIES`. The UI builds its parameter form from the specs,
   so nothing else needs to change.
3. Add a test that the strategy produces trades on a synthetic series and none
   during warmup.

Keep `signals()` pure and bar-aligned: return `null` where a value is not ready
rather than substituting zero.
