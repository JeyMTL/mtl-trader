"""
MTL Trader - MT5 Sync Agent
Connects to MetaTrader 5 and syncs closed trades to your MTL Trader account.

Usage:
    python mt5_agent.py <user_id> <token> [broker_name] [server] [login]

Or set environment variables: MTL_USER_ID, MTL_TOKEN, MT5_BROKER, MT5_SERVER, MT5_LOGIN, MT5_PASSWORD

The agent prompts for your MT5 password interactively when it starts, so it
never appears in shell history or in the copied command. Alternatively you
can pass it as the 6th CLI argument or set MT5_PASSWORD.
"""

import MetaTrader5 as mt5
import requests
import json
import time
import sys
import os
from collections import defaultdict
from datetime import datetime, timedelta
from getpass import getpass

# Default configuration
DEFAULT_APP_URL = "https://mtl-trader.vercel.app"
SYNC_INTERVAL = 60


def connect_to_mt5(broker_name, server, login, password):
    """Initialize and connect to MT5 terminal."""
    if not password:
        password = getpass(f"Enter MT5 password for {login}: ")

    print(f"Connecting to {broker_name} - {server}...")

    if not mt5.initialize():
        print(f"MT5 initialization failed: {mt5.last_error()}")
        return False

    # The server argument must be the MT5 server name (e.g. "MetaQuotes-Demo").
    # Prefer the explicit server; fall back to "broker/server" style only when
    # no server was provided.
    server_arg = server if server else broker_name
    authorized = mt5.login(
        login=int(login),
        password=password,
        server=server_arg,
    )

    if not authorized:
        print(f"Login failed: {mt5.last_error()}")
        mt5.shutdown()
        return False

    account_info = mt5.account_info()
    print(f"Connected to {account_info.server} - Account: {account_info.login}")
    return True


def get_trades(days=365):
    """Fetch CLOSED trades from MT5 by pairing opening/closing deals per position.

    MT5's history deals are individual transactions, so we group them by
    position_id: the entry==0 deal gives the entry price/time, the entry==1
    deal gives the exit price/time, and P&L is the sum across all related deals
    (including partial closes and their commissions/swaps).
    """
    to_date = datetime.now()
    from_date = to_date - timedelta(days=days)

    deals = mt5.history_deals_get(from_date, to_date)
    if deals is None:
        print(f"Error getting trades: {mt5.last_error()}")
        return []

    # Group deals by position id
    positions = defaultdict(list)
    for deal in deals:
        if deal.position_id == 0:
            # Deals without a position id (e.g. balance operations) are ignored
            continue
        positions[deal.position_id].append(deal)

    formatted_trades = []
    for pos_id, pos_deals in positions.items():
        opening = [d for d in pos_deals if d.entry == 0]
        closing = [d for d in pos_deals if d.entry == 1]

        # Skip still-open positions (no closing deal yet)
        if not opening or not closing:
            continue

        open_deal = opening[0]
        # Final close (last closing deal, handles partial closes)
        close_deal = closing[-1]

        # 0 = Buy, 1 = Sell (same direction on both legs)
        direction = open_deal.type

        formatted_trades.append({
            "ticket": close_deal.ticket,
            "symbol": open_deal.symbol,
            "type": "BUY" if direction == 0 else "SELL",
            "entry_price": open_deal.price,
            "exit_price": close_deal.price,
            "lot_size": open_deal.volume,
            "stop_loss": 0,
            "take_profit": 0,
            "pnl": round(sum(d.profit + d.commission + d.swap for d in pos_deals), 2),
            "commission": round(sum(d.commission for d in pos_deals), 2),
            "swap": round(sum(d.swap for d in pos_deals), 2),
            "open_time": datetime.fromtimestamp(open_deal.time).isoformat(),
            "close_time": datetime.fromtimestamp(close_deal.time).isoformat(),
            "timeframe": "",
            "strategy": ""
        })

    return formatted_trades


def sync_trades(app_url, user_id, token, trades):
    """Send trades to MTL Trader API."""
    url = f"{app_url}/api/sync"
    payload = {
        "userId": user_id,
        "token": token,
        "trades": trades
    }

    try:
        response = requests.post(url, json=payload, timeout=30)
        result = response.json()

        if response.status_code == 200:
            print(f"Sync successful: {result.get('imported', 0)} trades imported")
            return True
        else:
            print(f"Sync failed: {result.get('error', 'Unknown error')}")
            return False
    except requests.RequestException as e:
        print(f"Connection error: {e}")
        return False


def main():
    print("=" * 50)
    print("MTL Trader - MT5 Sync Agent")
    print("=" * 50)

    # Try to load from environment variables first
    user_id = os.environ.get("MTL_USER_ID")
    token = os.environ.get("MTL_TOKEN")
    app_url = os.environ.get("MTL_APP_URL", DEFAULT_APP_URL)

    broker_name = os.environ.get("MT5_BROKER")
    server = os.environ.get("MT5_SERVER", "")
    login = os.environ.get("MT5_LOGIN", "")
    password = os.environ.get("MT5_PASSWORD", "")

    # Fallback to CLI arguments if env vars are missing
    if not user_id or not token:
        if len(sys.argv) < 3:
            print("Usage: python mt5_agent.py <user_id> <token> [broker_name] [server] [login] [password]")
            print("\nOr set environment variables: MTL_USER_ID, MTL_TOKEN, MT5_BROKER, MT5_SERVER, MT5_LOGIN, MT5_PASSWORD")
            sys.exit(1)
        user_id = sys.argv[1]
        token = sys.argv[2]
        if len(sys.argv) > 3: broker_name = sys.argv[3]
        if len(sys.argv) > 4: server = sys.argv[4]
        if len(sys.argv) > 5: login = sys.argv[5]
        if len(sys.argv) > 6: password = sys.argv[6]

    if not broker_name or not login:
        print("Error: Broker name and Login are required via CLI or environment variables.")
        sys.exit(1)

    if not connect_to_mt5(broker_name, server, login, password):
        sys.exit(1)

    print("\nFetching trades...")
    trades = get_trades()
    print(f"Found {len(trades)} closed trades")

    if trades:
        print("\nSyncing trades to MTL Trader...")
        sync_trades(app_url, user_id, token, trades)

    print(f"\nSync complete! Next sync in {SYNC_INTERVAL} seconds...")
    print("Press Ctrl+C to stop.\n")

    try:
        while True:
            time.sleep(SYNC_INTERVAL)
            trades = get_trades()
            if trades:
                sync_trades(app_url, user_id, token, trades)
    except KeyboardInterrupt:
        print("\nStopping sync agent...")
        mt5.shutdown()
        print("Disconnected from MT5.")


if __name__ == "__main__":
    main()