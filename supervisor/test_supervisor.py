"""Tests for the supervisor's terminal resolution.

The MetaTrader5 package only exists on Windows and needs a real terminal, so it
is replaced by a stub before the supervisor module is imported. What is under
test is the part that decides which terminal to use and what it tells the
customer when none of them can log in.
"""

import base64
import contextlib
import importlib
import io
import json
import os
import queue
import sys
import tempfile
import types
import unittest
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Imported by the supervisor at module import time.
if "MetaTrader5" not in sys.modules:
    stub = types.ModuleType("MetaTrader5")
    stub.initialize = lambda *args, **kwargs: False
    stub.account_info = lambda: None
    stub.shutdown = lambda: None
    stub.last_error = lambda: (0, "stub")
    sys.modules["MetaTrader5"] = stub

SUPERVISOR_DIR = Path(__file__).parent
sys.path.insert(0, str(SUPERVISOR_DIR))

import mt5_supervisor as sup  # noqa: E402


def base64_key():
    """A SYNC_CREDENTIAL_KEY that passes the length check."""
    return base64.b64encode(b"k" * 32).decode()


class FakeMt5:
    """A terminal host that answers from a script, one call per attempt."""

    def __init__(self, answers):
        self.answers = list(answers)
        self.calls = []
        self._last = (0, "ok")

    def initialize(self, path=None, portable=False, timeout=0, **session):
        self.calls.append((path, session.get("login"), session.get("server")))
        answer = self.answers.pop(0) if self.answers else ("fail", (-6, "exhausted"))
        if answer[0] == "ok":
            self._last = (1, "ok")
            return True
        self._last = answer[1]
        return False

    def account_info(self):
        login = self.calls[-1][1]
        return types.SimpleNamespace(login=login)

    def shutdown(self):
        return True

    def last_error(self):
        return self._last


def make_terminal(directory, name="terminal64.exe"):
    folder = Path(directory) / name.replace(".exe", "")
    folder.mkdir(parents=True, exist_ok=True)
    binary = folder / "terminal64.exe"
    binary.write_text("", encoding="utf-8")
    return str(binary)


class ServerSpellingTests(unittest.TestCase):
    def test_fixes_the_missing_space_in_an_old_fundednext_row(self):
        self.assertEqual(
            sup.canonical_server_name("FundedNext", "fundednext-server3"),
            "FundedNext-Server 3",
        )

    def test_matches_the_broker_through_an_alias(self):
        self.assertEqual(
            sup.canonical_server_name("Funding Pips", "fundingpips-sim1"),
            "FundingPips-SIM1",
        )

    def test_leaves_an_unknown_server_alone(self):
        self.assertEqual(
            sup.canonical_server_name("FundedNext", "FundedNext-Unknown"),
            "FundedNext-Unknown",
        )
        self.assertEqual(
            sup.canonical_server_name("Some Local Broker", "Any-Server 1"),
            "Any-Server 1",
        )


class TerminalResolutionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cache = Path(self.tmp.name) / "terminal-cache.json"

        self._saved = {
            "MT5_PATH": sup.MT5_PATH,
            "MT5_PORTABLE": sup.MT5_PORTABLE,
            "TERMINAL_CACHE": sup.TERMINAL_CACHE,
            "discover_terminals": sup.discover_terminals,
            "decrypt_credential": sup.decrypt_credential,
            "mt5": sup.mt5,
        }
        self.addCleanup(self._restore)

        sup.TERMINAL_CACHE = self.cache
        sup.MT5_PORTABLE = False
        sup.discover_terminals = lambda: []
        sup.decrypt_credential = lambda blob: "investor-password"
        os.environ.pop("MT5_PATHS", None)

    def _restore(self):
        sup.MT5_PATH = self._saved["MT5_PATH"]
        sup.MT5_PORTABLE = self._saved["MT5_PORTABLE"]
        sup.TERMINAL_CACHE = self._saved["TERMINAL_CACHE"]
        sup.discover_terminals = self._saved["discover_terminals"]
        sup.decrypt_credential = self._saved["decrypt_credential"]
        sup.mt5 = self._saved["mt5"]

    def row(self, broker="fundednext", server="FundedNext-Server3", login=35476861):
        return {
            "user_id": "u1",
            "broker_name": broker,
            "server": server,
            "account_login": str(login),
            "credential_cipher": "v1:unused",
        }

    def test_remembers_the_terminal_that_worked(self):
        first = make_terminal(self.tmp.name, "plain")
        second = make_terminal(self.tmp.name, "fundednext")
        sup.MT5_PATH = first
        os.environ["MT5_PATHS"] = second
        try:
            sup.mt5 = FakeMt5([("fail", (-10005, "IPC timeout"))] * 2 + [("ok", None)])
            sup.open_session(self.row())
        finally:
            os.environ.pop("MT5_PATHS", None)

        stored = json.loads(self.cache.read_text(encoding="utf-8"))
        self.assertEqual(stored["fundednext|fundednext-server 3"], second)
        self.assertEqual(sup.mt5.calls[0][2], "FundedNext-Server 3")

        # The next login goes straight to the terminal that worked.
        sup.mt5 = FakeMt5([("ok", None)])
        sup.open_session(self.row())
        self.assertEqual(sup.mt5.calls[0][0], second)

    def test_tries_the_next_terminal_when_one_cannot_start(self):
        first = make_terminal(self.tmp.name, "plain")
        second = make_terminal(self.tmp.name, "branded")
        sup.MT5_PATH = first
        os.environ["MT5_PATHS"] = second
        try:
            sup.mt5 = FakeMt5([("fail", (-10005, "IPC timeout"))] * 2 + [("ok", None)])
            sup.open_session(self.row())
        finally:
            os.environ.pop("MT5_PATHS", None)

        paths = [call[0] for call in sup.mt5.calls]
        self.assertEqual(paths, [first, first, second])

    def test_a_terminal_side_failure_is_retried_once(self):
        only = make_terminal(self.tmp.name, "plain")
        sup.MT5_PATH = only
        sup.mt5 = FakeMt5([("fail", (-10005, "IPC timeout")), ("ok", None)])

        sup.open_session(self.row())

        self.assertEqual([call[0] for call in sup.mt5.calls], [only, only])

    def test_a_rejected_password_is_not_retried(self):
        only = make_terminal(self.tmp.name, "plain")
        sup.MT5_PATH = only
        sup.mt5 = FakeMt5([("fail", (-6, "Terminal: Authorization failed"))])

        with self.assertRaises(RuntimeError) as caught:
            sup.open_session(self.row())

        self.assertEqual(len(sup.mt5.calls), 1)
        self.assertIn("Authorization failed", str(caught.exception))

    def test_a_terminal_on_another_account_is_rejected(self):
        first = make_terminal(self.tmp.name, "plain")
        second = make_terminal(self.tmp.name, "branded")
        sup.MT5_PATH = first
        os.environ["MT5_PATHS"] = second
        try:
            sup.mt5 = FakeMt5([("ok", None), ("ok", None)])
            sup.mt5.account_info = lambda: types.SimpleNamespace(
                login=11111111 if sup.mt5.calls[-1][0] == first else 35476861
            )
            sup.open_session(self.row())
        finally:
            os.environ.pop("MT5_PATHS", None)

        self.assertEqual([call[0] for call in sup.mt5.calls], [first, second])

    def test_no_terminal_at_all_still_tries_the_default_install(self):
        sup.MT5_PATH = ""
        sup.mt5 = FakeMt5([("ok", None)])

        sup.open_session(self.row())

        self.assertEqual(sup.mt5.calls[0][0], None)

    def test_the_error_names_every_terminal_it_tried(self):
        first = make_terminal(self.tmp.name, "plain")
        second = make_terminal(self.tmp.name, "branded")
        sup.MT5_PATH = first
        os.environ["MT5_PATHS"] = second
        try:
            sup.mt5 = FakeMt5([("fail", (-10005, "IPC timeout"))] * 4)
            with self.assertRaises(RuntimeError) as caught:
                sup.open_session(self.row())
        finally:
            os.environ.pop("MT5_PATHS", None)

        message = str(caught.exception)
        self.assertIn("no terminal could log in to FundedNext-Server 3", message)
        self.assertIn(first, message)
        self.assertIn(second, message)

    def test_an_installed_terminal_is_discovered_from_the_install_roots(self):
        roots = Path(self.tmp.name) / "Programs"
        branded = roots / "Some Prop MT5"
        branded.mkdir(parents=True)
        (branded / "terminal64.exe").write_text("", encoding="utf-8")

        # Prop-firm installers often nest the executable under a vendor folder.
        nested = roots / "Vendor" / "MT5"
        nested.mkdir(parents=True)
        (nested / "terminal64.exe").write_text("", encoding="utf-8")

        saved_local = os.environ.get("LOCALAPPDATA")
        saved_pf = os.environ.get("ProgramFiles")
        os.environ["LOCALAPPDATA"] = str(Path(self.tmp.name))
        os.environ["ProgramFiles"] = str(Path(self.tmp.name) / "nothing-here")
        try:
            # The real discovery function, not the suite's empty stand-in.
            found = self._saved["discover_terminals"](force=True)
        finally:
            if saved_local is None:
                os.environ.pop("LOCALAPPDATA", None)
            else:
                os.environ["LOCALAPPDATA"] = saved_local
            if saved_pf is None:
                os.environ.pop("ProgramFiles", None)
            else:
                os.environ["ProgramFiles"] = saved_pf

        self.assertIn(str(branded / "terminal64.exe"), found)
        self.assertIn(str(nested / "terminal64.exe"), found)


class ClaimPriorityTests(unittest.TestCase):
    def test_new_connections_are_processed_before_refreshes(self):
        rows = [
            {"user_id": "old", "status": "connected", "last_sync_at": "2026-01-01"},
            {"user_id": "new", "status": "pending", "last_sync_at": None},
            {"user_id": "retry", "status": "connecting", "last_sync_at": "2026-01-02"},
            {"user_id": "failed", "status": "failed", "last_sync_at": None},
        ]

        ordered = sup.prioritize_connections(rows)

        self.assertEqual(
            [row["user_id"] for row in ordered],
            ["new", "retry", "failed", "old"],
        )

    def test_a_second_shard_does_not_claim_the_same_rows(self):
        saved = (sup.SUPERVISOR_SHARDS, sup.SUPERVISOR_SHARD)
        self.addCleanup(setattr, sup, "SUPERVISOR_SHARDS", saved[0])
        self.addCleanup(setattr, sup, "SUPERVISOR_SHARD", saved[1])
        sup.SUPERVISOR_SHARDS = 2
        sup.SUPERVISOR_SHARD = 1
        rows = [
            {"user_id": "a", "status": "pending", "last_sync_at": None},
            {"user_id": "b", "status": "pending", "last_sync_at": None},
            {"user_id": "c", "status": "pending", "last_sync_at": None},
            {"user_id": "d", "status": "pending", "last_sync_at": None},
        ]

        claimed = sup.owned_by_this_host(sup.prioritize_connections(rows))

        self.assertTrue(claimed)
        for row in claimed:
            self.assertEqual(sup.shard_of(row["user_id"]), 1)


class ShardOwnershipTests(unittest.TestCase):
    """Two hosts on one project must never work the same account.

    The claim is a plain GET, so nothing on the server hands out rows
    exclusively: the split has to be computed identically on every host.
    """

    def setUp(self):
        self.saved = (sup.SUPERVISOR_SHARDS, sup.SUPERVISOR_SHARD, sup.MAX_ACCOUNTS)
        self.addCleanup(self._restore)

    def _restore(self):
        sup.SUPERVISOR_SHARDS, sup.SUPERVISOR_SHARD, sup.MAX_ACCOUNTS = self.saved

    def test_shares_are_disjoint_and_cover_every_account(self):
        sup.SUPERVISOR_SHARDS = 3
        accounts = [f"user-{index}" for index in range(60)]
        rows = [{"user_id": account} for account in accounts]

        shares = []
        for index in range(3):
            sup.SUPERVISOR_SHARD = index
            shares.append({row["user_id"] for row in sup.owned_by_this_host(rows)})

        self.assertEqual(set().union(*shares), set(accounts))
        self.assertEqual(sum(len(share) for share in shares), len(accounts))
        for left in range(3):
            for right in range(left + 1, 3):
                self.assertFalse(shares[left] & shares[right])

    def test_owner_is_computed_with_crc32_so_hosts_agree(self):
        sup.SUPERVISOR_SHARDS = 4
        self.assertEqual(sup.shard_of("u1"), zlib.crc32(b"u1") % 4)

    def test_a_single_host_still_takes_everything(self):
        sup.SUPERVISOR_SHARDS = 1
        sup.SUPERVISOR_SHARD = 0
        rows = [{"user_id": f"user-{index}"} for index in range(5)]
        self.assertEqual(sup.owned_by_this_host(rows), rows)

    def test_the_cap_serves_the_least_recently_synced_first(self):
        sup.SUPERVISOR_SHARDS = 1
        sup.MAX_ACCOUNTS = 2
        self.addCleanup(setattr, sup, "_capacity_warned_at", sup._capacity_warned_at)
        sup._capacity_warned_at = 0.0
        rows = [
            {"user_id": "recent", "status": "connected", "last_sync_at": "2026-01-03"},
            {"user_id": "oldest", "status": "connected", "last_sync_at": "2026-01-01"},
            {"user_id": "middle", "status": "connected", "last_sync_at": "2026-01-02"},
        ]

        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            kept = sup.owned_by_this_host(sup.prioritize_connections(rows))

        # A capped host rotates the backlog instead of pinning the same rows.
        self.assertEqual([row["user_id"] for row in kept], ["oldest", "middle"])
        # And says so, once per CAPACITY_WARN_SECONDS, so a silent slowdown is
        # not mistaken for the accounts being synced normally.
        self.assertIn("[capacity]", printed.getvalue())


class SymbolDigitsTests(unittest.TestCase):
    def setUp(self):
        self.saved = sup.mt5
        self.addCleanup(self._restore)

    def _restore(self):
        sup.mt5 = self.saved

    def test_uses_the_terminal_digits_for_the_symbol(self):
        sup.mt5 = types.SimpleNamespace(
            symbol_info=lambda symbol: types.SimpleNamespace(digits=2)
        )
        self.assertEqual(sup.symbol_digits("XAUUSDM"), 2)

    def test_unknown_symbol_falls_back_to_eight(self):
        sup.mt5 = types.SimpleNamespace(symbol_info=lambda symbol: None)
        self.assertEqual(sup.symbol_digits("XAUUSDM"), 8)

    def test_a_terminal_error_does_not_stop_a_sync(self):
        def boom(symbol):
            raise RuntimeError("terminal is gone")

        sup.mt5 = types.SimpleNamespace(symbol_info=boom)
        self.assertEqual(sup.symbol_digits("XAUUSDM"), 8)

    def test_rounding_a_noisy_average_gives_a_quoted_price(self):
        noisy = 3595.7380000000003
        self.assertEqual(round(noisy, 2), 3595.74)
        self.assertEqual(round(3587.8869999999997, 3), 3587.887)


class Deal:
    """The handful of fields `build_trade` reads from a deal."""

    def __init__(self, position_id, entry, volume, price, when, ticket=1):
        self.position_id = position_id
        self.entry = entry
        self.volume = volume
        self.price = price
        self.time = when
        self.ticket = ticket
        self.symbol = "EURUSD"
        self.type = 0
        self.profit = 0.0
        self.commission = 0.0
        self.swap = 0.0


class TradeTimeTests(unittest.TestCase):
    """Deal times are the broker's clock; the journal stores UTC."""

    def setUp(self):
        self.saved = sup.mt5
        self.addCleanup(self._restore)

    def _restore(self):
        sup.mt5 = self.saved

    def fake_mt5(self, opened, closed):
        deals = [opened, closed]
        return types.SimpleNamespace(
            history_deals_get=lambda position=None: deals,
            history_orders_get=lambda position=None: (),
            symbol_info=lambda symbol: types.SimpleNamespace(digits=5),
        )

    def test_deal_times_are_moved_from_the_broker_clock_onto_utc(self):
        server_noon = int(datetime(2026, 11, 20, 14, 0, tzinfo=timezone.utc).timestamp())
        opened = Deal(7, 0, 0.10, 1.10000, server_noon)
        closed = Deal(7, 1, 0.10, 1.10100, server_noon + 600, ticket=2)
        sup.mt5 = self.fake_mt5(opened, closed)

        trade = sup.build_trade(7, offset=7200)

        self.assertEqual(trade["open_time"], "2026-11-20T12:00:00+00:00")
        self.assertEqual(trade["close_time"], "2026-11-20T12:10:00+00:00")

    def test_an_unknown_offset_leaves_the_time_alone(self):
        server_noon = int(datetime(2026, 11, 20, 14, 0, tzinfo=timezone.utc).timestamp())
        opened = Deal(7, 0, 0.10, 1.10000, server_noon)
        closed = Deal(7, 1, 0.10, 1.10100, server_noon + 600, ticket=2)
        sup.mt5 = self.fake_mt5(opened, closed)

        trade = sup.build_trade(7)

        self.assertEqual(trade["open_time"], "2026-11-20T14:00:00+00:00")


class HistoryClockTests(unittest.TestCase):
    """History reads are bounded by the broker's clock, not UTC."""

    def setUp(self):
        self.saved = sup.mt5
        self.addCleanup(self._restore)

    def _restore(self):
        sup.mt5 = self.saved

    def test_every_broker_offset_is_shifted_from_utc(self):
        for offset in (0, 7200, 10800, 19800, -14400):
            with self.subTest(offset=offset):
                windows = []

                def history_deals_get(start, end):
                    windows.append((start, end))
                    return ()

                sup.mt5 = types.SimpleNamespace(
                    history_deals_get=history_deals_get
                )
                start = datetime.now(timezone.utc)

                sup.deals_between(start, start + timedelta(minutes=30), offset)

                self.assertEqual(
                    (windows[0][0] - start).total_seconds(), offset
                )
                self.assertEqual(
                    (windows[0][1] - windows[0][0]).total_seconds(), 1800
                )

    def test_position_trades_reads_recent_closes_on_the_broker_clock(self):
        close_server = int(
            (datetime.now(timezone.utc) + timedelta(seconds=7200)).timestamp()
        )
        opened = Deal(7, 0, 0.10, 1.10000, close_server - 300)
        closed = Deal(7, 1, 0.10, 1.10100, close_server, ticket=2)
        windows = []

        def history_deals_get(start=None, end=None, position=None):
            if position is not None:
                return [opened, closed]
            windows.append((start, end))
            return [closed]

        sup.mt5 = types.SimpleNamespace(
            history_deals_get=history_deals_get,
            history_orders_get=lambda position=None: (),
            symbol_info=lambda symbol: types.SimpleNamespace(digits=5),
        )

        before = datetime.now(timezone.utc)
        trades = sup.position_trades(
            before - timedelta(minutes=30), offset=7200
        )
        after = datetime.now(timezone.utc)

        self.assertEqual([trade["position_id"] for trade in trades], [7])
        self.assertEqual(len(windows), 1)
        start, end = windows[0]
        # The 30-minute UTC window is shifted forward onto a UTC+2 broker.
        self.assertGreaterEqual((start - before).total_seconds(), 5398)
        self.assertLessEqual((end - after).total_seconds(), 7202)


class ServerOffsetTests(unittest.TestCase):
    def setUp(self):
        self.saved = sup.mt5
        self.saved_cache = sup.SERVER_OFFSET_CACHE
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        sup.SERVER_OFFSET_CACHE = Path(self.tmp.name) / "offset.json"
        self.addCleanup(self._restore)

    def _restore(self):
        sup.mt5 = self.saved
        sup.SERVER_OFFSET_CACHE = self.saved_cache

    def tick(self, when):
        return types.SimpleNamespace(time=when, bid=1.0, ask=1.0)

    def test_a_live_tick_measures_the_broker_clock(self):
        now = int(sup.time.time())
        answers = iter([self.tick(now + 7200), self.tick(now + 7203)])
        sup.mt5 = types.SimpleNamespace(symbol_info_tick=lambda symbol: next(answers, None))

        self.assertEqual(sup.measure_server_offset(pause=0), 7200)

    def test_a_suffixed_symbol_still_calibrates_the_clock(self):
        now = int(sup.time.time())
        answers = iter([self.tick(now + 7200), self.tick(now + 7203)])
        sup.mt5 = types.SimpleNamespace(
            symbols_get=lambda: [types.SimpleNamespace(name="EURUSDm")],
            symbol_info_tick=lambda symbol: next(answers, None),
        )

        self.assertEqual(sup.measure_server_offset(pause=0), 7200)

    def test_an_unselected_symbol_is_selected_before_calibrating(self):
        now = int(sup.time.time())
        answers = iter(
            [None, self.tick(now + 7200), self.tick(now + 7203)]
        )
        selected = []
        sup.mt5 = types.SimpleNamespace(
            symbols_get=lambda: [types.SimpleNamespace(name="EURUSDm")],
            symbol_select=lambda symbol, enable: selected.append((symbol, enable)),
            symbol_info_tick=lambda symbol: next(answers, None),
        )

        self.assertEqual(sup.measure_server_offset(pause=0), 7200)
        self.assertEqual(selected, [("EURUSDm", True)])

    def test_a_frozen_tick_is_not_an_offset(self):
        frozen = self.tick(int(sup.time.time()) + 7200)
        sup.mt5 = types.SimpleNamespace(symbol_info_tick=lambda symbol: frozen)

        self.assertIsNone(sup.measure_server_offset(pause=0))

    def test_the_offset_is_measured_once_and_then_reused(self):
        now = int(sup.time.time())
        answers = iter([self.tick(now + 10800), self.tick(now + 10803)])
        sup.mt5 = types.SimpleNamespace(symbol_info_tick=lambda symbol: next(answers, None))
        row = {"broker_name": "fundednext", "server": "FundedNext-Server 3"}

        self.assertEqual(sup.server_offset(row), 10800)

        # A measure that would answer differently must not be consulted again
        # today: calibrating on every sync would put three seconds of sleep in
        # front of every login.
        sup.mt5 = types.SimpleNamespace(symbol_info_tick=lambda symbol: None)
        self.assertEqual(sup.server_offset(row), 10800)


class FirstSyncHistoryTests(unittest.TestCase):
    def setUp(self):
        self.saved = sup.mt5
        self.addCleanup(self._restore)

    def _restore(self):
        sup.mt5 = self.saved

    def test_a_download_in_flight_is_waited_out(self):
        answers = iter([0, 0, 7])
        sup.mt5 = types.SimpleNamespace(
            history_deals_total=lambda start, end: next(answers, 0)
        )

        total = sup.history_total(
            datetime.now(timezone.utc), wait_seconds=30, pause=0
        )

        self.assertEqual(total, 7)

    def test_an_unreadable_history_is_not_reported_as_empty(self):
        sup.mt5 = types.SimpleNamespace(
            history_deals_total=lambda start, end: -1
        )

        total = sup.history_total(
            datetime.now(timezone.utc), wait_seconds=30, pause=0
        )

        self.assertEqual(total, -1)

    def test_the_wait_window_is_read_on_the_broker_clock(self):
        windows = []

        def history_deals_total(start, end):
            windows.append((start, end))
            return 7

        sup.mt5 = types.SimpleNamespace(history_deals_total=history_deals_total)
        start = datetime.now(timezone.utc)

        total = sup.history_total(start, wait_seconds=30, offset=7200)

        self.assertEqual(total, 7)
        self.assertGreaterEqual((windows[0][0] - start).total_seconds(), 7199)


class BackfillTests(unittest.TestCase):
    """A first sync reads the year a month at a time, and keeps trying.

    On the XM account a single year-long read answered with the opening deposit
    and no trades, so the sync reported 0 positions and the cursor moved past
    three real closes. These tests pin the read that replaced it.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.saved = {
            name: getattr(sup, name)
            for name in (
                "mt5",
                "BACKFILL_DIR",
                "server_offset",
                "push",
                "mark",
                "HISTORY_WAIT_SECONDS",
            )
        }
        sup.BACKFILL_DIR = Path(self.tmp.name) / "backfill"
        sup.HISTORY_WAIT_SECONDS = 0
        sup.server_offset = lambda row: 0
        self.pushed = []

        def push(user_id, trades):
            self.pushed.append(list(trades))
            return len(trades)

        sup.push = push
        sup.mark = lambda *args, **kwargs: None
        self.windows = []
        self.addCleanup(self._restore)

    def _restore(self):
        for name, value in self.saved.items():
            setattr(sup, name, value)

    def terminal(self, groups):
        """A terminal whose cache answers only narrow, recent reads.

        That is the behaviour that lost the XM block: a wide range arrives empty.
        """
        wides = []

        def history_deals_get(start=None, end=None, position=None):
            if position is not None:
                return groups.get(position, [])
            self.windows.append((start, end))
            if (end - start) > timedelta(days=sup.BACKFILL_CHUNK_DAYS + 1):
                wides.append((start, end))
                return []
            return [
                deal
                for group in groups.values()
                for deal in group
                if start <= datetime.fromtimestamp(deal.time, timezone.utc) < end
            ]

        def history_deals_total(start, end):
            return sum(len(group) for group in groups.values())

        return types.SimpleNamespace(
            history_deals_get=history_deals_get,
            history_deals_total=history_deals_total,
            history_orders_get=lambda position=None: (),
            symbol_info=lambda symbol: types.SimpleNamespace(digits=5),
            last_error=lambda: (0, "stub"),
        )

    def position(self, closed_days_ago):
        close = int(
            (datetime.now(timezone.utc) - timedelta(days=closed_days_ago)).timestamp()
        )
        opened = Deal(7, 0, 0.01, 1.10000, close - 600)
        closed = Deal(7, 1, 0.01, 1.10100, close, ticket=2)
        return [opened, closed]

    def test_an_old_close_a_wide_read_misses_is_backfilled(self):
        sup.mt5 = self.terminal({7: self.position(200)})

        trades = sup.backfill_trades(
            datetime.now(timezone.utc) - timedelta(days=365), wait_seconds=0
        )

        self.assertEqual([trade["position_id"] for trade in trades], [7])
        # A year is twelve-ish month-sized reads, never one wide one.
        self.assertGreaterEqual(len(self.windows), 12)
        for start, end in self.windows:
            self.assertLessEqual((end - start).days, sup.BACKFILL_CHUNK_DAYS)

    def test_the_newest_month_is_read_first(self):
        sup.mt5 = self.terminal({})

        sup.backfill_trades(
            datetime.now(timezone.utc) - timedelta(days=365), wait_seconds=0
        )

        first_start, first_end = self.windows[0]
        last_start, _ = self.windows[-1]
        self.assertGreater(first_start, last_start)
        self.assertLess(datetime.now(timezone.utc) - first_end, timedelta(minutes=1))

    def first_sync(self):
        row = {
            "user_id": "u1",
            "server": "XMGlobal-MT5 9",
            "last_sync_at": None,
        }
        sup.read_closed(row)

    def test_a_first_sync_leaves_a_marker_to_read_the_year_again(self):
        sup.mt5 = self.terminal({7: self.position(200)})

        self.first_sync()

        state = json.loads(sup.backfill_path("u1").read_text(encoding="utf-8"))
        self.assertEqual(state["left"], sup.BACKFILL_PASSES - 1)
        self.assertEqual(len(self.pushed[-1]), 1)

    def test_a_fresh_cursor_does_not_skip_the_pending_backfill(self):
        sup.mt5 = self.terminal({7: self.position(200)})
        self.first_sync()
        windows_after_first = len(self.windows)
        row = {
            "user_id": "u1",
            "server": "XMGlobal-MT5 9",
            "last_sync_at": datetime.now(timezone.utc).isoformat(),
        }

        sup.read_closed(row)

        # Still a year's worth of months, not the one 15-minute cursor window.
        self.assertGreaterEqual(len(self.windows) - windows_after_first, 12)
        self.assertEqual(len(self.pushed[-1]), 1)

    def test_a_reconnect_with_a_stale_cursor_still_reads_the_year(self):
        sup.mt5 = self.terminal({7: self.position(200)})

        sup.read_closed(
            {
                "user_id": "u1",
                "server": "XMGlobal-MT5 9",
                "status": "pending",
                "last_sync_at": datetime.now(timezone.utc).isoformat(),
            }
        )

        self.assertGreaterEqual(len(self.windows), 12)
        self.assertEqual(len(self.pushed[-1]), 1)

    def test_the_marker_retires_once_its_passes_are_used(self):
        sup.mt5 = self.terminal({})
        row = {"user_id": "u1", "server": "XMGlobal-MT5 9", "last_sync_at": None}

        for _ in range(sup.BACKFILL_PASSES):
            sup.read_closed(row)

        self.assertEqual(list(Path(sup.BACKFILL_DIR).glob("*.json")), [])
        windows = len(self.windows)

        sup.read_closed(
            {
                **row,
                "last_sync_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        # A settled account is read through the cursor again: one window.
        self.assertEqual(len(self.windows) - windows, 1)


class AccountZeroLoginTests(unittest.TestCase):
    """A terminal that starts without authorising is retried, not reported."""

    def setUp(self):
        self.saved = {
            name: getattr(sup, name)
            for name in (
                "mt5",
                "decrypt_credential",
                "remember_terminal",
                "warn_if_no_algo_trading",
            )
        }
        sup.decrypt_credential = lambda blob: "secret"
        sup.remember_terminal = lambda key, path: None
        sup.warn_if_no_algo_trading = lambda path: None
        self.calls = []
        self.addCleanup(self._restore)

    def _restore(self):
        for name, value in self.saved.items():
            setattr(sup, name, value)

    def terminal(self, logins):
        answers = list(logins)

        def initialize(path=None, portable=False, timeout=0, **session):
            self.calls.append((path, session.get("login")))
            return True

        def account_info():
            return types.SimpleNamespace(login=answers.pop(0) if answers else None)

        return types.SimpleNamespace(
            initialize=initialize,
            account_info=account_info,
            shutdown=lambda: True,
            last_error=lambda: (0, "ok"),
        )

    def row(self):
        return {
            "user_id": "u1",
            "account_login": 337339457,
            "server": "XMGlobal-MT5 9",
            "credential_cipher": "v1:x:y:z",
        }

    def test_account_zero_is_retried_on_the_same_terminal(self):
        sup.mt5 = self.terminal([0, 337339457])

        sup.open_session(self.row(), "C:/fleet/slot-1/terminal64.exe")

        self.assertEqual(len(self.calls), 2)

    def test_another_customers_account_is_still_refused(self):
        sup.mt5 = self.terminal([999, 999])

        with self.assertRaises(RuntimeError):
            sup.open_session(self.row(), "C:/fleet/slot-1/terminal64.exe")

        self.assertEqual(len(self.calls), 1)


class RetiredInstallTests(unittest.TestCase):
    def test_the_folder_the_updater_renamed_is_recognised(self):
        self.assertTrue(sup.is_retired_install("MetaTrader 5.old6324"))
        self.assertTrue(sup.is_retired_install("MetaTrader 5 - Backup"))
        self.assertFalse(sup.is_retired_install("MetaTrader 5"))
        self.assertFalse(sup.is_retired_install("MetaTrader 5 (Oldfield)"))

    def test_discovery_skips_a_retired_install(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        good = make_terminal(Path(tmp.name) / "MetaTrader 5")
        make_terminal(Path(tmp.name) / "MetaTrader 5.old6324")

        saved = {name: os.environ.get(name) for name in (
            "ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"
        )}
        self.addCleanup(
            lambda: [
                os.environ.__setitem__(name, value)
                if value is not None
                else os.environ.pop(name, None)
                for name, value in saved.items()
            ]
        )
        os.environ["ProgramFiles"] = tmp.name
        os.environ["ProgramFiles(x86)"] = ""
        os.environ["LOCALAPPDATA"] = ""

        self.assertEqual(sup.discover_terminals(force=True), [good])


class SessionLossTests(unittest.TestCase):
    """A watched account that drops its session must not look quiet.

    An empty deal history is the same answer for "nothing closed" and "we are
    logged out", so the terminal's own connected flag is the only witness.
    """

    def setUp(self):
        self.saved_mt5 = sup.mt5
        self.saved_decrypt = sup.decrypt_credential
        self.addCleanup(setattr, sup, "mt5", self.saved_mt5)
        self.addCleanup(setattr, sup, "decrypt_credential", self.saved_decrypt)

    def row(self):
        return {
            "user_id": "row-1",
            "account_login": 35326084,
            "server": "FundedNext-Server 3",
            "broker_name": "FundedNext",
            "credential_cipher": "v1:blob",
        }

    def test_a_terminal_that_reports_no_connection_has_lost_its_session(self):
        sup.mt5 = types.SimpleNamespace(
            terminal_info=lambda: types.SimpleNamespace(connected=False)
        )

        self.assertTrue(sup.terminal_session_lost())

    def test_a_live_connection_is_not_mistaken_for_a_lost_session(self):
        sup.mt5 = types.SimpleNamespace(
            terminal_info=lambda: types.SimpleNamespace(connected=True)
        )

        self.assertFalse(sup.terminal_session_lost())

    def test_a_dead_ipc_pipe_counts_as_a_lost_session(self):
        def boom():
            raise RuntimeError("IPC down")

        sup.mt5 = types.SimpleNamespace(terminal_info=boom)

        self.assertTrue(sup.terminal_session_lost())

    def test_re_login_reuses_the_stored_investor_password(self):
        calls = []
        sup.decrypt_credential = lambda blob: "investor-pass"
        sup.mt5 = types.SimpleNamespace(
            login=lambda login, password=None, server=None: (
                calls.append((login, password, server)) or True
            )
        )

        self.assertTrue(sup.relogin(self.row()))
        self.assertEqual(
            calls,
            [
                (
                    35326084,
                    "investor-pass",
                    sup.canonical_server_name("FundedNext", "FundedNext-Server 3"),
                )
            ],
        )

    def test_a_rejected_re_login_is_reported_rather_than_raised(self):
        sup.decrypt_credential = lambda blob: "investor-pass"
        sup.mt5 = types.SimpleNamespace(login=lambda *args, **kwargs: False)

        self.assertFalse(sup.relogin(self.row()))

    def test_an_undecryptable_credential_needs_a_new_connect(self):
        def boom(blob):
            raise ValueError("bad blob")

        sup.decrypt_credential = boom
        sup.mt5 = types.SimpleNamespace(
            login=lambda *args, **kwargs: self.fail("must not try to log in")
        )

        self.assertFalse(sup.relogin(self.row()))


class FleetModeTests(unittest.TestCase):
    """FLEET_SIZE>0 holds a terminal open per account instead of taking turns.

    Each slot needs its own directory (two copies cannot run from one) and its
    own process (the package keeps one IPC connection per process), so the
    pieces worth testing here are which terminals pair with which slot and what
    a worker reports when a slot fails.
    """

    def setUp(self):
        self.saved_dirs = sup.MT5_FLEET_DIRS
        self.addCleanup(setattr, sup, "MT5_FLEET_DIRS", self.saved_dirs)

    def test_a_directory_or_an_exe_both_name_a_slot(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        first = make_terminal(Path(tmp.name) / "slot-1")
        second = make_terminal(Path(tmp.name) / "slot-2")

        # A directory is the usual form; an exe path must work too, so the same
        # value can be pasted from Explorer or from setup_fleet.ps1.
        sup.MT5_FLEET_DIRS = f"{Path(first).parent};{second}"

        self.assertEqual(sup.fleet_terminals(), [first, second])

    def test_a_missing_directory_does_not_become_a_slot(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        real = make_terminal(Path(tmp.name) / "slot-1")
        sup.MT5_FLEET_DIRS = f"{Path(real).parent}, {Path(tmp.name) / 'slot-9'}"

        self.assertEqual(sup.fleet_terminals(), [real])

    def test_the_same_terminal_is_never_two_slots(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        real = make_terminal(Path(tmp.name) / "slot-1")
        sup.MT5_FLEET_DIRS = f"{real};{Path(real).parent}"

        self.assertEqual(len(sup.fleet_terminals()), 1)

    def test_a_fleet_larger_than_the_terminals_refuses_to_start(self):
        saved = (sup.FLEET_SIZE, sup.SUPABASE_URL, sup.SERVICE_KEY,
                 sup.CREDENTIAL_KEY, sup.SUPERVISOR_TOKEN, sup.MT5_PATH)
        self.addCleanup(self._restore, saved)
        sup.FLEET_SIZE = 4
        sup.SUPABASE_URL = "https://example.test"
        sup.SERVICE_KEY = "service"
        sup.CREDENTIAL_KEY = base64_key()
        sup.SUPERVISOR_TOKEN = "token"
        sup.MT5_PATH = ""
        sup.MT5_FLEET_DIRS = ""

        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit):
                sup.check_config()

    def _restore(self, saved):
        (sup.FLEET_SIZE, sup.SUPABASE_URL, sup.SERVICE_KEY,
         sup.CREDENTIAL_KEY, sup.SUPERVISOR_TOKEN, sup.MT5_PATH) = saved

    def test_a_failed_slot_reports_the_account_and_its_cause(self):
        jobs, results = queue.Queue(), queue.Queue()
        row = {"user_id": "row-1", "status": "pending"}
        jobs.put(("row-1", row))
        jobs.put(None)
        saved_sync, saved_watch = sup.sync_one, sup.watch
        self.addCleanup(setattr, sup, "sync_one", saved_sync)
        self.addCleanup(setattr, sup, "watch", saved_watch)

        def boom(sync_row, terminal=None):
            raise RuntimeError("terminal went away")

        sup.sync_one = boom
        sup.watch = lambda *args, **kwargs: None

        sup.fleet_worker(2, "terminal64.exe", jobs, results)

        done = results.get_nowait()
        self.assertEqual(done["slot"], 2)
        self.assertEqual(done["row"], row)
        self.assertEqual(done["error"], "terminal went away")
        self.assertTrue(results.empty())

    def test_a_slot_keeps_its_terminal_and_reads_before_watching(self):
        jobs, results = queue.Queue(), queue.Queue()
        row = {"user_id": "row-2", "status": "pending"}
        calls = []
        jobs.put(("row-2", row))
        jobs.put(None)
        saved_sync, saved_watch, saved_seconds = sup.sync_one, sup.watch, sup.WATCH_SECONDS
        self.addCleanup(setattr, sup, "sync_one", saved_sync)
        self.addCleanup(setattr, sup, "watch", saved_watch)
        self.addCleanup(setattr, sup, "WATCH_SECONDS", saved_seconds)

        sup.sync_one = lambda sync_row, terminal=None: calls.append(("sync", terminal))

        def fake_watch(watch_row, terminal=None, contended=True, should_yield=None):
            calls.append(("watch", terminal, contended, should_yield))

        sup.watch = fake_watch
        sup.WATCH_SECONDS = 2

        sup.fleet_worker(0, "C:/fleet/slot-1/terminal64.exe", jobs, results)

        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0], ("sync", "C:/fleet/slot-1/terminal64.exe"))
        watch_call = calls[1]
        self.assertEqual(
            watch_call[:3], ("watch", "C:/fleet/slot-1/terminal64.exe", False)
        )
        # The yield hook exists so a full fleet can hand a terminal to an account
        # that has none, and it must stay quiet while nobody is waiting.
        self.assertTrue(callable(watch_call[3]))
        self.assertFalse(watch_call[3]())
        self.assertEqual(results.get_nowait()["error"], "")

    def test_a_slot_yields_once_another_account_is_waiting(self):
        jobs, results = queue.Queue(), queue.Queue()
        row = {"user_id": "row-3", "status": "pending"}
        hooks = {}
        jobs.put(("row-3", row))
        jobs.put(None)
        saved_sync, saved_watch, saved_seconds, saved_hold = (
            sup.sync_one, sup.watch, sup.WATCH_SECONDS, sup.FLEET_MIN_HOLD_SECONDS
        )
        self.addCleanup(setattr, sup, "sync_one", saved_sync)
        self.addCleanup(setattr, sup, "watch", saved_watch)
        self.addCleanup(setattr, sup, "WATCH_SECONDS", saved_seconds)
        self.addCleanup(setattr, sup, "FLEET_MIN_HOLD_SECONDS", saved_hold)

        sup.sync_one = lambda sync_row, terminal=None: None
        sup.watch = lambda watch_row, terminal=None, contended=True, should_yield=None: hooks.update(
            should_yield=should_yield
        )
        sup.WATCH_SECONDS = 2
        sup.FLEET_MIN_HOLD_SECONDS = 0
        waiting = types.SimpleNamespace(value=0)

        sup.fleet_worker(0, "terminal64.exe", jobs, results, waiting)

        self.assertFalse(hooks["should_yield"]())
        waiting.value = 1
        self.assertTrue(hooks["should_yield"]())


class FailureNoticeTests(unittest.TestCase):
    """What the phone is told when an account stops syncing."""

    def setUp(self):
        self.sent = []
        saved_mark, saved_notify = sup.mark, sup.notify
        self.addCleanup(setattr, sup, "mark", saved_mark)
        self.addCleanup(setattr, sup, "notify", saved_notify)
        sup.mark = lambda *args, **kwargs: None
        sup.notify = lambda user_id, title, body: self.sent.append((title, body))

    def test_a_lapsed_plan_is_not_reported_as_a_broken_connection(self):
        # The exact shape `push()` raises: status plus the server's code.
        error = RuntimeError(
            'ingest rejected (402): {"error":"Pro required","code":"upgrade_required"}'
        )
        sup.report_failure({"user_id": "u-1", "server": "Exness", "status": "connected"}, error)

        self.assertEqual(len(self.sent), 1)
        title, body = self.sent[0]
        self.assertIn("paused", title.lower())
        self.assertIn("plan", body.lower())
        # The old wording sent a lapsed customer to a reconnect screen that
        # cannot fix a plan, so it must not survive in any form.
        self.assertNotIn("reconnect", body.lower())
        self.assertNotIn("could not be read", body.lower())

    def test_a_broken_connection_still_asks_for_a_reconnect(self):
        error = RuntimeError("terminal went away")
        sup.report_failure({"user_id": "u-2", "server": "Exness", "status": "connected"}, error)

        self.assertEqual(len(self.sent), 1)
        title, body = self.sent[0]
        self.assertEqual(title, "MT5 sync stopped")
        self.assertIn("Exness", body)
        self.assertIn("reconnect", body)

    def test_a_row_already_failed_is_not_announced_again(self):
        sup.report_failure({"user_id": "u-3", "status": "failed"}, RuntimeError("boom"))

        self.assertEqual(self.sent, [])

    def test_a_lapse_is_announced_once_because_it_never_fixes_itself(self):
        error = RuntimeError('ingest rejected (402): {"code":"upgrade_required"}')
        row = {"user_id": "u-4", "server": "Exness", "status": "connecting"}

        # The supervisor retries a failed row every FAILED_RETRY_SECONDS and
        # marks it `connecting` again, so the status guard alone would push the
        # same sentence every ten minutes for as long as the plan stays lapsed.
        sup.report_failure(row, error)
        sup.report_failure(row, error)
        sup.report_failure(row, error)

        self.assertEqual(len(self.sent), 1)

    def test_syncing_again_re_arms_the_lapse_notice(self):
        superseded = sup._lapse_notified
        self.addCleanup(setattr, sup, "_lapse_notified", superseded)
        sup._lapse_notified = {"u-5"}

        # A successful sync clears the throttle, or a customer who renews and
        # later lapses again would never be told the second time.
        sup.forget_lapse("u-5")

        self.assertEqual(sup._lapse_notified, set())


class SessionReminderTickTests(unittest.TestCase):
    """The supervisor is what asks for a session reminder often enough to land."""

    def setUp(self):
        self.calls = []
        self.addCleanup(setattr, sup.requests, "post", sup.requests.post)
        self.addCleanup(setattr, sup, "SESSION_REMINDER_SECONDS", sup.SESSION_REMINDER_SECONDS)
        self.addCleanup(setattr, sup, "_last_session_check", sup._last_session_check)
        sup.requests.post = lambda url, **kwargs: self.calls.append(url)
        sup.SESSION_REMINDER_SECONDS = 60
        sup._last_session_check = 0.0

    def test_asks_the_api_once_per_interval(self):
        sup.session_reminders()
        sup.session_reminders()

        self.assertEqual(len(self.calls), 1)
        self.assertTrue(self.calls[0].endswith("/api/push/sessions"))

    def test_a_refused_reminder_never_reaches_the_sync_loop(self):
        def boom(*args, **kwargs):
            raise sup.requests.RequestException("offline")

        sup.requests.post = boom
        sup.session_reminders()  # must not raise
        sup._last_session_check = 0.0


class AlgoTradingConfigTests(unittest.TestCase):
    """The one MT5 setting a headless host cannot click."""

    def config(self, text):
        folder = Path(tempfile.mkdtemp())
        path = folder / "common.ini"
        path.write_text(text, encoding="utf-8")
        return path

    def test_adds_the_section_when_the_file_has_none(self):
        path = self.config("[Common]\nLogin=486046720\n")

        self.assertFalse(sup.ensure_algo_trading(path))  # False == changed

        text = path.read_text(encoding="utf-8")
        self.assertIn("[Experts]", text)
        self.assertIn("AllowLiveTrading=1", text)
        self.assertIn("Enabled=1", text)
        self.assertIn("Login=486046720", text)

    def test_corrects_a_disabled_value_without_touching_neighbours(self):
        path = self.config("[Experts]\nEnabled=0\nAllowDllImport=0\n[Objects]\nX=1\n")

        self.assertFalse(sup.ensure_algo_trading(path))

        text = path.read_text(encoding="utf-8")
        self.assertIn("Enabled=1", text)
        self.assertNotIn("Enabled=0", text)
        self.assertIn("AllowDllImport=0", text)
        self.assertIn("[Objects]", text)

    def test_is_a_no_op_when_the_terminal_already_allows_trading(self):
        path = self.config("[Experts]\nAllowLiveTrading=1\nEnabled=1\n")

        self.assertTrue(sup.ensure_algo_trading(path))

    def test_does_not_invent_a_config_that_is_not_there(self):
        path = Path(tempfile.mkdtemp()) / "common.ini"

        self.assertTrue(sup.ensure_algo_trading(path))
        self.assertFalse(path.exists())

    def test_a_terminal_with_its_own_config_folder_is_portable(self):
        folder = Path(tempfile.mkdtemp())
        (folder / "config").mkdir()
        (folder / "config" / "common.ini").write_text("", encoding="utf-8")

        self.assertTrue(sup.looks_portable(str(folder / "terminal64.exe")))
        self.assertFalse(sup.looks_portable(str(Path(tempfile.mkdtemp()) / "terminal64.exe")))
        self.assertFalse(sup.looks_portable(""))

    def test_finds_the_config_of_a_portable_terminal_only(self):
        folder = Path(tempfile.mkdtemp())
        (folder / "config").mkdir()
        config = folder / "config" / "common.ini"
        config.write_text("[Experts]\n", encoding="utf-8")

        self.assertEqual(sup.terminal_config_path(str(folder / "terminal64.exe"), True), config)
        # A normal install keeps its config under %APPDATA% for a hash only the
        # terminal knows; guessing there would edit the wrong profile.
        self.assertIsNone(sup.terminal_config_path(str(folder / "terminal64.exe"), False))


class AlgoTradingWarningTests(unittest.TestCase):
    """A host that cannot trade must say so rather than cancel nothing forever."""

    def setUp(self):
        self.terminal = types.SimpleNamespace(trade_allowed=True)
        self.account = types.SimpleNamespace(login=486046720, trade_allowed=True)
        self.addCleanup(setattr, sup, "_algo_warned", sup._algo_warned)
        sup._algo_warned = set()
        self.stub("terminal_info", lambda: self.terminal)
        self.stub("account_info", lambda: self.account)

    def stub(self, name, value):
        """The MT5 module only grows these attributes on a machine with a terminal,
        so remember whether the name existed before stubbing it."""
        had = hasattr(sup.mt5, name)
        saved = getattr(sup.mt5, name, None)
        setattr(sup.mt5, name, value)
        self.addCleanup(
            lambda: setattr(sup.mt5, name, saved) if had else delattr(sup.mt5, name)
        )

    def said(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            sup.warn_if_no_algo_trading(r"C:\MT5-Fleet\slot-01\terminal64.exe")
        return out.getvalue()

    def test_silent_when_the_host_can_trade(self):
        self.assertEqual(self.said(), "")

    def test_names_the_terminal_setting_once(self):
        self.terminal = types.SimpleNamespace(trade_allowed=False)

        first = self.said()
        self.assertIn("Algo Trading", first)
        self.assertEqual(self.said(), "")  # repeated every 15s otherwise

    def test_names_a_read_only_account(self):
        self.account = types.SimpleNamespace(login=486046720, trade_allowed=False)

        first = self.said()
        self.assertIn("read-only", first)
        self.assertIn("486046720", first)
        self.assertEqual(self.said(), "")


class AgentTokenLookupTests(unittest.TestCase):
    """The EA token sits on `users`; the connection row does not carry it."""

    def setUp(self):
        self.addCleanup(setattr, sup, "_agent_tokens", sup._agent_tokens)
        self.addCleanup(setattr, sup.requests, "get", sup.requests.get)
        sup._agent_tokens = {}
        self.calls = []

    def test_reads_the_token_once_and_remembers_it(self):
        def get(url, **kwargs):
            self.calls.append((url, kwargs.get("params")))
            return FakeResponse(200, [{"agent_token": "tok-1"}])

        sup.requests.get = get

        self.assertEqual(sup.agent_token_for("u-1"), "tok-1")
        self.assertEqual(sup.agent_token_for("u-1"), "tok-1")
        self.assertEqual(len(self.calls), 1)  # asked every 30s otherwise
        self.assertTrue(self.calls[0][0].endswith("/rest/v1/users"))
        self.assertEqual(self.calls[0][1], {"select": "agent_token", "id": "eq.u-1"})

    def test_a_failed_lookup_is_retried_rather_than_cached(self):
        sup.requests.get = lambda url, **kwargs: FakeResponse(401, {"message": "no"})

        self.assertEqual(sup.agent_token_for("u-2"), "")
        self.assertEqual(sup.agent_token_for("u-2"), "")
        self.assertNotIn("u-2", sup._agent_tokens)


class FakeResponse:
    def __init__(self, status, body):
        self.status_code = status
        self._body = body

    def json(self):
        return self._body


class SoftLockTests(unittest.TestCase):
    """The half of the guard EA a supervisor-synced account would be missing."""

    def setUp(self):
        self.cancelled = []
        self.asked = []
        self.lock_body = {"locked": True, "mode": "soft", "reason": "Daily loss budget reached."}
        self.lock_status = 200
        self.orders = []
        self.addCleanup(setattr, sup.requests, "get", sup.requests.get)
        self.addCleanup(setattr, sup, "ENFORCE_LOCK", sup.ENFORCE_LOCK)
        self.addCleanup(setattr, sup, "_lock_checked_at", sup._lock_checked_at)
        saved_orders = getattr(sup.mt5, "orders_get", None)
        saved_send = getattr(sup.mt5, "order_send", None)
        self.addCleanup(lambda: setattr(sup.mt5, "orders_get", saved_orders))
        self.addCleanup(lambda: setattr(sup.mt5, "order_send", saved_send))

        sup.ENFORCE_LOCK = True
        sup._lock_checked_at = {}
        sup.requests.get = lambda url, **kwargs: (
            self.asked.append((url, kwargs.get("params"))),
            FakeResponse(self.lock_status, self.lock_body),
        )[1]
        sup.mt5.orders_get = lambda *args, **kwargs: self.orders
        sup.mt5.order_send = lambda request: (
            self.cancelled.append(request),
            types.SimpleNamespace(retcode=sup.TRADE_RETCODE_DONE),
        )[1]

    def row(self, **over):
        return {"user_id": "u-lock", "agent_token": "token-1", **over}

    def order(self, ticket, kind):
        return types.SimpleNamespace(ticket=ticket, type=kind)

    def test_cancels_resting_orders_once_the_day_is_over(self):
        self.orders = [self.order(11, 2), self.order(12, 4), self.order(13, 0)]

        self.assertEqual(sup.enforce_lock(self.row()), 2)

        self.assertEqual([c["order"] for c in self.cancelled], [11, 12])
        self.assertTrue(all(c["action"] == sup.TRADE_ACTION_REMOVE for c in self.cancelled))

    def test_never_closes_an_open_position(self):
        # A market order is a position, not a resting order: the supervisor is
        # not allowed to close one, whatever the lock says.
        self.orders = [self.order(21, 0), self.order(22, 1)]

        self.assertEqual(sup.enforce_lock(self.row()), 0)
        self.assertEqual(self.cancelled, [])

    def test_inside_the_limits_touches_nothing(self):
        self.lock_body = {"locked": False, "mode": "soft", "reason": "Inside the limits."}
        self.orders = [self.order(31, 2)]

        self.assertEqual(sup.enforce_lock(self.row()), 0)
        self.assertEqual(self.cancelled, [])

    def test_a_server_error_cancels_nothing(self):
        # Fail open, like the EA: an outage must not strand an account.
        self.lock_status = 500
        self.orders = [self.order(41, 2)]

        self.assertEqual(sup.enforce_lock(self.row()), 0)
        self.assertEqual(self.cancelled, [])

    def test_asks_at_most_once_per_interval(self):
        sup.enforce_lock(self.row())
        sup.enforce_lock(self.row())

        self.assertEqual(len(self.asked), 1)
        self.assertTrue(self.asked[0][0].endswith("/api/ea/lock"))
        self.assertEqual(self.asked[0][1], {"userId": "u-lock"})

    def test_an_account_with_no_agent_token_is_left_alone(self):
        row = {"user_id": "u-lock"}
        self.addCleanup(setattr, sup, "agent_token_for", sup.agent_token_for)
        sup.agent_token_for = lambda user_id: ""

        self.assertEqual(sup.enforce_lock(row), 0)
        self.assertEqual(self.asked, [])

    def test_enforcement_can_be_switched_off(self):
        sup.ENFORCE_LOCK = False
        self.orders = [self.order(51, 2)]

        self.assertEqual(sup.enforce_lock(self.row()), 0)
        self.assertEqual(self.asked, [])
        self.assertEqual(self.cancelled, [])


class CapacityTests(unittest.TestCase):
    """A fleet must not spawn more terminals than the host can hold.

    Spawning past the budget does not degrade gracefully: the allocation fails
    inside OpenBLAS, the supervisor exits, and the wrapper restarts it into the
    same wall. On the 8 GB VPS that was a crash loop with every account offline.
    """

    def test_fits_the_measured_host(self):
        # 30 requested, 4.3 GB free, 900 MB reserved, 240 MB a slot.
        self.assertEqual(sup.capacity_slots(30, available_mb=4279), 14)

    def test_never_exceeds_what_was_asked_for(self):
        self.assertEqual(sup.capacity_slots(4, available_mb=64_000), 4)

    def test_always_keeps_one_slot(self):
        # A host with no headroom still syncs, slowly, instead of not at all.
        self.assertEqual(sup.capacity_slots(30, available_mb=500), 1)

    def test_sequential_mode_stays_sequential(self):
        self.assertEqual(sup.capacity_slots(0, available_mb=64_000), 0)

    def test_unreadable_memory_trusts_the_configuration(self):
        self.addCleanup(setattr, sup, "available_memory_mb", sup.available_memory_mb)
        sup.available_memory_mb = lambda: None

        self.assertEqual(sup.capacity_slots(30), 30)

    def test_a_bigger_slot_estimate_shrinks_the_fleet(self):
        self.assertEqual(
            sup.capacity_slots(30, available_mb=4279, slot_mb=400), 8
        )


if __name__ == "__main__":
    unittest.main()
