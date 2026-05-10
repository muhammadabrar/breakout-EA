//+------------------------------------------------------------------+
//|                                          PrevDayBreakoutEA.mq5   |
//|                        Previous Day High/Low Breakout EA         |
//+------------------------------------------------------------------+
#property copyright "Previous Day Breakout EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Trailing Stop Modes                                               |
//+------------------------------------------------------------------+
enum ENUM_TSL_MODE
{
   TSL_OFF,              // Trailing Stop Off
   TSL_PIPS              // Trailing Stop in Pips
};

//+------------------------------------------------------------------+
//| Breakout Mode Selection                                           |
//+------------------------------------------------------------------+
enum ENUM_BREAKOUT_MODE
{
   BREAKOUT_DAILY_ONLY,  // Daily Breakout Only
   BREAKOUT_LONDON_ONLY, // London Session Breakout Only
   BREAKOUT_BOTH         // Both Daily and London
};

//+------------------------------------------------------------------+
//| Color Palette Selection                                           |
//+------------------------------------------------------------------+
enum ENUM_COLOR_PALETTE
{
   PALETTE_ONYX,        // Onyx
   PALETTE_NIGHT,       // Night
   PALETTE_ARCTIC,      // Arctic
   PALETTE_SMC,         // SMC
   PALETTE_LAVENDER,    // Lavender
   PALETTE_CLAUDE,      // Claude
   PALETTE_DEFAULT      // Default
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input double InpLotSize = 0.01;                    // Lot Size
input int InpStopLossPips = 60;                    // Stop Loss (Pips)
input int InpTakeProfitPips = 120;                 // Take Profit (Pips)
input int InpMagicNumber = 54322;                  // Magic Number
input string InpOrderComment = "PrevDayBO";        // Order Comment
input ENUM_BREAKOUT_MODE InpBreakoutMode = BREAKOUT_BOTH;  // Breakout Mode

input group "=== London Session Settings ==="
input int InpLondonStartHour = 8;                  // London Session Start Hour (GMT, 0-23)
input int InpLondonStartMinute = 0;                // London Session Start Minute (0-59)
input int InpLondonEndHour = 16;                    // London Session End Hour (GMT, 0-23)
input int InpLondonEndMinute = 0;                   // London Session End Minute (0-59)

input group "=== Trailing Stop Settings ==="
input ENUM_TSL_MODE InpTrailingMode = TSL_OFF;     // Trailing Stop Mode
input int InpTrailingStart = 10;                   // Trailing Start (Pips)
input int InpTrailingDistance = 10;                // Trailing Distance (Pips)
input double InpTrailingStep = 0.5;                // Trailing Step (Pips)

input group "=== Trading Hours ==="
input int InpStartHour = 1;                        // Trading Start Hour (0-23)
input int InpStartMinute = 15;                     // Trading Start Minute (0-59)
input int InpCloseHour = 22;                       // Trading Close Hour (0-23)
input int InpCloseMinute = 0;                      // Trading Close Minute (0-59)

input group "=== Chart Settings ==="
input bool InpShowLines = true;                    // Show High/Low Lines
input bool InpConfigureChart = true;               // Configure Chart Colors


input group "=== Chart Settings ==="
input bool InpShowLines = true;                    // Show High/Low Lines
input bool InpConfigureChart = true;               // Configure Chart Colors
input ENUM_COLOR_PALETTE InpColorPalette = PALETTE_DEFAULT;  // Color Palette
input double InpRiskPercent = 1.0;                 // Risk Per Trade (%)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
COrderInfo order;

double prevDayHigh = 0;
double prevDayLow = 0;
bool prevDayCalculated = false;

double londonHigh = 0;
double londonLow = 0;
bool londonCalculated = false;

bool ordersPlaced = false;
bool dailyOrdersPlaced = false;
bool londonOrdersPlaced = false;
int currentDate = 0;
bool tradesClosedToday = false;
double todayOpenPrice = 0;

string lineHigh = "PrevDay_High";
string lineLow = "PrevDay_Low";
string lineLondonHigh = "London_High";
string lineLondonLow = "London_Low";

// Panel object names
string panelBG       = "Panel_BG";
string panelTitle    = "Panel_Title";
string panelRisk     = "Panel_Risk";
string panelProfit   = "Panel_Profit";
string panelStatus   = "Panel_Status";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   
   trade.SetAsyncMode(false);
   
   if(InpConfigureChart)
      ConfigureChartColors();
   
   CreatePanel();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, lineHigh);
   ObjectDelete(0, lineLow);
   ObjectDelete(0, lineLondonHigh);
   ObjectDelete(0, lineLondonLow);
   DeletePanel();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   int newDate = timeStruct.year * 10000 + timeStruct.mon * 100 + timeStruct.day;
   
   if(currentDate != newDate)
   {
      currentDate = newDate;
      prevDayCalculated = false;
      londonCalculated = false;
      ordersPlaced = false;
      dailyOrdersPlaced = false;
      londonOrdersPlaced = false;
      tradesClosedToday = false;
      
      GetTodayOpenPrice();
      DeletePendingOrders();
   }
   
   if(!IsWeekday())
   {
      if(!tradesClosedToday)
      {
         CloseAllTrades();
         tradesClosedToday = true;
      }
      UpdatePanel();
      return;
   }
   
   if(!tradesClosedToday && IsCloseTime())
   {
      CloseAllTrades();
      tradesClosedToday = true;
   }
   
   if(!prevDayCalculated && (InpBreakoutMode == BREAKOUT_DAILY_ONLY || InpBreakoutMode == BREAKOUT_BOTH))
      CalculatePreviousDayHighLow();
   
   if((InpBreakoutMode == BREAKOUT_LONDON_ONLY || InpBreakoutMode == BREAKOUT_BOTH))
   {
      if(IsLondonSessionTime() || IsLondonSessionEnded())
         CalculateLondonSessionHighLow();
   }
   
   if((InpBreakoutMode == BREAKOUT_DAILY_ONLY || InpBreakoutMode == BREAKOUT_BOTH) && 
      !dailyOrdersPlaced && prevDayCalculated && IsTradingStartTime())
   {
      PlaceDailyOrders(InpLotSize, 
                      InpStopLossPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                      InpTakeProfitPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      dailyOrdersPlaced = true;
   }
   
   if((InpBreakoutMode == BREAKOUT_LONDON_ONLY || InpBreakoutMode == BREAKOUT_BOTH) && 
      !londonOrdersPlaced && londonCalculated)
   {
      if(IsLondonSessionEnded())
      {
         PlaceLondonOrders(InpLotSize,
                           InpStopLossPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                           InpTakeProfitPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
         
         int pendingOrders = 0;
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            if(order.SelectByIndex(i))
            {
               if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
               {
                  string orderComment = order.Comment();
                  if(StringFind(orderComment, "_London") >= 0)
                     pendingOrders++;
               }
            }
         }
         if(pendingOrders > 0)
            londonOrdersPlaced = true;
      }
   }
   
   ordersPlaced = dailyOrdersPlaced || londonOrdersPlaced;
   
   if(IsWeekday() && InpTrailingMode != TSL_OFF)
      ManageTrailingStops();
   
   static datetime lastConflictCheck = 0;
   if(TimeCurrent() - lastConflictCheck >= 10)
   {
      CancelConflictingPendingOrders();
      lastConflictCheck = TimeCurrent();
   }
   
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
void OnTrade()
{
   CancelConflictingPendingOrders();
}

//+------------------------------------------------------------------+
//| Configure chart colors based on selected palette                 |
//+------------------------------------------------------------------+
void ConfigureChartColors()
{
   color bgColor, bullColor, bearColor, fgColor, gridColor, volColor, lineColor;
   
   switch(InpColorPalette)
   {
      case PALETTE_ONYX:
         bgColor   = C'18,18,18';       // #121212
         bullColor = C'200,184,154';    // #c8b89a
         bearColor = C'122,115,104';    // #7a7368
         fgColor   = C'160,155,148';
         gridColor = C'28,28,28';
         volColor  = C'50,48,44';
         lineColor = C'200,184,154';
         break;
         
      case PALETTE_NIGHT:
         bgColor   = C'11,18,32';       // #0b1220
         bullColor = C'199,226,247';    // #c7e2f7
         bearColor = C'90,100,114';     // #5a6472
         fgColor   = C'120,140,165';
         gridColor = C'18,26,44';
         volColor  = C'30,40,60';
         lineColor = C'100,160,220';
         break;
         
      case PALETTE_ARCTIC:
         bgColor   = C'241,246,251';    // #f1f6fb
         bullColor = C'255,255,255';    // #ffffff
         bearColor = C'199,216,230';    // #c7d8e6
         fgColor   = C'80,100,120';
         gridColor = C'220,232,242';
         volColor  = C'180,200,215';
         lineColor = C'100,140,180';
         break;
         
      case PALETTE_SMC:
         bgColor   = C'243,241,236';    // #f3f1ec
         bullColor = C'107,143,122';    // #6b8f7a
         bearColor = C'47,42,37';       // #2f2a25
         fgColor   = C'80,75,65';
         gridColor = C'225,222,215';
         volColor  = C'180,175,165';
         lineColor = C'107,143,122';
         break;
         
      case PALETTE_LAVENDER:
         bgColor   = C'244,239,251';    // #f4effb
         bullColor = C'255,255,255';    // #ffffff
         bearColor = C'122,98,133';     // #7a6285
         fgColor   = C'100,85,115';
         gridColor = C'228,220,240';
         volColor  = C'190,178,205';
         lineColor = C'122,98,133';
         break;
         
      case PALETTE_CLAUDE:
         bgColor   = C'31,28,25';       // #1f1c19
         bullColor = C'211,138,93';     // #d38a5d
         bearColor = C'126,122,117';    // #7e7a75
         fgColor   = C'160,155,148';
         gridColor = C'40,36,32';
         volColor  = C'55,50,45';
         lineColor = C'211,138,93';
         break;
         
      default: // PALETTE_DEFAULT
         bgColor   = C'18,22,30';
         bullColor = C'72,199,142';
         bearColor = C'220,95,95';
         fgColor   = C'160,170,190';
         gridColor = C'30,36,48';
         volColor  = C'60,70,90';
         lineColor = C'100,160,220';
         break;
   }
   
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,  bgColor);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,  fgColor);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, bullColor);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, bearColor);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,    bullColor);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  bearColor);
   ChartSetInteger(0, CHART_COLOR_BID,         lineColor);
   ChartSetInteger(0, CHART_COLOR_ASK,         lineColor);
   ChartSetInteger(0, CHART_COLOR_LAST,        lineColor);
   ChartSetInteger(0, CHART_COLOR_VOLUME,      volColor);
   ChartSetInteger(0, CHART_COLOR_GRID,        gridColor);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create info panel (top-left box)                                 |
//+------------------------------------------------------------------+
void CreatePanel()
{
   // Background rectangle
   ObjectCreate(0, panelBG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelBG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelBG, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, panelBG, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, panelBG, OBJPROP_XSIZE, 200);
   ObjectSetInteger(0, panelBG, OBJPROP_YSIZE, 90);
   ObjectSetInteger(0, panelBG, OBJPROP_BGCOLOR, C'22,28,40');
   ObjectSetInteger(0, panelBG, OBJPROP_BORDER_COLOR, C'50,60,80');
   ObjectSetInteger(0, panelBG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, panelBG, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, panelBG, OBJPROP_BACK, false);
   ObjectSetInteger(0, panelBG, OBJPROP_SELECTABLE, false);
   
   // Title label
   ObjectCreate(0, panelTitle, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelTitle, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelTitle, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, panelTitle, OBJPROP_YDISTANCE, 28);
   ObjectSetString(0, panelTitle, OBJPROP_TEXT, "▪ BREAKOUT EA");
   ObjectSetString(0, panelTitle, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, panelTitle, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, panelTitle, OBJPROP_COLOR, C'100,160,220');
   ObjectSetInteger(0, panelTitle, OBJPROP_SELECTABLE, false);
   
   // Risk label
   ObjectCreate(0, panelRisk, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelRisk, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelRisk, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, panelRisk, OBJPROP_YDISTANCE, 50);
   ObjectSetString(0, panelRisk, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, panelRisk, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, panelRisk, OBJPROP_SELECTABLE, false);
   
   // Today profit label
   ObjectCreate(0, panelProfit, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelProfit, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelProfit, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, panelProfit, OBJPROP_YDISTANCE, 70);
   ObjectSetString(0, panelProfit, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, panelProfit, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, panelProfit, OBJPROP_SELECTABLE, false);
   
   // Status label
   ObjectCreate(0, panelStatus, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelStatus, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelStatus, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, panelStatus, OBJPROP_YDISTANCE, 90);
   ObjectSetString(0, panelStatus, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, panelStatus, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, panelStatus, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Delete panel objects                                             |
//+------------------------------------------------------------------+
void DeletePanel()
{
   ObjectDelete(0, panelBG);
   ObjectDelete(0, panelTitle);
   ObjectDelete(0, panelRisk);
   ObjectDelete(0, panelProfit);
   ObjectDelete(0, panelStatus);
}

//+------------------------------------------------------------------+
//| Calculate today's closed + open profit for this EA              |
//+------------------------------------------------------------------+
double GetTodayProfit()
{
   double totalProfit = 0;
   
   // Open positions profit
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            totalProfit += position.Profit() + position.Swap() + position.Commission();
      }
   }
   
   // Closed deals today
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(dayStart, TimeCurrent());
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         (long)HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
      {
         totalProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(ticket, DEAL_SWAP) +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Calculate actual risk in account currency from SL + lot size     |
//+------------------------------------------------------------------+
double GetActualRiskAmount()
{
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipInPoints  = GetPipInPoints();
   
   // SL distance in price terms
   double slDistance   = InpStopLossPips * pipInPoints * point;
   
   // Ticks in SL distance
   double ticksInSL    = (tickSize > 0) ? slDistance / tickSize : 0;
   
   // Risk per lot
   double riskPerLot   = ticksInSL * tickValue;
   
   // Total risk
   return riskPerLot * InpLotSize;
}

//+------------------------------------------------------------------+
//| Update panel values                                              |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double actualRisk     = GetActualRiskAmount();
   double riskPct        = (accountBalance > 0) ? (actualRisk / accountBalance) * 100.0 : 0.0;
   double todayProfit    = GetTodayProfit();
   
   // Risk row — actual SL-based risk
   string riskText = "Risk: " + DoubleToString(actualRisk, 2) + " " +
                     AccountInfoString(ACCOUNT_CURRENCY) +
                     " (" + DoubleToString(riskPct, 2) + "%)";
   ObjectSetString(0, panelRisk, OBJPROP_TEXT, riskText);
   
   // Color code: green if within target, red if over
   if(riskPct <= InpRiskPercent)
      ObjectSetInteger(0, panelRisk, OBJPROP_COLOR, C'72,199,142');
   else
      ObjectSetInteger(0, panelRisk, OBJPROP_COLOR, C'220,95,95');
   
   // Profit row
   string profitText = "Today P&L: " + (todayProfit >= 0 ? "+" : "") +
                       DoubleToString(todayProfit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
   ObjectSetString(0, panelProfit, OBJPROP_TEXT, profitText);
   if(todayProfit > 0)
      ObjectSetInteger(0, panelProfit, OBJPROP_COLOR, C'72,199,142');
   else if(todayProfit < 0)
      ObjectSetInteger(0, panelProfit, OBJPROP_COLOR, C'220,95,95');
   else
      ObjectSetInteger(0, panelProfit, OBJPROP_COLOR, C'160,170,190');
   
   // Status row
   string statusText = "";
   if(!IsWeekday())
      statusText = "Weekend";
   else if(IsCloseTime())
      statusText = "Closed";
   else if(!IsTradingStartTime())
      statusText = "Waiting...";
   else
      statusText = "Active";
   
   ObjectSetString(0, panelStatus, OBJPROP_TEXT, statusText);
   ObjectSetInteger(0, panelStatus, OBJPROP_COLOR, C'80,100,130');
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Calculate previous day high and low                              |
//+------------------------------------------------------------------+
void CalculatePreviousDayHighLow()
{
   double high[];
   double low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   int copiedHigh = CopyHigh(_Symbol, PERIOD_D1, 1, 1, high);
   int copiedLow = CopyLow(_Symbol, PERIOD_D1, 1, 1, low);
   
   if(copiedHigh > 0 && copiedLow > 0)
   {
      prevDayHigh = high[0];
      prevDayLow = low[0];
      prevDayCalculated = true;
      
      if(InpShowLines)
         DrawPrevDayLines();
   }
}

//+------------------------------------------------------------------+
//| Check if current time is during London session                  |
//+------------------------------------------------------------------+
bool IsLondonSessionTime()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   
   datetime londonStart = today + InpLondonStartHour * 3600 + InpLondonStartMinute * 60;
   datetime londonEnd   = today + InpLondonEndHour * 3600 + InpLondonEndMinute * 60;
   
   if(londonEnd < londonStart)
      londonEnd += 86400;
   
   return (TimeCurrent() >= londonStart);
}

//+------------------------------------------------------------------+
//| Check if London session has ended                                |
//+------------------------------------------------------------------+
bool IsLondonSessionEnded()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   
   datetime londonStart = today + InpLondonStartHour * 3600 + InpLondonStartMinute * 60;
   datetime londonEnd   = today + InpLondonEndHour * 3600 + InpLondonEndMinute * 60;
   
   if(londonEnd < londonStart)
      londonEnd += 86400;
   
   return (TimeCurrent() > londonEnd);
}

//+------------------------------------------------------------------+
//| Calculate current day London session high and low                |
//+------------------------------------------------------------------+
void CalculateLondonSessionHighLow()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   
   datetime londonStart = today + InpLondonStartHour * 3600 + InpLondonStartMinute * 60;
   datetime londonEnd   = today + InpLondonEndHour * 3600 + InpLondonEndMinute * 60;
   
   if(londonEnd < londonStart)
      londonEnd += 86400;
   
   datetime currentTime = TimeCurrent();
   datetime endTime = (currentTime < londonEnd) ? currentTime : londonEnd;
   
   int startBar = iBarShift(_Symbol, PERIOD_M1, londonStart);
   int endBar   = iBarShift(_Symbol, PERIOD_M1, endTime);
   
   if(startBar < 0)
      return;
   if(endBar < 0)
      endBar = 0;
   
   if(startBar < endBar)
   {
      int temp = startBar;
      startBar = endBar;
      endBar = temp;
   }
   
   int bars = startBar - endBar + 1;
   if(bars <= 0)
      return;
   
   double high[];
   double low[];
   ArrayResize(high, bars);
   ArrayResize(low, bars);
   
   int copiedHigh = CopyHigh(_Symbol, PERIOD_M1, endBar, bars, high);
   int copiedLow  = CopyLow(_Symbol, PERIOD_M1, endBar, bars, low);
   
   if(copiedHigh > 0 && copiedLow > 0)
   {
      londonHigh = high[ArrayMaximum(high)];
      londonLow  = low[ArrayMinimum(low)];
      londonCalculated = true;
      
      if(InpShowLines)
         DrawLondonLines();
   }
}

//+------------------------------------------------------------------+
//| Get today's open price                                            |
//+------------------------------------------------------------------+
void GetTodayOpenPrice()
{
   double open[];
   ArraySetAsSeries(open, true);
   
   int copied = CopyOpen(_Symbol, PERIOD_D1, 0, 1, open);
   if(copied > 0)
      todayOpenPrice = open[0];
   else
      todayOpenPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| Check if current day is a weekday (Monday-Friday)                |
//+------------------------------------------------------------------+
bool IsWeekday()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   return (timeStruct.day_of_week >= 1 && timeStruct.day_of_week <= 5);
}

//+------------------------------------------------------------------+
//| Check if current time is after trading start time                |
//+------------------------------------------------------------------+
bool IsTradingStartTime()
{
   if(!IsWeekday())
      return false;
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   int startMinutes   = InpStartHour * 60 + InpStartMinute;
   
   return (currentMinutes >= startMinutes);
}

//+------------------------------------------------------------------+
//| Check if current time is at or after close time                  |
//+------------------------------------------------------------------+
bool IsCloseTime()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   int closeMinutes   = InpCloseHour * 60 + InpCloseMinute;
   
   return (currentMinutes >= closeMinutes);
}

//+------------------------------------------------------------------+
//| Close all positions and pending orders                           |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            trade.PositionClose(position.Ticket());
      }
   }
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(order.SelectByIndex(i))
      {
         if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
            trade.OrderDelete(order.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Place daily breakout orders                                       |
//+------------------------------------------------------------------+
void PlaceDailyOrders(double lotSize, double slDistance, double tpDistance)
{
   string comment = InpOrderComment + "_Daily";
   
   if(todayOpenPrice <= prevDayHigh)
   {
      double buyPrice = NormalizeDouble(prevDayHigh, _Digits);
      double buySL    = NormalizeDouble(buyPrice - slDistance, _Digits);
      double buyTP    = NormalizeDouble(buyPrice + tpDistance, _Digits);
      
      if(buySL > 0 && buyTP > 0 && buySL < buyPrice && buyTP > buyPrice)
         trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_DAY, 0, comment);
   }
   
   if(todayOpenPrice >= prevDayLow)
   {
      double sellPrice = NormalizeDouble(prevDayLow, _Digits);
      double sellSL    = NormalizeDouble(sellPrice + slDistance, _Digits);
      double sellTP    = NormalizeDouble(sellPrice - tpDistance, _Digits);
      
      if(sellSL > 0 && sellTP > 0 && sellSL > sellPrice && sellTP < sellPrice)
         trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_DAY, 0, comment);
   }
}

//+------------------------------------------------------------------+
//| Place London session breakout orders                              |
//+------------------------------------------------------------------+
void PlaceLondonOrders(double lotSize, double slDistance, double tpDistance)
{
   string comment = InpOrderComment + "_London";
   
   if(londonHigh <= 0 || londonLow <= 0 || londonHigh <= londonLow)
      return;
   
   double currentBid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevel * point;
   double bufferPoints = 2 * point;
   double pipValue    = GetPipValue();
   double minPendingDistance = pipValue * 5;
   
   // --- BUY STOP ---
   double minBuyPriceForPending = currentAsk + minPendingDistance;
   double desiredBuy = MathMax(londonHigh + bufferPoints, minBuyPriceForPending);
   double minBuyPrice = currentAsk + minStopDist + bufferPoints;
   double buyPrice = NormalizeDouble(MathMax(desiredBuy, minBuyPrice), _Digits);
   
   if(currentAsk < londonHigh && buyPrice > currentAsk + minPendingDistance)
   {
      double buySL = NormalizeDouble(buyPrice - slDistance, _Digits);
      double buyTP = NormalizeDouble(buyPrice + tpDistance, _Digits);
      
      if(buySL > 0 && buyTP > 0 && buySL < buyPrice && buyTP > buyPrice)
         trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_DAY, 0, comment);
   }
   
   // --- SELL STOP ---
   double maxSellPriceForPending = currentBid - minPendingDistance;
   double desiredSell = MathMin(londonLow - bufferPoints, maxSellPriceForPending);
   double maxSellPrice = currentBid - minStopDist - bufferPoints;
   double sellPrice = NormalizeDouble(MathMin(desiredSell, maxSellPrice), _Digits);
   
   if(currentBid > londonLow && sellPrice < currentBid - minPendingDistance)
   {
      double sellSL = NormalizeDouble(sellPrice + slDistance, _Digits);
      double sellTP = NormalizeDouble(sellPrice - tpDistance, _Digits);
      
      if(sellSL > 0 && sellTP > 0 && sellSL > sellPrice && sellTP < sellPrice)
         trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_DAY, 0, comment);
   }
}

//+------------------------------------------------------------------+
//| Get pip value for the symbol (price value)                      |
//+------------------------------------------------------------------+
double GetPipValue()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return GetPipInPoints() * point;
}

//+------------------------------------------------------------------+
//| Get pip value in points for the symbol                          |
//+------------------------------------------------------------------+
double GetPipInPoints()
{
   string symbol = _Symbol;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   bool isXAU   = (StringFind(symbol, "XAU")  >= 0 || StringFind(symbol, "GOLD") >= 0 ||
                   StringFind(symbol, "xau")  >= 0 || StringFind(symbol, "gold") >= 0);
   bool isJPY   = (StringFind(symbol, "JPY")  >= 0);
   bool isIndex = (StringFind(symbol, "30")   >= 0 || StringFind(symbol, "100") >= 0 ||
                   StringFind(symbol, "500")  >= 0 || StringFind(symbol, "2000") >= 0 ||
                   StringFind(symbol, "cash") >= 0 || StringFind(symbol, "CFD")  >= 0);
   
   if(isXAU)
   {
      if(point > 0)
         return 0.10 / point;
      return (digits == 3) ? 100.0 : 10.0;
   }
   else if(isIndex)
   {
      if(point > 0)
         return 1.0 / point;
      return 1.0;
   }
   else if(isJPY)
   {
      return (digits == 3) ? 10.0 : 1.0;
   }
   else
   {
      return (digits == 5) ? 10.0 : 1.0;
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops                                            |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double openPrice  = position.PriceOpen();
            double currentSL  = position.StopLoss();
            double bidPrice   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double askPrice   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double pipValue   = GetPipValue();
            
            ENUM_POSITION_TYPE reportedType = position.Type();
            bool isLikelyBuy  = (openPrice < bidPrice);
            bool isLikelySell = (openPrice > bidPrice);
            
            ENUM_POSITION_TYPE posType;
            if(isLikelyBuy && !isLikelySell)
               posType = POSITION_TYPE_BUY;
            else if(isLikelySell && !isLikelyBuy)
               posType = POSITION_TYPE_SELL;
            else
               posType = reportedType;
            
            double currentPrice = bidPrice;
            double priceDifference;
            if(posType == POSITION_TYPE_BUY)
               priceDifference = currentPrice - openPrice;
            else
               priceDifference = openPrice - currentPrice;
            
            double profitPips = priceDifference / pipValue;
            
            if(profitPips >= InpTrailingStart)
            {
               double trailingDistance = InpTrailingDistance * pipValue;
               double trailingStep     = InpTrailingStep * pipValue;
               
               double newSL;
               if(posType == POSITION_TYPE_BUY)
                  newSL = bidPrice - trailingDistance;
               else
                  newSL = bidPrice + trailingDistance;
               
               double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
               long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               double minStop   = stopsLevel * point;
               
               if(posType == POSITION_TYPE_BUY && newSL >= bidPrice - minStop)
                  continue;
               if(posType == POSITION_TYPE_SELL && newSL <= askPrice + minStop)
                  continue;
               
               bool shouldUpdate = false;
               if(posType == POSITION_TYPE_BUY)
               {
                  if(currentSL == 0 || newSL > currentSL + trailingStep)
                     shouldUpdate = true;
               }
               else
               {
                  if(currentSL == 0)
                     shouldUpdate = true;
                  else if((currentSL - newSL) >= trailingStep)
                     shouldUpdate = true;
               }
               
               if(shouldUpdate)
                  trade.PositionModify(position.Ticket(), NormalizeDouble(newSL, _Digits), position.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete pending orders                                            |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(order.SelectByIndex(i))
      {
         if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
            trade.OrderDelete(order.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel conflicting pending orders when positions are open        |
//+------------------------------------------------------------------+
void CancelConflictingPendingOrders()
{
   for(int posIdx = PositionsTotal() - 1; posIdx >= 0; posIdx--)
   {
      if(position.SelectByIndex(posIdx))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double posEntry = position.PriceOpen();
            double posSL    = position.StopLoss();
            double posTP    = position.TakeProfit();
            ENUM_POSITION_TYPE posType = position.Type();
            
            double minPrice, maxPrice;
            
            if(posSL > 0 && posTP > 0)
            {
               minPrice = MathMin(posSL, posTP);
               maxPrice = MathMax(posSL, posTP);
            }
            else if(posSL > 0)
            {
               if(posType == POSITION_TYPE_BUY)
               { minPrice = posSL; maxPrice = posEntry; }
               else
               { minPrice = posEntry; maxPrice = posSL; }
            }
            else if(posTP > 0)
            {
               if(posType == POSITION_TYPE_BUY)
               { minPrice = posEntry; maxPrice = posTP; }
               else
               { minPrice = posTP; maxPrice = posEntry; }
            }
            else
               continue;
            
            for(int ordIdx = OrdersTotal() - 1; ordIdx >= 0; ordIdx--)
            {
               if(order.SelectByIndex(ordIdx))
               {
                  if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
                  {
                     double orderPrice = order.PriceOpen();
                     ENUM_ORDER_TYPE orderType = order.OrderType();
                     
                     bool isOpposite = false;
                     if(posType == POSITION_TYPE_BUY  && (orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL_LIMIT))
                        isOpposite = true;
                     else if(posType == POSITION_TYPE_SELL && (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_LIMIT))
                        isOpposite = true;
                     
                     if(isOpposite && orderPrice >= minPrice && orderPrice <= maxPrice)
                        trade.OrderDelete(order.Ticket());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw previous day high/low lines                                  |
//+------------------------------------------------------------------+
void DrawPrevDayLines()
{
   ObjectDelete(0, lineHigh);
   ObjectDelete(0, lineLow);
   
   ObjectCreate(0, lineHigh, OBJ_HLINE, 0, 0, prevDayHigh);
   ObjectSetInteger(0, lineHigh, OBJPROP_COLOR, C'255,165,50');
   ObjectSetInteger(0, lineHigh, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineHigh, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineHigh, OBJPROP_TEXT, "Prev Day High");
   
   ObjectCreate(0, lineLow, OBJ_HLINE, 0, 0, prevDayLow);
   ObjectSetInteger(0, lineLow, OBJPROP_COLOR, C'255,165,50');
   ObjectSetInteger(0, lineLow, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineLow, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineLow, OBJPROP_TEXT, "Prev Day Low");
}

//+------------------------------------------------------------------+
//| Draw London session high/low lines                                |
//+------------------------------------------------------------------+
void DrawLondonLines()
{
   ObjectDelete(0, lineLondonHigh);
   ObjectDelete(0, lineLondonLow);
   
   ObjectCreate(0, lineLondonHigh, OBJ_HLINE, 0, 0, londonHigh);
   ObjectSetInteger(0, lineLondonHigh, OBJPROP_COLOR, C'72,199,142');
   ObjectSetInteger(0, lineLondonHigh, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineLondonHigh, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineLondonHigh, OBJPROP_TEXT, "London High");
   
   ObjectCreate(0, lineLondonLow, OBJ_HLINE, 0, 0, londonLow);
   ObjectSetInteger(0, lineLondonLow, OBJPROP_COLOR, C'72,199,142');
   ObjectSetInteger(0, lineLondonLow, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineLondonLow, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineLondonLow, OBJPROP_TEXT, "London Low");
}
//+------------------------------------------------------------------+