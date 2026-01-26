//+------------------------------------------------------------------+
//|                                          VolumeAbsorptionEA.mq5   |
//|                        Volume Absorption Pattern EA               |
//+------------------------------------------------------------------+
#property copyright "Volume Absorption EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input double InpRiskPercent = 1.0;                 // Risk per Trade (% of Balance)
input int InpStopLossPips = 3;                     // Stop Loss (Pips) - Alternative to % Risk
input bool InpUsePercentRisk = true;               // Use % Risk for SL (true) or Fixed Pips (false)
input int InpMagicNumber = 54323;                 // Magic Number
input string InpOrderComment = "VolAbsorption";    // Order Comment

input group "=== Volume Settings ==="
input double InpVolumeMultiplier = 1.5;           // High Volume Multiplier (vs Average)
input double InpLowVolumeMultiplier = 0.7;        // Low Volume Multiplier (vs Average)
input int InpVolumeLookback = 20;                 // Volume Average Lookback Period

input group "=== Chart Settings ==="
input bool InpConfigureChart = true;              // Configure Chart Colors
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;   // Trading Timeframe

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
COrderInfo order;
CAccountInfo account;

ENUM_TIMEFRAMES chartTimeframe;
bool patternDetected = false;
datetime lastBarTime = 0;

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
   
   // Set chart timeframe
   chartTimeframe = InpTimeframe;
   
   // Configure chart colors
   if(InpConfigureChart)
      ConfigureChartColors();
   
   Print("Volume Absorption EA initialized on ", EnumToString(chartTimeframe), " timeframe");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, chartTimeframe, 0);
   if(currentBarTime == lastBarTime)
      return; // Same bar, no need to check again
   
   lastBarTime = currentBarTime;
   
   // Check if we already have an open position
   if(HasOpenPosition())
   {
      UpdateChartComment();
      return;
   }
   
   // Check for volume absorption pattern
   CheckVolumeAbsorptionPattern();
   
   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| Check for volume absorption pattern                               |
//+------------------------------------------------------------------+
void CheckVolumeAbsorptionPattern()
{
   // Need at least 2 completed bars
   if(Bars(_Symbol, chartTimeframe) < InpVolumeLookback + 2)
      return;
   
   // Get bar data (index 1 = previous completed bar, index 2 = bar before that)
   double high[], low[], open[], close[];
   long volume[];
   
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volume, true);
   
   // Copy data for last few bars
   int barsToCopy = InpVolumeLookback + 2;
   if(CopyHigh(_Symbol, chartTimeframe, 0, barsToCopy, high) < barsToCopy) return;
   if(CopyLow(_Symbol, chartTimeframe, 0, barsToCopy, low) < barsToCopy) return;
   if(CopyOpen(_Symbol, chartTimeframe, 0, barsToCopy, open) < barsToCopy) return;
   if(CopyClose(_Symbol, chartTimeframe, 0, barsToCopy, close) < barsToCopy) return;
   if(CopyTickVolume(_Symbol, chartTimeframe, 0, barsToCopy, volume) < barsToCopy) return;
   
   // Index 1 = previous completed bar (high volume candle)
   // Index 2 = bar before that (engulfing candle with low volume)
   
   // Calculate average volume (excluding the last 2 bars)
   long avgVolume = 0;
   for(int i = 2; i < barsToCopy; i++)
   {
      avgVolume += volume[i];
   }
   avgVolume = avgVolume / (barsToCopy - 2);
   
   if(avgVolume <= 0) return;
   
   // Pattern: High volume candle (index 2, older) followed by low volume engulfing candle (index 1, newer)
   // Check if bar at index 2 (older bar) has high volume
   bool isHighVolume = volume[2] >= (avgVolume * InpVolumeMultiplier);
   
   // Check if bar at index 1 (newer bar) has low volume
   bool isLowVolume = volume[1] <= (avgVolume * InpLowVolumeMultiplier);
   
   if(!isHighVolume || !isLowVolume)
      return;
   
   // Check if bar at index 1 (newer) engulfs bar at index 2 (older)
   bool isBullishEngulfing = (open[1] < close[2] && close[1] > open[2] && 
                               low[1] <= low[2] && high[1] >= high[2]);
   bool isBearishEngulfing = (open[1] > close[2] && close[1] < open[2] && 
                               low[1] <= low[2] && high[1] >= high[2]);
   
   if(isBullishEngulfing)
   {
      // Bullish pattern: High volume candle, then low volume bullish engulfing
      // Trade direction: BUY (engulfing is bullish)
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      OpenTrade(ORDER_TYPE_BUY, currentPrice, low[1]);
      Print("Bullish Volume Absorption Pattern Detected - Opening BUY trade");
   }
   else if(isBearishEngulfing)
   {
      // Bearish pattern: High volume candle, then low volume bearish engulfing
      // Trade direction: SELL (engulfing is bearish)
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      OpenTrade(ORDER_TYPE_SELL, currentPrice, high[1]);
      Print("Bearish Volume Absorption Pattern Detected - Opening SELL trade");
   }
}

//+------------------------------------------------------------------+
//| Open trade based on pattern                                       |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType, double entryPrice, double engulfingExtreme)
{
   // Calculate stop loss: 2-3 pips below/above engulfing extreme
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipValue = GetPipValue();
   double stopLoss = 0;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      stopLoss = engulfingExtreme - (InpStopLossPips * pipValue);
   }
   else // SELL
   {
      stopLoss = engulfingExtreme + (InpStopLossPips * pipValue);
   }
   
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   
   // Calculate SL distance from entry
   double slDistance = MathAbs(entryPrice - stopLoss);
   if(slDistance <= 0)
   {
      Print("Error: Invalid SL distance. Entry=", entryPrice, " SL=", stopLoss);
      return;
   }
   
   // Validate stop loss distance (broker requirements)
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevel * point;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      if(stopLoss >= entryPrice - minStopDist)
         stopLoss = NormalizeDouble(entryPrice - minStopDist - point, _Digits);
   }
   else
   {
      if(stopLoss <= entryPrice + minStopDist)
         stopLoss = NormalizeDouble(entryPrice + minStopDist + point, _Digits);
   }
   
   // Recalculate SL distance after adjustment
   slDistance = MathAbs(entryPrice - stopLoss);
   
   // Calculate lot size
   double lotSize = 0.01; // Default
   
   if(InpUsePercentRisk)
   {
      // Calculate lot size based on % risk
      double balance = account.Balance();
      double riskAmount = balance * (InpRiskPercent / 100.0);
      
      // Get symbol properties
      double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(contractSize > 0 && tickValue > 0 && tickSize > 0 && slDistance > 0)
      {
         // Calculate how many ticks the SL distance represents
         double ticksInSL = slDistance / tickSize;
         
         // Calculate loss per lot if SL is hit
         double lossPerLot = (tickValue / tickSize) * ticksInSL;
         
         if(lossPerLot > 0)
         {
            // Calculate lot size: Risk Amount / Loss per Lot
            lotSize = riskAmount / lossPerLot;
         }
      }
      
      // Validate and normalize lot size
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      if(minLot > 0) lotSize = MathMax(lotSize, minLot);
      if(maxLot > 0) lotSize = MathMin(lotSize, maxLot);
      if(lotStep > 0) lotSize = MathRound(lotSize / lotStep) * lotStep;
      
      // Ensure lot size is valid
      if(lotSize < minLot) lotSize = minLot;
   }
   
   // Open market order
   if(orderType == ORDER_TYPE_BUY)
   {
      if(trade.Buy(lotSize, _Symbol, 0, stopLoss, 0, InpOrderComment))
      {
         Print("BUY order opened: Lot=", lotSize, " Entry=", entryPrice, " SL=", stopLoss, 
               " Risk=", DoubleToString(InpRiskPercent, 2), "%");
      }
      else
      {
         Print("Failed to open BUY order. Error: ", GetLastError(), 
               " Code: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
      }
   }
   else
   {
      if(trade.Sell(lotSize, _Symbol, 0, stopLoss, 0, InpOrderComment))
      {
         Print("SELL order opened: Lot=", lotSize, " Entry=", entryPrice, " SL=", stopLoss,
               " Risk=", DoubleToString(InpRiskPercent, 2), "%");
      }
      else
      {
         Print("Failed to open SELL order. Error: ", GetLastError(),
               " Code: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there's an open position                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            return true;
         }
      }
   }
   return false;
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
      // For XAU/Gold: 1 pip = 0.10 (10 cents)
      if(point > 0)
      {
         double pipInPoints = 0.10 / point;
         return pipInPoints;
      }
      else
      {
         return (digits == 3) ? 100.0 : 10.0;
      }
   }
   else if(isIndex)
   {
      // For indices: 1 pip = 1.0 (whole number)
      if(point > 0)
      {
         double pipInPoints = 1.0 / point;
         return pipInPoints;
      }
      else
      {
         return 1.0;
      }
   }
   else if(isJPY)
   {
      // For JPY pairs: 1 pip = 0.01
      return (digits == 3) ? 10.0 : 1.0;
   }
   else
   {
      // For non-JPY forex pairs: 1 pip = 0.0001
      return (digits == 5) ? 10.0 : 1.0;
   }
}

//+------------------------------------------------------------------+
//| Configure chart colors (muted/matte colors)                      |
//+------------------------------------------------------------------+
void ConfigureChartColors()
{
   // Remove grid
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   // Set background to light gray (muted)
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'240,240,240');  // Light gray background
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'60,60,60');     // Dark gray foreground
   
   // Set candle colors - muted colors
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'180,200,220');   // Muted blue for bullish
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'200,180,180');   // Muted red for bearish
   ChartSetInteger(0, CHART_COLOR_CHART_UP, C'180,200,220');      // Muted blue
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'200,180,180');    // Muted red
   
   // Set price line colors - muted
   ChartSetInteger(0, CHART_COLOR_BID, C'150,150,150');          // Muted gray
   ChartSetInteger(0, CHART_COLOR_ASK, C'150,150,150');          // Muted gray
   ChartSetInteger(0, CHART_COLOR_LAST, C'150,150,150');         // Muted gray
   
   // Set volume colors - muted
   ChartSetInteger(0, CHART_COLOR_VOLUME, C'180,180,180');       // Muted gray for volume
   
   // Set chart line colors
   ChartSetInteger(0, CHART_COLOR_GRID, C'220,220,220');         // Very light gray grid (if enabled)
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update chart comment                                             |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string comment = "\n";
   comment += "===== Volume Absorption EA =====\n";
   comment += "Timeframe: " + EnumToString(chartTimeframe) + "\n";
   comment += "Risk: " + DoubleToString(InpRiskPercent, 2) + "% of Balance\n";
   comment += "SL: " + IntegerToString(InpStopLossPips) + " pips\n";
   comment += "High Vol Multiplier: " + DoubleToString(InpVolumeMultiplier, 2) + "x\n";
   comment += "Low Vol Multiplier: " + DoubleToString(InpLowVolumeMultiplier, 2) + "x\n";
   comment += "Volume Lookback: " + IntegerToString(InpVolumeLookback) + " bars\n";
   
   // Show current position info
   if(HasOpenPosition())
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(position.SelectByIndex(i))
         {
            if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            {
               string posType = (position.Type() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
               comment += "\n--- Open Position ---\n";
               comment += "Type: " + posType + "\n";
               comment += "Entry: " + DoubleToString(position.PriceOpen(), _Digits) + "\n";
               comment += "SL: " + DoubleToString(position.StopLoss(), _Digits) + "\n";
               comment += "Profit: " + DoubleToString(position.Profit(), 2) + " " + account.Currency() + "\n";
               break;
            }
         }
      }
   }
   else
   {
      comment += "\nStatus: Waiting for pattern...\n";
   }
   
   Comment(comment);
}
//+------------------------------------------------------------------+

