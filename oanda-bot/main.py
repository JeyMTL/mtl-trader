#!/usr/bin/env python3
"""Command line for the bot.

    python main.py fetch    --instrument EUR_USD --granularity M5 --start 2025-01-01
    python main.py backtest --instrument EUR_USD --granularity M5 --start 2025-01-01
    python main.py signal   --instrument EUR_USD --granularity M5
    python main.py trade    --instrument EUR_USD --granularity M5 [--send]
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone

from bot.backtest import Costs, Result, pip_size_for, run, split_run
from bot.broker import BrokerError, OandaBroker
from bot.config import ROOT, Settings, load_settings
from bot.data import GRANULARITY_SECONDS, ensure_candles, fetch_window
from bot.strategy import Params, build_indicators, describe, entry_signal

DISCLAIMER = (
    "Backtest results describe the past. They are not a prediction, and no part of "
    "this tool decides whether a trade is a good idea."
)


def _parse_when(value: str) -> datetime:
    when = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return when if when.tzinfo else when.replace(tzinfo=timezone.utc)


def _settings(args) -> Settings:
    return load_settings(instrument=args.instrument, granularity=args.granularity)


def _params(args) -> Params:
    return Params(
        fast=args.fast,
        slow=args.slow,
        atr_period=args.atr_period,
        stop_atr=args.stop_atr,
        target_atr=args.target_atr,
        allow_short=not args.long_only,
    )


def _costs(args, settings: Settings) -> Costs:
    return Costs(
        start_balance=args.balance if args.balance is not None else settings.balance,
        risk_pct=args.risk if args.risk is not None else settings.risk_pct,
        leverage=settings.leverage,
        slippage_pips=args.slippage if args.slippage is not None else settings.slippage_pips,
        pip_size=pip_size_for(settings.instrument),
    )


def _report(result: Result, title: str) -> str:
    span = ""
    if result.start:
        span = f"  ({result.start:%Y-%m-%d} -> {result.end:%Y-%m-%d})"
    lines = [
        f"--- {title} ---",
        f"  bars          {result.bars:,}{span}",
        f"  trades        {len(result.trades)}"
        f"   win rate {result.win_rate_pct:.1f}%"
        f"   profit factor {result.profit_factor:.2f}",
        f"  return        {result.net_return_pct:+.2f}%"
        f"   max drawdown {result.max_drawdown_pct:.2f}%"
        f"   avg R {result.avg_r:+.2f}",
        f"  balance       {result.costs.start_balance:,.2f} -> {result.final_balance:,.2f}",
    ]
    if 0 < len(result.trades) < 30:
        lines.append(f"  ! {len(result.trades)} trades is noise; do not read an edge into it")
    for note in result.notes:
        lines.append(f"  ! {note}")
    return "\n".join(lines)


def _recent_start(granularity: str, bars: int) -> datetime:
    seconds = GRANULARITY_SECONDS[granularity]
    return datetime.now(timezone.utc) - timedelta(seconds=seconds * bars * 2)


def _recent_candles(settings: Settings, params: Params):
    """Recent closed candles, widening the lookback if the market was shut."""
    needed = params.warmup() + 2
    for attempt in range(4):
        start = _recent_start(settings.granularity, needed * (2 ** (attempt + 1)))
        candles = fetch_window(settings.token, settings.instrument, settings.granularity,
                               start=start, host=settings.host)
        if len(candles) >= needed:
            return candles
    return candles


def cmd_fetch(args) -> int:
    settings = _settings(args)
    start = _parse_when(args.start)
    end = _parse_when(args.end) if args.end else None
    print(f"fetch {settings.instrument} {settings.granularity} from {start:%Y-%m-%d}"
          f"{f' to {end:%Y-%m-%d}' if end else ''}")
    candles = ensure_candles(settings.token, settings.instrument, settings.granularity,
                             start, end, host=settings.host)
    if not candles:
        print("no candles returned")
        return 1
    pip = pip_size_for(settings.instrument)
    spreads = sorted(c.spread / pip for c in candles)
    print(f"{len(candles):,} closed candles cached in data/")
    print(f"  {candles[0].time:%Y-%m-%d %H:%M} -> {candles[-1].time:%Y-%m-%d %H:%M}")
    print(f"  spread median {spreads[len(spreads) // 2]:.2f} pips, "
          f"95th pct {spreads[int(len(spreads) * 0.95)]:.2f} pips, "
          f"max {spreads[-1]:.2f} pips")
    return 0


def cmd_backtest(args) -> int:
    settings = _settings(args)
    params, costs = _params(args), _costs(args, settings)
    start = _parse_when(args.start)
    end = _parse_when(args.end) if args.end else None
    candles = ensure_candles(settings.token, settings.instrument, settings.granularity,
                             start, end, host=settings.host)
    if len(candles) < params.warmup() + 10:
        print(f"only {len(candles)} candles; need at least {params.warmup() + 10}")
        return 1

    whole = run(candles, params, costs, settings.instrument)
    first, second = split_run(candles, params, costs, settings.instrument)

    print(f"{settings.instrument} {settings.granularity} | {describe(params)}")
    print(f"costs: balance {costs.start_balance:,.0f}, risk {costs.risk_pct:.2%}/trade, "
          f"slippage {costs.slippage_pips:g} pip/side, real bid/ask spread per bar")
    print()
    print(_report(whole, "whole range"))
    print(_report(first, "first 70% (in sample)"))
    print(_report(second, "last 30% (out of sample)"))
    if whole.trades:
        ordered = sorted(whole.trades, key=lambda t: t.pnl, reverse=True)
        print()
        print("best  " + ", ".join(f"{t.pnl:+,.0f}" for t in ordered[:3]))
        print("worst " + ", ".join(f"{t.pnl:+,.0f}" for t in ordered[-3:]))
    print()
    print(DISCLAIMER)

    if args.save:
        out = ROOT / "runs" / args.save
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({
            "instrument": settings.instrument,
            "granularity": settings.granularity,
            "strategy": describe(params),
            "whole": _summary(whole),
            "in_sample": _summary(first),
            "out_of_sample": _summary(second),
            "trades": [
                {"direction": t.direction,
                 "entry_time": t.entry_time.isoformat(),
                 "exit_time": t.exit_time.isoformat(),
                 "entry_price": t.entry_price,
                 "exit_price": t.exit_price,
                 "units": t.units,
                 "pnl": round(t.pnl, 2),
                 "reason": t.reason}
                for t in whole.trades
            ],
        }, indent=2), encoding="utf-8")
        print(f"saved {out.relative_to(ROOT)}")
    return 0


def _summary(result: Result) -> dict:
    factor = result.profit_factor
    return {
        "bars": result.bars,
        "trades": len(result.trades),
        "return_pct": round(result.net_return_pct, 3),
        "max_drawdown_pct": round(result.max_drawdown_pct, 3),
        "win_rate_pct": round(result.win_rate_pct, 2),
        "profit_factor": None if factor == float("inf") else round(factor, 3),
        "avg_r": round(result.avg_r, 3),
    }


def cmd_signal(args) -> int:
    settings = _settings(args)
    params = _params(args)
    candles = _recent_candles(settings, params)
    if len(candles) < params.warmup() + 2:
        print(f"only {len(candles)} closed candles; need {params.warmup() + 2}")
        return 1

    indicators = build_indicators(candles, params)
    last = len(candles) - 1
    atr = indicators.atr[last]
    signal = entry_signal(last, candles, indicators, params)
    pip = pip_size_for(settings.instrument)

    print(f"{settings.instrument} {settings.granularity} | {describe(params)}")
    print(f"last closed bar {candles[last].time:%Y-%m-%d %H:%M}Z  "
          f"close {candles[last].mid_close:.5f}  spread {candles[last].spread / pip:.2f} pips")
    print(f"  EMA{params.fast} {indicators.fast[last]:.5f}   "
          f"EMA{params.slow} {indicators.slow[last]:.5f}   ATR {atr:.5f}")
    print(f"  signal: {signal or 'none'}")
    if atr:
        print(f"  if taken: stop {params.stop_atr * atr / pip:.1f} pips away, "
              f"target {params.target_atr * atr / pip:.1f} pips away")
    print("\nA signal is not an order. `trade --send` is a separate decision.")
    return 0


def cmd_trade(args) -> int:
    settings = _settings(args)
    params = _params(args)
    try:
        broker = OandaBroker(settings.token, settings.host, allow_live=settings.allow_live)
    except BrokerError as error:
        print(f"refusing: {error}")
        return 2

    print(f"host: {'LIVE (real money)' if broker.is_live else 'practice (demo money)'}")
    try:
        account = broker.account()
        price = broker.price(settings.instrument)
    except BrokerError as error:
        print(f"broker error: {error}")
        return 1
    print(f"account: {account.describe()}")
    print(f"price {price.bid:.5f} / {price.ask:.5f} (spread {price.spread:.5f})")

    candles = _recent_candles(settings, params)
    if len(candles) < params.warmup() + 2:
        print("not enough candles for a signal")
        return 1
    indicators = build_indicators(candles, params)
    last = len(candles) - 1
    signal = entry_signal(last, candles, indicators, params)
    atr = indicators.atr[last]
    print(f"signal: {signal or 'none'}")

    if signal is None or not atr:
        print("nothing to do")
        return 0
    if broker.open_trades(settings.instrument):
        print("a position is already open on this instrument; not stacking another")
        return 0

    # Sized from the same stop distance and risk percentage the backtest used,
    # so live risk matches the risk that was measured.
    risk_amount = account.balance * settings.risk_pct
    distance = params.stop_atr * atr
    units = int(min(risk_amount / distance, account.balance * settings.leverage / price.ask))
    if units <= 0:
        print("computed size is zero; nothing to send")
        return 0

    signed = units if signal == "long" else -units
    entry = price.ask if signal == "long" else price.bid
    stop = entry - distance if signal == "long" else entry + distance
    target = (entry + params.target_atr * atr if signal == "long"
              else entry - params.target_atr * atr)

    print(f"would {signal} {abs(signed):,} units at ~{entry:.5f}, "
          f"stop {stop:.5f}, target {target:.5f}, risk {risk_amount:,.2f} {account.currency}")
    if not args.send:
        print("\npreview only. add --send to place it on the practice account.")
        return 0
    if broker.is_live and not args.allow_live:
        print("live account needs --allow-live as well as --send; nothing sent")
        return 2

    try:
        result = broker.market_order(settings.instrument, signed, stop_loss=stop, take_profit=target)
    except BrokerError as error:
        print(f"order rejected: {error}")
        return 1
    fill = result.get("orderFillTransaction")
    if fill:
        trade_id = fill.get("tradeOpened", {}).get("tradeID", "?")
        print(f"filled {fill['units']} {settings.instrument} at {fill['price']} (trade {trade_id})")
    else:
        print(f"order not filled: {json.dumps(result)[:400]}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="OANDA trading bot (practice by default)")
    sub = parser.add_subparsers(dest="command", required=True)

    def shared(p):
        p.add_argument("--instrument", default=None, help="e.g. EUR_USD")
        p.add_argument("--granularity", default=None, help="M1, M5, M15, H1, H4, D")
        p.add_argument("--fast", type=int, default=20)
        p.add_argument("--slow", type=int, default=50)
        p.add_argument("--atr-period", type=int, default=14, dest="atr_period")
        p.add_argument("--stop-atr", type=float, default=1.5, dest="stop_atr")
        p.add_argument("--target-atr", type=float, default=3.0, dest="target_atr")
        p.add_argument("--long-only", action="store_true", dest="long_only")
        p.add_argument("--balance", type=float, default=None)
        p.add_argument("--risk", type=float, default=None, help="fraction of equity, e.g. 0.01")
        p.add_argument("--slippage", type=float, default=None, help="pips per side")

    fetch = sub.add_parser("fetch", help="download and cache candles")
    shared(fetch)
    fetch.add_argument("--start", required=True)
    fetch.add_argument("--end", default=None)
    fetch.set_defaults(func=cmd_fetch)

    backtest = sub.add_parser("backtest", help="simulate the strategy on candles")
    shared(backtest)
    backtest.add_argument("--start", required=True)
    backtest.add_argument("--end", default=None)
    backtest.add_argument("--save", default=None, help="write a JSON run into runs/")
    backtest.set_defaults(func=cmd_backtest)

    signal = sub.add_parser("signal", help="what the strategy says right now")
    shared(signal)
    signal.set_defaults(func=cmd_signal)

    trade = sub.add_parser("trade", help="preview (or send) one order on the demo account")
    shared(trade)
    trade.add_argument("--send", action="store_true", help="actually place the order")
    trade.add_argument("--allow-live", action="store_true", dest="allow_live")
    trade.set_defaults(func=cmd_trade)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
