"""
MTL Trader - hosted sync supervisor.

This is the service that makes "connect automatically" real for customers who
only have a phone: they paste their investor (read-only) password in the app, and
this runs on our own Windows host, logs into MT5 with it, and posts closed trades
to /api/sync.

Design notes:

  * **One terminal, sequential sessions.** The MetaTrader5 package talks to a
    local terminal over IPC, so running one terminal per customer would need one
    Windows session each. Instead we log in, read, and move on: 40 accounts cost
    a few seconds each per cycle and share a single terminal. That is what makes
    the economics work.
  * **Read-only by construction.** Only the investor password is ever used, so a
    bug here cannot open, close or modify a trade.
  * **Claim before you work.** A connection is moved to `connecting` before the
    login attempt, so two supervisors cannot fight over the same account and the
    customer sees progress instead of a silent pending row.
  * **Credentials never leave the host.** The AES-GCM blob is decrypted here with
    SYNC_CREDENTIAL_KEY, the same key the app used to seal it.

Environment:
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    SYNC_CREDENTIAL_KEY   (base64, 32 bytes - same value as the Next.js app)
    SYNC_SUPERVISOR_TOKEN (shared secret the ingest endpoint accepts)
    APP_URL               (defaults to https://mtl-trader.vercel.app)
    CYCLE_SECONDS         (default 15 - how often a new connection is claimed)
    REFRESH_SECONDS       (default 60 - how often a connected account is re-read)
    WATCH_SECONDS         (default 2 - poll interval while watching the single
                           connected account; 0 disables the watch mode)

Run:
    python supervisor/mt5_supervisor.py --once
    python supervisor/mt5_supervisor.py
"""

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta, timezone

import MetaTrader5 as mt5
import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from dotenv import load_dotenv

# Optional `supervisor/.env` for local hosting. Real environment variables win,
# so a service manager or a shell export still overrides the file.
load_dotenv(Path(__file__).with_name(".env"), override=False)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
CREDENTIAL_KEY = os.environ.get("SYNC_CREDENTIAL_KEY", "")
SUPERVISOR_TOKEN = os.environ.get("SYNC_SUPERVISOR_TOKEN", "")
APP_URL = os.environ.get("APP_URL", "https://mtl-trader.vercel.app").rstrip("/")
# Optional: path to terminal64.exe. Needed when more than one terminal is
# installed, or when the default install is not the one holding the account.
MT5_PATH = os.environ.get("MT5_PATH", "")
# A copied terminal must run portable, or it shares %APPDATA% and fights the
# trader's own terminal for the same instance.
MT5_PORTABLE = os.environ.get("MT5_PORTABLE", "").strip().lower() in ("1", "true", "yes")
CYCLE_SECONDS = int(os.environ.get("CYCLE_SECONDS", "15"))
REFRESH_SECONDS = int(os.environ.get("REFRESH_SECONDS", "60"))
# With exactly one connected account, the supervisor can stay logged in and
# poll history, which is the only way to journal a close in seconds without an
# EA on the terminal. Two accounts cannot share one terminal session, so the
# watch falls back to the normal rotation.
WATCH_SECONDS = float(os.environ.get("WATCH_SECONDS", "2"))
WATCH_WINDOW = timedelta(minutes=30)
OVERLAP = timedelta(minutes=15)
CHUNK = 200
TIMEOUT = 30

REST_HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
}


def fail(message):
    print(f"[fatal] {message}")
    sys.exit(1)


def check_config():
    missing = [
        name
        for name, value in (
            ("SUPABASE_URL", SUPABASE_URL),
            ("SUPABASE_SERVICE_ROLE_KEY", SERVICE_KEY),
            ("SYNC_CREDENTIAL_KEY", CREDENTIAL_KEY),
            ("SYNC_SUPERVISOR_TOKEN", SUPERVISOR_TOKEN),
        )
        if not value
    ]
    if missing:
        fail("missing environment: " + ", ".join(missing))
    if len(base64.b64decode(CREDENTIAL_KEY)) != 32:
        fail("SYNC_CREDENTIAL_KEY must decode to 32 bytes")


def decrypt_credential(blob):
    """Mirrors `src/lib/broker-credentials.ts`: v1:<iv>:<tag>:<ciphertext>."""
    parts = blob.split(":")
    if len(parts) != 4 or parts[0] != "v1":
        raise ValueError("unrecognised credential format")
    _, iv_b64, tag_b64, data_b64 = parts
    iv = base64.b64decode(iv_b64)
    tag = base64.b64decode(tag_b64)
    data = base64.b64decode(data_b64)
    return AESGCM(base64.b64decode(CREDENTIAL_KEY)).decrypt(iv, data + tag, None).decode("utf-8")


def claim():
    """
    Rows needing work: never attempted, or connected but stale.

    `connecting` rows are re-claimed because a supervisor that crashed mid-login
    would otherwise leave them stuck forever.
    """
    # `+00:00` in a hand-built URL is decoded as a space, which Postgres then
    # rejects as an invalid timestamp. Let `requests` encode the params; it
    # turns `+` into `%2B`.
    stale = (datetime.now(timezone.utc) - timedelta(seconds=REFRESH_SECONDS)).isoformat()
    params = {
        "select": (
            "user_id,broker_name,server,account_login,"
            "credential_cipher,status,last_sync_at"
        ),
        "or": (
            "(status.eq.pending,status.eq.connecting,"
            f"and(status.eq.connected,or(last_sync_at.is.null,last_sync_at.lt.{stale})))"
        ),
        "credential_cipher": "neq.",
        "limit": "10",
    }
    response = requests.get(
        f"{SUPABASE_URL}/rest/v1/broker_connections",
        headers=REST_HEADERS,
        params=params,
        timeout=TIMEOUT,
    )
    if response.status_code != 200:
        print(f"[warn] claim failed ({response.status_code}): {response.text[:200]}")
        return []
    return response.json()


def mark(user_id, status, error=None, synced_at=None):
    body = {"status": status, "updated_at": datetime.now(timezone.utc).isoformat()}
    if error is not None:
        # A provider message is useful to the customer; a stack trace is not.
        body["last_error"] = str(error)[:300]
    if synced_at:
        body["last_sync_at"] = synced_at
    requests.patch(
        f"{SUPABASE_URL}/rest/v1/broker_connections?user_id=eq.{user_id}",
        headers={**REST_HEADERS, "Prefer": "return=minimal"},
        data=json.dumps(body),
        timeout=TIMEOUT,
    )


def build_trade(position_id):
    """
    One fully closed position, or None.

    A position is included only when its closing volume covers its opening
    volume. The API ignores a duplicate `position_id`, so pushing a scale-out as
    if it were final would freeze a partial P&L forever.
    """
    group = mt5.history_deals_get(position=int(position_id))
    if not group:
        return None

    opens = [d for d in group if d.entry == 0]
    closes = [d for d in group if d.entry in (1, 2, 3)]
    if not opens or not closes:
        return None

    opened_volume = sum(d.volume for d in opens)
    closed_volume = sum(d.volume for d in closes)
    if closed_volume + 1e-6 < opened_volume:
        return None  # still open; a partial close is not a finished trade

    first_open = min(opens, key=lambda d: d.time)
    last_close = max(closes, key=lambda d: d.time)
    closed_at = datetime.fromtimestamp(last_close.time, timezone.utc)

    lot = round(min(opened_volume, closed_volume), 2)
    if lot <= 0:
        return None

    def weighted(items):
        volume = sum(d.volume for d in items)
        return sum(d.price * d.volume for d in items) / volume if volume else items[-1].price

    stop_loss, take_profit = 0.0, 0.0
    orders = mt5.history_orders_get(position=int(position_id)) or ()
    for order in orders:
        if order.sl:
            stop_loss, take_profit = float(order.sl), float(order.tp or 0)
            break

    return {
        "position_id": int(position_id),
        "ticket": int(last_close.ticket),
        "symbol": first_open.symbol,
        "type": "BUY" if first_open.type == 0 else "SELL",
        "entry_price": float(weighted(opens)),
        "exit_price": float(weighted(closes)),
        "lot_size": lot,
        "stop_loss": stop_loss,
        "take_profit": take_profit,
        "pnl": round(sum(d.profit + d.commission + d.swap for d in group), 2),
        "commission": round(sum(d.commission for d in group), 2),
        "swap": round(sum(d.swap for d in group), 2),
        "open_time": datetime.fromtimestamp(first_open.time, timezone.utc).isoformat(),
        "close_time": closed_at.isoformat(),
    }


def position_trades(since):
    """
    Closed positions changed since `since`, in the shape /api/sync expects.

    The cursor only finds *closing* deals. The full position is then fetched by
    id, because the opening deal of a trade held for longer than the 15-minute
    overlap is not in the cursor window. Building from the cursor alone silently
    dropped every trade that had been open for more than 15 minutes.
    """
    now = datetime.now(timezone.utc)
    window_start = since if since is not None else now - timedelta(days=365)
    recent = mt5.history_deals_get(window_start, now)
    if recent is None:
        raise RuntimeError(f"history_deals_get failed: {mt5.last_error()}")

    closing_ids = {
        deal.position_id
        for deal in recent
        if deal.position_id and deal.entry in (1, 2, 3)
    }

    trades = []
    for position_id in closing_ids:
        trade = build_trade(position_id)
        if not trade:
            continue
        if since is not None and datetime.fromisoformat(trade["close_time"]) < since:
            continue  # closed before the cursor; a previous cycle owns it
        trades.append(trade)

    trades.sort(key=lambda item: item["close_time"])
    return trades


def push(user_id, trades):
    for start in range(0, len(trades), CHUNK):
        chunk = trades[start:start + CHUNK]
        response = requests.post(
            f"{APP_URL}/api/sync",
            headers={"Authorization": f"Bearer {SUPERVISOR_TOKEN}", "Content-Type": "application/json"},
            data=json.dumps({"userId": user_id, "trades": chunk}),
            timeout=TIMEOUT,
        )
        if response.status_code not in (200, 202):
            raise RuntimeError(f"ingest rejected ({response.status_code}): {response.text[:160]}")
    return len(trades)


def open_session(row):
    """Attach to MT5 and log in. Raises with a message the customer can act on."""
    password = decrypt_credential(row["credential_cipher"])

    # Log in as part of `initialize`. A terminal with no saved account fails
    # `initialize()` with (-6, 'Terminal: Authorization failed') before a
    # separate `login()` is ever reached, so a plain initialize-then-login never
    # works on a fresh machine.
    session = {
        "login": int(row["account_login"]),
        "password": password,
        "server": row["server"],
    }
    if MT5_PATH:
        initialized = mt5.initialize(MT5_PATH, portable=MT5_PORTABLE, **session)
    else:
        initialized = mt5.initialize(**session)
    if not initialized:
        raise RuntimeError(
            f"MT5 initialise failed: {mt5.last_error()}. Open MT5 once and log in, "
            "or set MT5_PATH to terminal64.exe."
        )


def sync_one(row):
    user_id = row["user_id"]
    mark(user_id, "connecting")
    open_session(row)
    try:
        since = None
        if row.get("last_sync_at"):
            since = datetime.fromisoformat(row["last_sync_at"].replace("Z", "+00:00")) - OVERLAP
        else:
            # First sync after connecting. The terminal has just logged in and
            # may still be downloading history; a zero read here would advance
            # `last_sync_at` past real trades and the 15-minute cursor would
            # never look back far enough to find them.
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                probe = mt5.history_deals_get(
                    datetime.now(timezone.utc) - timedelta(days=7),
                    datetime.now(timezone.utc),
                )
                if probe:
                    break
                time.sleep(1)
        trades = position_trades(since)
        synced = push(user_id, trades) if trades else 0
        mark(user_id, "connected", error="", synced_at=datetime.now(timezone.utc).isoformat())
        print(f"  {user_id[:8]}… {row['server']} -> {synced} position(s)")
    finally:
        mt5.shutdown()


def single_connected():
    """The one connected account, if there is exactly one."""
    try:
        response = requests.get(
            f"{SUPABASE_URL}/rest/v1/broker_connections",
            headers=REST_HEADERS,
            params={
                "select": (
                    "user_id,broker_name,server,account_login,"
                    "credential_cipher,status,last_sync_at"
                ),
                "status": "eq.connected",
                "limit": "2",
            },
            timeout=TIMEOUT,
        )
    except requests.RequestException:
        return None
    if response.status_code != 200:
        return None
    rows = response.json()
    return rows[0] if len(rows) == 1 else None


def watch(row):
    """
    Stay logged in and journal a close within `WATCH_SECONDS`.

    Only valid with exactly one connected account: one terminal has one session,
    so two accounts cannot both be watched. Returns when another connection
    needs the terminal; the caller falls back to the rotation.
    """
    user_id = row["user_id"]
    open_session(row)
    try:
        now = datetime.now(timezone.utc)
        since = None
        if row.get("last_sync_at"):
            since = datetime.fromisoformat(
                row["last_sync_at"].replace("Z", "+00:00")
            ) - OVERLAP

        # Catch up once before watching, then treat everything already closed in
        # the window as seen. Partially closed positions are deliberately left
        # out: they are not a finished trade, and they must be retried when the
        # rest of the position closes.
        trades = position_trades(since)
        if trades:
            push(user_id, trades)
            mark(user_id, "connected", error="", synced_at=now.isoformat())
            print(f"  {user_id[:8]}… {row['server']} -> {len(trades)} position(s)")

        seen = {trade["position_id"] for trade in trades}
        seen.update(
            trade["position_id"] for trade in position_trades(now - WATCH_WINDOW)
        )
        print(
            f"  watching {user_id[:8]}… {row['server']} "
            f"(close latency ~{WATCH_SECONDS:.0f}s)"
        )

        last_claim = time.monotonic()
        while True:
            time.sleep(WATCH_SECONDS)
            tick = datetime.now(timezone.utc)
            recent = mt5.history_deals_get(tick - WATCH_WINDOW, tick) or []
            candidates = {
                deal.position_id
                for deal in recent
                if deal.position_id and deal.entry in (1, 2, 3)
            } - seen

            fresh = []
            for position_id in candidates:
                trade = build_trade(position_id)
                if not trade:
                    continue  # partial close; retry on the next tick
                fresh.append(trade)
                seen.add(position_id)

            if fresh:
                fresh.sort(key=lambda item: item["close_time"])
                push(user_id, fresh)
                mark(user_id, "connected", error="", synced_at=tick.isoformat())
                for trade in fresh:
                    print(
                        f"  {user_id[:8]}… closed {trade['symbol']} "
                        f"{trade['lot_size']} -> {trade['pnl']}"
                    )

            if time.monotonic() - last_claim >= CYCLE_SECONDS:
                last_claim = time.monotonic()
                try:
                    needs_work = [r for r in claim() if r["user_id"] != user_id]
                except requests.RequestException:
                    needs_work = []
                if needs_work:
                    return
    finally:
        mt5.shutdown()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    check_config()
    print("MTL Trader supervisor - polling for connections")

    while True:
        try:
            rows = claim()
        except requests.RequestException as error:
            print(f"[warn] could not reach Supabase: {error}")
            rows = []

        for row in rows:
            try:
                sync_one(row)
            except Exception as error:  # noqa: BLE001 - one account must not stop the rest
                print(f"  {row['user_id'][:8]}… failed: {error}")
                try:
                    mark(row["user_id"], "failed", error=error)
                except Exception:  # noqa: BLE001
                    pass

        if args.once:
            break

        if WATCH_SECONDS > 0:
            watched = single_connected()
            if watched:
                try:
                    watch(watched)
                except Exception as error:  # noqa: BLE001
                    print(f"  {watched['user_id'][:8]}… watch failed: {error}")
                    try:
                        mark(watched["user_id"], "failed", error=error)
                    except Exception:  # noqa: BLE001
                        pass
                continue

        time.sleep(CYCLE_SECONDS)


if __name__ == "__main__":
    main()
