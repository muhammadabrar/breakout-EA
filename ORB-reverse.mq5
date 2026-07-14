//+------------------------------------------------------------------+
//|                                          OpenRangeBreakout.mq5   |
//|                                   Professional ORB Strategy EA    |
//|                                                          v1.7     |
//+------------------------------------------------------------------+
#property copyright "Open Range Breakout EA"
#property link      ""
#property version   "1.70"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// Opening Range Settings
input group "=== Opening Range Settings ==="
input int InpMarketOpenHour = 9;                    // Market Open Hour (24h format)
input int InpMarketOpenMinute = 30;                  // Market Open Minute
input ENUM_TIMEFRAMES InpORTimeframe = PERIOD_M15;   // Opening Range Timeframe

// Breakout Settings
input group "=== Breakout Settings ==="
input ENUM_TIMEFRAMES InpBreakoutTimeframe = PERIOD_M1; // Breakout Candle Timeframe
input bool InpRequireRetest = false;                    // Require Retest & Confirmation
input int InpRetestBars = 10;                           // Max Bars to Wait for Retest

// Reverse ORB Settings
input group "=== Reverse ORB Settings ==="
input bool InpReverseORB = false;                    // Enable Reverse ORB (BUY→SELL, SELL→BUY)

// Stop Loss Placement Options
enum ENUM_SL_TYPE
{
    SL_BREAKOUT_CANDLE = 0,    // Breakout Candle High/Low
    SL_MID_RANGE = 1,           // Middle of Opening Range
    SL_OPPOSITE_RANGE = 2       // Opposite Side of Range
};

// Stop Loss Settings
input group "=== Stop Loss & TP Settings ==="
input ENUM_SL_TYPE InpSLPlacement = SL_BREAKOUT_CANDLE;  // Stop Loss Placement Method
input double InpSLBufferPoints = 5.0;                // Stop Loss Buffer (points)
input bool InpEnablePartialClose = true;             // Enable Partial Close at 1:1
input bool InpEnableBreakeven = true;                // Move SL to Breakeven at 30% Profit
input double InpFinalTPRR = 2.0;                     // Final Take Profit at 1:2 RR

// Risk Management
input group "=== Risk Management ==="
input double InpRiskAmount = 100.0;                  // Risk Amount per Trade ($)

// Trading Days
input group "=== Trading Days ==="
input bool InpTradeMonday = true;                    // Trade on Monday
input bool InpTradeTuesday = true;                   // Trade on Tuesday
input bool InpTradeWednesday = true;                 // Trade on Wednesday
input bool InpTradeThursday = true;                  // Trade on Thursday
input bool InpTradeFriday = true;                    // Trade on Friday
input bool InpTradeSaturday = false;                 // Trade on Saturday
input bool InpTradeSunday = false;                   // Trade on Sunday

// Display Settings
input group "=== Display Settings ==="
input color InpRangeHighColor = clrDodgerBlue;       // Opening Range High Color
input color InpRangeLowColor = clrDodgerBlue;        // Opening Range Low Color
input color InpRangeArrowColor = clrYellow;          // Range Candle Arrow Color
input color InpBuyBreakoutColor = clrLime;           // Buy Breakout Arrow Color
input color InpSellBreakoutColor = clrRed;           // Sell Breakout Arrow Color

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+

CTrade trade;

// Opening Range Variables
double g_rangeHigh = 0.0;
double g_rangeLow = 0.0;
datetime g_rangeStartTime = 0;
datetime g_rangeEndTime = 0;
bool g_rangeSet = false;

// Trade Management
bool g_tradeToday = false;
datetime g_lastTradeDate = 0;
ulong g_positionTicket = 0;
double g_entryPrice = 0.0;
double g_originalSL = 0.0;
double g_slDistance = 0.0;
bool g_partialClosed = false;
bool g_movedToBreakeven = false;
datetime g_lastCheckedBar = 0;

// Retest tracking
bool g_waitingForRetest = false;
bool g_isBullishBreakout = false;
datetime g_breakoutTime = 0;
int g_barsAfterBreakout = 0;
double g_confirmationCandleLow = 0.0;
double g_confirmationCandleHigh = 0.0;

// Object Names
const string OBJ_RANGE_HIGH = "OR_High";
const string OBJ_RANGE_LOW = "OR_Low";
const string OBJ_INFO_BOX = "OR_InfoBox";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetDeviationInPoints(10);
    
    if(!ValidateInputs())
    {
        Print("Invalid input parameters!");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    CreateInfoBox();
    
    if(InpReverseORB)
        Print("Open Range Breakout EA v1.7 initialized | *** REVERSE ORB MODE ACTIVE ***");
    else
        Print("Open Range Breakout EA v1.7 initialized successfully");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DeleteAllObjects();
    Print("Open Range Breakout EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    if(IsNewDay())
    {
        ResetDaily();
    }
    
    if(!IsTradingDay())
    {
        static bool printedOnce = false;
        if(!printedOnce)
        {
            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            string dayName = "";
            switch(dt.day_of_week)
            {
                case 0: dayName = "Sunday"; break;
                case 1: dayName = "Monday"; break;
                case 2: dayName = "Tuesday"; break;
                case 3: dayName = "Wednesday"; break;
                case 4: dayName = "Thursday"; break;
                case 5: dayName = "Friday"; break;
                case 6: dayName = "Saturday"; break;
            }
            Print("⏸️ Trading disabled for ", dayName, ". EA is paused.");
            printedOnce = true;
        }
        return;
    }
    
    if(!g_rangeSet && IsTimeToSetRange())
    {
        SetOpeningRange();
    }
    
    if(g_rangeSet && !g_tradeToday)
    {
        if(!g_waitingForRetest)
        {
            CheckForBreakout();
        }
        else
        {
            CheckForRetestConfirmation();
        }
    }
    
    if(g_tradeToday && g_positionTicket > 0)
    {
        ManageActivePosition();
    }
    
    UpdateInfoBox();
}

//+------------------------------------------------------------------+
//| Validate Input Parameters                                         |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    if(InpMarketOpenHour < 0 || InpMarketOpenHour > 23)
    {
        Print("Invalid market open hour: ", InpMarketOpenHour);
        return false;
    }
    
    if(InpMarketOpenMinute < 0 || InpMarketOpenMinute > 59)
    {
        Print("Invalid market open minute: ", InpMarketOpenMinute);
        return false;
    }
    
    if(InpRiskAmount <= 0)
    {
        Print("Invalid risk amount: ", InpRiskAmount);
        return false;
    }
    
    if(!InpTradeMonday && !InpTradeTuesday && !InpTradeWednesday && 
       !InpTradeThursday && !InpTradeFriday && !InpTradeSaturday && !InpTradeSunday)
    {
        Print("❌ ERROR: At least one trading day must be selected!");
        return false;
    }
    
    Print("✅ Inputs validated successfully");
    Print("   Opening Range TF: ", EnumToString(InpORTimeframe));
    Print("   Breakout TF: ", EnumToString(InpBreakoutTimeframe));
    Print("   SL Placement: ", (InpSLPlacement == SL_BREAKOUT_CANDLE ? "Breakout Candle" : 
                                InpSLPlacement == SL_MID_RANGE ? "Mid Range" : "Opposite Range"));
    Print("   Reverse ORB: ", (InpReverseORB ? "✅ ENABLED (signals flipped)" : "❌ Disabled (normal)"));
    
    string tradingDays = "   Trading Days: ";
    if(InpTradeMonday) tradingDays += "Mon ";
    if(InpTradeTuesday) tradingDays += "Tue ";
    if(InpTradeWednesday) tradingDays += "Wed ";
    if(InpTradeThursday) tradingDays += "Thu ";
    if(InpTradeFriday) tradingDays += "Fri ";
    if(InpTradeSaturday) tradingDays += "Sat ";
    if(InpTradeSunday) tradingDays += "Sun ";
    Print(tradingDays);
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if today is a trading day                                   |
//+------------------------------------------------------------------+
bool IsTradingDay()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    switch(dt.day_of_week)
    {
        case 0: return InpTradeSunday;
        case 1: return InpTradeMonday;
        case 2: return InpTradeTuesday;
        case 3: return InpTradeWednesday;
        case 4: return InpTradeThursday;
        case 5: return InpTradeFriday;
        case 6: return InpTradeSaturday;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if it's a new day                                           |
//+------------------------------------------------------------------+
bool IsNewDay()
{
    MqlDateTime current;
    TimeToStruct(TimeCurrent(), current);
    
    MqlDateTime lastTrade;
    TimeToStruct(g_lastTradeDate, lastTrade);
    
    if(current.day != lastTrade.day || current.mon != lastTrade.mon || current.year != lastTrade.year)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Reset daily variables                                             |
//+------------------------------------------------------------------+
void ResetDaily()
{
    g_rangeSet = false;
    g_tradeToday = false;
    g_rangeHigh = 0.0;
    g_rangeLow = 0.0;
    g_rangeStartTime = 0;
    g_rangeEndTime = 0;
    g_positionTicket = 0;
    g_entryPrice = 0.0;
    g_originalSL = 0.0;
    g_slDistance = 0.0;
    g_partialClosed = false;
    g_movedToBreakeven = false;
    g_lastCheckedBar = 0;
    
    g_waitingForRetest = false;
    g_isBullishBreakout = false;
    g_breakoutTime = 0;
    g_barsAfterBreakout = 0;
    g_confirmationCandleLow = 0.0;
    g_confirmationCandleHigh = 0.0;
    
    ObjectDelete(0, OBJ_RANGE_HIGH);
    ObjectDelete(0, OBJ_RANGE_LOW);
    
    Print("Daily reset completed");
}

//+------------------------------------------------------------------+
//| Check if it's time to set the range                               |
//+------------------------------------------------------------------+
bool IsTimeToSetRange()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(dt.hour > InpMarketOpenHour || 
       (dt.hour == InpMarketOpenHour && dt.min >= InpMarketOpenMinute))
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Set Opening Range                                                 |
//+------------------------------------------------------------------+
void SetOpeningRange()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = InpMarketOpenHour;
    dt.min = InpMarketOpenMinute;
    dt.sec = 0;
    
    g_rangeStartTime = StructToTime(dt);
    
    int rangePeriodSeconds = PeriodSeconds(InpORTimeframe);
    g_rangeEndTime = g_rangeStartTime + rangePeriodSeconds;
    
    if(TimeCurrent() < g_rangeEndTime)
    {
        Print("⏳ Waiting for opening range to complete. Ends at: ", TimeToString(g_rangeEndTime));
        return;
    }
    
    int barsToCopy = 0;
    if(InpORTimeframe == PERIOD_M5)
        barsToCopy = (int)(rangePeriodSeconds / PeriodSeconds(PERIOD_M5));
    else if(InpORTimeframe == PERIOD_M15)
        barsToCopy = (int)(rangePeriodSeconds / PeriodSeconds(PERIOD_M15));
    else if(InpORTimeframe == PERIOD_H1)
        barsToCopy = (int)(rangePeriodSeconds / PeriodSeconds(PERIOD_H1));
    
    int startBarIndex = iBarShift(_Symbol, InpORTimeframe, g_rangeStartTime);
    
    if(startBarIndex < 0)
    {
        Print("❌ Cannot find opening range start bar");
        return;
    }
    
    double high[], low[];
    int copied_high = CopyHigh(_Symbol, InpORTimeframe, startBarIndex, barsToCopy, high);
    int copied_low = CopyLow(_Symbol, InpORTimeframe, startBarIndex, barsToCopy, low);
    
    if(copied_high <= 0 || copied_low <= 0)
    {
        Print("Failed to copy price data for opening range. Copied: ", copied_high, " bars");
        return;
    }
    
    g_rangeHigh = high[ArrayMaximum(high)];
    g_rangeLow = low[ArrayMinimum(low)];
    
    g_rangeSet = true;
    
    DrawRangeLines();
    MarkOpeningRangeCandles();
    
    Print("✅ Opening Range set from ", TimeToString(g_rangeStartTime), " to ", TimeToString(g_rangeEndTime));
    Print("   High: ", g_rangeHigh, " | Low: ", g_rangeLow);
}

//+------------------------------------------------------------------+
//| Draw Opening Range Lines                                          |
//+------------------------------------------------------------------+
void DrawRangeLines()
{
    ObjectDelete(0, OBJ_RANGE_HIGH);
    ObjectCreate(0, OBJ_RANGE_HIGH, OBJ_HLINE, 0, 0, g_rangeHigh);
    ObjectSetInteger(0, OBJ_RANGE_HIGH, OBJPROP_COLOR, InpRangeHighColor);
    ObjectSetInteger(0, OBJ_RANGE_HIGH, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, OBJ_RANGE_HIGH, OBJPROP_WIDTH, 2);
    ObjectSetString(0, OBJ_RANGE_HIGH, OBJPROP_TEXT, "OR High: " + DoubleToString(g_rangeHigh, _Digits));
    
    ObjectDelete(0, OBJ_RANGE_LOW);
    ObjectCreate(0, OBJ_RANGE_LOW, OBJ_HLINE, 0, 0, g_rangeLow);
    ObjectSetInteger(0, OBJ_RANGE_LOW, OBJPROP_COLOR, InpRangeLowColor);
    ObjectSetInteger(0, OBJ_RANGE_LOW, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, OBJ_RANGE_LOW, OBJPROP_WIDTH, 2);
    ObjectSetString(0, OBJ_RANGE_LOW, OBJPROP_TEXT, "OR Low: " + DoubleToString(g_rangeLow, _Digits));
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Mark First and Last Candles of Opening Range                      |
//+------------------------------------------------------------------+
void MarkOpeningRangeCandles()
{
    datetime time[];
    double high[];
    
    int copied = CopyTime(_Symbol, InpORTimeframe, g_rangeStartTime, g_rangeEndTime, time);
    int copied_high = CopyHigh(_Symbol, InpORTimeframe, g_rangeStartTime, g_rangeEndTime, high);
    
    if(copied <= 0 || copied_high <= 0)
    {
        Print("Failed to get opening range candles");
        return;
    }
    
    datetime firstCandleTime = time[0];
    int firstBarIndex = iBarShift(_Symbol, _Period, firstCandleTime);
    
    if(firstBarIndex >= 0)
    {
        double firstHigh[];
        CopyHigh(_Symbol, _Period, firstBarIndex, 1, firstHigh);
        
        string objName = "OR_First_" + TimeToString(firstCandleTime);
        ObjectDelete(0, objName);
        ObjectCreate(0, objName, OBJ_ARROW, 0, firstCandleTime, firstHigh[0]);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, InpRangeArrowColor);
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 159);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
        ObjectSetString(0, objName, OBJPROP_TEXT, "OR Start");
        
        Print("📍 First OR candle marked at: ", TimeToString(firstCandleTime));
    }
    
    if(copied > 1)
    {
        datetime lastCandleTime = time[copied - 1];
        int lastBarIndex = iBarShift(_Symbol, _Period, lastCandleTime);
        
        if(lastBarIndex >= 0)
        {
            double lastHigh[];
            CopyHigh(_Symbol, _Period, lastBarIndex, 1, lastHigh);
            
            string objName = "OR_Last_" + TimeToString(lastCandleTime);
            ObjectDelete(0, objName);
            ObjectCreate(0, objName, OBJ_ARROW, 0, lastCandleTime, lastHigh[0]);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, InpRangeArrowColor);
            ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 159);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
            ObjectSetString(0, objName, OBJPROP_TEXT, "OR End");
            
            Print("📍 Last OR candle marked at: ", TimeToString(lastCandleTime));
        }
    }
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Detect Bullish Engulfing Pattern                                  |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int barIndex = 1)
{
    double open[], close[], high[], low[];
    
    int copied = CopyOpen(_Symbol, InpBreakoutTimeframe, barIndex, 2, open);
    CopyClose(_Symbol, InpBreakoutTimeframe, barIndex, 2, close);
    CopyHigh(_Symbol, InpBreakoutTimeframe, barIndex, 2, high);
    CopyLow(_Symbol, InpBreakoutTimeframe, barIndex, 2, low);
    
    if(copied < 2) return false;
    
    double prevOpen = open[1];
    double prevClose = close[1];
    bool prevBearish = prevClose < prevOpen;
    
    double currOpen = open[0];
    double currClose = close[0];
    bool currBullish = currClose > currOpen;
    
    if(prevBearish && currBullish)
    {
        if(currOpen <= prevClose && currClose >= prevOpen)
        {
            Print("📊 Bullish Engulfing detected: Prev[", prevOpen, "-", prevClose, "] Curr[", currOpen, "-", currClose, "]");
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Hammer Pattern                                             |
//+------------------------------------------------------------------+
bool IsHammer(int barIndex = 1)
{
    double open[], close[], high[], low[];
    
    int copied = CopyOpen(_Symbol, InpBreakoutTimeframe, barIndex, 1, open);
    CopyClose(_Symbol, InpBreakoutTimeframe, barIndex, 1, close);
    CopyHigh(_Symbol, InpBreakoutTimeframe, barIndex, 1, high);
    CopyLow(_Symbol, InpBreakoutTimeframe, barIndex, 1, low);
    
    if(copied < 1) return false;
    
    double candleOpen = open[0];
    double candleClose = close[0];
    double candleHigh = high[0];
    double candleLow = low[0];
    
    double body = MathAbs(candleClose - candleOpen);
    double totalRange = candleHigh - candleLow;
    double lowerWick = MathMin(candleOpen, candleClose) - candleLow;
    double upperWick = candleHigh - MathMax(candleOpen, candleClose);
    
    if(totalRange > 0 && body > 0)
    {
        if(lowerWick >= body * 2.0 && upperWick <= body * 0.5)
        {
            Print("📊 Hammer detected: Body=", body, " Lower Wick=", lowerWick, " Upper Wick=", upperWick);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Bearish Engulfing Pattern                                  |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(int barIndex = 1)
{
    double open[], close[], high[], low[];
    
    int copied = CopyOpen(_Symbol, InpBreakoutTimeframe, barIndex, 2, open);
    CopyClose(_Symbol, InpBreakoutTimeframe, barIndex, 2, close);
    CopyHigh(_Symbol, InpBreakoutTimeframe, barIndex, 2, high);
    CopyLow(_Symbol, InpBreakoutTimeframe, barIndex, 2, low);
    
    if(copied < 2) return false;
    
    double prevOpen = open[1];
    double prevClose = close[1];
    bool prevBullish = prevClose > prevOpen;
    
    double currOpen = open[0];
    double currClose = close[0];
    bool currBearish = currClose < currOpen;
    
    if(prevBullish && currBearish)
    {
        if(currOpen >= prevClose && currClose <= prevOpen)
        {
            Print("📊 Bearish Engulfing detected: Prev[", prevOpen, "-", prevClose, "] Curr[", currOpen, "-", currClose, "]");
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Shooting Star Pattern                                      |
//+------------------------------------------------------------------+
bool IsShootingStar(int barIndex = 1)
{
    double open[], close[], high[], low[];
    
    int copied = CopyOpen(_Symbol, InpBreakoutTimeframe, barIndex, 1, open);
    CopyClose(_Symbol, InpBreakoutTimeframe, barIndex, 1, close);
    CopyHigh(_Symbol, InpBreakoutTimeframe, barIndex, 1, high);
    CopyLow(_Symbol, InpBreakoutTimeframe, barIndex, 1, low);
    
    if(copied < 1) return false;
    
    double candleOpen = open[0];
    double candleClose = close[0];
    double candleHigh = high[0];
    double candleLow = low[0];
    
    double body = MathAbs(candleClose - candleOpen);
    double totalRange = candleHigh - candleLow;
    double upperWick = candleHigh - MathMax(candleOpen, candleClose);
    double lowerWick = MathMin(candleOpen, candleClose) - candleLow;
    
    if(totalRange > 0 && body > 0)
    {
        if(upperWick >= body * 2.0 && lowerWick <= body * 0.5)
        {
            Print("📊 Shooting Star detected: Body=", body, " Upper Wick=", upperWick, " Lower Wick=", lowerWick);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for Breakout                                                |
//+------------------------------------------------------------------+
void CheckForBreakout()
{
    datetime currentBarTime = iTime(_Symbol, InpBreakoutTimeframe, 0);
    
    if(currentBarTime == g_lastCheckedBar)
        return;
    
    g_lastCheckedBar = currentBarTime;
    
    double close[], high[], low[];
    
    int copied      = CopyClose(_Symbol, InpBreakoutTimeframe, 1, 1, close);
    int copied_high = CopyHigh(_Symbol, InpBreakoutTimeframe, 1, 1, high);
    int copied_low  = CopyLow(_Symbol, InpBreakoutTimeframe, 1, 1, low);
    
    if(copied <= 0 || copied_high <= 0 || copied_low <= 0)
    {
        Print("Failed to copy breakout candle data");
        return;
    }
    
    double lastClose = close[0];
    double candleHigh = high[0];
    double candleLow  = low[0];
    
    Print("🔍 Breakout check - Close: ", lastClose, " | OR High: ", g_rangeHigh, " | OR Low: ", g_rangeLow,
          (InpReverseORB ? " | [REVERSE MODE]" : ""));
    
    // ── BULLISH BREAKOUT SIGNAL (candle closed above range high) ──
    if(lastClose > g_rangeHigh)
    {
        if(InpReverseORB)
        {
            // Reverse: bullish signal → open SELL
            Print("🔄 [REVERSE] Bullish breakout detected → Opening SELL instead");
            if(InpRequireRetest)
            {
                g_waitingForRetest    = true;
                g_isBullishBreakout   = false;   // reversed
                g_breakoutTime        = TimeCurrent();
                g_barsAfterBreakout   = 0;
                Print("⏳ Retest mode - Waiting to SELL at retest of ", g_rangeHigh);
                MarkBreakoutCandle(false);       // mark as sell (red arrow)
            }
            else
            {
                Print("⚡ [REVERSE] Opening SELL at current market price");
                if(ExecuteTrade(ORDER_TYPE_SELL, candleHigh))
                    MarkBreakoutCandle(false);
            }
        }
        else
        {
            // Normal: bullish breakout → BUY
            Print("🚀 BULLISH BREAKOUT! Candle closed at ", lastClose, " (above ", g_rangeHigh, ")");
            if(InpRequireRetest)
            {
                g_waitingForRetest  = true;
                g_isBullishBreakout = true;
                g_breakoutTime      = TimeCurrent();
                g_barsAfterBreakout = 0;
                Print("⏳ Retest mode - Waiting for pullback to ", g_rangeHigh, " and bullish confirmation");
                MarkBreakoutCandle(true);
            }
            else
            {
                Print("⚡ Opening BUY position at current market price");
                if(ExecuteTrade(ORDER_TYPE_BUY, candleLow))
                    MarkBreakoutCandle(true);
            }
        }
    }
    // ── BEARISH BREAKOUT SIGNAL (candle closed below range low) ──
    else if(lastClose < g_rangeLow)
    {
        if(InpReverseORB)
        {
            // Reverse: bearish signal → open BUY
            Print("🔄 [REVERSE] Bearish breakout detected → Opening BUY instead");
            if(InpRequireRetest)
            {
                g_waitingForRetest  = true;
                g_isBullishBreakout = true;      // reversed
                g_breakoutTime      = TimeCurrent();
                g_barsAfterBreakout = 0;
                Print("⏳ Retest mode - Waiting to BUY at retest of ", g_rangeLow);
                MarkBreakoutCandle(true);        // mark as buy (green arrow)
            }
            else
            {
                Print("⚡ [REVERSE] Opening BUY at current market price");
                if(ExecuteTrade(ORDER_TYPE_BUY, candleLow))
                    MarkBreakoutCandle(true);
            }
        }
        else
        {
            // Normal: bearish breakout → SELL
            Print("📉 BEARISH BREAKOUT! Candle closed at ", lastClose, " (below ", g_rangeLow, ")");
            if(InpRequireRetest)
            {
                g_waitingForRetest  = true;
                g_isBullishBreakout = false;
                g_breakoutTime      = TimeCurrent();
                g_barsAfterBreakout = 0;
                Print("⏳ Retest mode - Waiting for pullback to ", g_rangeLow, " and bearish confirmation");
                MarkBreakoutCandle(false);
            }
            else
            {
                Print("⚡ Opening SELL position at current market price");
                if(ExecuteTrade(ORDER_TYPE_SELL, candleHigh))
                    MarkBreakoutCandle(false);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for Retest and Confirmation                                 |
//+------------------------------------------------------------------+
void CheckForRetestConfirmation()
{
    datetime currentBarTime = iTime(_Symbol, InpBreakoutTimeframe, 0);
    
    if(currentBarTime == g_lastCheckedBar)
        return;
    
    g_lastCheckedBar = currentBarTime;
    g_barsAfterBreakout++;
    
    if(g_barsAfterBreakout > InpRetestBars)
    {
        Print("⏰ Retest timeout - ", InpRetestBars, " bars passed without confirmation. Resetting.");
        g_waitingForRetest  = false;
        g_barsAfterBreakout = 0;
        return;
    }
    
    double close[], high[], low[];
    int copied      = CopyClose(_Symbol, InpBreakoutTimeframe, 1, 1, close);
    int copied_high = CopyHigh(_Symbol, InpBreakoutTimeframe, 1, 1, high);
    int copied_low  = CopyLow(_Symbol, InpBreakoutTimeframe, 1, 1, low);
    
    if(copied <= 0) return;
    
    double lastClose = close[0];
    double candleHigh = high[0];
    double candleLow  = low[0];
    
    // g_isBullishBreakout already accounts for reversal (set in CheckForBreakout)
    if(g_isBullishBreakout)
    {
        // Looking for BULLISH confirmation → will open BUY
        bool retested = (candleLow <= g_rangeHigh + (10 * _Point));
        
        if(retested)
        {
            Print("✅ Retest detected! Low: ", candleLow, " touched ", g_rangeHigh);
            
            bool bullishEngulfing = IsBullishEngulfing(1);
            bool hammer           = IsHammer(1);
            
            if(bullishEngulfing || hammer)
            {
                string pattern = bullishEngulfing ? "Bullish Engulfing" : "Hammer";
                Print("🎯 CONFIRMATION: ", pattern, " pattern detected!");
                
                g_confirmationCandleLow  = candleLow;
                g_confirmationCandleHigh = candleHigh;
                
                string tradeLabel = InpReverseORB ? "[REVERSE] Opening BUY (was bearish signal)" : "Opening BUY";
                Print("⚡ ", tradeLabel, " with confirmation");
                
                if(ExecuteTrade(ORDER_TYPE_BUY, g_confirmationCandleLow))
                    g_waitingForRetest = false;
            }
            else
            {
                Print("⏳ Retest occurred but no bullish pattern yet. Waiting... (Bar ", g_barsAfterBreakout, "/", InpRetestBars, ")");
            }
        }
        else
        {
            Print("⏳ Waiting for retest of ", g_rangeHigh, " | Current Low: ", candleLow, " (Bar ", g_barsAfterBreakout, "/", InpRetestBars, ")");
        }
    }
    else
    {
        // Looking for BEARISH confirmation → will open SELL
        bool retested = (candleHigh >= g_rangeLow - (10 * _Point));
        
        if(retested)
        {
            Print("✅ Retest detected! High: ", candleHigh, " touched ", g_rangeLow);
            
            bool bearishEngulfing = IsBearishEngulfing(1);
            bool shootingStar     = IsShootingStar(1);
            
            if(bearishEngulfing || shootingStar)
            {
                string pattern = bearishEngulfing ? "Bearish Engulfing" : "Shooting Star";
                Print("🎯 CONFIRMATION: ", pattern, " pattern detected!");
                
                g_confirmationCandleLow  = candleLow;
                g_confirmationCandleHigh = candleHigh;
                
                string tradeLabel = InpReverseORB ? "[REVERSE] Opening SELL (was bullish signal)" : "Opening SELL";
                Print("⚡ ", tradeLabel, " with confirmation");
                
                if(ExecuteTrade(ORDER_TYPE_SELL, g_confirmationCandleHigh))
                    g_waitingForRetest = false;
            }
            else
            {
                Print("⏳ Retest occurred but no bearish pattern yet. Waiting... (Bar ", g_barsAfterBreakout, "/", InpRetestBars, ")");
            }
        }
        else
        {
            Print("⏳ Waiting for retest of ", g_rangeLow, " | Current High: ", candleHigh, " (Bar ", g_barsAfterBreakout, "/", InpRetestBars, ")");
        }
    }
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//| In Reverse mode: SL reference and TP are mirrored automatically  |
//| because the order type itself is already flipped.                 |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE orderType, double slReference)
{
    MqlTick latest_tick;
    if(!SymbolInfoTick(_Symbol, latest_tick))
    {
        Print("❌ Failed to get current tick data");
        return false;
    }
    
    double price = (orderType == ORDER_TYPE_BUY) ? latest_tick.ask : latest_tick.bid;
    
    Print("💰 CURRENT LIVE PRICE: ", (orderType == ORDER_TYPE_BUY ? "Ask" : "Bid"), " = ", price);
    
    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // ── Stop Loss Calculation ──
    // slReference is already the correct candle extreme for the flipped order type,
    // because CheckForBreakout() passes the right candle side per order direction.
    double stopLoss = 0.0;
    string slMethod = "";
    
    switch(InpSLPlacement)
    {
        case SL_BREAKOUT_CANDLE:
        {
            if(orderType == ORDER_TYPE_BUY)
            {
                stopLoss = slReference - (InpSLBufferPoints * pointSize);
                slMethod = "Breakout Candle Low";
            }
            else
            {
                stopLoss = slReference + (InpSLBufferPoints * pointSize);
                slMethod = "Breakout Candle High";
            }
            break;
        }
        case SL_MID_RANGE:
        {
            double midRange = (g_rangeHigh + g_rangeLow) / 2.0;
            if(orderType == ORDER_TYPE_BUY)
            {
                stopLoss = midRange - (InpSLBufferPoints * pointSize);
                slMethod = "Mid Range";
            }
            else
            {
                stopLoss = midRange + (InpSLBufferPoints * pointSize);
                slMethod = "Mid Range";
            }
            break;
        }
        case SL_OPPOSITE_RANGE:
        {
            if(orderType == ORDER_TYPE_BUY)
            {
                stopLoss = g_rangeLow - (InpSLBufferPoints * pointSize);
                slMethod = "Range Low (Opposite Side)";
            }
            else
            {
                stopLoss = g_rangeHigh + (InpSLBufferPoints * pointSize);
                slMethod = "Range High (Opposite Side)";
            }
            break;
        }
    }
    
    stopLoss = NormalizeDouble(stopLoss, digits);
    
    double lotSize = CalculateLotSize(price, stopLoss);
    
    if(lotSize <= 0)
    {
        Print("❌ Invalid lot size: ", lotSize);
        return false;
    }
    
    g_slDistance = MathAbs(price - stopLoss);
    
    double takeProfit = 0.0;
    if(InpFinalTPRR > 0)
    {
        if(orderType == ORDER_TYPE_BUY)
            takeProfit = price + (g_slDistance * InpFinalTPRR);
        else
            takeProfit = price - (g_slDistance * InpFinalTPRR);
        
        takeProfit = NormalizeDouble(takeProfit, digits);
    }
    
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("📋 TRADE EXECUTION DETAILS", (InpReverseORB ? " [REVERSE ORB]" : ""), ":");
    Print("   Type: ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"));
    Print("   Entry Price: ", price, " ← CURRENT MARKET PRICE");
    Print("   SL Method: ", slMethod);
    Print("   Stop Loss: ", stopLoss, " (", DoubleToString(g_slDistance / pointSize, 1), " points away)");
    Print("   Take Profit: ", takeProfit, " (", DoubleToString((g_slDistance * InpFinalTPRR) / pointSize, 1), " points away)");
    Print("   Lot Size: ", lotSize);
    Print("   Risk: $", InpRiskAmount);
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    string comment = InpReverseORB ? "ORB Reverse " : "ORB ";
    comment += (orderType == ORDER_TYPE_BUY ? "Buy" : "Sell");
    
    bool result = false;
    if(orderType == ORDER_TYPE_BUY)
        result = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, comment);
    else
        result = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, comment);
    
    if(result)
    {
        Sleep(100);
        
        if(PositionSelect(_Symbol))
        {
            g_positionTicket = PositionGetInteger(POSITION_TICKET);
            g_entryPrice     = PositionGetDouble(POSITION_PRICE_OPEN);
            g_originalSL     = stopLoss;
            g_slDistance     = MathAbs(g_entryPrice - stopLoss);
            
            Print("✅✅✅ POSITION OPENED ✅✅✅");
            Print("   Ticket: ", g_positionTicket);
            Print("   Actual Fill: ", g_entryPrice);
            Print("   Slippage: ", DoubleToString((g_entryPrice - price) / pointSize, 1), " points");
            
            g_tradeToday    = true;
            g_lastTradeDate = TimeCurrent();
            return true;
        }
        else
        {
            Print("⚠️ Trade sent but position not found");
            g_tradeToday = true;
            return true;
        }
    }
    else
    {
        Print("❌ TRADE FAILED: ", trade.ResultRetcodeDescription());
        Print("   Return Code: ", trade.ResultRetcode());
        Print("   Last Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
    double slDistance = MathAbs(entryPrice - stopLoss);
    
    if(slDistance <= 0)
    {
        Print("Invalid SL distance: ", slDistance);
        return 0;
    }
    
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    double slTicks = slDistance / tickSize;
    double lotSize = InpRiskAmount / (slTicks * tickValue);
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Mark Breakout Candle on Chart                                     |
//+------------------------------------------------------------------+
void MarkBreakoutCandle(bool isBullish)
{
    datetime time[];
    double high[], low[];
    
    int copied = CopyTime(_Symbol, InpBreakoutTimeframe, 1, 1, time);
    CopyHigh(_Symbol, InpBreakoutTimeframe, 1, 1, high);
    CopyLow(_Symbol, InpBreakoutTimeframe, 1, 1, low);
    
    if(copied <= 0)
        return;
    
    datetime candleTime = time[0];
    int barIndex = iBarShift(_Symbol, _Period, candleTime);
    
    if(barIndex < 0)
        return;
    
    double chartHigh[], chartLow[];
    CopyHigh(_Symbol, _Period, barIndex, 1, chartHigh);
    CopyLow(_Symbol, _Period, barIndex, 1, chartLow);
    
    string objName = "OR_Breakout_" + TimeToString(candleTime);
    ObjectDelete(0, objName);
    
    if(isBullish)
    {
        ObjectCreate(0, objName, OBJ_ARROW, 0, candleTime, chartLow[0]);
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 241);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, InpBuyBreakoutColor);
    }
    else
    {
        ObjectCreate(0, objName, OBJ_ARROW, 0, candleTime, chartHigh[0]);
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 242);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, InpSellBreakoutColor);
    }
    
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
    ObjectSetString(0, objName, OBJPROP_TEXT, InpReverseORB ? "Reverse Breakout" : "Breakout");
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Manage Active Position                                            |
//+------------------------------------------------------------------+
void ManageActivePosition()
{
    if(!PositionSelect(_Symbol))
    {
        g_positionTicket = 0;
        return;
    }
    
    double currentPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL     = PositionGetDouble(POSITION_SL);
    double currentTP     = PositionGetDouble(POSITION_TP);
    double currentVolume = PositionGetDouble(POSITION_VOLUME);
    double entryPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    double profitPoints = 0.0;
    if(posType == POSITION_TYPE_BUY)
        profitPoints = currentPrice - entryPrice;
    else
        profitPoints = entryPrice - currentPrice;
    
    double fullTargetDistance = g_slDistance * InpFinalTPRR;
    double profitPercentage   = (profitPoints / fullTargetDistance) * 100.0;
    
    // Partial close at 1:1
    if(InpEnablePartialClose && !g_partialClosed && profitPoints >= g_slDistance)
    {
        double halfVolume = currentVolume / 2.0;
        double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        halfVolume = MathFloor(halfVolume / lotStep) * lotStep;
        
        double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        if(halfVolume >= minLot)
        {
            bool result = trade.PositionClosePartial(_Symbol, halfVolume);
            if(result)
            {
                g_partialClosed = true;
                Print("✅ PARTIAL CLOSE: ", halfVolume, " lots at 1:1 RR. Price: ", currentPrice);
            }
        }
        else
        {
            g_partialClosed = true;
        }
    }
    
    // Move to breakeven at 30% progress
    if(InpEnableBreakeven && !g_movedToBreakeven && profitPercentage >= 30.0)
    {
        double newSL = NormalizeDouble(entryPrice, digits);
        
        bool needsUpdate = false;
        if(posType == POSITION_TYPE_BUY  && currentSL < entryPrice - _Point) needsUpdate = true;
        if(posType == POSITION_TYPE_SELL && currentSL > entryPrice + _Point) needsUpdate = true;
        
        if(needsUpdate)
        {
            bool result = trade.PositionModify(_Symbol, newSL, currentTP);
            if(result)
            {
                g_movedToBreakeven = true;
                Print("✅ BREAKEVEN: SL moved to ", newSL, " at ", DoubleToString(profitPercentage, 1), "% progress");
            }
        }
        else
        {
            g_movedToBreakeven = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Create Info Box                                                   |
//+------------------------------------------------------------------+
void CreateInfoBox()
{
    ObjectDelete(0, OBJ_INFO_BOX);
    
    ObjectCreate(0, OBJ_INFO_BOX, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, OBJ_INFO_BOX, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, OBJ_INFO_BOX, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, OBJ_INFO_BOX, OBJPROP_YDISTANCE, 30);
    ObjectSetInteger(0, OBJ_INFO_BOX, OBJPROP_COLOR, clrDarkGray);
    ObjectSetInteger(0, OBJ_INFO_BOX, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, OBJ_INFO_BOX, OBJPROP_FONT, "Consolas");
    
    UpdateInfoBox();
}

//+------------------------------------------------------------------+
//| Update Info Box                                                   |
//+------------------------------------------------------------------+
void UpdateInfoBox()
{
    string orTF = "";
    switch(InpORTimeframe)
    {
        case PERIOD_M5:  orTF = "5min";  break;
        case PERIOD_M15: orTF = "15min"; break;
        case PERIOD_H1:  orTF = "1hr";   break;
        default:         orTF = "Unknown";
    }
    
    string breakoutTF = "";
    switch(InpBreakoutTimeframe)
    {
        case PERIOD_M1: breakoutTF = "1min"; break;
        case PERIOD_M5: breakoutTF = "5min"; break;
        default:        breakoutTF = "Unknown";
    }
    
    string infoText = "ORB EA v1.7 | Range: " + orTF + " | Breakout: " + breakoutTF;
    
    if(InpReverseORB)
        infoText += " | 🔄 REVERSE MODE";
    
    if(InpRequireRetest)
        infoText += " | RETEST MODE";
    
    infoText += " | Risk: $" + DoubleToString(InpRiskAmount, 0);
    
    if(!IsTradingDay())
    {
        infoText += " | ⏸️ PAUSED (Non-Trading Day)";
    }
    else
    {
        if(g_waitingForRetest)
        {
            string direction = g_isBullishBreakout ? "BUY" : "SELL";
            infoText += " | ⏳ WAITING RETEST (→" + direction + " " + IntegerToString(g_barsAfterBreakout) + "/" + IntegerToString(InpRetestBars) + ")";
        }
        else if(g_rangeSet)
        {
            infoText += " | H: " + DoubleToString(g_rangeHigh, _Digits) + " L: " + DoubleToString(g_rangeLow, _Digits);
        }
        
        if(g_tradeToday)
            infoText += " | TRADED";
    }
    
    ObjectSetString(0, OBJ_INFO_BOX, OBJPROP_TEXT, infoText);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete All Objects                                                |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
    ObjectDelete(0, OBJ_RANGE_HIGH);
    ObjectDelete(0, OBJ_RANGE_LOW);
    ObjectDelete(0, OBJ_INFO_BOX);
    
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "OR_") >= 0)
            ObjectDelete(0, name);
    }
    
    ChartRedraw();
}
//+------------------------------------------------------------------+