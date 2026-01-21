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
input double InpTrailingStep = 0.5;                     // Trailing Step (Pips)

input group "=== Trading Hours ==="
input int InpStartHour = 1;                        // Trading Start Hour (0-23)
input int InpStartMinute = 15;                     // Trading Start Minute (0-59)
input int InpCloseHour = 22;                       // Trading Close Hour (0-23)
input int InpCloseMinute = 0;                     // Trading Close Minute (0-59)

input group "=== Chart Settings ==="
input bool InpShowLines = true;                    // Show High/Low Lines
input bool InpConfigureChart = true;               // Configure Chart Colors

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

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   
   // Set filling mode
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   
   trade.SetAsyncMode(false);
   
   // Configure chart colors
   if(InpConfigureChart)
      ConfigureChartColors();
   
   Print("Previous Day Breakout EA Initialized");
   Print("Symbol: ", _Symbol);
   Print("SL: ", InpStopLossPips, " pips | TP: ", InpTakeProfitPips, " pips");
   
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
   
   // Reset on new day
   if(currentDate != newDate)
   {
      currentDate = newDate;
      prevDayCalculated = false;
      londonCalculated = false;
      ordersPlaced = false;
      dailyOrdersPlaced = false;
      londonOrdersPlaced = false;
      tradesClosedToday = false;
      
      // Get today's open price
      GetTodayOpenPrice();
      
      // Delete old pending orders
      DeletePendingOrders();
   }
   
   // Check if it's a weekend - if so, close all trades and don't trade
   if(!IsWeekday())
   {
      if(!tradesClosedToday)
      {
         CloseAllTrades();
         tradesClosedToday = true;
         Print("Weekend detected - all trades closed. Trading disabled until Monday.");
      }
      UpdateChartComment();
      return; // Exit early on weekends
   }
   
   // Check if it's time to close all trades (Friday 22:00 or any day at close time)
   if(!tradesClosedToday && IsCloseTime())
   {
      CloseAllTrades();
      tradesClosedToday = true;
      
      MqlDateTime timeStruct;
      TimeToStruct(TimeCurrent(), timeStruct);
      if(timeStruct.day_of_week == 5) // Friday
      {
         Print("Friday 22:00 - All trades closed. Trading will resume Monday 1:15.");
      }
   }
   
   // Calculate previous day high/low (only on weekdays)
   if(!prevDayCalculated && (InpBreakoutMode == BREAKOUT_DAILY_ONLY || InpBreakoutMode == BREAKOUT_BOTH))
   {
      CalculatePreviousDayHighLow();
   }
   
   // Calculate current day London session high/low (only on weekdays)
   // Update continuously during London session, or do final calculation after session ends
   if((InpBreakoutMode == BREAKOUT_LONDON_ONLY || InpBreakoutMode == BREAKOUT_BOTH))
   {
      // Calculate during session (updates continuously) or after session ends (final calculation)
      if(IsLondonSessionTime() || IsLondonSessionEnded())
      {
         CalculateLondonSessionHighLow();
      }
   }
   
   // Place daily orders if ready and trading hours allow
   if((InpBreakoutMode == BREAKOUT_DAILY_ONLY || InpBreakoutMode == BREAKOUT_BOTH) && 
      !dailyOrdersPlaced && prevDayCalculated && IsTradingStartTime())
   {
      PlaceDailyOrders(InpLotSize, 
                      InpStopLossPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                      InpTakeProfitPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      dailyOrdersPlaced = true;
   }
   
   // Place London orders ONLY AFTER London session has ended
   if((InpBreakoutMode == BREAKOUT_LONDON_ONLY || InpBreakoutMode == BREAKOUT_BOTH) && 
      !londonOrdersPlaced && londonCalculated)
   {
      // Only place orders AFTER the London session has ended
      if(IsLondonSessionEnded())
      {
         Print("=== London session ended - Placing pending orders at High: ", londonHigh, " Low: ", londonLow, " ===");
         PlaceLondonOrders(InpLotSize,
                           InpStopLossPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                           InpTakeProfitPips * GetPipInPoints() * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
         
         // Check if orders were actually placed before setting flag
         int pendingOrders = 0;
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            if(order.SelectByIndex(i))
            {
               if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
               {
                  string orderComment = order.Comment();
                  if(StringFind(orderComment, "_London") >= 0)
                  {
                     pendingOrders++;
                  }
               }
            }
         }
         
         if(pendingOrders > 0)
         {
            londonOrdersPlaced = true;
            Print("London orders successfully placed. Count: ", pendingOrders);
         }
         else
         {
            Print("WARNING: London orders were not placed. Check PlaceLondonOrders() output for errors.");
         }
      }
      else
      {
         // Session still active - wait for it to end
         static datetime lastLogTime = 0;
         if(TimeCurrent() - lastLogTime >= 60) // Log every minute to avoid spam
         {
            Print("London session still active - Waiting for session to end before placing orders. High: ", londonHigh, " Low: ", londonLow);
            lastLogTime = TimeCurrent();
         }
      }
   }
   
   // Update combined ordersPlaced flag for backward compatibility
   ordersPlaced = dailyOrdersPlaced || londonOrdersPlaced;
   
   // Manage trailing stops (only on weekdays and during trading hours)
   if(IsWeekday() && InpTrailingMode != TSL_OFF)
      ManageTrailingStops();
   
   // Periodically check for conflicting pending orders (every 10 seconds)
   static datetime lastConflictCheck = 0;
   if(TimeCurrent() - lastConflictCheck >= 10)
   {
      CancelConflictingPendingOrders();
      lastConflictCheck = TimeCurrent();
   }
   
   // Update chart comment
   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Check for new positions and cancel conflicting pending orders
   CancelConflictingPendingOrders();
}

//+------------------------------------------------------------------+
//| Configure chart colors                                            |
//+------------------------------------------------------------------+
void ConfigureChartColors()
{
   // Remove grid
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   // Set background color to white
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);  // White background
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   
   // Set candle colors - yellowish for bullish, blackish for bearish
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'255,235,59');   // Yellowish
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'30,30,30');     // Blackish
   ChartSetInteger(0, CHART_COLOR_CHART_UP, C'255,235,59');      // Yellowish
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'30,30,30');      // Blackish
   ChartSetInteger(0, CHART_COLOR_BID, clrYellow);
   ChartSetInteger(0, CHART_COLOR_ASK, clrYellow);
   ChartSetInteger(0, CHART_COLOR_LAST, clrYellow);
   ChartSetInteger(0, CHART_COLOR_VOLUME, C'100,100,100');       // Gray for volume
   
   // Set chart line colors
   ChartSetInteger(0, CHART_COLOR_GRID, C'200,200,200');       // Light gray grid (if enabled)
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);        // White background
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Calculate previous day high and low                              |
//+------------------------------------------------------------------+
void CalculatePreviousDayHighLow()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Get previous day's date
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   datetime prevDayStart = today - 86400; // 24 hours ago
   datetime prevDayEnd = today;
   
   // Get high/low for previous day
   int startBar = iBarShift(_Symbol, PERIOD_D1, prevDayStart);
   int endBar = iBarShift(_Symbol, PERIOD_D1, prevDayEnd);
   
   if(startBar < 0 || endBar < 0)
   {
      // Try using M1 bars for more precision
      startBar = iBarShift(_Symbol, PERIOD_M1, prevDayStart);
      endBar = iBarShift(_Symbol, PERIOD_M1, prevDayEnd);
      
      if(startBar < 0 || endBar < 0)
      {
         Print("Cannot find bars for previous day");
         return;
      }
   }
   
   int bars = MathAbs(startBar - endBar) + 1;
   if(bars <= 0) bars = 100; // Default to 100 bars if calculation fails
   
   double high[];
   double low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   // Use daily period for calculation
   int copiedHigh = CopyHigh(_Symbol, PERIOD_D1, 1, 1, high);
   int copiedLow = CopyLow(_Symbol, PERIOD_D1, 1, 1, low);
   
   if(copiedHigh > 0 && copiedLow > 0)
   {
      prevDayHigh = high[0];
      prevDayLow = low[0];
      prevDayCalculated = true;
      
      // Draw lines
      if(InpShowLines)
         DrawPrevDayLines();
      
      Print("Previous day calculated - High: ", prevDayHigh, " | Low: ", prevDayLow);
   }
   else
   {
      Print("Failed to get previous day high/low");
   }
}

//+------------------------------------------------------------------+
//| Check if current time is during London session                  |
//+------------------------------------------------------------------+
bool IsLondonSessionTime()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Get today's date
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   
   // Calculate London session start and end times for current day
   datetime londonStart = today + InpLondonStartHour * 3600 + InpLondonStartMinute * 60;
   datetime londonEnd = today + InpLondonEndHour * 3600 + InpLondonEndMinute * 60;
   
   // If London session ends after midnight, adjust
   if(londonEnd < londonStart)
   {
      londonEnd += 86400; // Add 24 hours
   }
   
   datetime currentTime = TimeCurrent();
   
   // Check if current time is at or after London session start
   return (currentTime >= londonStart);
}

//+------------------------------------------------------------------+
//| Check if London session has ended                                |
//+------------------------------------------------------------------+
bool IsLondonSessionEnded()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Get today's date
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   
   // Calculate London session start and end times for current day
   datetime londonStart = today + InpLondonStartHour * 3600 + InpLondonStartMinute * 60;
   datetime londonEnd = today + InpLondonEndHour * 3600 + InpLondonEndMinute * 60;
   
   // If London session ends after midnight, adjust
   if(londonEnd < londonStart)
   {
      londonEnd += 86400; // Add 24 hours
   }
   
   datetime currentTime = TimeCurrent();
   
   // Check if current time is after London session end
   return (currentTime > londonEnd);
}

//+------------------------------------------------------------------+
//| Calculate current day London session high and low                |
//+------------------------------------------------------------------+
void CalculateLondonSessionHighLow()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Get today's date
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day) + " 00:00");
   
   // Calculate London session start and end times for current day
   datetime londonStart = today + InpLondonStartHour * 3600 + InpLondonStartMinute * 60;
   datetime londonEnd = today + InpLondonEndHour * 3600 + InpLondonEndMinute * 60;
   
   // If London session ends after midnight, adjust
   if(londonEnd < londonStart)
   {
      londonEnd += 86400; // Add 24 hours
   }
   
   datetime currentTime = TimeCurrent();
   
   // Use current time as end if London session hasn't ended yet
   datetime endTime = (currentTime < londonEnd) ? currentTime : londonEnd;
   
   // Get high/low for London session using M1 bars for precision
   int startBar = iBarShift(_Symbol, PERIOD_M1, londonStart);
   int endBar = iBarShift(_Symbol, PERIOD_M1, endTime);
   
   if(startBar < 0 || endBar < 0)
   {
      // If bars not found, try with current time
      if(startBar < 0)
      {
         Print("Cannot find start bar for London session. London Start: ", TimeToString(londonStart));
         return;
      }
      if(endBar < 0)
      {
         endBar = 0; // Use current bar if end bar not found
      }
   }
   
   // iBarShift returns bar index where 0 is current bar, larger numbers are older bars
   // londonStart is earlier (older), so startBar should be larger than endBar
   // If not, swap them
   if(startBar < endBar)
   {
      int temp = startBar;
      startBar = endBar;
      endBar = temp;
   }
   
   int bars = startBar - endBar + 1;
   if(bars <= 0)
   {
      Print("Invalid bar range for London session. StartBar: ", startBar, " EndBar: ", endBar);
      return;
   }
   
   // Copy high and low data for London session
   // Copy from endBar (more recent) to startBar (older), so we copy bars starting from endBar
   double high[];
   double low[];
   ArrayResize(high, bars);
   ArrayResize(low, bars);
   
   int copiedHigh = CopyHigh(_Symbol, PERIOD_M1, endBar, bars, high);
   int copiedLow = CopyLow(_Symbol, PERIOD_M1, endBar, bars, low);
   
   if(copiedHigh > 0 && copiedLow > 0)
   {
      // Find maximum high and minimum low
      londonHigh = high[ArrayMaximum(high)];
      londonLow = low[ArrayMinimum(low)];
      
      londonCalculated = true;
      
      // Draw lines
      if(InpShowLines)
         DrawLondonLines();
      
      string status = (currentTime < londonEnd) ? " (Live)" : " (Complete)";
      Print("Current day London session calculated - High: ", londonHigh, " | Low: ", londonLow, 
            " | Bars: ", bars, status, " (", TimeToString(londonStart), " to ", TimeToString(endTime), ")");
   }
   else
   {
      Print("Failed to get London session high/low. CopiedHigh: ", copiedHigh, " CopiedLow: ", copiedLow);
   }
}

//+------------------------------------------------------------------+
//| Get today's open price                                            |
//+------------------------------------------------------------------+
void GetTodayOpenPrice()
{
   double open[];
   ArraySetAsSeries(open, true);
   
   // Get today's open from daily chart
   int copied = CopyOpen(_Symbol, PERIOD_D1, 0, 1, open);
   if(copied > 0)
   {
      todayOpenPrice = open[0];
      Print("Today's open price: ", todayOpenPrice);
   }
   else
   {
      // Fallback: use current price if daily data not available
      todayOpenPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      Print("Warning: Could not get today's open, using current price: ", todayOpenPrice);
   }
}

//+------------------------------------------------------------------+
//| Check if current day is a weekday (Monday-Friday)                |
//+------------------------------------------------------------------+
bool IsWeekday()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // day_of_week: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
   // Return true for Monday (1) through Friday (5)
   return (timeStruct.day_of_week >= 1 && timeStruct.day_of_week <= 5);
}

//+------------------------------------------------------------------+
//| Check if current time is after trading start time                |
//+------------------------------------------------------------------+
bool IsTradingStartTime()
{
   // First check if it's a weekday
   if(!IsWeekday())
      return false;
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   int startMinutes = InpStartHour * 60 + InpStartMinute;
   
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
   int closeMinutes = InpCloseHour * 60 + InpCloseMinute;
   
   return (currentMinutes >= closeMinutes);
}

//+------------------------------------------------------------------+
//| Close all positions and pending orders                           |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   Print("=== Closing all trades at close time ===");
   
   // Close all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            if(trade.PositionClose(position.Ticket()))
            {
               Print("Position closed: ", position.Ticket());
            }
            else
            {
               Print("Failed to close position: ", position.Ticket(), " Error: ", GetLastError());
            }
         }
      }
   }
   
   // Delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(order.SelectByIndex(i))
      {
         if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
         {
            if(trade.OrderDelete(order.Ticket()))
            {
               Print("Pending order deleted: ", order.Ticket());
            }
            else
            {
               Print("Failed to delete pending order: ", order.Ticket(), " Error: ", GetLastError());
            }
         }
      }
   }
   
   Print("All trades closed/deleted");
}

//+------------------------------------------------------------------+
//| Place pending orders                                              |
//+------------------------------------------------------------------+
void PlaceOrders()
{
   double lotSize = InpLotSize;
   
   // Validate lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   
   // Convert pips to points, then to price distance
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipInPoints = GetPipInPoints();
   double slDistance = InpStopLossPips * pipInPoints * point;
   double tpDistance = InpTakeProfitPips * pipInPoints * point;
   
   // Debug output
   Print("=== Order Calculation Debug ===");
   Print("Symbol: ", _Symbol);
   Print("Digits: ", _Digits);
   Print("Point: ", point);
   Print("PipInPoints: ", pipInPoints);
   Print("SL Pips: ", InpStopLossPips, " | SL Distance: ", slDistance);
   Print("TP Pips: ", InpTakeProfitPips, " | TP Distance: ", tpDistance);
   
   // Place Daily Breakout Orders
   if(InpBreakoutMode == BREAKOUT_DAILY_ONLY || InpBreakoutMode == BREAKOUT_BOTH)
   {
      PlaceDailyOrders(lotSize, slDistance, tpDistance);
   }
   
   // Place London Session Breakout Orders
   if(InpBreakoutMode == BREAKOUT_LONDON_ONLY || InpBreakoutMode == BREAKOUT_BOTH)
   {
      PlaceLondonOrders(lotSize, slDistance, tpDistance);
   }
}

//+------------------------------------------------------------------+
//| Place daily breakout orders                                       |
//+------------------------------------------------------------------+
void PlaceDailyOrders(double lotSize, double slDistance, double tpDistance)
{
   string comment = InpOrderComment + "_Daily";
   
   // Check if today's open is above previous day high - if so, skip buy trade
   if(todayOpenPrice > prevDayHigh)
   {
      Print("Daily Buy trade skipped: Today's open (", todayOpenPrice, ") is above previous day high (", prevDayHigh, ")");
   }
   else
   {
      // Buy Stop above high
      double buyPrice = NormalizeDouble(prevDayHigh, _Digits);
      double buySL = NormalizeDouble(buyPrice - slDistance, _Digits);
      double buyTP = NormalizeDouble(buyPrice + tpDistance, _Digits);
      
      // Validate SL/TP are correct distance from entry
      if(buySL > 0 && buyTP > 0 && buySL < buyPrice && buyTP > buyPrice)
      {
         if(trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_DAY, 0, comment))
         {
            Print("Daily Buy Stop placed at ", buyPrice, " | SL: ", buySL, " (", InpStopLossPips, " pips) | TP: ", buyTP, " (", InpTakeProfitPips, " pips)");
         }
         else
         {
            Print("Failed to place Daily Buy Stop. Error: ", GetLastError(), " | Code: ", trade.ResultRetcode(), " | Description: ", trade.ResultRetcodeDescription());
         }
      }
      else
      {
         Print("Invalid Daily Buy Stop parameters - Price: ", buyPrice, " SL: ", buySL, " TP: ", buyTP);
      }
   }
   
   // Check if today's open is below previous day low - if so, skip sell trade
   if(todayOpenPrice < prevDayLow)
   {
      Print("Daily Sell trade skipped: Today's open (", todayOpenPrice, ") is below previous day low (", prevDayLow, ")");
   }
   else
   {
      // Sell Stop below low
      double sellPrice = NormalizeDouble(prevDayLow, _Digits);
      double sellSL = NormalizeDouble(sellPrice + slDistance, _Digits);
      double sellTP = NormalizeDouble(sellPrice - tpDistance, _Digits);
      
      // Validate SL/TP are correct distance from entry
      if(sellSL > 0 && sellTP > 0 && sellSL > sellPrice && sellTP < sellPrice)
      {
         if(trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_DAY, 0, comment))
         {
            Print("Daily Sell Stop placed at ", sellPrice, " | SL: ", sellSL, " (", InpStopLossPips, " pips) | TP: ", sellTP, " (", InpTakeProfitPips, " pips)");
         }
         else
         {
            Print("Failed to place Daily Sell Stop. Error: ", GetLastError(), " | Code: ", trade.ResultRetcode(), " | Description: ", trade.ResultRetcodeDescription());
         }
      }
      else
      {
         Print("Invalid Daily Sell Stop parameters - Price: ", sellPrice, " SL: ", sellSL, " TP: ", sellTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Place London session breakout orders                              |
//+------------------------------------------------------------------+
void PlaceLondonOrders(double lotSize, double slDistance, double tpDistance)
{
   string comment = InpOrderComment + "_London";
   
   // Validate London high/low are calculated and valid
   if(londonHigh <= 0 || londonLow <= 0 || londonHigh <= londonLow)
   {
      Print("London orders not placed: Invalid London high/low values. High: ", londonHigh, " Low: ", londonLow);
      return;
   }
   
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevel * point;   // minimum distance broker allows
   double bufferPoints = 2 * point;           // extra safety buffer
   
   Print("=== Placing London Orders ===");
   Print("London High: ", londonHigh, " | London Low: ", londonLow);
   Print("Current BID: ", currentBid, " | Current ASK: ", currentAsk);
   Print("StopsLevel (points): ", stopsLevel, " | MinStopDist (price): ", minStopDist);
   
   bool anyPlaced = false;
   
   // Add larger buffer to ensure orders remain pending (not execute immediately)
   // Use pip value to add meaningful distance
   double pipValue = GetPipValue();
   double minPendingDistance = pipValue * 5; // At least 5 pips above/below current price
   
   // --- BUY STOP at / above London High ---
   // For Buy Stop to remain pending, it must be significantly above current ASK
   double minBuyPriceForPending = currentAsk + minPendingDistance;
   double desiredBuy = MathMax(londonHigh + bufferPoints, minBuyPriceForPending);
   double minBuyPrice = currentAsk + minStopDist + bufferPoints;
   double buyPrice = NormalizeDouble(MathMax(desiredBuy, minBuyPrice), _Digits);
   
   // Check if price has already broken through London high (skip if so)
   if(currentAsk >= londonHigh)
   {
      Print("London Buy Stop skipped: Current ASK (", currentAsk, ") is already at or above London High (", londonHigh, ")");
   }
   // Ensure Buy Stop price is far enough above current ASK to remain pending
   else if(buyPrice <= currentAsk + minPendingDistance)
   {
      Print("London Buy Stop skipped: Buy price (", buyPrice, ") too close to current ASK (", currentAsk, 
            "). Need at least ", minPendingDistance, " distance to remain pending.");
   }
   else
   {
      double buySL = NormalizeDouble(buyPrice - slDistance, _Digits);
      double buyTP = NormalizeDouble(buyPrice + tpDistance, _Digits);
      
      // Validate SL/TP are correct distance from entry
      if(buySL > 0 && buyTP > 0 && buySL < buyPrice && buyTP > buyPrice)
      {
         if(trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_DAY, 0, comment))
         {
            anyPlaced = true;
            Print("✓ London Buy Stop placed at ", buyPrice,
                  " | SL: ", buySL, " | TP: ", buyTP,
                  " | Distance from ASK: ", (buyPrice - currentAsk));
         }
         else
         {
            Print("✗ Failed to place London Buy Stop. Error: ", GetLastError(),
                  " | Code: ", trade.ResultRetcode(),
                  " | Description: ", trade.ResultRetcodeDescription(),
                  " | Price: ", buyPrice,
                  " | SL: ", buySL,
                  " | TP: ", buyTP);
         }
      }
      else
      {
         Print("Invalid London Buy Stop parameters - Price: ", buyPrice,
               " SL: ", buySL, " TP: ", buyTP);
      }
   }
   
   // --- SELL STOP at / below London Low ---
   // For Sell Stop to remain pending, it must be significantly below current BID
   double maxSellPriceForPending = currentBid - minPendingDistance;
   double desiredSell = MathMin(londonLow - bufferPoints, maxSellPriceForPending);
   double maxSellPrice = currentBid - minStopDist - bufferPoints;
   double sellPrice = NormalizeDouble(MathMin(desiredSell, maxSellPrice), _Digits);
   
   // Check if price has already broken through London low (skip if so)
   if(currentBid <= londonLow)
   {
      Print("London Sell Stop skipped: Current BID (", currentBid, ") is already at or below London Low (", londonLow, ")");
   }
   // Ensure Sell Stop price is far enough below current BID to remain pending
   else if(sellPrice >= currentBid - minPendingDistance)
   {
      Print("London Sell Stop skipped: Sell price (", sellPrice, ") too close to current BID (", currentBid, 
            "). Need at least ", minPendingDistance, " distance to remain pending.");
   }
   else
   {
      double sellSL = NormalizeDouble(sellPrice + slDistance, _Digits);
      double sellTP = NormalizeDouble(sellPrice - tpDistance, _Digits);
      
      // Validate SL/TP are correct distance from entry
      if(sellSL > 0 && sellTP > 0 && sellSL > sellPrice && sellTP < sellPrice)
      {
         if(trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_DAY, 0, comment))
         {
            anyPlaced = true;
            Print("✓ London Sell Stop placed at ", sellPrice,
                  " | SL: ", sellSL, " | TP: ", sellTP,
                  " | Distance from BID: ", (currentBid - sellPrice));
         }
         else
         {
            Print("✗ Failed to place London Sell Stop. Error: ", GetLastError(),
                  " | Code: ", trade.ResultRetcode(),
                  " | Description: ", trade.ResultRetcodeDescription(),
                  " | Price: ", sellPrice,
                  " | SL: ", sellSL,
                  " | TP: ", sellTP);
         }
      }
      else
      {
         Print("Invalid London Sell Stop parameters - Price: ", sellPrice,
               " SL: ", sellSL, " TP: ", sellTP);
      }
   }
   
   if(!anyPlaced)
      Print("London orders: no pending orders were successfully placed.");
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
//| Get pip value in points (not price) for the symbol              |
//| Returns: number of points per pip                                |
//+------------------------------------------------------------------+
double GetPipInPoints()
{
   string symbol = _Symbol;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Check if symbol is XAU/Gold (case insensitive)
   bool isXAU = (StringFind(symbol, "XAU") >= 0 || 
                 StringFind(symbol, "GOLD") >= 0 ||
                 StringFind(symbol, "xau") >= 0 || 
                 StringFind(symbol, "gold") >= 0);
   
   // Check if symbol contains JPY (Japanese Yen pairs)
   bool isJPY = (StringFind(symbol, "JPY") >= 0);
   
   // Check if it's an index/CFD (like US30, NAS100, etc.)
   bool isIndex = (StringFind(symbol, "30") >= 0 || 
                   StringFind(symbol, "100") >= 0 || 
                   StringFind(symbol, "500") >= 0 ||
                   StringFind(symbol, "2000") >= 0 ||
                   StringFind(symbol, "cash") >= 0 ||
                   StringFind(symbol, "CFD") >= 0);
   
   if(isXAU)
   {
      // For XAU/Gold: 1 pip = 0.10 (10 cents) - this is the standard broker definition
      // If point = 0.01, then 1 pip (0.10) = 10 points
      // If point = 0.001, then 1 pip (0.10) = 100 points
      if(point > 0)
      {
         double pipInPoints = 0.10 / point;  // 0.10 divided by point value
         Print("XAU/Gold detected: ", symbol, " | Digits: ", digits, " | Point: ", point, " | PipInPoints: ", pipInPoints, " (1 pip = 0.10)");
         return pipInPoints;
      }
      else
      {
         Print("Warning: Point value is 0 for XAU, using fallback");
         return (digits == 3) ? 100.0 : 10.0; // Fallback: 100 points for 3 digits, 10 points for 2 digits
      }
   }
   else if(isIndex)
   {
      // For indices: 1 pip = 1.0 (whole number)
      // Calculate how many points make 1.0
      if(point > 0)
      {
         double pipInPoints = 1.0 / point;

         return pipInPoints;
      }
      else
      {
         Print("Warning: Point value is 0 for index, using fallback");
         return 1.0; // Fallback
      }
   }
   else if(isJPY)
   {
      // For JPY pairs: 1 pip = 0.01
      // If digits = 3, point = 0.001, so 1 pip = 10 points
      // If digits = 2, point = 0.01, so 1 pip = 1 point
      return (digits == 3) ? 10.0 : 1.0;
   }
   else
   {
      // For non-JPY forex pairs: 1 pip = 0.0001
      // If digits = 5, point = 0.00001, so 1 pip = 10 points
      // If digits = 4, point = 0.0001, so 1 pip = 1 point
      return (digits == 5) ? 10.0 : 1.0;
   }
}
//+------------------------------------------------------------------+
//| Manage trailing stops                  | 

//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double openPrice = position.PriceOpen();
            double currentSL = position.StopLoss();
            
            // Get current market prices
            double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            // Calculate pip value for this symbol (recalculate to ensure accuracy)
            double pipValue = GetPipValue();
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double pipInPoints = GetPipInPoints();
            
            // Get position type from broker
            ENUM_POSITION_TYPE reportedType = position.Type();
            
            // Additional verification: Check if open price vs current price makes sense
            // For BUY: openPrice < currentPrice (if profitable)
            // For SELL: openPrice > currentPrice (if profitable)
            bool isLikelyBuy = (openPrice < bidPrice);
            bool isLikelySell = (openPrice > bidPrice);
            
            // Use price relationship to determine actual position type
            // This is a workaround for cases where position.Type() returns incorrect value
            ENUM_POSITION_TYPE posType;
            if(isLikelyBuy && !isLikelySell)
            {
               posType = POSITION_TYPE_BUY;
            }
            else if(isLikelySell && !isLikelyBuy)
            {
               posType = POSITION_TYPE_SELL;
            }
            else
            {
               // If unclear, use reported type
               posType = reportedType;
            }
            
            // Log if there's a mismatch
            if(reportedType != posType)
            {
               Print("WARNING: Position type corrected! Ticket: ", position.Ticket(),
                     " | Reported Type: ", (reportedType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     " | Corrected Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     " | Open Price: ", openPrice, " | BID: ", bidPrice);
            }
            
            double currentPrice = bidPrice;  // Use BID for both position types
            
            // Calculate profit in pips
            // pipValue = price value of 1 pip (e.g., 0.10 for XAU, 1.0 for indices, 0.0001 for forex)
            double priceDifference;
            if(posType == POSITION_TYPE_BUY)
            {
               priceDifference = currentPrice - openPrice;
            }
            else // POSITION_TYPE_SELL
            {
               priceDifference = openPrice - currentPrice;
            }
            
            double profitPips = priceDifference / pipValue;
            
            // Debug: Log pip calculation details (only once per position to avoid spam)
            static int lastDebugTicket = 0;
            if(position.Ticket() != lastDebugTicket || MathAbs(profitPips - InpTrailingStart) < 2.0)
            {
               Print("Trailing Debug - Ticket: ", position.Ticket(),
                     " | Price Diff: ", priceDifference,
                     " | PipValue: ", pipValue,
                     " | PipInPoints: ", pipInPoints,
                     " | Point: ", point,
                     " | Profit Pips: ", DoubleToString(profitPips, 2),
                     " | Required: ", InpTrailingStart, " pips");
               lastDebugTicket = position.Ticket();
            }
            
            // Check if profit reached trailing start
            if(profitPips >= InpTrailingStart)
            {
               double trailingDistance = InpTrailingDistance * pipValue;
               double trailingStep = InpTrailingStep * pipValue;
               
               // Calculate new stop loss level
               double newSL;
               if(posType == POSITION_TYPE_BUY)
               {
                  // BUY: SL below current BID price
                  newSL = bidPrice - trailingDistance;
               }
               else // POSITION_TYPE_SELL
               {
                  // SELL: SL above current BID price
                  // As BID drops (favorable), newSL = bidPrice + trailingDistance will be lower
                  newSL = bidPrice + trailingDistance;
               }
               
               // Get minimum stop distance
               double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
               long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               double minStop = stopsLevel * point;
               
               // Safety check: Ensure SL respects minimum distance
               if(posType == POSITION_TYPE_BUY)
               {
                  // For BUY: SL must be below BID by at least minStop
                  if(newSL >= bidPrice - minStop)
                  {
                     Print("BUY trailing SL too close to market. New SL: ", newSL, 
                           " | BID: ", bidPrice, " | Min distance: ", minStop);
                     continue;
                  }
               }
               else // SELL
               {
                  // For SELL: SL must be above ASK by at least minStop
                  // Important: Use ASK here because broker will use ASK to trigger SELL SL
                  if(newSL <= askPrice + minStop)
                  {
                     Print("SELL trailing SL too close to market. New SL: ", newSL, 
                           " | ASK: ", askPrice, " | Min distance: ", minStop,
                           " | Required: ", askPrice + minStop);
                     continue;
                  }
               }
               
               // Determine if we should update the SL
               bool shouldUpdate = false;
               
               if(posType == POSITION_TYPE_BUY)
               {
                  // For BUY: Move SL up (higher is better)
                  if(currentSL == 0 || newSL > currentSL + trailingStep)
                     shouldUpdate = true;
               }
               else // SELL
               {
                  // For SELL: Move SL down (lower is better, locks more profit)
                  // currentSL is above entry, newSL should be lower than currentSL
                  if(currentSL == 0)
                  {
                     shouldUpdate = true; // First time setting trailing SL
                  }
                  else
                  {
                     // For SELL: newSL should be LOWER than currentSL (better)
                     // Check if newSL is at least trailingStep LOWER than currentSL
                     double slDifference = currentSL - newSL; // Positive when newSL is lower
                     if(slDifference >= trailingStep)
                     {
                        shouldUpdate = true;
                     }
                  }
               }
               
               if(shouldUpdate)
               {
                  double normalizedSL = NormalizeDouble(newSL, _Digits);
                  
                  if(trade.PositionModify(position.Ticket(), normalizedSL, position.TakeProfit()))
                  {
                     string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                     Print("✓ Trailing SL updated for ", posTypeStr, " #", position.Ticket(), 
                           " | New SL: ", normalizedSL, 
                           " | Old SL: ", currentSL,
                           " | BID: ", bidPrice,
                           " | ASK: ", askPrice,
                           " | Profit: ", DoubleToString(profitPips, 1), " pips");
                  }
                  else
                  {
                     string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                     Print("✗ Failed to update trailing SL for ", posTypeStr, " #", position.Ticket(), 
                           " | Error: ", GetLastError(), 
                           " | Code: ", trade.ResultRetcode(),
                           " | Description: ", trade.ResultRetcodeDescription(),
                           " | New SL: ", normalizedSL,
                           " | Current SL: ", currentSL,
                           " | BID: ", bidPrice,
                           " | ASK: ", askPrice);
                  }
               }
               else
               {
                  // Debug: Why wasn't it updated?
                  string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                  double slDifference = (posType == POSITION_TYPE_BUY) ? 
                                        (newSL - currentSL) : 
                                        (currentSL - newSL);
                  
                  Print("Trailing SL not updated for ", posTypeStr, " #", position.Ticket(),
                        " | Position Type Code: ", (int)posType, " (0=BUY, 1=SELL)",
                        " | Current SL: ", currentSL,
                        " | New SL: ", newSL,
                        " | SL Difference: ", slDifference,
                        " | Required step: ", trailingStep,
                        " | Profit: ", DoubleToString(profitPips, 1), " pips",
                        " | BID: ", bidPrice, " | ASK: ", askPrice);
               }
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
         {
            trade.OrderDelete(order.Ticket());
            Print("Pending order deleted: ", order.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel conflicting pending orders when positions are open        |
//+------------------------------------------------------------------+
void CancelConflictingPendingOrders()
{
   // Check all open positions
   for(int posIdx = PositionsTotal() - 1; posIdx >= 0; posIdx--)
   {
      if(position.SelectByIndex(posIdx))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double posEntry = position.PriceOpen();
            double posSL = position.StopLoss();
            double posTP = position.TakeProfit();
            ENUM_POSITION_TYPE posType = position.Type();
            
            // Determine the price range between SL and TP
            // For BUY: SL is below entry, TP is above entry
            // For SELL: SL is above entry, TP is below entry
            double minPrice, maxPrice;
            
            if(posSL > 0 && posTP > 0)
            {
               // Both SL and TP set - check if pending order is between them
               minPrice = MathMin(posSL, posTP);
               maxPrice = MathMax(posSL, posTP);
            }
            else if(posSL > 0)
            {
               // Only SL set - check from SL to entry (or beyond if needed)
               if(posType == POSITION_TYPE_BUY)
               {
                  // BUY: SL below entry, check from SL to entry
                  minPrice = posSL;
                  maxPrice = posEntry;
               }
               else // SELL
               {
                  // SELL: SL above entry, check from entry to SL
                  minPrice = posEntry;
                  maxPrice = posSL;
               }
            }
            else if(posTP > 0)
            {
               // Only TP set - check from entry to TP
               if(posType == POSITION_TYPE_BUY)
               {
                  // BUY: TP above entry, check from entry to TP
                  minPrice = posEntry;
                  maxPrice = posTP;
               }
               else // SELL
               {
                  // SELL: TP below entry, check from TP to entry
                  minPrice = posTP;
                  maxPrice = posEntry;
               }
            }
            else
            {
               // No SL/TP set, skip this position
               continue;
            }
            
            // Check all pending orders for conflicts
            for(int ordIdx = OrdersTotal() - 1; ordIdx >= 0; ordIdx--)
            {
               if(order.SelectByIndex(ordIdx))
               {
                  if(order.Symbol() == _Symbol && order.Magic() == InpMagicNumber)
                  {
                     double orderPrice = order.PriceOpen();
                     ENUM_ORDER_TYPE orderType = order.OrderType();
                     
                     // Check if this is an opposite order type (SELL orders for BUY position, BUY orders for SELL position)
                     bool isOpposite = false;
                     if(posType == POSITION_TYPE_BUY && (orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL_LIMIT))
                        isOpposite = true;
                     else if(posType == POSITION_TYPE_SELL && (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_LIMIT))
                        isOpposite = true;
                     
                     // If opposite order and price is between minPrice and maxPrice, cancel it
                     if(isOpposite && orderPrice >= minPrice && orderPrice <= maxPrice)
                     {
                        if(trade.OrderDelete(order.Ticket()))
                        {
                           string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                           string orderTypeStr = "";
                           if(orderType == ORDER_TYPE_BUY_STOP) orderTypeStr = "BUY_STOP";
                           else if(orderType == ORDER_TYPE_BUY_LIMIT) orderTypeStr = "BUY_LIMIT";
                           else if(orderType == ORDER_TYPE_SELL_STOP) orderTypeStr = "SELL_STOP";
                           else if(orderType == ORDER_TYPE_SELL_LIMIT) orderTypeStr = "SELL_LIMIT";
                           
                           Print("✓ Conflicting order cancelled: ", orderTypeStr, " at ", DoubleToString(orderPrice, _Digits), 
                                 " (conflicts with open ", posTypeStr, " position #", position.Ticket(),
                                 " | Entry: ", DoubleToString(posEntry, _Digits), 
                                 " | SL: ", DoubleToString(posSL, _Digits), 
                                 " | TP: ", DoubleToString(posTP, _Digits),
                                 " | Range: ", DoubleToString(minPrice, _Digits), " - ", DoubleToString(maxPrice, _Digits), ")");
                        }
                        else
                        {
                           Print("✗ Failed to delete conflicting order: ", order.Ticket(), " Error: ", GetLastError());
                        }
                     }
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
   // Delete old lines
   ObjectDelete(0, lineHigh);
   ObjectDelete(0, lineLow);
   
   // Draw high line
   ObjectCreate(0, lineHigh, OBJ_HLINE, 0, 0, prevDayHigh);
   ObjectSetInteger(0, lineHigh, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, lineHigh, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineHigh, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineHigh, OBJPROP_TEXT, "Prev Day High");
   
   // Draw low line
   ObjectCreate(0, lineLow, OBJ_HLINE, 0, 0, prevDayLow);
   ObjectSetInteger(0, lineLow, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, lineLow, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineLow, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineLow, OBJPROP_TEXT, "Prev Day Low");
}

//+------------------------------------------------------------------+
//| Draw London session high/low lines                                |
//+------------------------------------------------------------------+
void DrawLondonLines()
{
   // Delete old lines
   ObjectDelete(0, lineLondonHigh);
   ObjectDelete(0, lineLondonLow);
   
   // Draw high line
   ObjectCreate(0, lineLondonHigh, OBJ_HLINE, 0, 0, londonHigh);
   ObjectSetInteger(0, lineLondonHigh, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, lineLondonHigh, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineLondonHigh, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineLondonHigh, OBJPROP_TEXT, "London High");
   
   // Draw low line
   ObjectCreate(0, lineLondonLow, OBJ_HLINE, 0, 0, londonLow);
   ObjectSetInteger(0, lineLondonLow, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, lineLondonLow, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineLondonLow, OBJPROP_WIDTH, 1);
   ObjectSetString(0, lineLondonLow, OBJPROP_TEXT, "London Low");
}

//+------------------------------------------------------------------+
//| Update chart comment                                             |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   int startMinutes = InpStartHour * 60 + InpStartMinute;
   int closeMinutes = InpCloseHour * 60 + InpCloseMinute;
   
   // Get day name
   string dayNames[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
   string currentDay = dayNames[timeStruct.day_of_week];
   bool isWeekday = IsWeekday();
   
   string comment = "\n";
   comment += "===== Previous Day Breakout EA =====\n";
   comment += "Day: " + currentDay + (isWeekday ? " (Weekday)" : " (Weekend)") + "\n";
   
   // Show breakout mode
   string modeStr = "";
   if(InpBreakoutMode == BREAKOUT_DAILY_ONLY)
      modeStr = "Daily Only";
   else if(InpBreakoutMode == BREAKOUT_LONDON_ONLY)
      modeStr = "London Only";
   else
      modeStr = "Both Daily & London";
   comment += "Breakout Mode: " + modeStr + "\n";
   
   // Daily breakout info
   if(InpBreakoutMode == BREAKOUT_DAILY_ONLY || InpBreakoutMode == BREAKOUT_BOTH)
   {
      comment += "--- Daily Breakout ---\n";
      comment += "Previous Day High: " + DoubleToString(prevDayHigh, _Digits) + "\n";
      comment += "Previous Day Low: " + DoubleToString(prevDayLow, _Digits) + "\n";
      comment += "Daily Calculated: " + (prevDayCalculated ? "Yes" : "No") + "\n";
      comment += "Daily Orders Placed: " + (dailyOrdersPlaced ? "Yes" : "No") + "\n";
   }
   
   // London session info
   if(InpBreakoutMode == BREAKOUT_LONDON_ONLY || InpBreakoutMode == BREAKOUT_BOTH)
   {
      comment += "--- London Session Breakout (Current Day) ---\n";
      comment += "London High: " + DoubleToString(londonHigh, _Digits) + "\n";
      comment += "London Low: " + DoubleToString(londonLow, _Digits) + "\n";
      comment += "London Session: " + IntegerToString(InpLondonStartHour) + ":" + 
                 StringFormat("%02d", InpLondonStartMinute) + " - " + 
                 IntegerToString(InpLondonEndHour) + ":" + 
                 StringFormat("%02d", InpLondonEndMinute) + " GMT\n";
      comment += "London Calculated: " + (londonCalculated ? "Yes" : "No") + "\n";
      comment += "London Orders Placed: " + (londonOrdersPlaced ? "Yes" : "No") + "\n";
   }
   
   comment += "Today's Open: " + DoubleToString(todayOpenPrice, _Digits) + "\n";
   comment += "Trading Days: Monday - Friday\n";
   comment += "Trading Hours: " + IntegerToString(InpStartHour) + ":" + 
              StringFormat("%02d", InpStartMinute) + " - " + 
              IntegerToString(InpCloseHour) + ":" + 
              StringFormat("%02d", InpCloseMinute) + "\n";
   comment += "Current Time: " + IntegerToString(timeStruct.hour) + ":" + 
              StringFormat("%02d", timeStruct.min) + " | ";
   
   if(!isWeekday)
      comment += "Weekend - Trading disabled\n";
   else if(currentMinutes < startMinutes)
      comment += "Waiting for start time\n";
   else if(currentMinutes >= closeMinutes)
   {
      if(timeStruct.day_of_week == 5) // Friday
         comment += "Friday close - Trading resumes Monday 1:15\n";
      else
         comment += "Trading closed\n";
   }
   else
      comment += "Trading active\n";
   comment += "SL: " + IntegerToString(InpStopLossPips) + " pips | TP: " + 
              IntegerToString(InpTakeProfitPips) + " pips\n";
   
   if(InpTrailingMode != TSL_OFF)
      comment += "Trailing: Active (" + IntegerToString(InpTrailingStart) + 
                 "/" + IntegerToString(InpTrailingDistance) + "/" + 
                 DoubleToString(InpTrailingStep, 1) + " pips)\n";
   
   Comment(comment);
}
//+------------------------------------------------------------------+

