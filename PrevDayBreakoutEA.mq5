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
      
      // Delete old pending orders
      DeletePendingOrders();
   }
   
   // Calculate previous day high/low
   if(!prevDayCalculated)
   {
      CalculatePreviousDayHighLow();
   }
   
   // Place orders if ready
   if(prevDayCalculated && !ordersPlaced)
   {
      PlaceOrders();
      ordersPlaced = true;
   }
   
   // Manage trailing stops
   if(InpTrailingMode != TSL_OFF)
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
   
   // Set background color to gray
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'40,40,40');  // Dark gray
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   
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
   ChartSetInteger(0, CHART_COLOR_GRID, C'60,60,60');           // Gray grid (if enabled)
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'40,40,40');     // Dark gray background
   
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
   
   // Check if symbol contains JPY (Japanese Yen pairs)
   bool isJPY = (StringFind(symbol, "JPY") >= 0);
   
   // Check if it's an index/CFD (like US30, NAS100, etc.)
   bool isIndex = (StringFind(symbol, "30") >= 0 || 
                   StringFind(symbol, "100") >= 0 || 
                   StringFind(symbol, "500") >= 0 ||
                   StringFind(symbol, "2000") >= 0 ||
                   StringFind(symbol, "cash") >= 0 ||
                   StringFind(symbol, "CFD") >= 0);
   
   if(isIndex)
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
            double currentPrice = position.Type() == POSITION_TYPE_BUY ? 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                                  SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            double profitPips = position.Type() == POSITION_TYPE_BUY ? 
                               (currentPrice - openPrice) / pipValue :
                               (openPrice - currentPrice) / pipValue;
            
            // Check if profit reached trailing start
            if(profitPips >= InpTrailingStart)
            {
               double trailingDistance = InpTrailingDistance * pipValue;
               double trailingStep = InpTrailingStep * pipValue;
               
               double newSL = position.Type() == POSITION_TYPE_BUY ? 
                             currentPrice - trailingDistance : 
                             currentPrice + trailingDistance;
               
               // Only move SL if it's better by at least the step value
               bool shouldUpdate = false;
               
               if(position.Type() == POSITION_TYPE_BUY)
               {
                  if(currentSL == 0 || newSL > currentSL + trailingStep)
                     shouldUpdate = true;
               }
               else
               {
                  if(currentSL == 0 || newSL < currentSL - trailingStep)
                     shouldUpdate = true;
               }
               
               if(shouldUpdate)
               {
                  if(trade.PositionModify(position.Ticket(), 
                                         NormalizeDouble(newSL, _Digits), 
                                         position.TakeProfit()))
                  {
                     Print("Trailing SL updated to ", newSL, " (Profit: ", DoubleToString(profitPips, 1), " pips)");
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
   string comment = "\n";
   comment += "===== Previous Day Breakout EA =====\n";
   comment += "Previous Day High: " + DoubleToString(prevDayHigh, _Digits) + "\n";
   comment += "Previous Day Low: " + DoubleToString(prevDayLow, _Digits) + "\n";
   comment += "Calculated: " + (prevDayCalculated ? "Yes" : "No") + "\n";
   comment += "Orders Placed: " + (ordersPlaced ? "Yes" : "No") + "\n";
   comment += "SL: " + IntegerToString(InpStopLossPips) + " pips | TP: " + 
              IntegerToString(InpTakeProfitPips) + " pips\n";
   
   if(InpTrailingMode != TSL_OFF)
      comment += "Trailing: Active (" + IntegerToString(InpTrailingStart) + 
                 "/" + IntegerToString(InpTrailingDistance) + "/" + 
                 DoubleToString(InpTrailingStep, 1) + " pips)\n";
   
   Comment(comment);
}
//+------------------------------------------------------------------+

