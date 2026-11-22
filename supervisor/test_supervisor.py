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
        self.assertEqual(stored["fundednext|fundednext-server3"], second)

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
        self.assertIn("no terminal could log in to FundedNext-Server3", message)
        self.assertIn(first, message)
        self.assertIn(second, message)

    def test_an_installed_terminal_is_discovered_from_the_install_roots(self):
        roots = Path(self.tmp.name) / "Programs"
        branded = roots / "Some Prop MT5"
        branded.mkdir(parents=True)
        (branded / "terminal64.exe").write_text("", encoding="utf-8")

        saved_local = os.environ.get("LOCALAPPDATA")
        saved_pf = os.environ.get("ProgramFiles")
        os.environ["LOCALAPPDATA"] = str(Path(self.tmp.name))
        os.environ["ProgramFiles"] = str(Path(self.tmp.name) / "nothing-here")
        try:
            # The real discovery function, not the suite's empty stand-in.
            found = self._saved["discover_terminals"]()
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


if __name__ == "__main__":
    unittest.main()
