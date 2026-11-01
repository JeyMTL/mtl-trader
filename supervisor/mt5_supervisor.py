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
    CYCLE_SECONDS         (default 120)
    REFRESH_SECONDS       (default 300 - how often a connected account is re-read)

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
from collections import defaultdict
from datetime import datetime, timedelta, timezone

import MetaTrader5 as mt5
import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
CREDENTIAL_KEY = os.environ.get("SYNC_CREDENTIAL_KEY", "")
SUPERVISOR_TOKEN = os.environ.get("SYNC_SUPERVISOR_TOKEN", "")
APP_URL = os.environ.get("APP_URL", "https://mtl-trader.vercel.app").rstrip("/")
CYCLE_SECONDS = int(os.environ.get("CYCLE_SECONDS", "120"))
REFRESH_SECONDS = int(os.environ.get("REFRESH_SECONDS", "300"))
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
    stale = (datetime.now(timezone.utc) - timedelta(seconds=REFRESH_SECONDS)).isoformat()
    query = (
        "broker_connections?select=user_id,broker_name,server,account_login,"
        "credential_cipher,status,last_sync_at"
        "&or=(status.eq.pending,status.eq.connecting,"
        f"and(status.eq.connected,or(last_sync_at.is.null,last_sync_at.lt.{stale})))"
        "&credential_cipher=neq.&limit=10"
    )
    response = requests.get(f"{SUPABASE_URL}/rest/v1/{query}", headers=REST_HEADERS, timeout=TIMEOUT)
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


def position_trades(since):
    """Closed positions changed since `since`, in the shape /api/sync expects."""
    deals = mt5.history_deals_get(since or datetime.now(timezone.utc) - timedelta(days=365),
                                 datetime.now(timezone.utc))
    if deals is None:
        raise RuntimeError(f"history_deals_get failed: {mt5.last_error()}")

    grouped = defaultdict(list)
    for deal in deals:
        if deal.position_id:
            grouped[deal.position_id].append(deal)

    trades = []
    for position_id, group in grouped.items():
        opens = [d for d in group if d.entry == 0]
        closes = [d for d in group if d.entry in (1, 2, 3)]
        if not opens or not closes:
            continue
        first_open = min(opens, key=lambda d: d.time)
        last_close = max(closes, key=lambda d: d.time)
        lot = round(min(sum(d.volume for d in opens), sum(d.volume for d in closes)), 2)
        if lot <= 0:
            continue

        def weighted(items):
            volume = sum(d.volume for d in items)
            return sum(d.price * d.volume for d in items) / volume if volume else items[-1].price

        stop_loss, take_profit = 0.0, 0.0
        orders = mt5.history_orders_get(position=int(position_id)) or ()
        for order in orders:
            if order.sl:
                stop_loss, take_profit = float(order.sl), float(order.tp or 0)
                break

        trades.append({
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
            "close_time": datetime.fromtimestamp(last_close.time, timezone.utc).isoformat(),
        })

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


def sync_one(row):
    user_id = row["user_id"]
    mark(user_id, "connecting")
    password = decrypt_credential(row["credential_cipher"])

    if not mt5.initialize():
        raise RuntimeError(f"MT5 initialise failed: {mt5.last_error()}")
    try:
        if not mt5.login(int(row["account_login"]), password=password, server=row["server"]):
            raise RuntimeError("login rejected - check the investor password and server name")

        since = None
        if row.get("last_sync_at"):
            since = datetime.fromisoformat(row["last_sync_at"].replace("Z", "+00:00")) - OVERLAP
        trades = position_trades(since)
        synced = push(user_id, trades) if trades else 0
        mark(user_id, "connected", error="", synced_at=datetime.now(timezone.utc).isoformat())
        print(f"  {user_id[:8]}… {row['server']} -> {synced} position(s)")
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
        time.sleep(CYCLE_SECONDS)


if __name__ == "__main__":
    main()
