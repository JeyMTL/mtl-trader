"""
What one supervisor sync pass costs in CPU, measured on a live account.

The supervisor holds one terminal per account at a time. The cost that decides
how many accounts fit on a host is not the terminal sitting idle, it is the
work each pass asks of it: a 365-day deals read on claim, a short deals read
every WATCH_SECONDS while watching, and a per-position rebuild when something
closed. This measures those against a running terminal and reports terminal
CPU and client CPU separately, because both run on the same box.

Usage, with a terminal already logged in (any account, read-only is fine):

    python measure_sync_cost.py
    python measure_sync_cost.py --samples 40 --idle 30

The account needs to be authorized already. This script never logs in, so it
never needs a password, and it never writes to the account.
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import subprocess
import time
from datetime import datetime, timedelta, timezone

import MetaTrader5 as mt5

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)


class FILETIME(ctypes.Structure):
    _fields_ = [("low", wt.DWORD), ("high", wt.DWORD)]


def _ft(value):
    return ((value.high << 32) | value.low) / 1e7


def process_cpu_seconds(pid):
    """Kernel + user seconds for a pid, or None if it is gone."""
    handle = KERNEL32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None
    created, exited, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
    ok = KERNEL32.GetProcessTimes(
        handle,
        ctypes.byref(created),
        ctypes.byref(exited),
        ctypes.byref(kernel),
        ctypes.byref(user),
    )
    KERNEL32.CloseHandle(handle)
    if not ok:
        return None
    return _ft(kernel) + _ft(user)


def terminal_pid():
    """Newest terminal64.exe, the one this process is talking to."""
    try:
        out = subprocess.check_output(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "(Get-Process terminal64 -ErrorAction SilentlyContinue | "
                "Sort-Object StartTime -Descending | Select-Object -First 1).Id",
            ],
            text=True,
            timeout=30,
        )
    except subprocess.SubprocessError:
        return None
    out = out.strip()
    return int(out) if out.isdigit() else None


def ms(seconds):
    return round(seconds * 1000.0, 2)


def measure(label, calls, pid, fn):
    """Run fn() until the terminal's CPU delta is measurable, then report per call.

    One call costs microseconds, and GetProcessTimes ticks at 15.6 ms, so a
    handful of calls always reads as zero. Repeat until the delta clears the
    resolution instead of reporting a rounded-off zero.
    """
    while True:
        start_term = process_cpu_seconds(pid)
        start_wall = time.perf_counter()
        start_client = time.process_time()
        result = None
        for _ in range(calls):
            result = fn()
        wall = time.perf_counter() - start_wall
        client = time.process_time() - start_client
        end_term = process_cpu_seconds(pid)
        term = (end_term - start_term) if (end_term is not None and start_term is not None) else 0.0
        if term >= 0.05 or calls >= 20000:
            break
        calls *= 4
    print(
        f"{label:<34} {calls:>6} calls  "
        f"wall {1e6 * wall / calls:>7.1f} us  "
        f"terminal {1e6 * term / calls:>6.1f} us  "
        f"client {1e6 * client / calls:>6.1f} us"
    )
    return {"wall": wall / calls, "terminal": term / calls, "client": client / calls, "result": result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=25, help="calls per phase (default 25)")
    parser.add_argument("--idle", type=int, default=20, help="idle baseline seconds (default 20)")
    args = parser.parse_args()

    if not mt5.initialize():
        raise SystemExit(f"initialize failed: {mt5.last_error()}")
    try:
        info = mt5.account_info()
        if info is None:
            raise SystemExit("no account logged in; log in once and rerun")
        pid = terminal_pid()
        if pid is None:
            raise SystemExit("terminal64.exe is not running")

        now = datetime.now(timezone.utc)
        deals = mt5.history_deals_get(now - timedelta(days=365), now) or ()
        positions = set(d.position_id for d in deals if d.position_id and d.entry in (1, 2, 3))
        symbols = sorted({d.symbol for d in deals if d.symbol})

        print(f"account   : {info.login} {info.server} ({info.company})")
        print(f"build     : {mt5.version()[1]}  terminal pid {pid}")
        print(f"data      : {len(deals)} deal(s), {len(positions)} closed position(s), {len(symbols)} symbol(s)")
        print()

        # Idle: what the terminal burns with a session open and nothing asked.
        start = process_cpu_seconds(pid)
        time.sleep(args.idle)
        idle_cpu = (process_cpu_seconds(pid) or start) - start
        print(f"{'idle (session open, no calls)':<34} {args.idle:>3} s     terminal "
              f"{ms(idle_cpu / args.idle):>7} ms/s = {100 * idle_cpu / args.idle:.1f}% of one core")
        print()

        passes = {}
        passes["365d deals read (claim)"] = measure(
            "365d deals read (claim)",
            args.samples,
            pid,
            lambda: mt5.history_deals_get(now - timedelta(days=365), now),
        )
        passes["30m deals read (watch tick)"] = measure(
            "30m deals read (watch tick)",
            args.samples,
            pid,
            lambda: mt5.history_deals_get(now - timedelta(minutes=30), now),
        )
        passes["positions_get + orders_get"] = measure(
            "positions_get + orders_get",
            args.samples,
            pid,
            lambda: (mt5.positions_get(), mt5.orders_get()),
        )
        if symbols:
            passes["symbol_info x symbols"] = measure(
                f"symbol_info x {len(symbols)}",
                args.samples,
                pid,
                lambda: [mt5.symbol_info(s) for s in symbols],
            )

        def full_pass():
            recent = mt5.history_deals_get(now - timedelta(days=365), now) or ()
            for deal in recent:
                if deal.position_id and deal.entry in (1, 2, 3):
                    mt5.history_deals_get(position=int(deal.position_id))
                    mt5.history_orders_get(position=int(deal.position_id))
                    mt5.symbol_info(deal.symbol)

        passes["full pass, rebuild all"] = measure(
            "full pass, rebuild all", max(5, args.samples // 5), pid, full_pass
        )
        print()

        tick = passes["30m deals read (watch tick)"]
        # Watching means one short deals read every WATCH_SECONDS (2 s in the
        # supervisor), so this is the steady cost of a terminal holding a watch.
        watch_cpu = tick["terminal"] / 2.0 + tick["client"] / 2.0
        claim = passes["365d deals read (claim)"]
        claim_cpu = claim["terminal"] + claim["client"]
        idle_core = idle_cpu / args.idle
        print(f"{'watch tick cost':<34} {ms(watch_cpu):>7} ms/s = {100 * watch_cpu:.3f}% of one core")
        print(f"{'idle cost (what dominates)':<34} {100 * idle_core:>7.1f}% of one core")
        print(f"{'one claim pass (365d read)':<34} {1e3 * claim_cpu:>7.2f} ms")
        print()
        print("per-terminal total = idle + watch; idle is what actually sizes a host")
        for n in (1, 10, 30):
            total = (idle_core + watch_cpu) * n
            print(f"  {n:>2} terminals logged in {' ' * 14}{100 * total:>6.1f}% of one core, "
                  f"{100 * total / 8:>5.1f}% of 8 vCPU")
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    main()
