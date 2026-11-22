"""OANDA v20 candle downloader with a local CSV cache.

Facts this module encodes (all verified against the v20 endpoints):

* A page holds at most 5,000 candles, and `count` may not be combined with
  `from` + `to`, so paging is done with `from` + `count` only.
* `price=BA` returns bid and ask OHLC per bar, which is what makes a realistic
  spread model possible.
* M1 history reaches back to at least 2005 for the major pairs; `S5` exists but
  is expected to be retained for a much shorter window, so it is not the default.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

from .config import ROOT, PRACTICE_HOST

MAX_COUNT = 5_000

GRANULARITY_SECONDS = {
    "S5": 5, "S10": 10, "S15": 15, "S30": 30,
    "M1": 60, "M2": 120, "M4": 240, "M5": 300, "M10": 600,
    "M15": 900, "M30": 1_800,
    "H1": 3_600, "H2": 7_200, "H3": 10_800, "H4": 14_400,
    "H6": 21_600, "H8": 28_800, "H12": 43_200,
    "D": 86_400, "W": 604_800,
}

CACHE_DIR = ROOT / "data"


@dataclass(frozen=True)
class Quote:
    o: float
    h: float
    l: float
    c: float


@dataclass(frozen=True)
class Candle:
    time: datetime
    bid: Quote
    ask: Quote
    volume: int
    complete: bool

    @property
    def mid_open(self) -> float:
        return (self.bid.o + self.ask.o) / 2

    @property
    def mid_close(self) -> float:
        return (self.bid.c + self.ask.c) / 2

    @property
    def mid_high(self) -> float:
        return (self.bid.h + self.ask.h) / 2

    @property
    def mid_low(self) -> float:
        return (self.bid.l + self.ask.l) / 2

    @property
    def spread(self) -> float:
        return self.ask.c - self.bid.c


def parse_candle(raw: dict) -> Candle:
    when = datetime.fromisoformat(raw["time"].replace("Z", "+00:00"))
    if "bid" in raw:
        bid = Quote(*(float(raw["bid"][k]) for k in "ohlc"))
        ask = Quote(*(float(raw["ask"][k]) for k in "ohlc"))
    else:  # price=M: no spread was requested, mirror mid into both sides.
        mid = Quote(*(float(raw["mid"][k]) for k in "ohlc"))
        bid = ask = mid
    return Candle(
        time=when,
        bid=bid,
        ask=ask,
        volume=int(raw.get("volume", 0)),
        complete=bool(raw.get("complete", True)),
    )


def _iso(when: datetime) -> str:
    return when.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _as_utc(value: datetime | str) -> datetime:
    if isinstance(value, datetime):
        when = value
    else:
        when = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return when.astimezone(timezone.utc)


def _session() -> requests.Session:
    session = requests.Session()
    session.headers.update({"Content-Type": "application/json"})
    return session


def fetch_window(
    token: str,
    instrument: str,
    granularity: str,
    start: datetime | str,
    end: datetime | str | None = None,
    *,
    host: str = PRACTICE_HOST,
    price: str = "BA",
    pause: float = 0.12,
    timeout: float = 30.0,
) -> list[Candle]:
    """Every candle in [start, end], paging past OANDA's 5,000-candle cap."""
    if granularity not in GRANULARITY_SECONDS:
        raise ValueError(f"unsupported granularity {granularity!r}")
    begin = _as_utc(start)
    finish = _as_utc(end) if end else datetime.now(timezone.utc)
    if finish <= begin:
        raise ValueError("end must be after start")

    step = timedelta(seconds=GRANULARITY_SECONDS[granularity])
    url = f"{host.rstrip('/')}/v3/instruments/{instrument}/candles"
    headers = {"Authorization": f"Bearer {token}"}

    found: dict[datetime, Candle] = {}
    cursor = begin
    with _session() as session:
        while cursor <= finish:
            params = {
                "granularity": granularity,
                "count": MAX_COUNT,
                "price": price,
                "from": _iso(cursor),
            }
            response = session.get(url, params=params, headers=headers, timeout=timeout)
            if response.status_code != 200:
                payload = response.json() if response.content else {}
                message = payload.get("errorMessage", response.text[:200])
                raise RuntimeError(f"{response.status_code} {message}")
            page = [parse_candle(raw) for raw in response.json().get("candles", [])]
            if not page:
                break

            for candle in page:
                if begin <= candle.time <= finish and candle.complete:
                    found[candle.time] = candle

            if len(page) < MAX_COUNT:
                break
            following = page[-1].time + step
            if following <= cursor:  # defensive: never loop on one bar
                break
            cursor = following
            if pause:
                import time

                time.sleep(pause)

    # Only closed bars are kept: a forming bar has no final high/low, so both a
    # backtest and a signal would be reading a number that is still moving.
    return sorted(found.values(), key=lambda c: c.time)


def cache_path(instrument: str, granularity: str, price: str = "BA") -> Path:
    return CACHE_DIR / f"{instrument}_{granularity}_{price}.csv"


def save_candles(candles: list[Candle], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["time", "bid_o", "bid_h", "bid_l", "bid_c",
             "ask_o", "ask_h", "ask_l", "ask_c", "volume", "complete"]
        )
        for c in candles:
            writer.writerow([
                c.time.isoformat(),
                c.bid.o, c.bid.h, c.bid.l, c.bid.c,
                c.ask.o, c.ask.h, c.ask.l, c.ask.c,
                c.volume, int(c.complete),
            ])


def load_candles(path: Path) -> list[Candle]:
    if not path.exists():
        return []
    candles = []
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            when = datetime.fromisoformat(row["time"])
            if when.tzinfo is None:
                when = when.replace(tzinfo=timezone.utc)
            candles.append(Candle(
                time=when,
                bid=Quote(*(float(row[f"bid_{k}"]) for k in "ohlc")),
                ask=Quote(*(float(row[f"ask_{k}"]) for k in "ohlc")),
                volume=int(row["volume"]),
                complete=bool(int(row["complete"])),
            ))
    return candles


def trim(candles: list[Candle], start, end=None) -> list[Candle]:
    begin = _as_utc(start)
    finish = _as_utc(end) if end else None
    return [c for c in candles if c.time >= begin and (finish is None or c.time <= finish)]


def ensure_candles(
    token: str,
    instrument: str,
    granularity: str,
    start,
    end=None,
    *,
    host: str = PRACTICE_HOST,
    price: str = "BA",
    refresh: bool = False,
) -> list[Candle]:
    """Cached candles for the window, fetching only the part the cache lacks."""
    begin = _as_utc(start)
    finish = _as_utc(end) if end else datetime.now(timezone.utc)
    path = cache_path(instrument, granularity, price)
    cached = [] if refresh and path.exists() else load_candles(path)

    if cached:
        oldest, newest = cached[0].time, cached[-1].time
        head = begin < oldest
        tail = finish > newest + timedelta(seconds=GRANULARITY_SECONDS[granularity])
        if not head and not tail:
            return trim(cached, begin, finish)
        merged = {c.time: c for c in cached}
        if head:
            merged.update({c.time: c for c in fetch_window(
                token, instrument, granularity, begin, oldest, host=host, price=price)})
        if tail:
            merged.update({c.time: c for c in fetch_window(
                token, instrument, granularity, newest, finish, host=host, price=price)})
        candles = sorted(merged.values(), key=lambda c: c.time)
    else:
        candles = fetch_window(token, instrument, granularity, begin, finish,
                               host=host, price=price)

    if candles:
        save_candles(candles, path)
    return trim(candles, begin, finish)
