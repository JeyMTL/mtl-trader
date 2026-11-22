"""Bar-by-bar backtest that pays the real spread instead of assuming one.

Every assumption is printed with the result, because a curve without its
assumptions is a sales pitch. The rules, exactly:

1. A signal is decided on a bar's close and filled at the next bar's open.
2. A long enters at the ask and exits at the bid; a short enters at the bid and
   exits at the ask. That is the spread, charged once on the way in and once on
   the way out, with no scalar approximation.
3. Slippage is applied against you on entry and on stop exits, in pips.
4. If a bar covers both the stop and the target, the stop is assumed to have
   filled first.
5. A bar that opens beyond the stop fills at the open, then pays slippage.
6. Size is risk-based: a stop-out costs `risk_pct` of equity, capped by leverage.
7. A position still open on the last bar is closed there, so P&L is realised.
8. A bar's range never resolves the order of a stop and a target inside it.
   Sub-minute data narrows that gap; nothing here removes it.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from datetime import datetime
from typing import Sequence

from .data import Candle
from .strategy import Indicators, Params, build_indicators, entry_signal


@dataclass(frozen=True)
class Costs:
    start_balance: float = 10_000.0
    risk_pct: float = 0.01
    leverage: float = 30.0
    slippage_pips: float = 0.2
    commission_round_turn: float = 0.0
    pip_size: float = 0.0001


@dataclass
class Trade:
    direction: str
    entry_time: datetime
    entry_price: float
    exit_time: datetime
    exit_price: float
    units: float
    stop: float
    target: float
    pnl: float
    reason: str

    @property
    def r_multiple(self) -> float:
        risk = abs(self.entry_price - self.stop) * self.units
        return self.pnl / risk if risk else 0.0


@dataclass
class Position:
    direction: str
    entry_time: datetime
    entry_price: float
    units: float
    stop: float
    target: float
    risk_amount: float


@dataclass
class Result:
    instrument: str
    params: Params
    costs: Costs
    trades: list[Trade]
    curve: list[tuple[datetime, float]]
    bars: int
    start: datetime | None
    end: datetime | None
    notes: list[str] = field(default_factory=list)

    @property
    def final_balance(self) -> float:
        return self.curve[-1][1] if self.curve else self.costs.start_balance

    @property
    def net_return_pct(self) -> float:
        return (self.final_balance / self.costs.start_balance - 1) * 100

    @property
    def wins(self) -> int:
        return sum(1 for t in self.trades if t.pnl > 0)

    @property
    def win_rate_pct(self) -> float:
        return 100 * self.wins / len(self.trades) if self.trades else 0.0

    @property
    def profit_factor(self) -> float:
        gains = sum(t.pnl for t in self.trades if t.pnl > 0)
        losses = -sum(t.pnl for t in self.trades if t.pnl < 0)
        if losses == 0:
            return float("inf") if gains > 0 else 0.0
        return gains / losses

    @property
    def max_drawdown_pct(self) -> float:
        peak, worst = self.costs.start_balance, 0.0
        for _, equity in self.curve:
            peak = max(peak, equity)
            if peak > 0:
                worst = max(worst, (peak - equity) / peak * 100)
        return worst

    @property
    def avg_r(self) -> float:
        return sum(t.r_multiple for t in self.trades) / len(self.trades) if self.trades else 0.0


def pip_size_for(instrument: str) -> float:
    """3-decimal 'pip' is a JPY-quote convention; metals are quoted in dollars."""
    if instrument.endswith("_JPY"):
        return 0.01
    if instrument.startswith(("XAU", "XAG")):
        return 0.01
    return 0.0001


def _exit_for(position: Position, bar: Candle, slip: float) -> tuple[float, str] | None:
    """Fill price and reason if the bar closes the position, else None."""
    if position.direction == "long":
        # A long is sold at the bid.
        if bar.bid.o <= position.stop:
            return bar.bid.o - slip, "stop gap"
        if bar.bid.l <= position.stop:
            return position.stop - slip, "stop"
        if bar.bid.h >= position.target:
            return position.target, "target"
    else:
        # A short is bought back at the ask.
        if bar.ask.o >= position.stop:
            return bar.ask.o + slip, "stop gap"
        if bar.ask.h >= position.stop:
            return position.stop + slip, "stop"
        if bar.ask.l <= position.target:
            return position.target, "target"
    return None


def run(
    bars: Sequence[Candle],
    params: Params | None = None,
    costs: Costs | None = None,
    instrument: str = "EUR_USD",
) -> Result:
    params = params or Params()
    costs = replace(costs, pip_size=pip_size_for(instrument)) if costs \
        else Costs(pip_size=pip_size_for(instrument))

    notes: list[str] = []
    if not instrument.endswith("_USD"):
        notes.append(
            "P&L is in the quote currency and is not converted to the account "
            "currency, so return and drawdown percentages are approximate."
        )
    if len(bars) < params.warmup() + 10:
        return Result(instrument, params, costs, [], [], len(bars),
                      bars[0].time if bars else None, bars[-1].time if bars else None,
                      notes + ["Not enough bars to warm the indicators up."])

    indicators: Indicators = build_indicators(bars, params)
    slip = costs.slippage_pips * costs.pip_size
    balance = costs.start_balance
    position: Position | None = None
    trades: list[Trade] = []
    curve: list[tuple[datetime, float]] = []

    for i, bar in enumerate(bars):
        flat_at_open = position is None

        if position is not None:
            exit_fill = _exit_for(position, bar, slip)
            if exit_fill is not None:
                price, reason = exit_fill
                move = (price - position.entry_price) if position.direction == "long" \
                    else (position.entry_price - price)
                pnl = move * position.units - costs.commission_round_turn
                balance += pnl
                trades.append(Trade(
                    direction=position.direction,
                    entry_time=position.entry_time,
                    entry_price=position.entry_price,
                    exit_time=bar.time,
                    exit_price=price,
                    units=position.units,
                    stop=position.stop,
                    target=position.target,
                    pnl=pnl,
                    reason=reason,
                ))
                position = None

        if flat_at_open and i >= params.warmup():
            signal = entry_signal(i - 1, bars, indicators, params)
            atr = indicators.atr[i - 1]
            if signal and atr:
                distance_stop = params.stop_atr * atr
                distance_target = params.target_atr * atr
                entry = (bar.ask.o + slip) if signal == "long" else (bar.bid.o - slip)
                stop = entry - distance_stop if signal == "long" else entry + distance_stop
                target = entry + distance_target if signal == "long" else entry - distance_target
                risk_amount = balance * costs.risk_pct
                units = risk_amount / distance_stop if distance_stop > 0 else 0.0
                notional_cap = balance * costs.leverage / entry
                units = min(units, notional_cap)
                units = float(int(units))
                if units > 0:
                    position = Position(
                        direction=signal,
                        entry_time=bar.time,
                        entry_price=entry,
                        units=units,
                        stop=stop,
                        target=target,
                        risk_amount=risk_amount,
                    )

        if position is not None:
            marked = (bar.bid.c - position.entry_price) if position.direction == "long" \
                else (position.entry_price - bar.ask.c)
            curve.append((bar.time, balance + marked * position.units))
        else:
            curve.append((bar.time, balance))

    if position is not None:
        last = bars[-1]
        price = last.bid.c if position.direction == "long" else last.ask.c
        move = (price - position.entry_price) if position.direction == "long" \
            else (position.entry_price - price)
        pnl = move * position.units - costs.commission_round_turn
        balance += pnl
        trades.append(Trade(
            direction=position.direction,
            entry_time=position.entry_time,
            entry_price=position.entry_price,
            exit_time=last.time,
            exit_price=price,
            units=position.units,
            stop=position.stop,
            target=position.target,
            pnl=pnl,
            reason="end of data",
        ))
        curve[-1] = (last.time, balance)

    return Result(instrument, params, costs, trades, curve, len(bars),
                  bars[0].time, bars[-1].time, notes)


def split_run(
    bars: Sequence[Candle],
    params: Params | None = None,
    costs: Costs | None = None,
    instrument: str = "EUR_USD",
    first_share: float = 0.7,
) -> tuple[Result, Result]:
    """Two independent windows from the same balance: the honest out-of-sample test."""
    if not 0.1 <= first_share <= 0.9:
        raise ValueError("first_share must be between 0.1 and 0.9")
    cut = int(len(bars) * first_share)
    return (
        run(bars[:cut], params, costs, instrument),
        run(bars[cut:], params, costs, instrument),
    )
