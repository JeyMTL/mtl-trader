# OANDA bot

A small, self-contained trading bot for a personal OANDA practice account: download
real candles, backtest a rule, look at the current signal, and optionally place one
sized order on the demo account.

No external services beyond OANDA. One dependency (`requests`). The token never
leaves the machine except in the `Authorization` header to OANDA.

## Quickstart

```bash
cd oanda-bot
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env      # paste your practice token into OANDA_API_TOKEN
```

```bash
python main.py fetch    --instrument EUR_USD --granularity M5 --start 2025-01-01
python main.py backtest --instrument EUR_USD --granularity M5 --start 2025-01-01
python main.py signal   --instrument EUR_USD --granularity M5
python main.py trade    --instrument EUR_USD --granularity M5            # preview only
python main.py trade    --instrument EUR_USD --granularity M5 --send     # demo order
```

Candles are cached in `data/` and only the missing head or tail is fetched on the
next run, so repeat backtests need no network (a 137k-bar run takes about 6 seconds,
almost all of it the Python engine).

## What is built

| File | Job |
|---|---|
| `bot/data.py` | Paginated v20 downloader (5,000 candles/page), CSV cache, bid/ask parsing |
| `bot/strategy.py` | EMA cross + ATR stop/target + optional session windows |
| `bot/backtest.py` | Bar-by-bar engine, risk sizing, 70/30 split, metrics |
| `bot/broker.py` | Account, price, open trades, market order, close trade |
| `bot/config.py` | `.env` loading, settings, live-host guard |
| `main.py` | CLI: `fetch`, `backtest`, `signal`, `trade` |

## Backtest assumptions (printed with every run)

1. Signal decided on a bar's close, filled at the **next bar's open**.
2. A long enters at the **ask** and exits at the **bid**; a short the reverse. The
   spread is the real per-bar bid/ask, not a constant.
3. Slippage is charged against you on entry and on stop exits (`--slippage`, pips).
4. If a bar spans both stop and target, the **stop** is assumed to have filled first.
5. A bar opening beyond the stop fills at the open, then pays slippage.
6. Size is risk-based: a stop-out costs `--risk` of equity, capped by leverage.
7. A position open on the last bar is closed there, so P&L is realised.
8. A bar's range never resolves whether the stop or the target was touched first.
   Sub-minute data (`--granularity S5`) narrows that; nothing removes it.

Known gaps: P&L is in the quote currency and is not FX-converted, so returns are
exact for `*_USD` pairs and approximate otherwise; one instrument at a time; no
order-book or news modelling.

## Measured result, and why it is reported as a loss

Run on **136,789 real EUR/USD M5 bars** (2025-01-01 → 2026-10-30) from the practice
feed, defaults (EMA 20/50, 1.5×ATR stop, 3×ATR target, 1% risk, 0.2 pip slippage):

| Window | Trades | Win rate | Profit factor | Return | Max DD |
|---|---|---|---|---|---|
| Whole | 2,521 | 20.8% | 0.55 | **−100.0%** | 100.0% |
| First 70% (in sample) | 1,782 | 21.7% | 0.55 | −99.9% | 99.9% |
| Last 30% (out of sample) | 738 | 18.6% | 0.43 | −97.1% | 97.2% |

A 3:1 target needs better than 25% wins to break even; the cross delivers ~21%, and
the residual is spread plus slippage. This is the tool working correctly: it says
the naive trend cross on M5 is a losing rule, consistently, in and out of sample.
It was left as-is rather than tuned until it flattered itself.

## The safety model

- Practice host is the default; one env var and one flag are both required before a
  live host is touched (`BOT_ALLOW_LIVE=true` **and** `--allow-live`).
- `trade` is a preview unless `--send` is passed, and it prints the exact order,
  size, stop, target and risk first.
- `--send` refuses to stack a second position on an instrument that already has one.
- `.env`, `data/` and `runs/` are gitignored.

None of this stops a bad strategy from losing a demo account. It exists so the
decision to use real money is explicit rather than accidental.

## Testing

```bash
python -m unittest discover -s tests
```

Ten tests pin the parts that decide money: next-open fills, the stop-first rule on
an ambiguous bar, a round trip costing exactly one spread, risk sizing against its
budget, the leverage cap, no trades during warmup, and equity matching realised P&L.

## Changing the strategy

Edit `entry_signal()` in `bot/strategy.py` (return `"long"`, `"short"` or `None`),
keep `signals()` bar-aligned, and re-run. Everything downstream — sizing, costs,
splits, the CLI — needs no change.

## Moving it out

This directory is standalone; nothing here is imported by the parent project. Move
it wherever you keep personal code, create a fresh practice token for it in OANDA
rather than reusing one, and keep `.env` out of any repository.
