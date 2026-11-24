"""Tests for the supervisor's terminal resolution.

The MetaTrader5 package only exists on Windows and needs a real terminal, so it
is replaced by a stub before the supervisor module is imported. What is under
test is the part that decides which terminal to use and what it tells the
customer when none of them can log in.
"""

import importlib
import json
import os
import sys
import tempfile
import types
import unittest
from datetime import datetime, timezone
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


if __name__ == "__main__":
    unittest.main()
