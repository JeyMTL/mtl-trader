"""
MTL Ledger - hosted sync supervisor.

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
    APP_URL               (defaults to https://mtlledger.com)
    MT5_PATH              (optional - the terminal to try first)
    MT5_PATHS             (optional - more terminals, comma or semicolon separated;
                           any terminal64.exe under Program Files is found anyway)
    CYCLE_SECONDS         (default 15 - how often a new connection is claimed)
    REFRESH_SECONDS       (default 60 - how often a connected account is re-read)
    FAILED_RETRY_SECONDS  (default 600 - cooldown before a failed login is retried)
    HISTORY_WAIT_SECONDS  (default 90 - how long a first sync waits for the
                           terminal to finish downloading history)
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
import re
import sys
import time
import unicodedata
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
APP_URL = os.environ.get("APP_URL", "https://mtlledger.com").rstrip("/")
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
# How long a failed connection waits before the supervisor tries it again.
FAILED_RETRY_SECONDS = int(os.environ.get("FAILED_RETRY_SECONDS", "600"))
OVERLAP = timedelta(minutes=15)
CHUNK = 200
TIMEOUT = 30
# The terminal can need well over the module's 60s default to come up on a cold
# or history-loading host. A timeout there is not harmless: it leaves a
# half-started terminal that the module will not attach to again (every later
# call fails with "Process create failed"), so one slow start becomes a
# connection that never recovers. Wait longer before giving up.
INIT_TIMEOUT_MS = 120_000

# A fresh login answers "no deals" for a moment while the terminal downloads
# history in the background. Reading that as an empty account and advancing the
# cursor past it lost real trades permanently, so the first sync waits for the
# download before it decides anything.
HISTORY_WAIT_SECONDS = float(os.environ.get("HISTORY_WAIT_SECONDS", "90"))

# Deal and tick times arrive in the *broker's* clock, not UTC: FundedNext is
# UTC+2 in winter, most brokers are +2 or +3, and the EA already subtracts
# `TimeTradeServer() - TimeGMT()`. Python has no such call, so the offset is
# measured from live ticks and remembered per server.
SERVER_OFFSET_CACHE = Path(__file__).with_name(".server-offset.json")

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
    try:
        key_bytes = len(base64.b64decode(CREDENTIAL_KEY))
    except (ValueError, TypeError):
        fail("SYNC_CREDENTIAL_KEY is not valid base64")
    if key_bytes != 32:
        fail("SYNC_CREDENTIAL_KEY must decode to 32 bytes")
    # A path mangled by shell quoting (a stray \t is a tab, not a backslash and
    # a t) still "looks" right in the file. Catch it here, because the failure
    # otherwise surfaces as "Process create failed" from MT5 and reads like a
    # broken terminal.
    if MT5_PATH and not os.path.isfile(MT5_PATH):
        fail(
            f"MT5_PATH is not a file: {MT5_PATH!r}. Leave the value unquoted in "
            ".env, e.g. MT5_PATH=C:\\Program Files\\MetaTrader 5\\terminal64.exe"
        )
    if not BROKER_DIRECTORY:
        print(
            "[warn] mt5-brokers.json is missing beside the supervisor; known "
            "server spellings will not be corrected"
        )


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


STATUS_PRIORITY = {"pending": 0, "connecting": 1, "failed": 2, "connected": 3}


def prioritize_connections(rows):
    """Put new work before periodic refreshes.

    With several users, a batch of stale `connected` rows must not fill the
    claim limit and push a new `pending` account out; otherwise a new customer
    waits behind every existing one. `connecting` is included because a
    supervisor that died mid-login leaves that status behind.
    """
    return sorted(
        rows,
        key=lambda row: (
            STATUS_PRIORITY.get(row.get("status"), 9),
            row.get("last_sync_at") or "",
        ),
    )


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
    # A failure is often the terminal rather than the account: a cold start, a
    # history download, a transient "Process create failed". Retrying those after
    # a cooldown is what stops one bad minute from leaving the row unusable until
    # the customer disconnects and reconnects by hand.
    retry_failed = (datetime.now(timezone.utc) - timedelta(seconds=FAILED_RETRY_SECONDS)).isoformat()
    params = {
        "select": (
            "user_id,broker_name,server,account_login,"
            "credential_cipher,status,last_sync_at"
        ),
        "or": (
            "(status.eq.pending,status.eq.connecting,"
            f"and(status.eq.failed,updated_at.lt.{retry_failed}),"
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
    return prioritize_connections(response.json())


def mark(user_id, status, error=None, synced_at=None):
    body = {"status": status, "updated_at": datetime.now(timezone.utc).isoformat()}
    if error is not None:
        # A provider message is useful to the customer; a stack trace is not.
        body["last_error"] = str(error)[:300]
    if synced_at:
        body["last_sync_at"] = synced_at
    # Never write over a withdrawn connection. A trader who presses "Disconnect"
    # while a login is in flight wipes the credential and marks the row
    # `disconnected`; the attempt that was already running then reports its
    # failure, which used to land on top of that and leave a row saying
    # "Connection failed" for an account whose password no longer exists, and
    # whose error pointed at the terminal rather than at the disconnect.
    response = requests.patch(
        f"{SUPABASE_URL}/rest/v1/broker_connections?user_id=eq.{user_id}&status=neq.disconnected",
        headers={**REST_HEADERS, "Prefer": "return=minimal"},
        data=json.dumps(body),
        timeout=TIMEOUT,
    )
    # A rejected write used to be invisible: the row stayed on `connecting` and
    # the app showed that forever, with nothing in the log to explain it.
    if response.status_code >= 300:
        print(
            f"[warn] could not set {user_id[:8]}… to {status} "
            f"({response.status_code}): {response.text[:160]}"
        )


def symbol_digits(symbol):
    """How many decimals this symbol quotes, from the terminal itself."""
    try:
        info = mt5.symbol_info(symbol)
    except Exception:  # noqa: BLE001 - a missing symbol must not stop a sync
        info = None
    digits = getattr(info, "digits", None)
    if isinstance(digits, int) and 0 <= digits <= 8:
        return digits
    return 8


def build_trade(position_id, offset=0):
    """
    One fully closed position, or None.

    `offset` is the broker's clock ahead of UTC in seconds (see
    `server_offset`). Deal times are server time and the journal stores UTC, so
    every timestamp here is shifted back before it is sent; without that a trade
    closed at 15:00 server lands in the journal as 15:00 UTC, two or three hours
    early, and the calendar, the session stats and the day lock all read it wrong.

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
    opened_at = datetime.fromtimestamp(first_open.time - offset, timezone.utc)
    closed_at = datetime.fromtimestamp(last_close.time - offset, timezone.utc)

    lot = round(min(opened_volume, closed_volume), 2)
    if lot <= 0:
        return None

    def weighted(items):
        volume = sum(d.volume for d in items)
        return sum(d.price * d.volume for d in items) / volume if volume else items[-1].price

    # Prices are averaged out of deals in binary floating point, so 3595.738
    # arrives as 3595.7380000000003 and a gold average of 3587.887 lands on
    # 3587.8869999999997. Those digits are not a price: no instrument quotes 13
    # decimals, and the trader sees the noise in the journal. Round to the
    # symbol's own digits; eight is the fallback for a symbol the terminal does
    # not have in Market Watch, which is still far more precision than any MT5
    # instrument uses.

    stop_loss, take_profit = 0.0, 0.0
    orders = mt5.history_orders_get(position=int(position_id)) or ()
    for order in orders:
        if order.sl:
            stop_loss, take_profit = float(order.sl), float(order.tp or 0)
            break

    digits = symbol_digits(first_open.symbol)

    return {
        "position_id": int(position_id),
        "ticket": int(last_close.ticket),
        "symbol": first_open.symbol,
        "type": "BUY" if first_open.type == 0 else "SELL",
        "entry_price": round(weighted(opens), digits),
        "exit_price": round(weighted(closes), digits),
        "lot_size": round(lot, 3),
        "stop_loss": round(stop_loss, digits),
        "take_profit": round(take_profit, digits),
        "pnl": round(sum(d.profit + d.commission + d.swap for d in group), 2),
        "commission": round(sum(d.commission for d in group), 2),
        "swap": round(sum(d.swap for d in group), 2),
        "open_time": opened_at.isoformat(),
        "close_time": closed_at.isoformat(),
    }


def position_trades(since, offset=0):
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
        trade = build_trade(position_id, offset)
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


def notify(user_id, title, body):
    """Wake the customer's phone about a connection they cannot see failing.

    A phone-only customer has no terminal to look at, so a row that flips to
    `failed` on this host is invisible until they next open the app. Best effort
    by design: a missing notification must never turn into a failed sync.
    """
    try:
        requests.post(
            f"{APP_URL}/api/push/send",
            headers={
                "Authorization": f"Bearer {SUPERVISOR_TOKEN}",
                "Content-Type": "application/json",
            },
            data=json.dumps({"userId": user_id, "title": title, "body": body}),
            timeout=10,
        )
    except requests.RequestException:
        pass


def history_total(start, wait_seconds, pause=2.0):
    """
    How many deals the terminal holds in [start, now], waiting for a download.

    `history_deals_total` asks the server, so immediately after a fresh login it
    answers 0 while the terminal is still fetching that account's history and the
    real number arrives a second or two later. Treating that 0 as "this account
    has no trades" advanced `last_sync_at` past the window, and the 15-minute
    cursor never looked back far enough again: the trades were lost for good.
    Returns -1 if the terminal cannot answer, which says nothing about the
    account and must not be read as a zero.
    """
    deadline = time.monotonic() + max(0.0, wait_seconds)
    while True:
        total = mt5.history_deals_total(start, datetime.now(timezone.utc))
        if total > 0 or total < 0:
            return total
        if time.monotonic() >= deadline:
            return total
        time.sleep(pause)


def load_offset_cache():
    try:
        decoded = json.loads(SERVER_OFFSET_CACHE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def measure_server_offset(pause=3.0):
    """
    Seconds the broker's clock runs ahead of UTC, or None if unknowable.

    The offset is the difference between a tick's timestamp and this machine's
    clock. A frozen tick (weekend, market closed, symbol not in Market Watch)
    is indistinguishable from a real offset, so two ticks are taken three seconds
    apart: only a clock that moves with ours is evidence. Rounded to a quarter
    hour because broker offsets are always whole quarter hours.
    """
    for symbol in ("EURUSD", "XAUUSD", "GBPUSD"):
        try:
            first = mt5.symbol_info_tick(symbol)
            if first is None:
                continue
            time.sleep(pause)
            second = mt5.symbol_info_tick(symbol)
        except Exception:  # noqa: BLE001 - calibration is best effort
            return None
        if second is None:
            continue
        if 1 <= second.time - first.time <= 30:
            return int(round((second.time - time.time()) / 900.0) * 900)
    return None


def server_offset(row):
    """The broker offset for this account, measured at most once a day."""
    server = canonical_server_name(row.get("broker_name"), row["server"])
    cache = load_offset_cache()
    entry = cache.get(server)
    if not isinstance(entry, dict):
        entry = None
    today = datetime.now(timezone.utc).date().isoformat()
    if entry and entry.get("at") == today and isinstance(entry.get("offset"), int):
        return entry["offset"]

    measured = measure_server_offset()
    if measured is None:
        # Reuse the last good value: a weekend measurement would be a lie, and
        # guessing UTC would shift every trade by a couple of hours.
        return int(entry["offset"]) if entry and isinstance(entry.get("offset"), int) else 0

    cache[server] = {"offset": measured, "at": today}
    try:
        SERVER_OFFSET_CACHE.write_text(json.dumps(cache, indent=2), encoding="utf-8")
    except OSError:
        pass  # a read-only host just recalibrates on the next run
    return measured


# ---------------------------------------------------------------------------
# Terminal resolution
#
# One terminal install cannot be assumed to reach every broker: a prop-firm
# account is often on a server its own branded terminal resolves and a plain
# MetaQuotes install does not know, and a machine that hosts sync for several
# customers ends up with more than one terminal anyway. So the terminal is
# chosen per account: the one that worked for this account last time, then the
# configured ones, then anything installed in the usual places.
# ---------------------------------------------------------------------------
TERMINAL_CACHE = Path(__file__).with_name(".terminal-cache.json")


# ---------------------------------------------------------------------------
# Server spelling
#
# The app canonicalises a known server before saving it, but rows created
# before the directory existed still carry the typed spelling. The same table
# the app uses is shipped beside this script, so an old `FundedNext-Server3`
# row still logs in as `FundedNext-Server 3` without asking the customer to
# reconnect. Unknown servers are left exactly as saved; this is a correction,
# not a whitelist.
# ---------------------------------------------------------------------------

def normalize_broker_query(value):
    decomposed = unicodedata.normalize("NFD", str(value or ""))
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", " ", stripped.lower()).strip()


def load_broker_directory():
    candidates = (
        Path(__file__).with_name("mt5-brokers.json"),
        Path(__file__).resolve().parent.parent / "shared" / "mt5-brokers.json",
    )
    for path in candidates:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, list):
            return [
                entry
                for entry in data
                if isinstance(entry, dict) and entry.get("name")
            ]
    return []


BROKER_DIRECTORY = load_broker_directory()


def canonical_server_name(broker_name, server):
    target = normalize_broker_query(broker_name)
    if not target:
        return server

    exact = next(
        (
            entry
            for entry in BROKER_DIRECTORY
            if normalize_broker_query(entry["name"]) == target
            or any(
                normalize_broker_query(alias) == target
                for alias in entry.get("aliases") or []
            )
        ),
        None,
    )
    broker = exact or next(
        (
            entry
            for entry in BROKER_DIRECTORY
            if normalize_broker_query(entry["name"]).startswith(target)
            or any(
                normalize_broker_query(alias).startswith(target)
                for alias in entry.get("aliases") or []
            )
        ),
        None,
    )
    if not broker:
        return server

    key = normalize_broker_query(server).replace(" ", "")
    if not key:
        return server
    matches = [
        candidate
        for candidate in broker.get("servers") or []
        if normalize_broker_query(candidate).replace(" ", "") == key
    ]
    return matches[0] if len(matches) == 1 else server


TERMINAL_SCAN_DEPTH = 3
TERMINAL_SCAN_TTL = 60
_SKIP_INSTALL_DIRS = {
    "common files",
    "modifiablewindowsapps",
    "windows defender",
    "windowsapps",
}


def is_retired_install(name):
    """A terminal the MT5 updater renamed rather than deleted.

    An update moves the old install to `MetaTrader 5.old6324` and leaves it
    runnable. Logging in there logs the customer into a terminal that will never
    update and lives outside the install the customer manages, and it turns one
    broken attempt into two in the message they are shown.
    """
    lowered = name.lower()
    return any(
        marker in lowered
        for marker in (".old", "-backup", "_backup", " backup", "-copy", " copy")
    )
_terminal_scan = {"roots": (), "at": 0.0, "paths": []}


def discover_terminals(force=False):
    """terminal64.exe under the usual install roots, including nested ones.

    Broker and prop-firm installers do not agree on a layout: some put
    terminal64.exe directly under Program Files, others nest it under a vendor
    or product folder. Walk a few levels deep so a branded terminal is found
    without requiring MT5_PATHS, but stop early and cache the result because
    this runs for every login.
    """
    roots = tuple(
        root
        for root in (
            os.environ.get("ProgramFiles"),
            os.environ.get("ProgramFiles(x86)"),
            os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs"),
        )
        if root and os.path.isdir(root)
    )
    now = time.monotonic()
    if (
        not force
        and _terminal_scan["roots"] == roots
        and now - _terminal_scan["at"] < TERMINAL_SCAN_TTL
    ):
        return list(_terminal_scan["paths"])

    found = []
    for root in roots:
        for current, dirs, files in os.walk(root):
            relative = os.path.relpath(current, root)
            depth = 0 if relative == "." else relative.count(os.sep) + 1
            if depth >= TERMINAL_SCAN_DEPTH:
                dirs[:] = []
            else:
                dirs[:] = sorted(
                    name
                    for name in dirs
                    if name.lower() not in _SKIP_INSTALL_DIRS
                    and not is_retired_install(name)
                )
            if "terminal64.exe" not in files:
                continue
            candidate = os.path.join(current, "terminal64.exe")
            if candidate not in found:
                found.append(candidate)

    _terminal_scan.update({"roots": roots, "at": now, "paths": list(found)})
    return found


def configured_terminals():
    """Every terminal we may try, without duplicates, configured ones first."""
    paths = []

    def add(value):
        value = (value or "").strip().strip('"')
        if value and os.path.isfile(value) and value not in paths:
            paths.append(value)

    add(MT5_PATH)
    for raw in os.environ.get("MT5_PATHS", "").replace(";", ",").split(","):
        add(raw)
    for path in discover_terminals():
        add(path)
    return paths


def load_terminal_cache():
    try:
        decoded = json.loads(TERMINAL_CACHE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def remember_terminal(key, path):
    """Lets the next cycle skip straight to the terminal that worked."""
    cache = load_terminal_cache()
    if cache.get(key) == path:
        return
    cache[key] = path
    try:
        TERMINAL_CACHE.write_text(json.dumps(cache, indent=2), encoding="utf-8")
    except OSError:
        pass  # a read-only host just tries them in order every time


def terminal_key(row):
    server = canonical_server_name(row.get("broker_name"), row["server"])
    return f"{row.get('broker_name') or ''}|{server}".lower()


def terminal_order(row):
    """Candidate terminals for this account, best first. Empty means the
    module's own default install, which is the right choice on a host with one."""
    configured = configured_terminals()
    if not configured:
        return []
    remembered = load_terminal_cache().get(terminal_key(row))
    order = []
    if remembered and os.path.isfile(remembered):
        order.append(remembered)
    for path in configured:
        if path not in order:
            order.append(path)
    return order


def initialize_terminal(session, path):
    if path is None:
        return mt5.initialize(timeout=INIT_TIMEOUT_MS, **session)
    return mt5.initialize(
        path, portable=MT5_PORTABLE, timeout=INIT_TIMEOUT_MS, **session
    )


def open_session(row):
    """Attach to MT5 and log in, trying every installed terminal until one can.

    Raises with a message the customer can act on, listing what was tried. A
    terminal that comes up but is logged into a *different* account is rejected
    too: on a host that serves several customers that terminal would stream the
    wrong account's trades into this journal.
    """
    password = decrypt_credential(row["credential_cipher"])

    # Log in as part of `initialize`. A terminal with no saved account fails
    # `initialize()` with (-6, 'Terminal: Authorization failed') before a
    # separate `login()` is ever reached, so a plain initialize-then-login never
    # works on a fresh machine.
    login = int(row["account_login"])
    server = canonical_server_name(row.get("broker_name"), row["server"])
    session = {"login": login, "password": password, "server": server}
    key = terminal_key(row)

    attempts = []
    for path in terminal_order(row) or [None]:
        for _ in range(2):  # one retry: a stale terminal often clears on shutdown
            initialized = initialize_terminal(session, path)
            if initialized:
                info = mt5.account_info()
                if info is not None and int(info.login) == login:
                    remember_terminal(key, path or "")
                    return
                attempts.append(
                    (
                        path or "default install",
                        f"logged in as account {getattr(info, 'login', 'unknown')}"
                        f" instead of {login}",
                    )
                )
                mt5.shutdown()
                break  # a different account is not a stale-terminal problem
            error = mt5.last_error()
            attempts.append((path or "default install", str(error)))
            mt5.shutdown()
            # Only a terminal-side failure is worth a second try; a rejected
            # password or an unknown server answers the same way twice.
            if "IPC timeout" not in str(error) and "Process create failed" not in str(error):
                break

    tried = "; ".join(f"{where} -> {why}" for where, why in attempts)
    raise RuntimeError(
        f"no terminal could log in to {server} as {login} ({tried}). "
        "Install the broker's own terminal and list it in MT5_PATHS, or open MT5 "
        "once by hand, log in, and close it."
    )



def sync_one(row):
    user_id = row["user_id"]
    mark(user_id, "connecting")
    try:
        open_session(row)
        offset = server_offset(row)
        since = None
        if row.get("last_sync_at"):
            since = datetime.fromisoformat(row["last_sync_at"].replace("Z", "+00:00")) - OVERLAP
        else:
            # First sync after connecting: read the whole year, and only once the
            # terminal has actually downloaded it. A zero here used to be taken
            # as "this account never traded", which advanced the cursor and lost
            # every trade the terminal was still fetching.
            lookback = datetime.now(timezone.utc) - timedelta(days=365)
            found = history_total(lookback, HISTORY_WAIT_SECONDS)
            if found < 0:
                raise RuntimeError(f"terminal could not read history: {mt5.last_error()}")
            if found == 0:
                print(
                    f"  {user_id[:8]}… no deals in the last 365 days after waiting "
                    f"{HISTORY_WAIT_SECONDS:.0f}s; marking it synced. "
                    "Press Reconnect if trades are missing."
                )
        trades = position_trades(since, offset)
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
                # A disconnected row has its credential wiped; holding the
                # terminal open on one only delays the next real login.
                "credential_cipher": "neq.",
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


def connection_state(user_id):
    """
    The current status of one account's connection, or None if unreadable.

    The watch loop asks for it every cycle. `disconnect` in the app sets the row
    to `disconnected` and a reconnect sets it back to `pending`, but either way
    this process is still holding the terminal's only session. Noticing that here
    is what releases the terminal so the new login can have it.
    """
    try:
        response = requests.get(
            f"{SUPABASE_URL}/rest/v1/broker_connections",
            headers=REST_HEADERS,
            params={
                "select": "status,credential_cipher",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
            timeout=TIMEOUT,
        )
    except requests.RequestException:
        return None
    if response.status_code != 200:
        return None
    rows = response.json()
    return rows[0] if rows else None


def must_release(user_id, state, claimed):
    """
    Whether the watch loop has to hand the terminal back.

    Two things end a watch: the account is no longer connected (the customer
    disconnected, or a reconnect reset the row to `pending`), or some other row
    needs the terminal. The **reconnect case** is the subtle one — it is the same
    account, so a check that only looks at other users would keep the session open
    and leave the app on "connecting" forever, which is exactly what it used to
    do. Only the watched `connected` row itself is ignored; a `pending` row for
    this same account is a new attempt that needs the terminal.
    """
    if state is None or state.get("status") != "connected":
        return True
    return any(
        row["user_id"] != user_id or row.get("status") == "pending"
        for row in claimed
    )


def watch(row):
    """
    Stay logged in and journal a close within `WATCH_SECONDS`.

    Only valid with exactly one connected account: one terminal has one session,
    so two accounts cannot both be watched. Returns when another connection
    needs the terminal; the caller falls back to the rotation.
    """
    user_id = row["user_id"]
    try:
        open_session(row)
        offset = server_offset(row)
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
        trades = position_trades(since, offset)
        if trades:
            push(user_id, trades)
            mark(user_id, "connected", error="", synced_at=now.isoformat())
            print(f"  {user_id[:8]}… {row['server']} -> {len(trades)} position(s)")

        seen = {trade["position_id"] for trade in trades}
        seen.update(
            trade["position_id"] for trade in position_trades(now - WATCH_WINDOW, offset)
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
                trade = build_trade(position_id, offset)
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
                # The account may have been disconnected, or disconnected and
                # reconnected, while this session was open. Both show up as a
                # status that is no longer `connected`, and both have to let go
                # of the terminal: it has one session, and the new login needs it.
                state = connection_state(user_id)
                try:
                    claimed = claim()
                except requests.RequestException:
                    claimed = []
                if must_release(user_id, state, claimed):
                    current_status = (state or {}).get("status")
                    print(
                        f"  {user_id[:8]}… connection is {current_status or 'gone'} "
                        "or work is waiting; releasing the terminal"
                    )
                    return
    finally:
        mt5.shutdown()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    check_config()
    print("MTL Ledger supervisor - polling for connections")

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
                # One notification per breakdown, not one every ten minutes: a
                # row that is already `failed` is being retried, not news.
                if row.get("status") != "failed":
                    notify(
                        row["user_id"],
                        "MT5 sync stopped",
                        f"{row.get('server') or 'Your broker'} could not be read. "
                        "Open the app to reconnect.",
                    )

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
                    notify(
                        watched["user_id"],
                        "MT5 sync stopped",
                        f"{watched.get('server') or 'Your broker'} could not be read. "
                        "Open the app to reconnect.",
                    )
                continue

        time.sleep(CYCLE_SECONDS)


if __name__ == "__main__":
    main()
