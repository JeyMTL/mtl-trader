"""Settings for the bot, loaded from the environment and an optional .env file.

The only secret is OANDA_API_TOKEN. It is never printed, logged or written to a
result file; everything that renders a summary goes through `redact()`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRACTICE_HOST = "https://api-fxpractice.oanda.com"
LIVE_HOST = "https://api-fxtrade.oanda.com"


def load_dotenv(path: Path | None = None) -> None:
    """Populate os.environ from ROOT/.env without overwriting real env vars."""
    path = path or ROOT / ".env"
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        # Strip an inline comment only when it follows whitespace.
        value = value.split(" #", 1)[0].strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, value)


def _flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    token: str
    host: str = PRACTICE_HOST
    instrument: str = "EUR_USD"
    granularity: str = "M5"
    balance: float = 10_000.0
    risk_pct: float = 0.01
    leverage: float = 30.0
    slippage_pips: float = 0.2
    allow_live: bool = False

    @property
    def is_live_host(self) -> bool:
        return "fxtrade" in self.host

    def describe(self) -> str:
        kind = "LIVE (real money)" if self.is_live_host else "practice (demo money)"
        return f"{kind} | {self.host} | token {redact(self.token)}"


def redact(token: str) -> str:
    """A token is never shown; only a length hint so a wrong key is noticeable."""
    if not token:
        return "<missing>"
    return f"<set, {len(token)} chars, starts {token[:4]}\u2026>"


def load_settings(**overrides) -> Settings:
    load_dotenv()
    token = os.environ.get("OANDA_API_TOKEN", "").strip()
    if not token:
        raise SystemExit(
            "OANDA_API_TOKEN is not set. Copy .env.example to .env and paste your "
            "practice token, or export it in the shell."
        )
    values = dict(
        token=token,
        host=os.environ.get("OANDA_API_BASE", PRACTICE_HOST).rstrip("/"),
        instrument=os.environ.get("BOT_INSTRUMENT", "EUR_USD"),
        granularity=os.environ.get("BOT_GRANULARITY", "M5"),
        balance=float(os.environ.get("BOT_BALANCE", "10000")),
        risk_pct=float(os.environ.get("BOT_RISK_PCT", "0.01")),
        leverage=float(os.environ.get("BOT_LEVERAGE", "30")),
        slippage_pips=float(os.environ.get("BOT_SLIPPAGE_PIPS", "0.2")),
        allow_live=_flag("BOT_ALLOW_LIVE"),
    )
    values.update({k: v for k, v in overrides.items() if v is not None})
    return Settings(**values)
