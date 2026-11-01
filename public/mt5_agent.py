"""
MTL Trader - MT5 sync agent (position-keyed, resumable).

Runs on a Windows machine with MetaTrader 5 installed and pushes closed trades to
MTL Trader. Customers who only have a phone should use the app's "connect
automatically" flow instead — this agent exists for traders who prefer their own
PC.

What changed from the first version, and why it matters:

  * Trades are keyed on the MT5 **position id**, which is stable for the whole
    life of a position. The old version keyed on a closing deal ticket, so a
    position that scaled out inserted itself twice and doubled its P&L.
  * A cursor is persisted next to the config and only advanced after the server
    acknowledges a batch, so a poll sends the new closes instead of a year of
    history every 60 seconds (which hit the 1000-trade cap on busy accounts).
  * Timestamps are sent in UTC. The old version used the machine's local time,
    which shifted every trade by the machine's timezone and quietly skewed the
    time-edge report.
  * Closing deals of type INOUT (2) and OUT_BY (3) are understood, so netting
    accounts and "close by" orders are no longer invisible.
  * Stop loss and take profit are read from the position's history orders rather
    than hardcoded to zero.
  * Permanent errors (401/403/400) stop with advice instead of retrying forever;
    transient ones back off exponentially.

Usage:
    python mt5_agent.py --config mtl-trader-config.json
    python mt5_agent.py --config mtl-trader-config.json --once
"""

import json
import os
import random
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from getpass import getpass

import MetaTrader5 as mt5
import requests

DEFAULT_APP_URL = "https://mtl-trader.vercel.app"
SYNC_INTERVAL = 60
CHUNK = 200
# Deals can land a little late on the broker's clock; re-read a short tail so a
# late-arriving close is not skipped. The server ignores anything it already has.
OVERLAP = timedelta(minutes=10)
STATE_FILE = "mtl-trader-state.json"
TIMEOUT = 30


def load_config(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(state):
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as handle:
            json.dump(state, handle)
    except OSError as error:
        print(f"Warning: could not save progress ({error}); the next sync will resend.")


def connect_to_mt5(broker_name, server, login, password):
    if not password:
        password = getpass(f"Enter MT5 password for {login}: ")

    print(f"Connecting to {broker_name} - {server}...")
    if not mt5.initialize():
        print(f"MT5 initialization failed: {mt5.last_error()}")
        return False

    if not mt5.login(login=int(login), password=password, server=server or broker_name):
        print(f"Login failed: {mt5.last_error()}")
        mt5.shutdown()
        return False

    info = mt5.account_info()
    print(f"Connected to {info.server} - account {info.login}")
    return True


def _weighted(deals):
    """Volume-weighted price across several deals (scale-ins and partial closes)."""
    total_volume = sum(d.volume for d in deals)
    if total_volume <= 0:
        return deals[-1].price if deals else 0.0
    return sum(d.price * d.volume for d in deals) / total_volume


def _stop_and_target(position_id):
    """
    The opening order carries the SL/TP the trader set. `history_orders_get` is
    the only place they survive after the position closes.
    """
    try:
        orders = mt5.history_orders_get(position=int(position_id))
    except Exception:  # noqa: BLE001 - a missing history must not abort the sync
        return 0.0, 0.0
    if not orders:
        return 0.0, 0.0
    for order in orders:
        if order.sl:
            return float(order.sl), float(order.tp or 0.0)
    return float(orders[0].sl or 0.0), float(orders[0].tp or 0.0)


def get_trades(since):
    """
    Closed positions changed since `since` (a UTC datetime), keyed by position id.

    `since=None` reads a year, which is what the first run of a new install does.
    """
    to_date = datetime.now(timezone.utc)
    from_date = since if since else to_date - timedelta(days=365)

    deals = mt5.history_deals_get(from_date, to_date)
    if deals is None:
        print(f"Could not read history: {mt5.last_error()}")
        return []

    by_position = defaultdict(list)
    for deal in deals:
        if deal.position_id:
            by_position[deal.position_id].append(deal)

    trades = []
    for position_id, group in by_position.items():
        # entry: 0 = in, 1 = out, 2 = inout, 3 = out by. INOUT closes the running
        # volume as part of a reversal, so it counts as an exit here.
        opens = [d for d in group if d.entry == 0]
        closes = [d for d in group if d.entry in (1, 2, 3)]
        if not opens or not closes:
            continue

        first_open = min(opens, key=lambda d: d.time)
        last_close = max(closes, key=lambda d: d.time)

        opened_volume = sum(d.volume for d in opens)
        closed_volume = sum(d.volume for d in closes)
        # What actually closed: a scale-out leaves part of the position to run,
        # and a re-opened netting position has more open volume than closed.
        lot = round(min(opened_volume, closed_volume), 2)
        if lot <= 0:
            continue

        stop_loss, take_profit = _stop_and_target(position_id)

        trades.append({
            "position_id": int(position_id),
            # Kept for reference and for matching rows written by the old agent.
            "ticket": int(last_close.ticket),
            "symbol": first_open.symbol,
            "type": "BUY" if first_open.type == 0 else "SELL",
            "entry_price": float(_weighted(opens)),
            "exit_price": float(_weighted(closes)),
            "lot_size": lot,
            "stop_loss": stop_loss,
            "take_profit": take_profit,
            "pnl": round(sum(d.profit + d.commission + d.swap for d in group), 2),
            "commission": round(sum(d.commission for d in group), 2),
            "swap": round(sum(d.swap for d in group), 2),
            "open_time": datetime.fromtimestamp(first_open.time, timezone.utc).isoformat(),
            "close_time": datetime.fromtimestamp(last_close.time, timezone.utc).isoformat(),
            "timeframe": "",
            "strategy": "",
        })

    trades.sort(key=lambda item: item["close_time"])
    return trades


def post_trades(app_url, user_id, token, trades):
    url = f"{app_url.rstrip('/')}/api/sync"
    payload = {"userId": user_id, "token": token, "trades": trades}
    try:
        return requests.post(url, json=payload, timeout=TIMEOUT)
    except requests.RequestException as error:
        print(f"Connection error: {error}")
        return None


def sync_trades(app_url, user_id, token, trades):
    """
    Sends the batch in chunks and returns True only when every chunk landed.

    Retries transient failures (429, 5xx, network) with backoff; stops on a
    permanent refusal, because a wrong token or an unverified email will never
    succeed by being sent again.
    """
    if not trades:
        return True

    total = 0
    for start in range(0, len(trades), CHUNK):
        chunk = trades[start:start + CHUNK]
        attempt = 0
        while True:
            attempt += 1
            response = post_trades(app_url, user_id, token, chunk)

            if response is None:
                if attempt >= 5:
                    print("Giving up on this batch; progress was not advanced.")
                    return False
            elif response.status_code == 200 or response.status_code == 202:
                body = response.json()
                total += int(body.get("imported", 0))
                break
            elif response.status_code in (400, 401, 403):
                detail = response.json().get("error", "request refused")
                print(f"Sync refused ({response.status_code}): {detail}")
                if response.status_code == 401:
                    print("The token does not match. Rotate it on the MT5 Sync page and update the config.")
                elif response.status_code == 403:
                    print("Confirm your email address before syncing.")
                return False
            elif attempt >= 5:
                print(f"Server kept failing (HTTP {response.status_code}); will retry next poll.")
                return False
            else:
                wait = min(60, (2 ** attempt) + random.uniform(0, 1))
                print(f"HTTP {response.status_code}; retrying in {wait:.0f}s...")
                time.sleep(wait)

    print(f"Synced {total} new trade(s) from {len(trades)} closed position(s)")
    return True


def main():
    print("=" * 52)
    print("MTL Trader - MT5 sync agent")
    print("=" * 52)

    config = {}
    if "--config" in sys.argv:
        index = sys.argv.index("--config")
        try:
            config = load_config(sys.argv[index + 1])
        except (IndexError, OSError, json.JSONDecodeError) as error:
            print(f"Could not read the setup file: {error}")
            sys.exit(1)

    user_id = os.environ.get("MTL_USER_ID") or config.get("user_id")
    token = os.environ.get("MTL_TOKEN") or config.get("token")
    app_url = os.environ.get("MTL_APP_URL") or config.get("app_url", DEFAULT_APP_URL)
    broker_name = os.environ.get("MT5_BROKER") or config.get("broker_name")
    server = os.environ.get("MT5_SERVER") or config.get("server", "")
    login = os.environ.get("MT5_LOGIN") or config.get("login", "")
    password = os.environ.get("MT5_PASSWORD", "")

    if not user_id or not token or not broker_name or not login:
        print("Missing connection details. Download the setup file from the MT5 Sync page.")
        sys.exit(1)

    if not connect_to_mt5(broker_name, server, login, password):
        sys.exit(1)

    state = load_state()
    once = "--once" in sys.argv
    backoff = 0

    while True:
        since = None
        cursor = state.get("last_close_time")
        if cursor:
            since = datetime.fromisoformat(cursor) - OVERLAP

        trades = get_trades(since)
        if trades:
            print(f"{len(trades)} closed position(s) to consider")
            if sync_trades(app_url, user_id, token, trades):
                state["last_close_time"] = trades[-1]["close_time"]
                save_state(state)
                backoff = 0
        elif since is None:
            print("No closed trades found yet")

        if once:
            break

        interval = min(SYNC_INTERVAL * (2 ** backoff), 15 * 60)
        time.sleep(interval)
        if trades is None:
            backoff = min(backoff + 1, 4)

    mt5.shutdown()
    print("Done.")


if __name__ == "__main__":
    main()
