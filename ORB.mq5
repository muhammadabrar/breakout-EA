//+------------------------------------------------------------------+
//|                                          OpenRangeBreakout.mq5   |
//|                                   Professional ORB Strategy EA    |
//|                                                          v1.4     |
//+------------------------------------------------------------------+
#property copyright "Open Range Breakout EA"
#property link      ""
#property version   "1.40"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// Opening Range Settings
input group "=== Opening Range Settings ==="
input int InpMarketOpenHour = 9;                    // Market Open Hour (24h format)
input int InpMarketOpenMinute = 30;                  // Market Open Minute
input ENUM_TIMEFRAMES InpORTimeframe = PERIOD_M15;   // Opening Range Timeframe (M5/M15/H1)

// Breakout Settings
input group "=== Breakout Settings ==="
input ENUM_TIMEFRAMES InpBreakoutTimeframe = PERIOD_M1; // Breakout Candle Timeframe (M1/M5)

// Stop Loss Settings
input group "=== Stop Loss & TP Settings ==="
input double InpSLBufferPoints = 5.0;                // Stop Loss Buffer (points)
input bool InpEnablePartialClose = true;             // Enable Partial Close at 1:1
input bool InpEnableBreakeven = true;                // Move SL to Breakeven at 30% Profit
input double InpFinalTPRR = 2.0;                     // Final Take Profit at 1:2 RR

// Risk Management
input group "=== Risk Management ==="
input double InpRiskAmount = 100.0;                  // Risk Amount per Trade ($)

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

// Object Names
const string OBJ_RANGE_HIGH = "OR_High";
const string OBJ_RANGE_LOW = "OR_Low";
const string OBJ_INFO_BOX = "OR_InfoBox";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set trade parameters
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetDeviationInPoints(10);
    
    // Validate inputs
    if(!ValidateInputs())
    {
        Print("Invalid input parameters!");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Create info box
    CreateInfoBox();
    
    Print("Open Range Breakout EA v1.4 initialized successfully");
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
    // Check if new day - reset everything
    if(IsNewDay())
    {
        ResetDaily();
    }
    
    // Define opening range if not set
    if(!g_rangeSet && IsTimeToSetRange())
    {
        SetOpeningRange();
    }
    
    // Check for breakout if range is set and no trade taken today
    if(g_rangeSet && !g_tradeToday)
    {
        CheckForBreakout();
    }
    
    // Manage active position
    if(g_tradeToday && g_positionTicket > 0)
    {
        ManageActivePosition();
    }
    
    // Update info box
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
    
    if(InpORTimeframe != PERIOD_M5 && InpORTimeframe != PERIOD_M15 && InpORTimeframe != PERIOD_H1)
    {
        Print("Invalid Opening Range timeframe. Use M5, M15, or H1");
        return false;
    }
    
    if(InpBreakoutTimeframe != PERIOD_M1 && InpBreakoutTimeframe != PERIOD_M5)
    {
        Print("Invalid Breakout timeframe. Use M1 or M5");
        return false;
    }
    
    return true;
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
    {
        return true;
    }
    
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
    {
        return true;
    }
    
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
    
    // Calculate when the range ENDS (start time + period)
    int rangePeriodSeconds = PeriodSeconds(InpORTimeframe);
    g_rangeEndTime = g_rangeStartTime + rangePeriodSeconds;
    
    // Check if current time is past the range END time
    if(TimeCurrent() < g_rangeEndTime)
    {
        Print("⏳ Waiting for opening range to complete. Ends at: ", TimeToString(g_rangeEndTime));
        return; // Wait for range period to complete
    }
    
    // Get the number of bars in the range period
    int barsToCopy = 0;
    if(InpORTimeframe == PERIOD_M5)
        barsToCopy = (int)(rangePeriodSeconds / PeriodSeconds(PERIOD_M5));
    else if(InpORTimeframe == PERIOD_M15)
        barsToCopy = (int)(rangePeriodSeconds / PeriodSeconds(PERIOD_M15));
    else if(InpORTimeframe == PERIOD_H1)
        barsToCopy = (int)(rangePeriodSeconds / PeriodSeconds(PERIOD_H1));
    
    // Get the bar index of the start time
    int startBarIndex = iBarShift(_Symbol, InpORTimeframe, g_rangeStartTime);
    
    if(startBarIndex < 0)
    {
        Print("❌ Cannot find opening range start bar");
        return;
    }
    
    // Copy high and low data from the range period
    double high[], low[];
    int copied_high = CopyHigh(_Symbol, InpORTimeframe, startBarIndex, barsToCopy, high);
    int copied_low = CopyLow(_Symbol, InpORTimeframe, startBarIndex, barsToCopy, low);
    
    if(copied_high <= 0 || copied_low <= 0)
    {
        Print("Failed to copy price data for opening range. Copied: ", copied_high, " bars");
        return;
    }
    
    // Find the highest high and lowest low in the range
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
    
    // Get all candles in the opening range period
    int copied = CopyTime(_Symbol, InpORTimeframe, g_rangeStartTime, g_rangeEndTime, time);
    int copied_high = CopyHigh(_Symbol, InpORTimeframe, g_rangeStartTime, g_rangeEndTime, high);
    
    if(copied <= 0 || copied_high <= 0)
    {
        Print("Failed to get opening range candles");
        return;
    }
    
    // Mark FIRST candle
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
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 159); // Down arrow
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
        ObjectSetString(0, objName, OBJPROP_TEXT, "OR Start");
        
        Print("📍 First OR candle marked at: ", TimeToString(firstCandleTime));
    }
    
    // Mark LAST candle (if more than 1 candle in range)
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
            ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 159); // Down arrow
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
            ObjectSetString(0, objName, OBJPROP_TEXT, "OR End");
            
            Print("📍 Last OR candle marked at: ", TimeToString(lastCandleTime));
        }
    }
    
    ChartRedraw();
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
    
    // Get the just-closed candle
    double close[], high[], low[];
    
    int copied = CopyClose(_Symbol, InpBreakoutTimeframe, 1, 1, close);
    int copied_high = CopyHigh(_Symbol, InpBreakoutTimeframe, 1, 1, high);
    int copied_low = CopyLow(_Symbol, InpBreakoutTimeframe, 1, 1, low);
    
    if(copied <= 0 || copied_high <= 0 || copied_low <= 0)
    {
        Print("Failed to copy breakout candle data");
        return;
    }
    
    double lastClose = close[0];
    double candleHigh = high[0];
    double candleLow = low[0];
    
    Print("🔍 Breakout check - Close: ", lastClose, " | OR High: ", g_rangeHigh, " | OR Low: ", g_rangeLow);
    
    // Bullish breakout - candle CLOSED above range
    if(lastClose > g_rangeHigh)
    {
        Print("🚀 BULLISH BREAKOUT! Candle closed at ", lastClose, " (above ", g_rangeHigh, ")");
        Print("⚡ Opening BUY position at CURRENT MARKET PRICE");
        
        if(ExecuteTrade(ORDER_TYPE_BUY, candleLow))
        {
            MarkBreakoutCandle(true);
        }
    }
    // Bearish breakout - candle CLOSED below range
    else if(lastClose < g_rangeLow)
    {
        Print("📉 BEARISH BREAKOUT! Candle closed at ", lastClose, " (below ", g_rangeLow, ")");
        Print("⚡ Opening SELL position at CURRENT MARKET PRICE");
        
        if(ExecuteTrade(ORDER_TYPE_SELL, candleHigh))
        {
            MarkBreakoutCandle(false);
        }
    }
}

//+------------------------------------------------------------------+
//| Execute Trade - Opens at CURRENT market price immediately         |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE orderType, double slReference)
{
    // Refresh tick data to get the LATEST price
    MqlTick latest_tick;
    if(!SymbolInfoTick(_Symbol, latest_tick))
    {
        Print("❌ Failed to get current tick data");
        return false;
    }
    
    // Use the CURRENT LIVE price at this exact moment
    double price = (orderType == ORDER_TYPE_BUY) ? latest_tick.ask : latest_tick.bid;
    
    Print("💰 CURRENT LIVE PRICE: ", (orderType == ORDER_TYPE_BUY ? "Ask" : "Bid"), " = ", price);
    
    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Calculate Stop Loss using the breakout candle's high/low (for SL placement only)
    double stopLoss = 0.0;
    if(orderType == ORDER_TYPE_BUY)
    {
        stopLoss = slReference - (InpSLBufferPoints * pointSize);
    }
    else
    {
        stopLoss = slReference + (InpSLBufferPoints * pointSize);
    }
    
    stopLoss = NormalizeDouble(stopLoss, digits);
    
    // Calculate lot size based on CURRENT price and SL
    double lotSize = CalculateLotSize(price, stopLoss);
    
    if(lotSize <= 0)
    {
        Print("❌ Invalid lot size: ", lotSize);
        return false;
    }
    
    // Store SL distance based on CURRENT PRICE (not breakout candle)
    g_slDistance = MathAbs(price - stopLoss);
    
    // Calculate TP at final RR from CURRENT PRICE
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
    Print("📋 TRADE EXECUTION DETAILS:");
    Print("   Type: ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"));
    Print("   Entry Price: ", price, " ← CURRENT MARKET PRICE");
    Print("   Stop Loss: ", stopLoss, " (", DoubleToString(g_slDistance / pointSize, 1), " points away)");
    Print("   Take Profit: ", takeProfit, " (", DoubleToString((g_slDistance * InpFinalTPRR) / pointSize, 1), " points away)");
    Print("   Lot Size: ", lotSize);
    Print("   Risk: $", InpRiskAmount);
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    // Execute trade at CURRENT MARKET PRICE
    bool result = false;
    if(orderType == ORDER_TYPE_BUY)
    {
        result = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "ORB Buy");
    }
    else
    {
        result = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "ORB Sell");
    }
    
    if(result)
    {
        Sleep(100); // Give time for position to register
        
        if(PositionSelect(_Symbol))
        {
            g_positionTicket = PositionGetInteger(POSITION_TICKET);
            g_entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            g_originalSL = stopLoss;
            
            // Recalculate SL distance with ACTUAL fill price
            g_slDistance = MathAbs(g_entryPrice - stopLoss);
            
            Print("✅✅✅ POSITION OPENED ✅✅✅");
            Print("   Ticket: ", g_positionTicket);
            Print("   Actual Fill: ", g_entryPrice);
            Print("   Slippage: ", DoubleToString((g_entryPrice - price) / pointSize, 1), " points");
            
            g_tradeToday = true;
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
    
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
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
    ObjectSetString(0, objName, OBJPROP_TEXT, "Breakout");
    
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
    
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    double currentVolume = PositionGetDouble(POSITION_VOLUME);
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    double profitPoints = 0.0;
    if(posType == POSITION_TYPE_BUY)
        profitPoints = currentPrice - entryPrice;
    else
        profitPoints = entryPrice - currentPrice;
    
    double fullTargetDistance = g_slDistance * InpFinalTPRR;
    double profitPercentage = (profitPoints / fullTargetDistance) * 100.0;
    
    // Partial close at 1:1
    if(InpEnablePartialClose && !g_partialClosed && profitPoints >= g_slDistance)
    {
        double halfVolume = currentVolume / 2.0;
        double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
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
        if(posType == POSITION_TYPE_BUY && currentSL < entryPrice - _Point)
            needsUpdate = true;
        else if(posType == POSITION_TYPE_SELL && currentSL > entryPrice + _Point)
            needsUpdate = true;
        
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
        case PERIOD_M5: orTF = "5min"; break;
        case PERIOD_M15: orTF = "15min"; break;
        case PERIOD_H1: orTF = "1hr"; break;
        default: orTF = "Unknown";
    }
    
    string breakoutTF = "";
    switch(InpBreakoutTimeframe)
    {
        case PERIOD_M1: breakoutTF = "1min"; break;
        case PERIOD_M5: breakoutTF = "5min"; break;
        default: breakoutTF = "Unknown";
    }
    
    string infoText = "ORB EA v1.4 | Range: " + orTF + " | Breakout: " + breakoutTF + " | Risk: $" + DoubleToString(InpRiskAmount, 0);
    
    if(g_rangeSet)
    {
        infoText += " | H: " + DoubleToString(g_rangeHigh, _Digits) + " L: " + DoubleToString(g_rangeLow, _Digits);
    }
    
    if(g_tradeToday)
    {
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
        {
            ObjectDelete(0, name);
        }
    }
    
    ChartRedraw();
}
//+------------------------------------------------------------------+
