"""
MTL Ledger - hosted sync supervisor.

This is the service that makes "connect automatically" real for customers who
only have a phone: they paste their investor (read-only) password in the app, and
this runs on our own Windows host, logs into MT5 with it, and posts closed trades
to /api/sync.

Design notes:

  * **One terminal, sequential sessions.** The MetaTrader5 package talks to a
    local terminal over IPC, and a terminal has one session, so by default we
    log in, read, and move on: 40 accounts cost a few seconds each per cycle and
    share a single terminal. That is what makes the cheap tier work.
  * **Or a fleet, when latency matters (FLEET_SIZE).** A close can only be
    journaled in seconds if something is still logged in when it happens, and
    one session cannot watch two accounts. With FLEET_SIZE=n, n accounts get
    their own terminal directory and their own worker process, so n sessions
    run at once. Measured cost per chartless terminal: ~140 MB working set and
    ~2.5% of one core, so 4 vCPU / 8 GB carries about 30 of them.
  * **One host owns a share, not everything.** Two hosts pointed at the same
    project both see every pending row, because the claim is a plain GET and
    PostgREST has no `for update skip locked`. Each host keeps only the accounts
    whose hash it owns, so the work stays disjoint without a schema change.
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
    SUPERVISOR_SHARDS     (default 1 - how many hosts share the account list)
    SUPERVISOR_SHARD      (default 0 - which share this host serves)
    MAX_ACCOUNTS          (default 0 - most accounts worked per cycle; 0 = no cap)
    FLEET_SIZE            (default 0 - terminals held open at once, one account
                           each; 0 keeps the sequential single-terminal mode)
    MT5_FLEET_DIRS        (needed when FLEET_SIZE > 0 - one directory or
                           terminal64.exe per slot, comma or semicolon separated)
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
import multiprocessing as mp
import os
import queue
import re
import sys
import time
import unicodedata
import zlib
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
# How many hosts share the account list, and which share this one serves. A
# single host is the default and takes everything.
SUPERVISOR_SHARDS = max(1, int(os.environ.get("SUPERVISOR_SHARDS", "1")))
SUPERVISOR_SHARD = int(os.environ.get("SUPERVISOR_SHARD", "0"))
# How many accounts one host will work on per cycle. This is a brake, not a load
# balancer: it keeps a small host inside its refresh budget instead of quietly
# stretching REFRESH_SECONDS for everyone. 0 means no cap.
MAX_ACCOUNTS = max(0, int(os.environ.get("MAX_ACCOUNTS", "0")))
# How many terminals stay open, one account each. 0 is the sequential mode: one
# session, taken in turns. Above 0, each slot owns a terminal *directory* (two
# copies cannot run from one directory) and a process (the package keeps one IPC
# connection per process), so accounts are watched at the same time instead of
# waiting for a turn. MT5_FLEET_DIRS lists those directories, one per slot.
FLEET_SIZE = max(0, int(os.environ.get("FLEET_SIZE", "0")))
MT5_FLEET_DIRS = os.environ.get("MT5_FLEET_DIRS", "")
# A slot keeps its account while watching, so with every slot taken a new
# sign-in would wait forever. Once a slot has watched for this long and another
# account is waiting for a terminal, it hands its account back to the rotation.
# Long enough that a busy account is not interrupted, short enough that a
# spare account gets a turn within a cycle or two.
FLEET_MIN_HOLD_SECONDS = float(os.environ.get("FLEET_MIN_HOLD_SECONDS", "60"))
# The claim sorts by least recently synced, so a capped host rotates through a
# backlog instead of serving the same few accounts forever.
CAPACITY_WARN_SECONDS = 300
_capacity_warned_at = 0.0
# With exactly one connected account, the supervisor can stay logged in and
# poll history, which is the only way to journal a close in seconds without an
# EA on the terminal. Two accounts cannot share one terminal session, so the
# watch falls back to the normal rotation.
WATCH_SECONDS = float(os.environ.get("WATCH_SECONDS", "2"))
WATCH_WINDOW = timedelta(minutes=30)
# The daily stop, as this host can enforce it. The server decides whether the day
# is locked (`/api/ea/lock`, the same answer the guard EA gets); this process can
# only do what a client-side program can do, which is remove resting orders. It
# deliberately never closes an open position: that costs the trader the spread
# and the slippage, and a sync daemon is the wrong place to make that call.
ENFORCE_LOCK = os.environ.get("ENFORCE_LOCK", "1").lower() not in ("0", "false", "no")
LOCK_POLL_SECONDS = int(os.environ.get("LOCK_POLL_SECONDS", "30"))
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
    # A shard outside the range would serve nobody, silently, and every account
    # it should have owned would go stale.
    if not 0 <= SUPERVISOR_SHARD < SUPERVISOR_SHARDS:
        fail(
            f"SUPERVISOR_SHARD must be 0..{SUPERVISOR_SHARDS - 1} when "
            f"SUPERVISOR_SHARDS={SUPERVISOR_SHARDS}, got {SUPERVISOR_SHARD}"
        )
    # A path mangled by shell quoting (a stray \t is a tab, not a backslash and
    # a t) still "looks" right in the file. Catch it here, because the failure
    # otherwise surfaces as "Process create failed" from MT5 and reads like a
    # broken terminal.
    if MT5_PATH and not os.path.isfile(MT5_PATH):
        fail(
            f"MT5_PATH is not a file: {MT5_PATH!r}. Leave the value unquoted in "
            ".env, e.g. MT5_PATH=C:\\Program Files\\MetaTrader 5\\terminal64.exe"
        )
    # A fleet slot with no terminal of its own silently does nothing, and the
    # account assigned to it is never read - fail loudly instead.
    if FLEET_SIZE:
        available = fleet_terminals()
        if len(available) < FLEET_SIZE:
            fail(
                f"FLEET_SIZE={FLEET_SIZE} needs {FLEET_SIZE} terminals in "
                f"MT5_FLEET_DIRS, found {len(available)}. Run "
                f"supervisor/setup_fleet.ps1 -Count {FLEET_SIZE} and paste its "
                "output into .env"
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


def shard_of(user_id):
    """Which share of the accounts owns this connection.

    crc32 rather than hash(): string hashing is salted per process, so two hosts
    would disagree about who owns an account and both would take it.
    """
    return zlib.crc32(str(user_id).encode("utf-8")) % SUPERVISOR_SHARDS


def owns(user_id):
    return SUPERVISOR_SHARDS == 1 or shard_of(user_id) == SUPERVISOR_SHARD


def owned_by_this_host(rows):
    """Drop other hosts' accounts, then stay inside this host's budget.

    `rows` arrives least urgent first by status, then least recently synced, so
    truncating to MAX_ACCOUNTS rotates a backlog rather than pinning the same
    accounts every cycle.
    """
    global _capacity_warned_at
    if SUPERVISOR_SHARDS > 1:
        rows = [row for row in rows if shard_of(row["user_id"]) == SUPERVISOR_SHARD]
    if MAX_ACCOUNTS and len(rows) > MAX_ACCOUNTS:
        now = time.monotonic()
        if now - _capacity_warned_at >= CAPACITY_WARN_SECONDS:
            _capacity_warned_at = now
            print(
                f"[capacity] {len(rows)} accounts need this host, serving "
                f"{MAX_ACCOUNTS} per cycle: raise MAX_ACCOUNTS, "
                "REFRESH_SECONDS, or add a host"
            )
        rows = rows[:MAX_ACCOUNTS]
    return rows


def claim():
    """
    Rows needing work this host owns: never attempted, or connected but stale.

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
        # Enough rows to fill a cycle after the split, so two hosts do not
        # starve each other by each reading ten rows the other one owns. A fleet
        # needs one row per slot or the extra terminals would never be filled.
        "limit": str(max(10, FLEET_SIZE) * SUPERVISOR_SHARDS),
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
    return owned_by_this_host(prioritize_connections(response.json()))


def mark(user_id, status, error=None, synced_at=None):
    # Syncing again is the only proof the plan is back, so it also re-arms the
    # "paused" notice for the next time the subscription does lapse.
    if status == "connected":
        forget_lapse(user_id)
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


# How often to ask the API whether a playbook reminder is due. A minute is well
# inside the shortest lead time the app offers (5 minutes), and the API dedupes
# per session start, so asking more often costs a query and sends nothing extra.
SESSION_REMINDER_SECONDS = int(os.environ.get("SESSION_REMINDER_SECONDS", "60"))
_last_session_check = 0.0


def session_reminders():
    """Let the API push a session reminder that is due, at most once a minute.

    The reminder itself belongs to the web app's playbook maths, which the phone
    also mirrors for its own alarms. What the phone cannot do is remind somebody
    whose alarms the OS dropped, or who has not opened the app since the session
    was added — and what the daily cron cannot do is fire at 14:00. This host is
    running anyway, so it is the cheap place to ask.

    Best effort: a failure here is one missed reminder, never a sync problem.
    """
    global _last_session_check
    now = time.monotonic()
    if now < _last_session_check:
        return
    _last_session_check = now + SESSION_REMINDER_SECONDS
    try:
        requests.post(
            f"{APP_URL}/api/push/sessions",
            headers={"Authorization": f"Bearer {SUPERVISOR_TOKEN}"},
            timeout=10,
        )
    except requests.RequestException:
        pass


# MT5 order types that rest on the book rather than fill a position: BUY_LIMIT,
# SELL_LIMIT, BUY_STOP, SELL_STOP, BUY_STOP_LIMIT, SELL_STOP_LIMIT. The numeric
# values come from the MQL5 enum, which is why they are not looked up on `mt5`:
# a test that stubs the module should not have to reimplement the constants.
PENDING_ORDER_TYPES = frozenset({2, 3, 4, 5, 6, 7})
TRADE_ACTION_REMOVE = 8
TRADE_RETCODE_DONE = 10009

_lock_checked_at = {}


def pending_tickets(orders):
    """Tickets of the resting orders a lock is allowed to cancel."""
    return [
        int(order.ticket)
        for order in orders or []
        if getattr(order, "type", None) in PENDING_ORDER_TYPES
    ]


_agent_tokens = {}


def agent_token_for(user_id):
    """The account's EA token, which lives on `users`, not on the connection.

    Cached because the watchdog asks for a lock every 30s per account and the
    token only changes when the customer connects a terminal again.
    """
    if user_id in _agent_tokens:
        return _agent_tokens[user_id]
    try:
        response = requests.get(
            f"{SUPABASE_URL}/rest/v1/users",
            params={"select": "agent_token", "id": f"eq.{user_id}"},
            headers=REST_HEADERS,
            timeout=TIMEOUT,
        )
        if response.status_code != 200:
            return ""  # an outage is not an answer; the next poll tries again
        rows = response.json()
    except (requests.RequestException, ValueError):
        return ""
    token = (rows[0].get("agent_token") or "") if rows else ""
    if token:
        # Only a real token is worth remembering: caching empty would hide the
        # customer connecting a terminal a minute later.
        _agent_tokens[user_id] = token
    return token


def lock_state(row):
    """Today's lock, exactly as the server answers the guard EA.

    `None` means "could not tell", and every caller treats that as unlocked. An
    outage must never leave a trader unable to close a position, which is the
    same fail-open the EA takes.
    """
    token = row.get("agent_token") or agent_token_for(row["user_id"])
    if not token:
        # No EA token means the customer never connected a terminal by hand; the
        # supervisor cannot pretend to be one.
        return None
    try:
        response = requests.get(
            f"{APP_URL}/api/ea/lock",
            params={"userId": row["user_id"]},
            headers={"Authorization": f"Bearer {token}"},
            timeout=TIMEOUT,
        )
    except requests.RequestException:
        return None
    if response.status_code != 200:
        return None
    try:
        return response.json()
    except ValueError:
        return None


def enforce_lock(row):
    """Cancel resting orders while the daily stop holds.

    The half of the guard EA that a supervisor-synced account would otherwise be
    missing: the trades arrive here, the server decides the day is over, and
    nobody on the terminal is listening. This runs from the watch loop, so it
    only acts while a session is actually open, and at most once per
    `LOCK_POLL_SECONDS` per account.

    Returns the number of orders cancelled.
    """
    if not ENFORCE_LOCK:
        return 0
    user_id = row["user_id"]
    now = time.monotonic()
    if now < _lock_checked_at.get(user_id, 0.0):
        return 0
    _lock_checked_at[user_id] = now + LOCK_POLL_SECONDS

    state = lock_state(row)
    if not state or not state.get("locked"):
        return 0

    try:
        tickets = pending_tickets(mt5.orders_get() or [])
    except Exception:  # noqa: BLE001 - a refusal here must not stop the watch
        return 0

    cancelled = 0
    for ticket in tickets:
        try:
            result = mt5.order_send({"action": TRADE_ACTION_REMOVE, "order": ticket})
        except Exception:  # noqa: BLE001
            continue
        if getattr(result, "retcode", None) == TRADE_RETCODE_DONE:
            cancelled += 1
    if tickets:
        reason = state.get("reason") or "daily stop active"
        print(
            f"  {user_id[:8]}… {reason} - cancelled {cancelled}/{len(tickets)} pending order(s)"
        )
    return cancelled


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


def fleet_terminals():
    """One terminal64.exe per fleet slot, in the order MT5_FLEET_DIRS lists them.

    An entry may be a directory or a terminal64.exe, so the same value works
    whether it was copied from Explorer or from setup_fleet.ps1. Order decides
    which slot owns which terminal, and a slot keeps its terminal, so a warm
    terminal stays warm across restarts.
    """
    terminals = []
    for raw in re.split(r"[;,]", MT5_FLEET_DIRS):
        entry = raw.strip().strip('"')
        if not entry:
            continue
        path = os.path.join(entry, "terminal64.exe") if os.path.isdir(entry) else entry
        if os.path.isfile(path) and path not in terminals:
            terminals.append(path)
    return terminals


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


# The two keys MT5 reads from `<terminal>/config/common.ini` before it will let a
# program send an order. `AllowLiveTrading` is the Expert Advisors tab setting and
# `Enabled` is the toolbar Algo Trading button; without both, `order_send` answers
# 10027 (TRADE_RETCODE_CLIENT_DISABLES_AT) and nothing can be cancelled or closed.
ALGO_TRADING_KEYS = (("AllowLiveTrading", "1"), ("Enabled", "1"))


def terminal_config_path(path, portable):
    """Where this terminal keeps `common.ini`, or None when it is not ours to edit.

    A portable terminal (every fleet slot) keeps its config beside the exe. A
    normal install keeps it under `%APPDATA%/MetaQuotes/Terminal/<hash>`, whose
    hash is only knowable after the terminal has started once, so that case
    is left alone rather than guessed at.
    """
    if not path:
        return None
    folder = Path(path).parent
    candidates = [folder / "config" / "common.ini"]
    if not portable:
        return None
    for candidate in candidates:
        if candidate.parent.is_dir():
            return candidate
    return None


def looks_portable(path):
    """A terminal directory with its own `config` folder is a portable install.

    The fleet slots are, and so is a `MT5_PATH` someone points at one: starting
    those non-portable reads `%APPDATA%` instead and silently loses the settings
    written beside the exe.
    """
    return bool(path) and (Path(path).parent / "config" / "common.ini").exists()


def ensure_algo_trading(config_path):
    """Turn programmatic trading on in a terminal's config, before it starts.

    This is the one MT5 setting a headless host cannot click, and without it the
    daily-stop enforcement and anything the guard EA does are dead on arrival.
    The file is rewritten by hand rather than with `configparser` because MT5's
    ini is not strict and must survive untouched: only the two keys inside
    `[Experts]` are added or corrected.

    Returns True when the file already said what we need, False when it was
    changed (so the caller restarts rather than attaching to a stale process).
    """
    if config_path is None:
        return True
    config_path = Path(config_path)
    if not config_path.exists():
        return True
    lines = config_path.read_text(encoding="utf-8", errors="ignore").splitlines()

    wanted = dict(ALGO_TRADING_KEYS)
    out = []
    in_experts = False
    seen_experts = False
    changed = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_experts:
                # Close the section by adding whatever it was missing.
                for key, value in ALGO_TRADING_KEYS:
                    if key in wanted:
                        out.append(f"{key}={value}")
                        wanted.pop(key)
                        changed = True
            in_experts = stripped == "[Experts]"
            seen_experts = seen_experts or in_experts
            out.append(line)
            continue
        if in_experts:
            key = stripped.split("=", 1)[0]
            if key in wanted:
                if stripped == f"{key}={wanted[key]}":
                    wanted.pop(key)
                else:
                    out.append(f"{key}={wanted[key]}")
                    wanted.pop(key)
                    changed = True
                continue
        out.append(line)

    if in_experts:
        for key, value in ALGO_TRADING_KEYS:
            if key in wanted:
                out.append(f"{key}={value}")
                wanted.pop(key)
                changed = True
    if not seen_experts:
        out += ["", "[Experts]"] + [f"{key}={value}" for key, value in ALGO_TRADING_KEYS]
        changed = True

    if changed:
        config_path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return not changed


def initialize_terminal(session, path, portable=None):
    # Written before the terminal starts: once it is running, it owns the file and
    # rewrites it on exit, so a late edit is lost.
    if path is not None:
        ensure_algo_trading(terminal_config_path(path, MT5_PORTABLE if portable is None else portable))
    if path is None:
        return mt5.initialize(timeout=INIT_TIMEOUT_MS, **session)
    return mt5.initialize(
        path,
        portable=MT5_PORTABLE if portable is None else portable,
        timeout=INIT_TIMEOUT_MS,
        **session,
    )


def open_session(row, terminal=None):
    """Attach to MT5 and log in, trying every installed terminal until one can.

    Raises with a message the customer can act on, listing what was tried. A
    terminal that comes up but is logged into a *different* account is rejected
    too: on a host that serves several customers that terminal would stream the
    wrong account's trades into this journal.

    `terminal` pins the attempt to one terminal64.exe, which is what a fleet
    slot does: that directory is this account's terminal and nothing else's.
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
    candidates = [terminal] if terminal else (terminal_order(row) or [None])
    for path in candidates:
        # A fleet terminal is always portable: its accounts, history and config
        # belong to that slot and must not leak into %APPDATA% or another slot.
        portable = True if terminal or looks_portable(path) else None
        for _ in range(2):  # one retry: a stale terminal often clears on shutdown
            initialized = initialize_terminal(session, path, portable)
            if initialized:
                info = mt5.account_info()
                if info is not None and int(info.login) == login:
                    warn_if_no_algo_trading(path)
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



_algo_warned = set()


def warn_if_no_algo_trading(path):
    """Say it once per terminal when orders are impossible, instead of silently
    cancelling nothing every 30 seconds when a lock is due."""
    try:
        info = mt5.terminal_info()
    except Exception:  # noqa: BLE001
        return
    if info is None:
        return
    where = path or "default install"

    if not getattr(info, "trade_allowed", False):
        if where not in _algo_warned:
            _algo_warned.add(where)
            print(
                f"[warn] {where} does not allow programmatic orders, so the daily "
                "stop cannot cancel anything on this terminal. Enable Algo Trading "
                "in Tools > Options > Expert Advisors (the supervisor writes it into "
                "a portable terminal's config, but an install under %APPDATA% has "
                "to be set by hand)."
            )
        return

    # The terminal is fine but the *account* is read-only: an investor password
    # logs in, syncs and read exactly like the master one, and only refuses when an
    # order is attempted (10017 Trade disabled). Saving the warning separately
    # means the two are reported independently.
    key = f"{where}:account"
    if key in _algo_warned:
        return
    try:
        account = mt5.account_info()
    except Exception:  # noqa: BLE001
        return
    if account is None or getattr(account, "trade_allowed", True):
        return
    _algo_warned.add(key)
    print(
        f"[warn] account {getattr(account, 'login', '?')} is read-only (investor "
        "password), so the daily stop cannot cancel anything on it either. Save the "
        "account's master password to let the lock act."
    )


def terminal_session_lost():
    """Whether the terminal we are attached to has dropped its broker session.

    A watching terminal reads an empty deal history both when nothing closed and
    when the session is gone, so without this check a dropped login looks like a
    quiet account: the row stays `connected` and nothing is journaled. Weekends,
    broker restarts and terminal updates all drop the session.
    """
    try:
        info = mt5.terminal_info()
    except Exception:  # noqa: BLE001 - a dead IPC pipe is a lost session too
        return True
    if info is None:
        return True
    return getattr(info, "connected", True) is False


def relogin(row):
    """Log the attached terminal back in, without restarting it.

    Re-logging in place keeps the slot warm: a full re-login through
    `open_session` costs a terminal start and a mode switch, while this costs one
    auth round trip.
    """
    try:
        password = decrypt_credential(row["credential_cipher"])
    except Exception:  # noqa: BLE001 - a bad blob needs a new connect from the app
        return False
    server = canonical_server_name(row.get("broker_name"), row["server"])
    try:
        return bool(
            mt5.login(int(row["account_login"]), password=password, server=server)
        )
    except Exception:  # noqa: BLE001
        return False


def read_closed(row):
    """Read this account's closed positions since the cursor, push, and mark.

    Assumes a session is already open, so a fleet worker can read without
    closing the terminal it is about to watch through.
    """
    user_id = row["user_id"]
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
    return synced


def sync_one(row, terminal=None):
    """Log in, read what changed, and hand the terminal back."""
    user_id = row["user_id"]
    mark(user_id, "connecting")
    try:
        open_session(row, terminal)
        return read_closed(row)
    finally:
        mt5.shutdown()


def single_connected():
    """The one connected account this host owns, if there is exactly one.

    Counted only over owned rows: another host's connected account must not
    switch our watch mode off, and must never be watched from here.
    """
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
                "limit": "50",
            },
            timeout=TIMEOUT,
        )
    except requests.RequestException:
        return None
    if response.status_code != 200:
        return None
    rows = [row for row in response.json() if owns(row["user_id"])]
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


def watch(row, terminal=None, contended=True, should_yield=None):
    """
    Stay logged in and journal a close within `WATCH_SECONDS`.

    `contended` is the sequential mode's problem: one terminal, one session, so
    the watch must hand the terminal back when another account is waiting. A
    fleet slot owns its terminal outright and passes False, so it only stops
    when this account is no longer connected.
    """
    user_id = row["user_id"]
    try:
        open_session(row, terminal)
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
        # The pass above may have just pushed the trade that ends the day, so the
        # lock is checked before the loop starts waiting, not after.
        enforce_lock(row)
        print(
            f"  watching {user_id[:8]}… {row['server']} "
            f"(close latency ~{WATCH_SECONDS:.0f}s)"
        )

        last_claim = time.monotonic()
        while True:
            time.sleep(WATCH_SECONDS)
            enforce_lock(row)
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
                # A dropped login has to be noticed here: the row still says
                # `connected`, so the app would otherwise show a live account
                # that silently journals nothing.
                if terminal_session_lost():
                    print(f"  {user_id[:8]}… terminal lost its session; logging back in")
                    if not relogin(row):
                        print(
                            f"  {user_id[:8]}… could not log back in; releasing "
                            "the terminal for a clean start"
                        )
                        return
                state = connection_state(user_id)
                if contended:
                    try:
                        claimed = claim()
                    except requests.RequestException:
                        claimed = []
                    release = must_release(user_id, state, claimed)
                    reason = " or work is waiting"
                else:
                    release = state is None or state.get("status") != "connected"
                    reason = ""
                if release:
                    current_status = (state or {}).get("status")
                    print(
                        f"  {user_id[:8]}… connection is {current_status or 'gone'}"
                        f"{reason}; releasing the terminal"
                    )
                    return
                # Fleet only: an account with no terminal to go to. This one is
                # only "first" by luck of the queue, so let it take a turn.
                if should_yield is not None and should_yield():
                    print(
                        f"  {user_id[:8]}… another account is waiting; "
                        "yielding the terminal"
                    )
                    return
    finally:
        mt5.shutdown()


# What `/api/sync` answers when the subscription no longer covers syncing, as
# opposed to the terminal or the broker failing. The status is in the raised
# message ("ingest rejected (402): …") and so is the machine-readable code.
LAPSE_MARKERS = ("(402)", "upgrade_required")


_lapse_notified = set()


def forget_lapse(user_id):
    """Re-arm the "paused" notice after a sync that worked."""
    _lapse_notified.discard(user_id)


def is_lapse(error):
    """Whether a failure is the plan, not the connection.

    The two need different words. A lapsed account is a terminal that logged in
    perfectly and was then refused at the door: sending that customer to
    "reconnect" points them at a screen that cannot help them, and reads as if
    their broker password were wrong.
    """
    text = str(error)
    return any(marker in text for marker in LAPSE_MARKERS)


def report_failure(row, error):
    """Mark the account failed and tell the customer once per breakdown."""
    user_id = row["user_id"]
    print(f"  {user_id[:8]}… failed: {error}")
    try:
        mark(user_id, "failed", error=error)
    except Exception:  # noqa: BLE001 - the log above already carries the cause
        pass
    # One notification per breakdown, not one every cycle: a row that is already
    # `failed` is being retried, not news.
    if row.get("status") == "failed":
        return
    if is_lapse(error):
        # A lapse is retried like any other failure, but unlike a dead terminal
        # it does not fix itself, so every retry would push the same sentence
        # again. Told once; cleared by `mark()` the moment a sync succeeds.
        if user_id in _lapse_notified:
            return
        _lapse_notified.add(user_id)
        notify(
            user_id,
            "MTL Ledger sync paused",
            "Your plan has ended, so no new trades are being imported. "
            "Open the app to renew - sync resumes on its own.",
        )
        return
    notify(
        user_id,
        "MT5 sync stopped",
        f"{row.get('server') or 'Your broker'} could not be read. "
        "Open the app to reconnect.",
    )


def fleet_worker(slot, terminal, jobs, results, waiting=None, log_path=None):
    """One terminal, one account at a time, in its own process.

    A process rather than a thread because the MetaTrader5 package keeps one IPC
    connection per process: two threads would share a single terminal, which is
    the thing the fleet exists to avoid. The queues are the only state this slot
    shares with the supervisor.

    `log_path` gets this slot's own log. A child's stdout does not reliably reach
    the parent's console: under `| Tee-Object` or a service wrapper the slot's
    prints are dropped, which leaves a silent fleet and nothing to read when an
    account stalls. One file per slot always works.
    """
    if log_path:
        handle = open(log_path, "a", encoding="utf-8", buffering=1)
        sys.stdout = handle
        sys.stderr = handle
    while True:
        job = jobs.get()
        if job is None:
            mt5.shutdown()
            return
        _, row = job
        error = ""
        started = time.monotonic()
        print(
            f"[slot {slot}] {row['user_id'][:8]}… {row.get('server') or '?'} "
            f"({row.get('account_login') or '?'}) start",
            flush=True,
        )

        def should_yield():
            """True once holding this account is keeping another one waiting."""
            if waiting is None or waiting.value <= 0:
                return False
            return time.monotonic() - started >= FLEET_MIN_HOLD_SECONDS

        try:
            sync_one(row, terminal)
            if WATCH_SECONDS > 0:
                watch(row, terminal, contended=False, should_yield=should_yield)
        except Exception as exc:  # noqa: BLE001 - the supervisor reports it
            error = str(exc) or type(exc).__name__
        finally:
            mt5.shutdown()
        print(
            f"[slot {slot}] {row['user_id'][:8]}… done"
            f"{': ' + error if error else ''}",
            flush=True,
        )
        results.put({"slot": slot, "row": row, "error": error})


def run_fleet():
    """Hand each account this host owns to a terminal of its own.

    A slot holds its account for as long as it stays connected, so the fleet's
    real capacity is FLEET_SIZE accounts at the same time. The slot returns to
    the pool when its account disconnects, goes stale for a refresh's worth of
    time, or fails; the account is re-claimed on a later cycle like any other.
    """
    terminals = fleet_terminals()[:FLEET_SIZE]
    jobs, results = mp.Queue(), mp.Queue()
    # How many accounts are waiting for a terminal right now. Shared, because it
    # is the slots that have to decide to give one back.
    waiting = mp.Value("i", 0)

    def spawn(slot):
        process = mp.Process(
            target=fleet_worker,
            args=(
                slot,
                terminals[slot],
                jobs,
                results,
                waiting,
                str(Path(__file__).with_name(f"fleet-slot-{slot}.log")),
            ),
            name=f"mt5-slot-{slot}",
            daemon=True,
        )
        process.start()
        return process

    workers = [spawn(slot) for slot in range(FLEET_SIZE)]
    print(f"fleet: {FLEET_SIZE} terminal(s) held open, one account each")

    free = list(range(FLEET_SIZE))
    busy = {}
    try:
        while True:
            session_reminders()
            while True:
                try:
                    done = results.get_nowait()
                except queue.Empty:
                    break
                busy.pop(done["slot"], None)
                if done["slot"] not in free:
                    free.append(done["slot"])
                if done["error"]:
                    report_failure(done["row"], done["error"])

            # A slot that died mid-account never reports, and without this its
            # account would be stuck `connecting` and its terminal unused for as
            # long as the supervisor runs.
            for slot, process in enumerate(workers):
                if slot in busy and not process.is_alive():
                    print(f"[warn] slot {slot} died mid-account; restarting it")
                    busy.pop(slot, None)
                    if slot not in free:
                        free.append(slot)
                    workers[slot] = spawn(slot)

            try:
                rows = claim()
            except requests.RequestException as error:
                print(f"[warn] could not reach Supabase: {error}")
                rows = []

            assigned = set(busy.values())
            for row in rows:
                if not free:
                    break
                if row["user_id"] in assigned:
                    continue
                slot = free.pop(0)
                busy[slot] = row["user_id"]
                assigned.add(row["user_id"])
                jobs.put((row["user_id"], row))
            waiting.value = sum(1 for row in rows if row["user_id"] not in assigned)
            time.sleep(CYCLE_SECONDS)
    finally:
        for _ in workers:
            jobs.put(None)
        for worker in workers:
            worker.join(timeout=10)
            if worker.is_alive():
                worker.terminate()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    check_config()
    if FLEET_SIZE:
        if args.once:
            print("[fleet] --once is one sequential pass; run without it for the fleet")
        else:
            run_fleet()
            return

    print("MTL Ledger supervisor - polling for connections")

    while True:
        session_reminders()
        try:
            rows = claim()
        except requests.RequestException as error:
            print(f"[warn] could not reach Supabase: {error}")
            rows = []

        for row in rows:
            try:
                sync_one(row)
            except Exception as error:  # noqa: BLE001 - one account must not stop the rest
                report_failure(row, error)

        if args.once:
            break

        if WATCH_SECONDS > 0:
            watched = single_connected()
            if watched:
                try:
                    watch(watched)
                except Exception as error:  # noqa: BLE001
                    report_failure(watched, error)
                continue

        time.sleep(CYCLE_SECONDS)


if __name__ == "__main__":
    main()
