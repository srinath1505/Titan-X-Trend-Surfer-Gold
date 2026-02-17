//+------------------------------------------------------------------+
//|                                                 TradeOfficer.mqh |
//|                                  Copyright 2024, Titan X Project |
//+------------------------------------------------------------------+
#property copyright "Titan X Project"
#property strict

#include <Trade/Trade.mqh>

class CTradeOfficer
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;
   
   // Settings
   int               m_atrPeriod;
   double            m_atrMultiplierSL;
   double            m_riskRewardRatio;
   int               m_maxSpreadPoints; // New Spread Filter
   int               m_minSLPoints;     // Min SL Distance Filter
   
   // Handles
   int               m_hATR;

public:
                     CTradeOfficer();
                    ~CTradeOfficer();
   
   void              Init(string symbol, ulong magic, int atrPeriod, double atrMultSL, double rrRatio, int maxSpread=20, int minSL=100);
   void              ReleaseHandles();
   
   bool              ExecuteBuy(double volume, string comment="Titan-X-HF");
   bool              ExecuteSell(double volume, string comment="Titan-X-HF");
   void              ManageTrailingStop();
   
   double            GetOptimalSL(bool isBuy);
   double            GetOptimalTP(bool isBuy, double slPrice);
   
private:
   double            GetATR();
   bool              IsSpreadOK(); // Spread Check Helper
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeOfficer::CTradeOfficer() : m_hATR(INVALID_HANDLE), m_maxSpreadPoints(50), m_minSLPoints(100)
  {
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTradeOfficer::~CTradeOfficer()
  {
   ReleaseHandles();
  }

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CTradeOfficer::Init(string symbol, ulong magic, int atrPeriod, double atrMultSL, double rrRatio, int maxSpread=20, int minSL=100)
  {
   m_symbol = symbol;
   m_magic = magic;
   m_atrPeriod = atrPeriod;
   m_atrMultiplierSL = atrMultSL;
   m_riskRewardRatio = rrRatio;
   m_maxSpreadPoints = maxSpread;
   m_minSLPoints = minSL;
   
   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(m_symbol);
   m_trade.SetDeviationInPoints(10);
   
   if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
   m_hATR = iATR(m_symbol, PERIOD_CURRENT, m_atrPeriod);
  }

//+------------------------------------------------------------------+
//| Cleanup                                                          |
//+------------------------------------------------------------------+
void CTradeOfficer::ReleaseHandles()
  {
   if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
   m_hATR = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//| Execution Logic                                                  |
//+------------------------------------------------------------------+
bool CTradeOfficer::ExecuteBuy(double volume, string comment="Titan-X-HF")
  {
   // 1. Spread Check
   if(!IsSpreadOK())
     {
      Print("TITAN X EXECUTION: Trade Skipped. High Spread.");
      return false;
     }

   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double sl = GetOptimalSL(true);
   double tp = GetOptimalTP(true, sl);
   
   // Normalize
   double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   sl = MathRound(sl / tickSize) * tickSize;
   tp = MathRound(tp / tickSize) * tickSize;
   
   return m_trade.Buy(volume, m_symbol, ask, sl, tp, comment);
  }

bool CTradeOfficer::ExecuteSell(double volume, string comment="Titan-X-HF")
  {
   // 1. Spread Check
   if(!IsSpreadOK())
     {
      Print("TITAN X EXECUTION: Trade Skipped. High Spread.");
      return false;
     }

   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double sl = GetOptimalSL(false);
   double tp = GetOptimalTP(false, sl);
   
   double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   sl = MathRound(sl / tickSize) * tickSize;
   tp = MathRound(tp / tickSize) * tickSize;
   
   return m_trade.Sell(volume, m_symbol, bid, sl, tp, comment);
  }

//+------------------------------------------------------------------+
//| Trailing Stop & Scale Out Management                             |
//+------------------------------------------------------------------+
void CTradeOfficer::ManageTrailingStop()
  {
   double atr = GetATR();
   if(atr <= 0) return;
   
   double trailDist = atr * 3.0; // AGGRESSIVE TRAIL: 3.0x ATR (Giving room to run)
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == m_symbol && PositionGetInteger(POSITION_MAGIC) == m_magic) 
        {
         ulong ticket = PositionGetTicket(i);
         double sl = PositionGetDouble(POSITION_SL);
         double startPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         long type = PositionGetInteger(POSITION_TYPE);
         
         // 1R Distance Calculation
         double rDistance = atr * m_atrMultiplierSL; 
         
         if(type == POSITION_TYPE_BUY)
           {
            double profitpips = currentPrice - startPrice;
            
            // 1. FRESH TRADE (SL below Entry)
            // Check if SL is at original risk distance (approx) or just below entry
            if(sl < startPrice - (tickSize*5))
              {
               if(profitpips >= rDistance)
                 {
                  // ACTION: Scale Out 50% & Move SL to Breakeven
                  m_trade.PositionClosePartial(ticket, volume/2.0);
                  m_trade.PositionModify(ticket, startPrice + (50*point), 0); // Move to BE + Buffer
                  Print("TITAN SURFER: Scaled Out 50% at 1R - Secured BE");
                 }
              }
            // 2. SCALED TRADE (SL at BE or better)
            else
              {
               // DYNAMIC TRAIL
               double newSL = currentPrice - trailDist;
               newSL = MathFloor(newSL / tickSize) * tickSize;
               
               if(newSL > sl + point) m_trade.PositionModify(ticket, newSL, 0); 
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double profitpips = startPrice - currentPrice;
            
            // 1. FRESH TRADE (SL above Entry)
            if(sl > startPrice + (tickSize*5))
              {
               if(profitpips >= rDistance)
                 {
                  // ACTION: Scale Out 50% & Move SL to Breakeven
                  m_trade.PositionClosePartial(ticket, volume/2.0);
                  m_trade.PositionModify(ticket, startPrice - (50*point), 0); // Move to BE - Buffer
                  Print("TITAN SURFER: Scaled Out 50% at 1R - Secured BE");
                 }
              }
            // 2. SCALED TRADE (SL at BE or better)
            else
              {
               // DYNAMIC TRAIL
               double newSL = currentPrice + trailDist;
               newSL = MathCeil(newSL / tickSize) * tickSize;
               
               if(newSL < sl - point || sl == 0) m_trade.PositionModify(ticket, newSL, 0);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss (ATR Based)                          |
//+------------------------------------------------------------------+
double CTradeOfficer::GetOptimalSL(bool isBuy)
  {
   double atr = GetATR();
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   // If ATR is invalid, callback to fixed points (e.g. 50 pips = 500 points)
   if(atr <= 0) atr = 500 * point; 
   
   // Safety: Ensure buffer is at least MinSLPoints
   // AND FORCE MINIMUM MULTIPLIER (Objective: Survive Volatility)
   if(m_atrMultiplierSL < 2.5) m_atrMultiplierSL = 2.5; 
   double buffer = atr * m_atrMultiplierSL;
   
   double minPoints = m_minSLPoints * point;
   if(buffer < minPoints) buffer = minPoints;
   
   if(isBuy)
     {
      // SL below recent low (using Bid) - Buffer
      double low = iLow(m_symbol, PERIOD_CURRENT, 1);
      return low - buffer;
     }
   else
     {
      // SL above recent high (using Ask logic, approx High) + Buffer
      double high = iHigh(m_symbol, PERIOD_CURRENT, 1);
      return high + buffer;
     }
  }

//+------------------------------------------------------------------+
//| Calculate Dynamic Take Profit (RR Ratio)                         |
//+------------------------------------------------------------------+
double CTradeOfficer::GetOptimalTP(bool isBuy, double slPrice)
  {
   // AGGRESSIVE STRATEGY: NO TAKE PROFIT (Unlimited Upside)
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Helper: ATR                                                      |
//+------------------------------------------------------------------+
double CTradeOfficer::GetATR()
  {
   if(m_hATR == INVALID_HANDLE) return 0;
   double buf[1];
   if(CopyBuffer(m_hATR, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
  }

//+------------------------------------------------------------------+
//| Helper: Spread Check                                             |
//+------------------------------------------------------------------+
bool CTradeOfficer::IsSpreadOK()
  {
   long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD); // Points
   return (spread <= (long)m_maxSpreadPoints);
  }
