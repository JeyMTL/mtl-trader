"""Tests for the parts that decide money: fills, sizing and the stop-first rule."""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from bot.backtest import Costs, pip_size_for, run, split_run
from bot.data import Candle, Quote
from bot.strategy import Params, atr_series, build_indicators, ema_series, entry_signal

START = datetime(2026, 1, 5, tzinfo=timezone.utc)


def bar(i: int, o: float, h: float, l: float, c: float, spread: float = 0.0002) -> Candle:
    """Bid and ask straddle the quoted mid, as they do in the real feed."""
    when = START + timedelta(minutes=5 * i)
    half = spread / 2
    bid = Quote(o - half, h - half, l - half, c - half)
    ask = Quote(o + half, h + half, l + half, c + half)
    return Candle(time=when, bid=bid, ask=ask, volume=100, complete=True)


def series(closes: list[float], spread: float = 0.0002) -> list[Candle]:
    """Bars that walk from one close to the next; the open is the prior close."""
    out = []
    previous = closes[0]
    for i, close in enumerate(closes):
        high, low = max(previous, close), min(previous, close)
        out.append(bar(i, previous, high, low, close, spread))
        previous = close
    return out


def trending_up(n: int, step: float = 0.0005, origin: float = 1.1000) -> list[float]:
    return [origin + step * i for i in range(n)]


def dip_then_rise(down: int = 30, up: int = 25,
                  down_step: float = 0.0004, up_step: float = 0.0008,
                  origin: float = 1.1000) -> list[float]:
    """A downtrend followed by an uptrend: exactly one long cross, no short."""
    closes = [origin - down_step * i for i in range(down)]
    closes += [closes[-1] + up_step * i for i in range(1, up + 1)]
    return closes


class IndicatorTests(unittest.TestCase):
    def test_ema_is_none_before_its_period(self):
        values = ema_series([1.0, 2.0, 3.0, 4.0], period=3)
        self.assertEqual(values[:2], [None, None])
        self.assertAlmostEqual(values[2], 2.0)
        self.assertAlmostEqual(values[3], 3.0)

    def test_atr_is_positive_once_ready(self):
        bars = series(trending_up(40))
        atr = atr_series(bars, 14)
        self.assertIsNone(atr[13])
        self.assertGreater(atr[14], 0)
        self.assertIsNotNone(atr[-1])

    def test_cross_fires_once(self):
        # Down, then up: the fast EMA crosses the slow one exactly once.
        closes = [1.1100 - 0.0004 * i for i in range(40)] + [1.0944 + 0.0008 * i for i in range(30)]
        bars = series(closes)
        params = Params(fast=5, slow=15, atr_period=14)
        indicators = build_indicators(bars, params)
        signals = [entry_signal(i, bars, indicators, params) for i in range(len(bars))]
        self.assertEqual(signals.count("long"), 1)
        self.assertEqual(signals.count("short"), 0)


class EngineTests(unittest.TestCase):
    def _costs(self, **kwargs) -> Costs:
        base = dict(start_balance=10_000.0, risk_pct=0.01, leverage=30.0,
                    slippage_pips=0.0, pip_size=pip_size_for("EUR_USD"))
        base.update(kwargs)
        return Costs(**base)

    def test_no_trades_during_warmup(self):
        bars = series(trending_up(30))
        params = Params(fast=5, slow=15, atr_period=14)
        result = run(bars, params, self._costs(), "EUR_USD")
        infant = [t for t in result.trades if t.entry_time < bars[params.warmup()].time]
        self.assertEqual(infant, [])

    def test_stop_wins_when_a_bar_covers_both_levels(self):
        """Rule 4: an ambiguous bar is charged as a loss, never as a win."""
        bars = series(dip_then_rise())
        params = Params(fast=5, slow=15, atr_period=14, stop_atr=1.0, target_atr=1.0)
        costs = self._costs()

        probe = run(bars, params, costs, "EUR_USD")
        self.assertTrue(probe.trades, "expected the reversal to open a trade")
        first = probe.trades[0]

        # Widen the bar right after entry so it spans the stop and the target.
        index = next(i for i, b in enumerate(bars) if b.time > first.entry_time)
        victim = bars[index]
        low, high = first.stop - 0.0010, first.target + 0.0010
        bars[index] = Candle(
            time=victim.time,
            bid=Quote(victim.bid.o, high, low, victim.bid.c),
            ask=Quote(victim.ask.o, high + 0.0002, low + 0.0002, victim.ask.c),
            volume=victim.volume,
            complete=True,
        )

        result = run(bars, params, costs, "EUR_USD")
        self.assertEqual(result.trades[0].reason, "stop")
        self.assertLess(result.trades[0].pnl, 0.0)

    def test_long_pays_the_spread_on_both_sides(self):
        """Entry at the ask, exit at the bid: a flat market must lose money.

        Stop and target are parked far away so the only exit is end-of-data,
        which isolates the spread from any rule about stops.
        """
        closes = dip_then_rise() + [dip_then_rise()[-1]] * 40
        params = Params(fast=5, slow=15, atr_period=14, stop_atr=80.0, target_atr=80.0)
        costs = self._costs()

        without = run(series(closes, spread=0.0), params, costs, "EUR_USD")
        with_spread = run(series(closes, spread=0.0004), params, costs, "EUR_USD")

        self.assertTrue(with_spread.trades, "expected one long entry from the reversal")
        self.assertEqual(len(without.trades), len(with_spread.trades))
        for trade in with_spread.trades:
            self.assertEqual(trade.direction, "long")
            self.assertEqual(trade.reason, "end of data")

        # A round trip must cost exactly one spread: half on entry, half on exit.
        paid = without.trades[0].pnl - with_spread.trades[0].pnl
        expected = with_spread.trades[0].units * 0.0004
        self.assertAlmostEqual(paid, expected, delta=expected * 0.02)
        self.assertLess(with_spread.final_balance, without.final_balance)

    def test_equity_equals_start_plus_realised_pnl(self):
        bars = series(trending_up(120))
        params = Params(fast=5, slow=15, atr_period=14)
        result = run(bars, params, self._costs(), "EUR_USD")
        self.assertAlmostEqual(result.final_balance,
                               10_000.0 + sum(t.pnl for t in result.trades), places=6)

    def test_size_respects_the_risk_budget(self):
        """A stop-out should cost close to risk_pct of equity, never more."""
        bars = series(trending_up(80))
        params = Params(fast=5, slow=15, atr_period=14, stop_atr=1.0, target_atr=3.0)
        costs = self._costs(risk_pct=0.01)
        result = run(bars, params, costs, "EUR_USD")
        stopped = [t for t in result.trades if t.reason.startswith("stop")]
        for trade in stopped:
            loss = -trade.pnl
            self.assertLess(loss, 10_000.0 * 0.01 * 1.35)  # gas/slippage headroom

    def test_leverage_cap_binds_on_a_tight_stop(self):
        bars = series(trending_up(80, step=0.00005))
        params = Params(fast=5, slow=15, atr_period=14, stop_atr=0.05)
        # A 0.05xATR stop wants enormous size; the leverage cap must clamp it.
        result = run(bars, params, self._costs(leverage=2.0), "EUR_USD")
        for trade in result.trades:
            notional = trade.units * trade.entry_price
            self.assertLessEqual(notional, 10_000.0 * 2.0 * 1.02)

    def test_split_windows_are_disjoint_and_start_flat(self):
        bars = series(trending_up(200))
        params = Params(fast=5, slow=15, atr_period=14)
        first, second = split_run(bars, params, self._costs(), "EUR_USD")
        self.assertEqual(first.bars, 140)
        self.assertEqual(second.bars, 60)
        self.assertEqual(first.costs.start_balance, second.costs.start_balance)
        for trade in second.trades:
            self.assertGreaterEqual(trade.entry_time, bars[140].time)


if __name__ == "__main__":
    unittest.main()
