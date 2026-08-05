"""
MTL Trader - MT5 Sync Agent
Connects to MetaTrader 5 and syncs trades to your MTL Trader account.
"""

import MetaTrader5 as mt5
import requests
import json
import time
import sys
from datetime import datetime, timedelta

APP_URL = "https://mtl-trader-bumx.vercel.app"
SYNC_INTERVAL = 60

def connect_to_mt5(broker_name, server, login, password):
    """Initialize and connect to MT5 terminal."""
    print(f"Connecting to {broker_name} - {server}...")
    
    if not mt5.initialize():
        print(f"MT5 initialization failed: {mt5.last_error()}")
        return False
    
    authorized = mt5.login(
        login=int(login),
        password=password,
        server=f"{broker_name}/{server}" if server not in broker_name else server
    )
    
    if not authorized:
        print(f"Login failed: {mt5.last_error()}")
        mt5.shutdown()
        return False
    
    account_info = mt5.account_info()
    print(f"Connected to {account_info.server} - Account: {account_info.login}")
    return True

def get_trades(days=365):
    """Fetch closed trades from MT5."""
    to_date = datetime.now()
    from_date = to_date - timedelta(days=days)
    
    trades = mt5.history_deals_get(from_date, to_date)
    if trades is None:
        print(f"Error getting trades: {mt5.last_error()}")
        return []
    
    formatted_trades = []
    for deal in trades:
        if deal.entry == 0:
            continue
        
        formatted_trades.append({
            "ticket": deal.ticket,
            "symbol": deal.symbol,
            "type": "BUY" if deal.type == 0 else "SELL",
            "entry_price": deal.price,
            "exit_price": deal.price,
            "lot_size": deal.volume,
            "stop_loss": 0,
            "take_profit": 0,
            "pnl": deal.profit + deal.commission + deal.swap,
            "commission": deal.commission,
            "swap": deal.swap,
            "open_time": datetime.fromtimestamp(deal.time).isoformat(),
            "close_time": datetime.fromtimestamp(deal.time).isoformat(),
            "timeframe": "",
            "strategy": ""
        })
    
    return formatted_trades

def sync_trades(user_id, token, trades):
    """Send trades to MTL Trader API."""
    url = f"{APP_URL}/api/sync"
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
    
    if len(sys.argv) < 4:
        print("Usage: python mt5_agent.py <user_id> <token> <broker_name> [server] [login] [password]")
        print("\nExample:")
        print('python mt5_agent.py your_user_id your_token "MetaQuotes" "MetaQuotes-Demo" 12345678 "your_password"')
        sys.exit(1)
    
    user_id = sys.argv[1]
    token = sys.argv[2]
    broker_name = sys.argv[3]
    server = sys.argv[4] if len(sys.argv) > 4 else ""
    login = sys.argv[5] if len(sys.argv) > 5 else ""
    password = sys.argv[6] if len(sys.argv) > 6 else ""
    
    if not connect_to_mt5(broker_name, server, login, password):
        sys.exit(1)
    
    print("\nFetching trades...")
    trades = get_trades()
    print(f"Found {len(trades)} trades")
    
    if trades:
        print("\nSyncing trades to MTL Trader...")
        sync_trades(user_id, token, trades)
    
    print(f"\nSync complete! Next sync in {SYNC_INTERVAL} seconds...")
    print("Press Ctrl+C to stop.\n")
    
    try:
        while True:
            time.sleep(SYNC_INTERVAL)
            trades = get_trades()
            if trades:
                sync_trades(user_id, token, trades)
    except KeyboardInterrupt:
        print("\nStopping sync agent...")
        mt5.shutdown()
        print("Disconnected from MT5.")

if __name__ == "__main__":
    main()
