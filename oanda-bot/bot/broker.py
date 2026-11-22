"""OANDA v20 account and order calls, with real money blocked by default.

The guard is deliberate and narrow: a live host is refused unless the caller
passes allow_live=True, which the CLI only does when BOT_ALLOW_LIVE=true *and*
--send were both given. A practice token cannot reach a live account anyway, but
the check makes the intent visible at the call site instead of implied.
"""

from __future__ import annotations

from dataclasses import dataclass

import requests

from .config import PRACTICE_HOST


class BrokerError(RuntimeError):
    pass


@dataclass(frozen=True)
class Account:
    balance: float
    currency: str
    nav: float
    open_trades: int

    def describe(self) -> str:
        return (f"balance {self.balance:,.2f} {self.currency} | "
                f"NAV {self.nav:,.2f} | open trades {self.open_trades}")


@dataclass(frozen=True)
class Price:
    instrument: str
    bid: float
    ask: float

    @property
    def spread(self) -> float:
        return self.ask - self.bid


class OandaBroker:
    def __init__(self, token: str, host: str = PRACTICE_HOST,
                 allow_live: bool = False, timeout: float = 20.0) -> None:
        if not token:
            raise BrokerError("no token")
        if "fxtrade" in host and not allow_live:
            raise BrokerError(
                "refusing to touch the LIVE host: set BOT_ALLOW_LIVE=true and pass "
                "--allow-live if you really mean to trade real money"
            )
        self._host = host.rstrip("/")
        self._allow_live = allow_live
        self._timeout = timeout
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

    @property
    def is_live(self) -> bool:
        return "fxtrade" in self._host

    def _url(self, path: str) -> str:
        return f"{self._host}/v3/{path.lstrip('/')}"

    def _request(self, method: str, path: str, **kwargs) -> dict:
        response = self._session.request(method, self._url(path), timeout=self._timeout, **kwargs)
        payload = response.json() if response.content else {}
        if response.status_code >= 400:
            message = payload.get("errorMessage") or payload.get("errorCode") or response.text[:300]
            raise BrokerError(f"{response.status_code} {message}")
        return payload

    # -- reads ------------------------------------------------------------

    def account(self) -> Account:
        payload = self._request("GET", "accounts")
        accounts = payload.get("accounts", [])
        if not accounts:
            raise BrokerError("token has no accounts")
        account_id = accounts[0]["id"]
        summary = self._request("GET", f"accounts/{account_id}/summary")["account"]
        return Account(
            balance=float(summary["balance"]),
            currency=summary["currency"],
            nav=float(summary["NAV"]),
            open_trades=int(summary.get("openTradeCount", 0)),
        )

    def price(self, instrument: str) -> Price:
        payload = self._request("GET", f"accounts/{self._account_id()}/pricing",
                                params={"instruments": instrument})
        prices = payload.get("prices", [])
        if not prices:
            raise BrokerError(f"no price for {instrument}")
        row = prices[0]
        bid = float(row["bids"][0]["price"])
        ask = float(row["asks"][0]["price"])
        return Price(instrument, bid, ask)

    def open_trades(self, instrument: str | None = None) -> list[dict]:
        payload = self._request("GET", f"accounts/{self._account_id()}/openTrades")
        trades = payload.get("trades", [])
        if instrument:
            trades = [t for t in trades if t.get("instrument") == instrument]
        return trades

    def _account_id(self) -> str:
        accounts = self._request("GET", "accounts").get("accounts", [])
        if not accounts:
            raise BrokerError("token has no accounts")
        return accounts[0]["id"]

    # -- writes -----------------------------------------------------------

    def market_order(self, instrument: str, units: int,
                     stop_loss: float | None = None,
                     take_profit: float | None = None) -> dict:
        """Positive units buy, negative units sell. FOK, so a fill is all or nothing."""
        order: dict = {
            "type": "MARKET",
            "instrument": instrument,
            "units": str(int(units)),
            "timeInForce": "FOK",
            "positionFill": "DEFAULT",
        }
        if stop_loss is not None:
            order["stopLossOnFill"] = {"price": f"{stop_loss:.5f}", "timeInForce": "GTC"}
        if take_profit is not None:
            order["takeProfitOnFill"] = {"price": f"{take_profit:.5f}", "timeInForce": "GTC"}
        return self._request("POST", f"accounts/{self._account_id()}/orders",
                             json={"order": order})

    def close_trade(self, trade_id: str) -> dict:
        return self._request("PUT", f"accounts/{self._account_id()}/trades/{trade_id}/close",
                             json={"units": "ALL"})
