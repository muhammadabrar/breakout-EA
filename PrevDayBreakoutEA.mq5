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
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input double InpLotSize = 0.01;                    // Lot Size
input int InpStopLossPips = 60;                    // Stop Loss (Pips)
input int InpTakeProfitPips = 120;                 // Take Profit (Pips)
input int InpMagicNumber = 54322;                  // Magic Number
input string InpOrderComment = "PrevDayBO";        // Order Comment

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
bool ordersPlaced = false;
int currentDate = 0;
bool tradesClosedToday = false;
double todayOpenPrice = 0;

string lineHigh = "PrevDay_High";
string lineLow = "PrevDay_Low";

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
      ordersPlaced = false;
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
   if(!prevDayCalculated)
   {
      CalculatePreviousDayHighLow();
   }
   
   // Place orders if ready and trading hours allow (only on weekdays)
   if(prevDayCalculated && !ordersPlaced && IsTradingStartTime())
   {
      PlaceOrders();
      ordersPlaced = true;
   }
   
   // Manage trailing stops (only on weekdays and during trading hours)
   if(IsWeekday() && InpTrailingMode != TSL_OFF)
      ManageTrailingStops();
   
   // Update chart comment
   UpdateChartComment();
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
   
   // Check if today's open is above previous day high - if so, skip buy trade
   if(todayOpenPrice > prevDayHigh)
   {
      Print("Buy trade skipped: Today's open (", todayOpenPrice, ") is above previous day high (", prevDayHigh, ")");
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
         if(trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_DAY, 0, InpOrderComment))
         {
            Print("Buy Stop placed at ", buyPrice, " | SL: ", buySL, " (", InpStopLossPips, " pips) | TP: ", buyTP, " (", InpTakeProfitPips, " pips)");
         }
         else
         {
            Print("Failed to place Buy Stop. Error: ", GetLastError(), " | Code: ", trade.ResultRetcode(), " | Description: ", trade.ResultRetcodeDescription());
         }
      }
      else
      {
         Print("Invalid Buy Stop parameters - Price: ", buyPrice, " SL: ", buySL, " TP: ", buyTP);
      }
   }
   
   // Check if today's open is below previous day low - if so, skip sell trade
   if(todayOpenPrice < prevDayLow)
   {
      Print("Sell trade skipped: Today's open (", todayOpenPrice, ") is below previous day low (", prevDayLow, ")");
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
         if(trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_DAY, 0, InpOrderComment))
         {
            Print("Sell Stop placed at ", sellPrice, " | SL: ", sellSL, " (", InpStopLossPips, " pips) | TP: ", sellTP, " (", InpTakeProfitPips, " pips)");
         }
         else
         {
            Print("Failed to place Sell Stop. Error: ", GetLastError(), " | Code: ", trade.ResultRetcode(), " | Description: ", trade.ResultRetcodeDescription());
         }
      }
      else
      {
         Print("Invalid Sell Stop parameters - Price: ", sellPrice, " SL: ", sellSL, " TP: ", sellTP);
      }
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
         Print("Index detected: ", symbol, " | Point: ", point, " | PipInPoints: ", pipInPoints);
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
//| Manage trailing stops                                            |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   double pipValue = GetPipValue();
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            double openPrice = position.PriceOpen();
            double currentSL = position.StopLoss();
            
            // Industry-standard: Use BID for both BUY and SELL trailing calculations
            // This avoids issues with ASK spread widening affecting SELL trailing stops
            // BUY: track BID - when BID goes up, profit increases, move SL up
            // SELL: track BID - when BID goes down, profit increases, move SL down
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            // Calculate profit in pips
            double profitPips = position.Type() == POSITION_TYPE_BUY ? 
                               (currentPrice - openPrice) / pipValue :
                               (openPrice - currentPrice) / pipValue;
            
            // Check if profit reached trailing start
            if(profitPips >= InpTrailingStart)
            {
               double trailingDistance = InpTrailingDistance * pipValue;
               double trailingStep = InpTrailingStep * pipValue;
               
               // Calculate new stop loss level
               double newSL;
               if(position.Type() == POSITION_TYPE_BUY)
               {
                  // BUY: SL below current BID price
                  newSL = currentPrice - trailingDistance;
               }
               else // SELL
               {
                  // SELL: SL above current BID price
                  // As BID drops (favorable), newSL will be lower, moving SL down to lock profit
                  newSL = currentPrice + trailingDistance;
               }
               
               // Safety clamp: Prevent SL from being too close to market price
               double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
               long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               double minStop = stopsLevel * point;
               
               if(position.Type() == POSITION_TYPE_SELL)
               {
                  double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  // For SELL: SL must be above ASK by at least minStop
                  if(newSL <= askPrice + minStop)
                  {
                     Print("SELL trailing SL rejected: Too close to ASK. New SL: ", newSL, 
                           " | ASK: ", askPrice, " | Min distance: ", minStop);
                     continue; // Skip this position, try next one
                  }
               }
               else // BUY
               {
                  // For BUY: SL must be below BID by at least minStop
                  if(newSL >= currentPrice - minStop)
                  {
                     Print("BUY trailing SL rejected: Too close to BID. New SL: ", newSL, 
                           " | BID: ", currentPrice, " | Min distance: ", minStop);
                     continue; // Skip this position, try next one
                  }
               }
               
               // Only move SL if it's better by at least the step value
               bool shouldUpdate = false;
               
               if(position.Type() == POSITION_TYPE_BUY)
               {
                  // For BUY: newSL should be higher (better) than currentSL
                  if(currentSL == 0 || newSL > currentSL + trailingStep)
                     shouldUpdate = true;
               }
               else
               {
                  // For SELL: newSL should be lower (better/closer to price) than currentSL
                  // Since SL is above entry for SELL, lower SL = better (locks in more profit)
                  // Only update if newSL is at least trailingStep LOWER than currentSL
                  if(currentSL == 0)
                  {
                     // No SL set yet, set it
                     shouldUpdate = true;
                  }
                  else if(newSL < currentSL - trailingStep)
                  {
                     // New SL is better (lower) by at least trailingStep
                     shouldUpdate = true;
                  }
               }
               
               if(shouldUpdate)
               {
                  if(trade.PositionModify(position.Ticket(), 
                                         NormalizeDouble(newSL, _Digits), 
                                         position.TakeProfit()))
                  {
                     string posType = position.Type() == POSITION_TYPE_BUY ? "BUY" : "SELL";
                     Print("Trailing SL updated for ", posType, " position #", position.Ticket(), 
                           " | New SL: ", newSL, 
                           " | Old SL: ", currentSL,
                           " | Current BID: ", currentPrice, 
                           " | Profit: ", DoubleToString(profitPips, 1), " pips");
                  }
                  else
                  {
                     string posType = position.Type() == POSITION_TYPE_BUY ? "BUY" : "SELL";
                     Print("Failed to update trailing SL for ", posType, " position #", position.Ticket(), 
                           " | Error: ", GetLastError(), 
                           " | Code: ", trade.ResultRetcode(),
                           " | New SL: ", newSL,
                           " | Current SL: ", currentSL);
                  }
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
//| Draw previous day high/low lines                                  |
//+------------------------------------------------------------------+
void DrawPrevDayLines()
{
   // Delete old lines
   ObjectDelete(0, lineHigh);
   ObjectDelete(0, lineLow);
   
   // Draw high line
   ObjectCreate(0, lineHigh, OBJ_HLINE, 0, 0, prevDayHigh);
   ObjectSetInteger(0, lineHigh, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, lineHigh, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineHigh, OBJPROP_WIDTH, 2);
   ObjectSetString(0, lineHigh, OBJPROP_TEXT, "Prev Day High");
   
   // Draw low line
   ObjectCreate(0, lineLow, OBJ_HLINE, 0, 0, prevDayLow);
   ObjectSetInteger(0, lineLow, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, lineLow, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineLow, OBJPROP_WIDTH, 2);
   ObjectSetString(0, lineLow, OBJPROP_TEXT, "Prev Day Low");
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
   comment += "Previous Day High: " + DoubleToString(prevDayHigh, _Digits) + "\n";
   comment += "Previous Day Low: " + DoubleToString(prevDayLow, _Digits) + "\n";
   comment += "Today's Open: " + DoubleToString(todayOpenPrice, _Digits) + "\n";
   comment += "Calculated: " + (prevDayCalculated ? "Yes" : "No") + "\n";
   comment += "Orders Placed: " + (ordersPlaced ? "Yes" : "No") + "\n";
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

