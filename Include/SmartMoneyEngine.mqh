//+------------------------------------------------------------------+
//|                                             SmartMoneyEngine.mqh |
//|                                  Copyright 2024, Titan X Project |
//+------------------------------------------------------------------+
#property copyright "Titan X Project"
#property strict

#include <Trade/Trade.mqh>

// --- Signal Types for Titan X ---
enum ENUM_SMC_SIGNAL
  {
   SMC_NONE,
   SMC_BUY_SWEEP,   // Now represents Trend Pullback Buy
   SMC_SELL_SWEEP   // Now represents Trend Pullback Sell
  };

class CSmartMoneyEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe; // Execution TF (M15)
   
   // Indicator Handles
   int               m_hMaTrend;      // H1 200 EMA (Master Trend)
   int               m_hMaPullback;   // M15 20 EMA (Pullback Zone)
   int               m_hATR;          // Current Volatility
   int               m_hAvgATR;       // Avg Volatility (SMA 20 of ATR)
   
public:
                     CSmartMoneyEngine();
                    ~CSmartMoneyEngine();
   
   void              Init(string symbol, ENUM_TIMEFRAMES timeframe);
   void              ReleaseHandles();
   
   ENUM_SMC_SIGNAL   GetSignal();
   
private:
   bool              IsTrendBullish();
   bool              IsTrendBearish();
   bool              IsVolatilityHealthy();
   bool              DetectPullbackEntry(bool isBullish);
   
   // Helper to safely get buffer data
   double            GetVal(int handle, int index);
  };

//+------------------------------------------------------------------+
//| Constructor & Destructor                                         |
//+------------------------------------------------------------------+
CSmartMoneyEngine::CSmartMoneyEngine() : 
   m_hMaTrend(INVALID_HANDLE), 
   m_hMaPullback(INVALID_HANDLE), 
   m_hATR(INVALID_HANDLE),
   m_hAvgATR(INVALID_HANDLE)
{}

CSmartMoneyEngine::~CSmartMoneyEngine()
{
   ReleaseHandles();
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
void CSmartMoneyEngine::Init(string symbol, ENUM_TIMEFRAMES timeframe)
{
   m_symbol = symbol;
   m_timeframe = timeframe;
   
   // 1. Master Trend: H1 200 EMA
   m_hMaTrend = iMA(m_symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   // 2. Pullback Zone: M15 20 EMA
   m_hMaPullback = iMA(m_symbol, m_timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
   
   // 3. Volatility: ATR 14
   m_hATR = iATR(m_symbol, m_timeframe, 14);
   
   // 4. Avg Volatility: SMA 20 of ATR
   m_hAvgATR = iMA(m_symbol, m_timeframe, 20, 0, MODE_SMA, m_hATR);
}

void CSmartMoneyEngine::ReleaseHandles()
{
   if(m_hMaTrend != INVALID_HANDLE)      IndicatorRelease(m_hMaTrend);
   if(m_hMaPullback != INVALID_HANDLE)   IndicatorRelease(m_hMaPullback);
   if(m_hATR != INVALID_HANDLE)          IndicatorRelease(m_hATR);
   if(m_hAvgATR != INVALID_HANDLE)       IndicatorRelease(m_hAvgATR);
   
   m_hMaTrend = m_hMaPullback = m_hATR = m_hAvgATR = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Main Execution Logic (Trend Surfer)                              |
//+------------------------------------------------------------------+
ENUM_SMC_SIGNAL CSmartMoneyEngine::GetSignal()
{
   // 1. Volatility Gatekeeper (Hard Floor)
   if(!IsVolatilityHealthy()) return SMC_NONE;

   // 2. Trend Direction (LONGS ONLY LOCK)
   bool trendUp = IsTrendBullish(); // Checking H1 200 EMA
   
   if(trendUp)
   {
      // 3. Pullback Entry Validation (BULLISH ONLY)
      if(DetectPullbackEntry(true)) return SMC_BUY_SWEEP;
   }
   
   // EXPLICITLY BLOCK ALL SELLS
   // if(trendDown) { ... } -> REMOVED
   
   return SMC_NONE;
}

//+------------------------------------------------------------------+
//| Logic Components                                                 |
//+------------------------------------------------------------------+

bool CSmartMoneyEngine::IsTrendBullish()
{
   // Price > H1 200 EMA
   double h1MA = GetVal(m_hMaTrend, 1);
   double price = iClose(m_symbol, PERIOD_H1, 1); 
   return (price > h1MA); 
}

bool CSmartMoneyEngine::IsTrendBearish()
{
   // Price < H1 200 EMA
   double h1MA = GetVal(m_hMaTrend, 1);
   double price = iClose(m_symbol, PERIOD_H1, 1);
   return (price < h1MA);
}

bool CSmartMoneyEngine::IsVolatilityHealthy()
{
   double currentATR = GetVal(m_hATR, 1);
   double avgATR = GetVal(m_hAvgATR, 1);
   
   if(avgATR == 0) return true; // Safety
   return (currentATR > avgATR * 0.8);
}

bool CSmartMoneyEngine::DetectPullbackEntry(bool isBullish)
{
   // Logic: Price touched 20 EMA zone but closed Strong
   
   double ema20 = GetVal(m_hMaPullback, 1);
   double open1 = iOpen(m_symbol, m_timeframe, 1);
   double close1 = iClose(m_symbol, m_timeframe, 1);
   double low1 = iLow(m_symbol, m_timeframe, 1);
   double high1 = iHigh(m_symbol, m_timeframe, 1);
   
   if(isBullish)
   {
      // 1. Green Candle (Strength)
      if(close1 <= open1) return false;
      
      // 2. Touched or Near 20 EMA (Value Area)
      // "Within 0.2%"
      double upperBand = ema20 * 1.002;
      double lowerBand = ema20 * 0.998; // Not strictly needed for buy, but good context
      
      // Did we dip into value?
      // Either Low touched the EMA OR Open was near it
      bool validTouch = (low1 <= upperBand && close1 > ema20);
      
      // 3. Breakout Confirmation (Close > Prev High)
      double prevHigh = iHigh(m_symbol, m_timeframe, 2);
      bool breakout = (close1 > prevHigh);
      
      return (validTouch && breakout);
   }
   else
   {
      // 1. Red Candle
      if(close1 >= open1) return false;
      
      // 2. Value Area
      double lowerBand = ema20 * 0.998;
      
      bool validTouch = (high1 >= lowerBand && close1 < ema20);
      
      // 3. Breakout Confirmation
      double prevLow = iLow(m_symbol, m_timeframe, 2);
      bool breakout = (close1 < prevLow);
      
      return (validTouch && breakout);
   }
}

//+------------------------------------------------------------------+
//| Internal Helpers                                                 |
//+------------------------------------------------------------------+

double CSmartMoneyEngine::GetVal(int handle, int index)
{
   if(handle == INVALID_HANDLE) return 0;
   double buf[1];
   if(CopyBuffer(handle, 0, index, 1, buf) > 0) return buf[0];
   return 0;
}
