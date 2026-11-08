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

## Is the edge real?

Two checks on every report attack the question a positive curve cannot answer.

**Versus buy and hold.** The same bars, one fully invested unit of notional equal
to the starting balance, no leverage, entered at the first open and sold at the
last close — paying the same spread, slippage and commission. If the rules do not
beat simply owning the instrument, the curve is describing the market rather than
an edge, and the report says so in its warnings.

**Luck check.** The run's trades are reshuffled 1,000 times with a generator
seeded from the trades themselves, keeping the same outcomes but destroying their
order. The report shows the 5th–95th percentile of final return and max drawdown,
the share of reshuffles that end profitable, and how many drew down deeper than
the actual run. When fewer than half the reshuffles make money, the result depends
on the sequence it happened in — luck, not a rule.

Both are derived deterministically: the same file and parameters reproduce the
same benchmark and the same stress range.

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

## Writing a strategy in your own words

The workbench has a **Write the strategy you want tested** panel for setups the
built-in strategies do not cover. You describe what has to happen before entry,
pick the timeframes, and the model compiles it into the same declarative spec the
engine runs — a list of comparisons, a stop and a target. Nothing you write is
executed as code, and the plain-English rules that come back are yours to check
before a bar is simulated.

What the vocabulary can hold:

- **Series:** price, SMA, EMA, RSI, ATR, highest/lowest over N bars, MACD and
  Bollinger bands, each optionally read from the confirmation timeframe or up to
  20 bars back.
- **Comparisons:** above, below, crosses above, crosses below. Operands are single
  values, so there is no arithmetic between them.
- **Limit:** four conditions per side. Anything beyond that is dropped.

So a fair value gap compiles exactly (`low` above `high` two bars ago), and a
sweep-and-reclaim compiles as a bar piercing the prior N-bar extreme and closing
back inside it. What cannot be expressed: session or killzone anchoring (there is
no time-of-day filter), a gap's midpoint, whether a gap is still unfilled, or a
candle's size relative to ATR. The compiler names those in **notes** rather than
pretending it encoded them.

### Your standing criteria

The compiler is stateless — it sees only what is sent with the request. The
**What I count as acceptable** field is where your own definition lives ("what I
count as a valid gap"). It is saved on the playbook row
(`playbooks.backtest_brief`, migration `20261121_backtest_brief.sql`) and sent
with every description. It is a constraint on what gets encoded, not a rule list:
whatever it asks for that cannot be expressed comes back in the notes.

### Charts and voice notes

Up to four screenshots (PNG, JPEG, WebP) can be attached. They are evidence for
the compile step only — the engine never sees them, so a picture can disambiguate
which series you meant but cannot add a rule the vocabulary lacks.

A voice note carries the nuance a short paragraph loses. It is recorded in the
browser as 16 kHz mono WAV capped at 60 seconds (`MediaRecorder`'s WebM is not a
format the model accepts), transcribed, and **inserted into the description as
text** — so a misheard trading term is fixable before anything is compiled. The
recording is never stored. Transcription needs `GEMINI_API_KEY` even when the
review provider is Anthropic, because that is the only audio-capable vendor
configured here; without the key the panel says so instead of dropping the note.

Charts and a recording share one request body. The budget is 3 MB of attachments
before base64 (`MAX_COMPILE_ATTACHMENT_BYTES`), because the platform caps a
function request at ~4.5 MB and base64 adds a third on top — so the panel refuses
an oversized set with a sentence instead of a 413 from the edge.

## Storage

Saved runs live in `public.backtests` (migration `20261106_backtests.sql`) with
RLS scoped to the owner and **no** insert/update policy: runs are written by
`POST /api/backtest` only, so a stored result cannot be edited after the fact.
Each row keeps the strategy parameters, cost model, data window, metrics, split
metrics, benchmark, stress range, equity curve, trades and assumptions.

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
