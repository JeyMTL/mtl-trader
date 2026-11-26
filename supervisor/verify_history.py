"""
Compare the journal with each broker's own closed history.

`/api/sync` is upsert-only, so a lost push is invisible: the journal simply has
fewer trades than the account really closed, and every screen looks fine. This
reads the account through MT5 the same way the supervisor does (month by month,
so a cold terminal fetches rather than answers from cache) and compares the two
sets by `position_id`.

  python supervisor/verify_history.py                 # last year, every account
  python supervisor/verify_history.py --days 3650     # deep import check
  python supervisor/verify_history.py --user <uuid>   # one customer
  python supervisor/verify_history.py --json > audit.json
  python supervisor/verify_history.py --repair        # audit, then re-arm only
                                                      # the accounts with gaps

What counts as a failure:

  * `missing` — the broker closed it and the journal does not have it. That is
    the sync gap this exists to find, and it exits non-zero.
  * `pnl` — both have the position but the numbers differ by more than a cent
    per unit of account currency (rounding across engines is not exact).
  * `clock` — `close_time` differs by more than two minutes, which is the
    fingerprint of a server-time/UTC mix-up rather than a sync gap.

`extra` (a journal row the broker did not return) is reported but does not fail
the run: an account that was replaced still has its old trades, and a customer
may also have imports that never came from MT5.

A position the customer deleted on purpose is not missing: the `trades` delete
trigger records it in `sync_suppressions`, and `/api/sync` refuses to bring it
back, so the comparison excludes those on purpose.

`--repair` turns the audit into the fix for exactly those gaps. It arms the
`.backfill` marker for each account that has a missing position (and for no other
account), so the supervisor's next session re-reads the audited window and the
upserts fill the holes without touching the rows that are already right. The
list of what it queued is written to `repair-history.json` (override with
`--repair-file`), so the run leaves a record even when the supervisor is stopped.
An account that could not be read is never queued: its history is unknown.

Stop the supervisor task first (`Stop-ScheduledTask -TaskName 'MTL Ledger Sync
Supervisor'`). Two processes logging into the same terminal fight over one
session, and the read fails in a way that looks like an account problem.
"""

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import mt5_supervisor as sup

# A cent in the journal's own rounding, with a little room for the float noise
# that comes from summing deals on two different code paths.
PNL_TOLERANCE = 0.02
CLOCK_TOLERANCE_SECONDS = 120
PAGE = 1000


def journal_rows(user_id, since):
    """Every journaled close for this user since `since`, oldest position first."""
    rows = []
    offset = 0
    while True:
        response = sup.requests.get(
            f"{sup.SUPABASE_URL}/rest/v1/trades",
            params={
                "select": "position_id,ticket,pnl,close_time,symbol",
                "user_id": f"eq.{user_id}",
                "close_time": f"gte.{since.isoformat()}",
                "order": "position_id.asc",
                "limit": PAGE,
                "offset": offset,
            },
            headers=sup.REST_HEADERS,
            timeout=sup.TIMEOUT,
        )
        if response.status_code != 200:
            raise RuntimeError(f"journal read failed ({response.status_code}): {response.text[:160]}")
        page = response.json()
        rows.extend(page)
        if len(page) < PAGE:
            return rows
        offset += PAGE


def suppressed_ids(user_id):
    """Positions this customer deleted, which the journal must not get back."""
    response = sup.requests.get(
        f"{sup.SUPABASE_URL}/rest/v1/sync_suppressions",
        params={"select": "position_id", "user_id": f"eq.{user_id}"},
        headers=sup.REST_HEADERS,
        timeout=sup.TIMEOUT,
    )
    if response.status_code != 200:
        return set()  # an unreadable table must not turn every trade into a loss
    return {int(row["position_id"]) for row in response.json() if row.get("position_id") is not None}


def connections(user_id=None):
    params = {
        "select": "user_id,broker_name,server,account_login,credential_cipher,status",
        "status": "neq.disconnected",
        "credential_cipher": "neq.",
    }
    if user_id:
        params["user_id"] = f"eq.{user_id}"
    response = sup.requests.get(
        f"{sup.SUPABASE_URL}/rest/v1/broker_connections",
        params=params,
        headers=sup.REST_HEADERS,
        timeout=sup.TIMEOUT,
    )
    if response.status_code != 200:
        raise RuntimeError(f"connection read failed ({response.status_code}): {response.text[:160]}")
    return response.json()


def compare(broker_trades, journal, suppressed=()):
    """The difference between what the account closed and what was journaled.

    Pure so it can be tested without a terminal: `broker_trades` is the shape
    `build_trade` returns and `journal` is what PostgREST answered.
    """
    broker = {int(trade["position_id"]): trade for trade in broker_trades}
    journaled = {}
    for row in journal:
        if row.get("position_id") is None:
            continue  # a CSV import has no position; it cannot be compared
        journaled[int(row["position_id"])] = row

    deleted = {int(item) for item in suppressed}
    missing = sorted(set(broker) - set(journaled) - deleted)
    extra = sorted(set(journaled) - set(broker))

    pnl = []
    clock = []
    for position_id in sorted(set(broker) & set(journaled)):
        broker_pnl = float(broker[position_id]["pnl"])
        journal_pnl = float(journaled[position_id].get("pnl") or 0)
        if abs(broker_pnl - journal_pnl) > PNL_TOLERANCE:
            pnl.append((position_id, round(broker_pnl, 2), round(journal_pnl, 2)))

        broker_close = datetime.fromisoformat(broker[position_id]["close_time"])
        raw = journaled[position_id].get("close_time") or ""
        try:
            journal_close = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            continue
        if abs((broker_close - journal_close).total_seconds()) > CLOCK_TOLERANCE_SECONDS:
            clock.append((position_id, broker_close.isoformat(), raw))

    return {
        "broker": len(broker),
        "journal": len(journaled),
        "missing": missing,
        "extra": extra,
        "deleted": len(deleted & set(broker)),
        "pnl": pnl,
        "clock": clock,
        "broker_pnl": round(sum(float(t["pnl"]) for t in broker.values()), 2),
        "journal_pnl": round(sum(float(r.get("pnl") or 0) for r in journaled.values()), 2),
    }


def read_account(row, days, wait):
    """Log in and read the account's closed positions, then hang up."""
    sup.open_session(row)
    try:
        offset = sup.server_offset(row)
        start = datetime.now(timezone.utc) - timedelta(days=days)
        return sup.backfill_trades(start, offset, wait_seconds=wait)
    finally:
        sup.mt5.shutdown()


def verify(row, days, wait):
    user_id = row["user_id"]
    since = datetime.now(timezone.utc) - timedelta(days=days)
    report = {
        "user_id": user_id,
        "account": row.get("account_login"),
        "broker": row.get("broker_name"),
        "server": row.get("server"),
    }
    try:
        broker_trades = read_account(row, days, wait)
        report.update(compare(broker_trades, journal_rows(user_id, since), suppressed_ids(user_id)))
    except Exception as error:  # noqa: BLE001 - one account must not stop the audit
        report["error"] = str(error)[:300]
    return report


def repair_entries(reports):
    """Accounts whose gap a backfill can close: a missing position, not an error.

    An unreadable account is left out on purpose. Its history is unknown, so
    arming a deep read for it would be a guess, and the audit says so instead.
    """
    return [
        {
            "user_id": report["user_id"],
            "account": report.get("account"),
            "broker": report.get("broker"),
            "missing": list(report.get("missing") or []),
        }
        for report in reports
        if not report.get("error") and report.get("missing")
    ]


def queue_repair(entry, days):
    """Arm the backfill marker for one account, and say what happened.

    A marker is what makes the supervisor read history again on the next claim:
    `read_closed` takes a marker as a reason to backfill even when the row is
    `connected` and has a cursor. Writing one does not depend on the customer
    pressing Reconnect.

    Never shortens a marker that is already deeper. An interrupted ten-year
    import must not be replaced by the one-year window this audit used, or the
    repair would undo the import it was meant to help.
    """
    user_id = entry["user_id"]
    start = datetime.now(timezone.utc) - timedelta(days=days)
    existing = sup.backfill_retry(user_id)
    if existing is not None and existing <= start:
        return "already queued"
    sup.start_backfill(user_id, start)
    return "queued" if sup.backfill_path(user_id).exists() else "marker not writable"


def verdict(report):
    """Whether this account passed, and the one-word reason when it did not."""
    if report.get("error"):
        return "error"
    if report["missing"]:
        return "missing"
    if report["pnl"] or report["clock"]:
        return "mismatch"
    return "ok"


def print_report(reports):
    header = f"{'account':>12}  {'broker':<16} {'journal':>7} {'broker':>7} {'missing':>7} {'extra':>5} {'pnl diff':>9}  result"
    print(header)
    print("-" * len(header))
    for report in reports:
        result = verdict(report)
        if report.get("error"):
            print(f"{str(report.get('account')):>12}  {str(report.get('broker'))[:16]:<16} {'':>7} {'':>7} {'':>7} {'':>5} {'':>9}  error: {report['error']}")
            continue
        diff = report["journal_pnl"] - report["broker_pnl"]
        print(
            f"{str(report.get('account')):>12}  {str(report.get('broker'))[:16]:<16}"
            f" {report['broker']:>7} {report['journal']:>7} {len(report['missing']):>7}"
            f" {len(report['extra']):>5} {diff:>9.2f}  {result}"
        )
        if report["missing"]:
            shown = ", ".join(str(item) for item in report["missing"][:12])
            more = " …" if len(report["missing"]) > 12 else ""
            print(f"{'':>12}  missing positions: {shown}{more}")
        for position_id, broker_pnl, journal_pnl in report["pnl"][:8]:
            print(f"{'':>12}  position {position_id}: broker {broker_pnl:.2f}, journal {journal_pnl:.2f}")
        for position_id, broker_close, journal_close in report["clock"][:8]:
            print(f"{'':>12}  position {position_id}: broker {broker_close}, journal {journal_close}")
        if report["deleted"]:
            print(f"{'':>12}  {report['deleted']} deleted by the customer, not counted as missing")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--days", type=int, default=sup.BACKFILL_DAYS, help="how far back to compare (default: BACKFILL_DAYS)")
    parser.add_argument("--user", default="", help="one customer's user id instead of the whole fleet")
    parser.add_argument("--wait", type=float, default=10.0, help="seconds each month gets for the terminal to fetch it")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--repair", action="store_true", help="re-arm the backfill for the accounts with missing positions")
    parser.add_argument("--repair-file", default="repair-history.json", help="where the repair list is written")
    args = parser.parse_args()

    sup.check_config()
    rows = connections(args.user or None)
    if not rows:
        print("No connections to verify.")
        return 0

    reports = []
    for index, row in enumerate(rows, start=1):
        if not args.json:
            print(f"[{index}/{len(rows)}] account {row.get('account_login')} on {row.get('broker')}…")
        reports.append(verify(row, args.days, args.wait))

    repairs = []
    repair_file = None
    if args.repair:
        repairs = repair_entries(reports)
        for entry in repairs:
            entry["status"] = queue_repair(entry, args.days)
        try:
            Path(args.repair_file).write_text(
                json.dumps(
                    {
                        "generated_at": datetime.now(timezone.utc).isoformat(),
                        "days": args.days,
                        "repairs": repairs,
                    },
                    indent=2,
                ),
                encoding="utf-8",
            )
            repair_file = args.repair_file
        except OSError as error:
            print(f"[warn] could not write {args.repair_file}: {error}", file=sys.stderr)

    if args.json:
        print(json.dumps({"days": args.days, "accounts": reports, "repairs": repairs}, indent=2, default=str))
    else:
        print()
        print_report(reports)
        if args.repair:
            print()
            if repair_file:
                print(f"Repair list: {repair_file}")
            for entry in repairs:
                print(
                    f"  account {entry['account']} ({entry['broker']}): "
                    f"{len(entry['missing'])} missing position(s) — {entry['status']}"
                )
            if not repairs:
                print("  no account needs a backfill; the journal matches the brokers.")

    failed = [report for report in reports if verdict(report) != "ok"]
    if not args.json:
        print()
        print(f"{len(reports) - len(failed)}/{len(reports)} account(s) match the broker's history.")
        if failed and not args.repair:
            print("Re-run with --repair to re-arm only the accounts above, or press Reconnect on the phone.")
        if failed and args.repair:
            print("The queued accounts are repaired by the supervisor's next read; run this audit again after it has worked them.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
