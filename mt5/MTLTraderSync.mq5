//+------------------------------------------------------------------+
//| MTLTraderSync.mq5 - desktop sync for traders who keep MT5 open    |
//|                                                                   |
//| Attach to one chart, fill in the two inputs, allow the URL in      |
//| Tools > Options > Expert Advisors > "Allow WebRequest for listed   |
//| URL", and every closed position is pushed as it happens.           |
//|                                                                   |
//| Trades are identified by PositionIdentifier, which is stable for   |
//| the whole life of a position, so a partial close cannot create a    |
//| duplicate row. Re-sending is harmless: the server ignores a         |
//| position it already has, and a delete on the server is remembered. |
//+------------------------------------------------------------------+
#property strict
#property description "Pushes closed MT5 positions to MTL Trader."

input string InpAppUrl   = "https://mtl-trader.vercel.app"; // App URL
input string InpUserId   = "";                                // User id (from MT5 Sync page)
input string InpSyncToken= "";                                // Sync token (from MT5 Sync page)
input int    InpReconcileMinutes = 5;                          // Full reconciliation interval
input int    InpLookbackDays     = 30;                          // Days re-read on reconcile

string g_lastClose = "";
int    g_reconcileSeconds = 0;

//--- UTC ISO-8601, matching what the ingest endpoint expects -------------
string IsoUtc(datetime when)
  => TimeToString(when, TIME_DATE | TIME_SECONDS) + "Z";

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
   return hasIn && hasOut && volume > 0;
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
   datetime opened = 0;
   for(int i = 0; i < deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      profit     += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      commission += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      swap       += HistoryDealGetDouble(ticket, DEAL_SWAP);

      if(symbol == "") symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
        {
         if(type < 0) type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         datetime when = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(opened == 0 || when < opened) opened = when;
        }
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
   if(HistoryOrdersTotal() > 0)
     {
      for(int i = 0; i < HistoryOrdersTotal(); i++)
        {
         ulong orderTicket = HistoryOrderGetTicket(i);
         if(orderTicket == 0) continue;
         if(HistoryOrderGetInteger(orderTicket, ORDER_POSITION_ID) != positionId) continue;
         sl = HistoryOrderGetDouble(orderTicket, ORDER_SL);
         tp = HistoryOrderGetDouble(orderTicket, ORDER_TP);
         if(sl > 0) break;
        }
     }

   double net = NormalizeDouble(profit + commission + swap, 2);
   string json = StringFormat(
      "{\"position_id\":%I64u,\"ticket\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\","
      "\"entry_price\":%.5f,\"exit_price\":%.5f,\"lot_size\":%.2f,"
      "\"stop_loss\":%.5f,\"take_profit\":%.5f,\"pnl\":%.2f,"
      "\"commission\":%.2f,\"swap\":%.2f,\"open_time\":\"%s\",\"close_time\":\"%s\"}",
      positionId, positionId, symbol, side, entryPrice, exitPrice, volume,
      sl, tp, net, commission, swap, IsoUtc(openedAt), IsoUtc(closedAt));
   return json;
  }

//--- POST a batch of position payloads ----------------------------------
bool Push(const string &bodies[])
  {
   int count = ArraySize(bodies);
   if(count == 0)
      return true;

   string payload = StringFormat("{\"userId\":\"%s\",\"trades\":[", InpUserId);
   for(int i = 0; i < count; i++)
     {
      if(bodies[i] == "") continue;
      if(StringLen(payload) > 12 && StringGetCharacter(payload, StringLen(payload) - 1) == '}')
         payload += ",";
      payload += bodies[i];
     }
   payload += "]}";

   char post[], result[];
   string headers = "Content-Type: application/json\r\n";
   string answer;
   StringToCharArray(payload, post, 0, StringLen(payload), CP_UTF8);

   ResetLastError();
   int status = WebRequest("POST", InpAppUrl + "/api/sync", headers, 15000,
                           post, result, answer);
   if(status == -1)
     {
      PrintFormat("WebRequest failed (%d). Add %s to Tools > Options > Expert Advisors "
                  "> Allow WebRequest for listed URL.", GetLastError(), InpAppUrl);
      return false;
     }
   if(status != 200 && status != 202)
     {
      PrintFormat("Sync rejected (HTTP %d): %s", status, answer);
      return false;
     }
   return true;
  }

//--- Push every closed position whose close time is newer than the cursor
void SyncNewDeals(const bool full)
  {
   datetime from = 0;
   if(!full && StringLen(g_lastClose) > 0)
      from = StringToTime(g_lastClose);
   if(full || from == 0)
      from = TimeCurrent() - InpLookbackDays * 86400;

   if(!HistorySelect(from, TimeCurrent()))
      return;

   int total = HistoryDealsTotal();
   ulong seen[];
   string bodies[];
   datetime newest = 0;

   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      ulong positionId = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(positionId == 0) continue;
      if(ArrayFind(seen, positionId) >= 0) continue;

      string body = TradeJson(positionId);
      if(body == "")
         continue;

      int size = ArraySize(seen);
      ArrayResize(seen, size + 1);
      seen[size] = positionId;

      size = ArraySize(bodies);
      ArrayResize(bodies, size + 1);
      bodies[size] = body;

      datetime closedAt;
      datetime openedAt;
      double volume;
      ClosedPosition(positionId, openedAt, closedAt, volume);
      if(closedAt > newest) newest = closedAt;
     }

   if(ArraySize(bodies) == 0)
      return;

   if(Push(bodies))
     {
      if(newest > 0) g_lastClose = TimeToString(newest, TIME_DATE | TIME_SECONDS) + "Z";
      PrintFormat("Pushed %d position(s)", ArraySize(bodies));
     }
  }

int OnInit()
  {
   if(InpUserId == "" || InpSyncToken == "")
     {
      // The agent path needs a token; hosted connections authenticate server-side.
      Print("Set InpUserId and InpSyncToken from the MT5 Sync page.");
      return INIT_PARAMETERS_INCORRECT;
     }
   EventSetTimer(30);
   SyncNewDeals(true);
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   g_reconcileSeconds += 30;
   bool full = g_reconcileSeconds >= InpReconcileMinutes * 60;
   if(full) g_reconcileSeconds = 0;
   SyncNewDeals(full);
  }

//--- Real-time: react to the deal itself, not a poll -------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.position == 0)
      return;

   string body = TradeJson(trans.position);
   if(body == "")
      return; // still open

   string bodies[];
   ArrayResize(bodies, 1);
   bodies[0] = body;
   if(Push(bodies))
      g_lastClose = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "Z";
  }
//+------------------------------------------------------------------+
