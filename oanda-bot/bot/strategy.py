"""One strategy, stated plainly: trend-following EMA cross with ATR risk.

Why this one: it is mechanical, needs no discretion, and its failure modes are
well known (whipsaw in ranges), which makes it a fair first thing to test rather
than a flattering one. Replace `entry_signal` to test your own idea.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import time
from typing import Sequence

from .data import Candle


@dataclass(frozen=True)
class Params:
    fast: int = 20
    slow: int = 50
    atr_period: int = 14
    stop_atr: float = 1.5
    target_atr: float = 3.0
    allow_short: bool = True
    # Up to four UTC windows (start_hour, start_min, end_hour, end_min).
    sessions: tuple[tuple[int, int, int, int], ...] = ()

    def warmup(self) -> int:
        """Bars needed before any signal can be trusted."""
        return max(self.slow, self.atr_period) + 2


@dataclass
class Indicators:
    fast: list[float | None]
    slow: list[float | None]
    atr: list[float | None]


def ema_series(values: Sequence[float], period: int) -> list[float | None]:
    """EMA seeded with a simple average, so early values are not distorted."""
    out: list[float | None] = [None] * len(values)
    if period <= 0 or len(values) < period:
        return out
    seed = sum(values[:period]) / period
    out[period - 1] = seed
    k = 2 / (period + 1)
    for i in range(period, len(values)):
        prev = out[i - 1]
        out[i] = values[i] * k + prev * (1 - k)  # type: ignore[operator]
    return out


def atr_series(bars: Sequence[Candle], period: int) -> list[float | None]:
    """Wilder's ATR on mid prices."""
    out: list[float | None] = [None] * len(bars)
    if len(bars) <= period:
        return out
    ranges: list[float] = []
    for i, bar in enumerate(bars):
        high, low = bar.mid_high, bar.mid_low
        if i == 0:
            ranges.append(high - low)
        else:
            previous_close = bars[i - 1].mid_close
            ranges.append(max(high - low, abs(high - previous_close), abs(low - previous_close)))
    first = sum(ranges[1:period + 1]) / period
    out[period] = first
    for i in range(period + 1, len(bars)):
        out[i] = (out[i - 1] * (period - 1) + ranges[i]) / period  # type: ignore[operator]
    return out


def build_indicators(bars: Sequence[Candle], params: Params) -> Indicators:
    closes = [b.mid_close for b in bars]
    return Indicators(
        fast=ema_series(closes, params.fast),
        slow=ema_series(closes, params.slow),
        atr=atr_series(bars, params.atr_period),
    )


def in_session(when, sessions: tuple[tuple[int, int, int, int], ...]) -> bool:
    if not sessions:
        return True
    clock = when.time()
    for start_hour, start_min, end_hour, end_min in sessions:
        start, end = time(start_hour, start_min), time(end_hour, end_min)
        if start <= end:
            if start <= clock < end:
                return True
        elif clock >= start or clock < end:  # window crosses midnight
            return True
    return False


def entry_signal(
    index: int,
    bars: Sequence[Candle],
    indicators: Indicators,
    params: Params,
) -> str | None:
    """'long', 'short' or None for the cross that completed at `index`."""
    if index < 1 or index >= len(bars):
        return None
    fast_now, fast_prev = indicators.fast[index], indicators.fast[index - 1]
    slow_now, slow_prev = indicators.slow[index], indicators.slow[index - 1]
    atr_now = indicators.atr[index]
    if None in (fast_now, fast_prev, slow_now, slow_prev, atr_now):
        return None
    if atr_now <= 0 or not in_session(bars[index].time, params.sessions):
        return None
    if fast_prev <= slow_prev and fast_now > slow_now:
        return "long"
    if params.allow_short and fast_prev >= slow_prev and fast_now < slow_now:
        return "short"
    return None


def describe(params: Params) -> str:
    bits = [
        f"EMA {params.fast}/{params.slow} cross",
        f"stop {params.stop_atr:g}xATR({params.atr_period})",
        f"target {params.target_atr:g}xATR",
        "long only" if not params.allow_short else "long and short",
    ]
    if params.sessions:
        windows = ", ".join(f"{a:02d}:{b:02d}-{c:02d}:{d:02d}Z" for a, b, c, d in params.sessions)
        bits.append(f"sessions {windows}")
    return " | ".join(bits)
