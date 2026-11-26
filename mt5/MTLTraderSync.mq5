//+------------------------------------------------------------------+
//| MTLTraderSync.mq5 - sync + hard daily stop for MT5 desktop        |
//|                                                                   |
//| Attach to one chart, fill in the User id and Sync token from the   |
//| MT5 Sync page, and allow the app URL in Tools > Options > Expert   |
//| Advisors > "Allow WebRequest for listed URL".                      |
//|                                                                   |
//| Two jobs, one EA:                                                  |
//|                                                                   |
//|  1. **Sync.** Every closed position is pushed as it closes. Trades |
//|     are keyed by PositionIdentifier, which is stable for the whole |
//|     life of a position, so a partial close cannot create a        |
//|     duplicate. Re-sending is harmless: the server ignores a        |
//|     position it already has, and a delete on the server is         |
//|     remembered.                                                    |
//|                                                                   |
//|  2. **Hard lock.** When the journal's daily stop is reached in     |
//|     "hard" mode, the EA deletes resting orders and closes a        |
//|     position opened after the stop.                                |
//|                                                                   |
//| What the lock cannot do: a manual market order is filled by the    |
//| broker before any EA sees it, and MQL5 has no hook that refuses a  |
//| terminal click. The immediate close is damage control, not         |
//| prevention, and it pays the spread and any slippage. Only a        |
//| broker-side block, or trading through an EA that calls             |
//| MtlOrderAllowed(), prevents the order outright.                    |
//|                                                                   |
//| If the server is unreachable the EA keeps its last lock state for  |
//| InpUnreachableGraceMinutes, then releases: an outage must never    |
//| leave a trader unable to close a position.                         |
//+------------------------------------------------------------------+
#property strict
#property description "Syncs closed MT5 positions and enforces MTL Ledger's hard daily stop."
#property version   "2.00"

#include <Trade\Trade.mqh>

input string InpAppUrl           = "https://mtlledger.com"; // App URL
input string InpUserId           = "";        // User id (from MT5 Sync page)
input string InpSyncToken        = "";        // Sync token (from MT5 Sync page)
input int    InpReconcileMinutes = 30;        // Full reconciliation interval
input int    InpLookbackDays     = 30;        // Days re-read on reconcile
input bool   InpEnforceLock      = true;      // Apply the daily stop in this terminal
input bool   InpDeletePending    = true;      // Delete pending orders while locked
input bool   InpCloseNewFills    = true;      // Close positions opened while locked
input int    InpDeviationPoints  = 30;        // Slippage allowed on the close
input int    InpLockPollSeconds  = 30;        // Lock poll interval while unlocked
input int    InpUnreachableGraceMinutes = 5;  // Release after this long offline

// The timer runs at a fixed five seconds so the lock can react quickly; the
// sync and the lock poll keep their own clocks.
#define TIMER_SECONDS 5

// While a day is locked the server's answer cannot change before `until` — a
// hard lock has no in-app release — so the EA can stop asking every 30 seconds
// and still release on time. Five minutes is the safety net for the one thing
// that does move the answer: a trader changing their timezone mid-day.
#define LOCKED_POLL_SECONDS 300
// How far the server and this terminal may disagree before `until` is treated
// as untrustworthy and the normal poll takes over again.
#define LOCK_SKEW_TOLERANCE 120

string   g_appUrl = "";           // InpAppUrl without a trailing slash

datetime g_lastClose = 0;          // server time of the newest pushed close
int      g_syncSeconds = 0;
int      g_reconcileSeconds = 0;
int      g_lockSeconds = 0;

bool     g_locked = false;
string   g_lockReason = "";
datetime g_lockLastOk = 0;
datetime g_lockedSince = 0;   // the stop instant, in server time
datetime g_lockUntil = 0;     // the day end the server reported, server time
long     g_serverSkew = 0;    // server clock minus this terminal's clock, seconds
string   g_lockMode = "";     // off | soft | hard, as the server reports it

CTrade   g_trade;

//--- `2026-11-13T14:00:00Z`, the only timestamp shape the API accepts ----
string IsoUtc(const datetime when)
  {
   MqlDateTime parts;
   TimeToStruct(when, parts);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       parts.year, parts.mon, parts.day,
                       parts.hour, parts.min, parts.sec);
  }

//--- Broker-server time to UTC -------------------------------------------
// Deal times are server time, not UTC and not the PC's local time. The current
// server offset is `TimeTradeServer() - TimeGMT()`, so a deal maps onto the UTC
// clock the journal stores. A DST change inside the lookback can skew a few
// older trades by an hour; new ones are exact.
datetime ServerToUtc(const datetime serverTime)
  {
   long offset = (long)TimeTradeServer() - (long)TimeGMT();
   return (datetime)((long)serverTime - offset);
  }

//--- `2026-11-13T14:00:00Z` (UTC) -> server time -----------------------
datetime ParseIsoUtc(const string value)
  {
   if(StringLen(value) < 19)
      return 0;

   MqlDateTime parts;
   parts.year = (int)StringToInteger(StringSubstr(value, 0, 4));
   parts.mon  = (int)StringToInteger(StringSubstr(value, 5, 2));
   parts.day  = (int)StringToInteger(StringSubstr(value, 8, 2));
   parts.hour = (int)StringToInteger(StringSubstr(value, 11, 2));
   parts.min  = (int)StringToInteger(StringSubstr(value, 14, 2));
   parts.sec  = (int)StringToInteger(StringSubstr(value, 17, 2));

   datetime utc = StructToTime(parts);
   long offset = (long)TimeTradeServer() - (long)TimeGMT();
   return (datetime)((long)utc + offset);
  }

//--- The value of `"key":"..."` in the flat JSON the lock route returns ---
string JsonString(const string body, const string key)
  {
   string needle = "\"" + key + "\":\"";
   int at = StringFind(body, needle);
   if(at < 0)
      return "";
   int from = at + StringLen(needle);
   int to = StringFind(body, "\"", from);
   if(to <= from)
      return "";
   return StringSubstr(body, from, to - from);
  }

//--- Position id -> whether it has a closing deal ------------------------
bool ClosedPosition(const ulong positionId, datetime &openedAt, datetime &closedAt, double &volume)
  {
   if(!HistorySelectByPosition(positionId))
      return false;

   int deals = HistoryDealsTotal();
   bool hasIn = false, hasOut = false;
   openedAt = 0; closedAt = 0;
   double inVolume = 0, outVolume = 0;

   for(int i = 0; i < deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      datetime when = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);

      // ENTRY_IN=0, ENTRY_OUT=1, ENTRY_INOUT=2, ENTRY_OUT_BY=3
      if(entry == DEAL_ENTRY_IN)
        {
         hasIn = true;
         inVolume += vol;
         if(openedAt == 0 || when < openedAt) openedAt = when;
        }
      else
        {
         hasOut = true;
         outVolume += vol;
         if(when > closedAt) closedAt = when;
        }
     }

   volume = MathMin(inVolume, outVolume);

   // **Fully** closed, not merely scaled out. The API ignores a duplicate row,
   // so pushing a position after its first partial close would freeze that
   // partial P&L forever. `Volume` is the matched amount to send.
   return hasIn && hasOut && volume > 0 && outVolume >= inVolume - 0.000001;
  }

//--- Weighted average price across the deals of one side -----------------
double SidePrice(const ulong positionId, const bool entrySide)
  {
   if(!HistorySelectByPosition(positionId))
      return 0;

   int deals = HistoryDealsTotal();
   double volume = 0, notional = 0;
   for(int i = 0; i < deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      bool isEntry = (entry == DEAL_ENTRY_IN);
      if(isEntry != entrySide)
         continue;
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      volume += vol;
      notional += HistoryDealGetDouble(ticket, DEAL_PRICE) * vol;
     }
   return volume > 0 ? notional / volume : 0;
  }

//--- Build the JSON object for one position ------------------------------
string TradeJson(const ulong positionId)
  {
   if(!HistorySelectByPosition(positionId))
      return "";
   int deals = HistoryDealsTotal();
   if(deals <= 0)
      return "";

   double profit = 0, commission = 0, swap = 0;
   long type = -1;
   string symbol = "";
   for(int i = 0; i < deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      profit     += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      commission += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      swap       += HistoryDealGetDouble(ticket, DEAL_SWAP);

      if(symbol == "") symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN && type < 0)
         type = HistoryDealGetInteger(ticket, DEAL_TYPE);
     }

   datetime openedAt, closedAt;
   double volume;
   if(!ClosedPosition(positionId, openedAt, closedAt, volume))
      return "";

   // Side comes from the opening deal: DEAL_TYPE_BUY=0, DEAL_TYPE_SELL=1.
   string side = (type == 0) ? "BUY" : "SELL";
   double entryPrice = SidePrice(positionId, true);
   double exitPrice  = SidePrice(positionId, false);

   // Stop and target from the opening order, the only place they survive.
   double sl = 0, tp = 0;
   for(int i = 0; i < HistoryOrdersTotal(); i++)
     {
      ulong orderTicket = HistoryOrderGetTicket(i);
      if(orderTicket == 0) continue;
      if(HistoryOrderGetInteger(orderTicket, ORDER_POSITION_ID) != positionId) continue;
      sl = HistoryOrderGetDouble(orderTicket, ORDER_SL);
      tp = HistoryOrderGetDouble(orderTicket, ORDER_TP);
      if(sl > 0) break;
     }

   double net = NormalizeDouble(profit + commission + swap, 2);
   string json = StringFormat(
      "{\"position_id\":%I64u,\"ticket\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\","
      "\"entry_price\":%.5f,\"exit_price\":%.5f,\"lot_size\":%.2f,"
      "\"stop_loss\":%.5f,\"take_profit\":%.5f,\"pnl\":%.2f,"
      "\"commission\":%.2f,\"swap\":%.2f,\"open_time\":\"%s\",\"close_time\":\"%s\"}",
      positionId, positionId, symbol, side, entryPrice, exitPrice, volume,
      sl, tp, net, commission, swap,
      IsoUtc(ServerToUtc(openedAt)), IsoUtc(ServerToUtc(closedAt)));
   return json;
  }

bool ContainsId(const ulong &ids[], const ulong id)
  {
   for(int i = 0; i < ArraySize(ids); i++)
      if(ids[i] == id) return true;
   return false;
  }

//--- POST one batch of position payloads ---------------------------------
bool PostBatch(const string &bodies[], const int start, const int count)
  {
   string payload = "{\"userId\":\"" + InpUserId + "\",\"token\":\"" + InpSyncToken + "\",\"trades\":[";
   bool first = true;
   for(int i = start; i < start + count; i++)
     {
      if(bodies[i] == "") continue;
      if(!first) payload += ",";
      payload += bodies[i];
      first = false;
     }
   payload += "]}";

   char post[], result[];
   string headers = "Content-Type: application/json\r\n";
   string answer;
   StringToCharArray(payload, post, 0, StringLen(payload), CP_UTF8);

   ResetLastError();
   int status = WebRequest("POST", g_appUrl + "/api/sync", headers, 20000,
                           post, result, answer);
   if(status == -1)
     {
      PrintFormat("WebRequest failed (%d). Add %s to Tools > Options > Expert Advisors "
                  "> Allow WebRequest for listed URL.", GetLastError(), g_appUrl);
      return false;
     }
   if(status != 200 && status != 202)
     {
      PrintFormat("Sync rejected (HTTP %d): %s", status, answer);
      return false;
     }
   return true;
  }

void CheckLock();

//--- Push every closed position, in chunks the API will accept -----------
bool Push(const string &bodies[])
  {
   int total = ArraySize(bodies);
   if(total == 0)
      return true;

   // The route rejects batches over 5000 and request bodies over 1 MB. Two
   // hundred positions is comfortably inside both.
   const int chunk = 200;
   for(int start = 0; start < total; start += chunk)
     {
      int count = MathMin(chunk, total - start);
      if(!PostBatch(bodies, start, count))
         return false;
     }
   return true;
  }

//--- Push every closed position whose close time is newer than the cursor
void SyncNewDeals(const bool full)
  {
   datetime from = 0;
   if(!full && g_lastClose > 0)
      from = g_lastClose - 60; // one minute of overlap; the upsert absorbs it
   if(full || from == 0)
      from = TimeCurrent() - (datetime)InpLookbackDays * 86400;

   if(!HistorySelect(from, TimeCurrent()))
      return;

   int total = HistoryDealsTotal();
   ulong ids[];

   // First pass: read only the current selection. `TradeJson` calls
   // `HistorySelectByPosition`, which replaces the selection — calling it here
   // would invalidate `HistoryDealGetTicket(i)` for every later deal.
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      ulong positionId = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(positionId == 0 || ContainsId(ids, positionId)) continue;
      // A position with only entry deals in the window is still open; one with
      // a closing deal is a candidate. `ClosedPosition` decides below.
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN) continue;

      int size = ArraySize(ids);
      ArrayResize(ids, size + 1);
      ids[size] = positionId;
     }

   string bodies[];
   datetime newest = 0;

   // Second pass: safe to re-select per position, and only fully closed ones
   // produce a body.
   for(int i = 0; i < ArraySize(ids); i++)
     {
      datetime openedAt, closedAt;
      double volume;
      if(!ClosedPosition(ids[i], openedAt, closedAt, volume))
         continue;
      if(closedAt > newest) newest = closedAt;

      string body = TradeJson(ids[i]);
      if(body == "")
         continue;

      int size = ArraySize(bodies);
      ArrayResize(bodies, size + 1);
      bodies[size] = body;
     }

   if(ArraySize(bodies) == 0)
      return;

   if(Push(bodies))
     {
      if(newest > 0) g_lastClose = newest;
      PrintFormat("Pushed %d position(s)", ArraySize(bodies));
      // A close from another terminal or the phone can breach the stop too.
      CheckLock();
     }
  }

//--- Ask the server whether today's stop is active ------------------------
bool FetchLock()
  {
   string url = g_appUrl + "/api/ea/lock?userId=" + InpUserId;
   string headers = "Authorization: Bearer " + InpSyncToken + "\r\n";
   char   data[], result[];
   string answer;

   ResetLastError();
   // A long timeout blocks the timer thread, and OnTradeTransaction runs on that
   // same thread: a hung poll would delay the close the lock exists to make.
   int status = WebRequest("GET", url, headers, 4000, data, result, answer);
   if(status == -1)
     {
      PrintFormat("Lock check failed (%d). Add %s to Tools > Options > Expert Advisors "
                  "> Allow WebRequest for listed URL.", GetLastError(), g_appUrl);
      return false;
     }
   if(status != 200)
     {
      PrintFormat("Lock check rejected (HTTP %d): %s", status, answer);
      return false;
     }

   bool locked = StringFind(answer, "\"locked\":true") >= 0;
   string reason = JsonString(answer, "reason");
   datetime since = ParseIsoUtc(JsonString(answer, "since"));

   // The day end and the server's clock are what let the EA stop polling every
   // 30 seconds while locked: nothing can change the answer before `until`.
   g_lockUntil = ParseIsoUtc(JsonString(answer, "until"));
   g_lockMode = JsonString(answer, "mode");
   datetime serverAt = ParseIsoUtc(JsonString(answer, "serverTime"));
   if(serverAt > 0)
      g_serverSkew = (long)serverAt - (long)TimeCurrent();

   g_lockLastOk = TimeCurrent();

   if(locked != g_locked)
     {
      g_locked = locked;
      g_lockReason = reason;
      if(locked)
        {
         // The stop instant, not the moment this poll saw it: a position opened
         // between the breach and the poll is still an after-stop fill.
         g_lockedSince = since > 0 ? since : TimeCurrent();
         PrintFormat("Daily stop active (%s): %s", g_lockMode, reason);
         // Say what happens, not what cannot: a manual market order still fills
         // at the broker before this terminal reports it.
         Alert("MTL Ledger: daily stop reached. Resting orders are removed and new "
               "fills are closed; a manual market order can still fill.");
        }
      else
        {
         g_lockedSince = 0;
         g_lockUntil = 0;
         g_serverSkew = 0;
         g_lockMode = "";
         Print("MTL Ledger: daily stop released.");
        }
     }

   return true;
  }

//--- A pending order is the only kind that can be removed before it fills
bool IsPendingOrder(const long type)
  {
   return type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
          type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
          type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT;
  }

//--- Remove every resting order while locked -----------------------------
void RemovePendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!IsPendingOrder(OrderGetInteger(ORDER_TYPE))) continue;

      if(g_trade.OrderDelete(ticket))
         PrintFormat("Daily stop: deleted pending order %I64u.", ticket);
      else
         PrintFormat("Daily stop: could not delete order %I64u (%d).",
                     ticket, g_trade.ResultRetcode());
     }
  }

//--- Was this position created by a deal that is still its entry? --------
bool OpenedByEntryDeal(const ulong positionId)
  {
   if(!HistorySelectByPosition(positionId)) return false;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID) != positionId) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN) return true;
     }
   return false;
  }

//--- Close a fill that landed while the day was locked -------------------
void CloseIfLocked(const ulong positionId)
  {
   if(!InpEnforceLock || !g_locked || !InpCloseNewFills || positionId == 0) return;
   if(!OpenedByEntryDeal(positionId)) return;
   if(!PositionSelectByTicket(positionId)) return;

   // Never close a position that existed before the stop. A partial close of an
   // older trade must not turn the lock into a forced exit.
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   if(g_lockedSince > 0 && opened < g_lockedSince)
      return;

   PrintFormat("Daily stop: closing position %I64u opened after the stop.", positionId);
   if(!g_trade.PositionClose(positionId))
      PrintFormat("Daily stop: close failed (%d) %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
  }

//--- How long to wait before the next lock poll, in seconds --------------
int LockPollInterval()
  {
   int normal = MathMax(5, InpLockPollSeconds);
   if(!g_locked || g_lockUntil <= 0)
      return normal;

   // Only a hard lock is guaranteed to last until the day ends. A soft lock can
   // be lifted from the journal at any moment, so slowing that poll would leave
   // MT5 frozen for minutes after the trader reopened the day.
   if(g_lockMode != "hard")
      return normal;

   // A terminal and a server whose clocks disagree cannot be trusted with
   // `until`; a trader changing timezone mid-day moves it. The normal poll is
   // the safe answer in both cases.
   if(g_serverSkew > LOCK_SKEW_TOLERANCE || g_serverSkew < -LOCK_SKEW_TOLERANCE)
      return normal;

   // Inside the last minute the release is imminent, so ask again normally.
   if(TimeCurrent() + 60 >= g_lockUntil)
      return normal;

   return MathMax(normal, LOCKED_POLL_SECONDS);
  }

void CheckLock()
  {
   if(!InpEnforceLock)
      return;

   if(!FetchLock())
     {
      // Keep the last state briefly: a dropped connection is not an unlock.
      if(g_locked && g_lockLastOk > 0 &&
         TimeCurrent() - g_lockLastOk > (datetime)InpUnreachableGraceMinutes * 60)
        {
         g_locked = false;
         g_lockedSince = 0;
         g_lockUntil = 0;
         g_serverSkew = 0;
         g_lockMode = "";
         Print("Daily stop: server unreachable past the grace period; releasing so the "
               "account can still be managed.");
        }
      return;
     }

   // Nothing to sweep is the common case on a quiet day; walking the order list
   // for it is pure waste.
   if(g_locked && InpDeletePending && OrdersTotal() > 0)
      RemovePendingOrders();
  }

int OnInit()
  {
   if(InpUserId == "" || InpSyncToken == "")
     {
      // The agent path needs a token; hosted connections authenticate server-side.
      Print("Set InpUserId and InpSyncToken from the MT5 Sync page.");
      return INIT_PARAMETERS_INCORRECT;
     }

   // A pasted URL often ends in a slash; `//api/sync` would 404.
   g_appUrl = InpAppUrl;
   int length = StringLen(g_appUrl);
   while(length > 0 && StringGetCharacter(g_appUrl, length - 1) == '/')
     {
      g_appUrl = StringSubstr(g_appUrl, 0, length - 1);
      length--;
     }

   g_trade.SetDeviationInPoints(InpDeviationPoints);
   EventSetTimer(TIMER_SECONDS);

   // Do not block the attach with two HTTP calls. Pretend both clocks are due
   // so the first timer tick (five seconds) does the lock check and the first
   // full sync.
   g_lockSeconds = MathMax(5, InpLockPollSeconds);
   g_syncSeconds = 5;  // journal a close from another terminal (the phone) within one tick
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void OnTimer()
  {
   g_lockSeconds += TIMER_SECONDS;
   if(g_lockSeconds >= LockPollInterval())
     {
      g_lockSeconds = 0;
      CheckLock();
     }

   g_reconcileSeconds += TIMER_SECONDS;
   g_syncSeconds += TIMER_SECONDS;
   if(g_syncSeconds >= 5)
     {
      g_syncSeconds = 0;
      bool full = g_reconcileSeconds >= InpReconcileMinutes * 60;
      if(full) g_reconcileSeconds = 0;
      SyncNewDeals(full);
     }
  }

//--- Real-time: react to the deal itself, not a poll -------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Polling is slow while locked, so a resting order must not wait for it: a
   // limit order placed on a locked day is removed the moment the terminal
   // reports it. Deleting it here is also what lets the five-minute poll be safe.
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
     {
      if(g_locked && InpEnforceLock && InpDeletePending && trans.order > 0 &&
         trans.order_state == ORDER_STATE_PLACED)
        {
         if(g_trade.OrderDelete(trans.order))
            PrintFormat("Daily stop: deleted pending order %I64u.", trans.order);
        }
      return;
     }

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.position == 0)
      return;

   // The lock reacts first: a fill that lands while locked is closed before it
   // has a chance to become a trade the trader keeps.
   CloseIfLocked(trans.position);

   string body = TradeJson(trans.position);
   if(body == "")
      return; // still open

   string bodies[];
   ArrayResize(bodies, 1);
   bodies[0] = body;
   // The cursor is advanced by the timer's cursor sync, which knows the close
   // time. Advancing it to "now" here could skip a trade that closed between
   // the old cursor and this single push.
   Push(bodies);

   // A close can be the one that breaches the daily stop. Ask now rather than
   // waiting for the next lock poll, so the freeze lands right after the loss.
   CheckLock();
  }

//--- For an execution EA: refuse to send unless this returns true ----------
bool MtlOrderAllowed()
  {
   return !g_locked;
  }

bool MtlTradingLocked()
  {
   return g_locked;
  }
//+------------------------------------------------------------------+
