//+------------------------------------------------------------------+
//|                                                RiskManagerV5.mqh |
//|                                  Copyright 2024, Titan X Project |
//+------------------------------------------------------------------+
#property copyright "Titan X Project"
#property strict

#include <Trade/Trade.mqh>

class CRiskManagerV5
  {
private:
   double            m_initialBalance;
   double            m_startOfDayEquity;
   double            m_currentEquity;
   
   double            m_maxExposureLots; // Max open lots allowed
   
   int               m_lastDay;
   double            m_dayStartBalance;
   
   // Constants
   double            m_dailyDDLimit; 
   double            m_totalDDLimit;

public:
                     CRiskManagerV5();
                    ~CRiskManagerV5();
   
   void              Init(double dailyDD, double totalDD, double maxExposure=40.0);
   void              OnTick();
   
   bool              CheckTradingStatus(double profitTargetPercent);
   bool              IsNewDay(); 
   
   double            CalculateLotSize(double slPoints, double riskPerTradePercent, string symbol);
   double            GetDailyDDPercent();
   double            GetTotalDDPercent();
   
private:
   void              UpdateDayStart();
   double            CheckRiskSafety(double proposedLots, double slDistance, double maxRiskMoney, string symbol);
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskManagerV5::CRiskManagerV5() : m_lastDay(-1), m_dailyDDLimit(3.0), m_totalDDLimit(8.0), m_maxExposureLots(40.0)
  {
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskManagerV5::~CRiskManagerV5()
  {
  }

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
void CRiskManagerV5::Init(double dailyDD, double totalDD, double maxExposure=40.0)
  {
   m_dailyDDLimit = dailyDD;
   m_totalDDLimit = totalDD;
   m_maxExposureLots = maxExposure;
   
   m_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Initialize Day Start Logic
   UpdateDayStart();
   
   Print("TITAN X RISK V5: Init. Balance: ", m_initialBalance, " | Daily Guard: ", m_dailyDDLimit, "% | Total Guard: ", m_totalDDLimit, "% | Max Exp: ", m_maxExposureLots, " lots");
  }

//+------------------------------------------------------------------+
//| OnTick Monitor                                                   |
//+------------------------------------------------------------------+
void CRiskManagerV5::OnTick()
  {
   if(IsNewDay()) UpdateDayStart();
   m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  }

//+------------------------------------------------------------------+
//| Check New Day                                                    |
//+------------------------------------------------------------------+
bool CRiskManagerV5::IsNewDay()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_year != m_lastDay);
  }

//+------------------------------------------------------------------+
//| Helper: Update Day Start Equity                                  |
//+------------------------------------------------------------------+
void CRiskManagerV5::UpdateDayStart()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   m_startOfDayEquity = AccountInfoDouble(ACCOUNT_EQUITY); 
   // Fallback if Equity is lower than Balance at start of day (e.g. open floating loss carried over)
   // Prop firms usually take the HIGHER of Balance or Equity at 00:00 as the baseline.
   // Let's stick to simple "Start of Day Balance/Equity" snapshot.
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > m_startOfDayEquity) m_startOfDayEquity = bal;
   
   m_lastDay = dt.day_of_year;
      
   // Global Variable Persistence
   string gvName = "TITAN_X_SOD_" + (string)AccountInfoInteger(ACCOUNT_LOGIN);
   GlobalVariableSet(gvName, m_startOfDayEquity);
      
   Print("TITAN X RISK V5: New Day Started. SOD Baseline: ", m_startOfDayEquity);
  }

//+------------------------------------------------------------------+
//| Check if Trading is Allowed                                      |
//+------------------------------------------------------------------+
bool CRiskManagerV5::CheckTradingStatus(double profitTargetPercent)
  {
   double currentDailyDD = GetDailyDDPercent();
   double currentTotalDD = GetTotalDDPercent();
   
   // 1. Check Drawdown Limits
   // Hard Stop 0.2% before the limit
   double dailyHardStop = m_dailyDDLimit - 0.2; 
   double totalHardStop = m_totalDDLimit - 0.2;
   
   if(currentDailyDD >= dailyHardStop) return false;
   if(currentTotalDD >= totalHardStop) return false;
   
   // 2. Check Daily Profit Target (V5.2)
   // If we made > X% today, stop trading to bag the win.
   if(profitTargetPercent > 0)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_startOfDayEquity > 0)
        {
         double profit = equity - m_startOfDayEquity;
         double profitPercent = (profit / m_startOfDayEquity) * 100.0;
         
         if(profitPercent >= profitTargetPercent)
           {
             // Print once per hour to avoid spam
             static datetime lastPrint = 0;
             if(TimeCurrent() - lastPrint > 3600)
               {
                Print("TITAN SUCCESS: Daily Profit Target Hit (", DoubleToString(profitPercent, 2), "%). Trading Paused.");
                lastPrint = TimeCurrent();
               }
             return false;
           }
        }
     }
   
   return true;
  }

//+------------------------------------------------------------------+
//| Stats Getters                                                    |
//+------------------------------------------------------------------+
double CRiskManagerV5::GetDailyDDPercent()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Check GV if simple restart happened
   if(m_startOfDayEquity == 0)
     {
      string gvName = "TITAN_X_SOD_" + (string)AccountInfoInteger(ACCOUNT_LOGIN);
      if(GlobalVariableCheck(gvName)) m_startOfDayEquity = GlobalVariableGet(gvName);
      else m_startOfDayEquity = AccountInfoDouble(ACCOUNT_BALANCE);
     }
     
   if(equity >= m_startOfDayEquity) return 0.0;
   
   return ((m_startOfDayEquity - equity) / m_startOfDayEquity) * 100.0;
  }

double CRiskManagerV5::GetTotalDDPercent()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity >= m_initialBalance) return 0.0;
   
   return ((m_initialBalance - equity) / m_initialBalance) * 100.0;
  }

//+------------------------------------------------------------------+
//| Precision Lot Sizing                                             |
//+------------------------------------------------------------------+
double CRiskManagerV5::CalculateLotSize(double slPriceDistance, double riskPerTradePercent, string symbol)
  {
   if(!CheckTradingStatus(100.0)) return 0; // Default loose check for sizing
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (riskPerTradePercent / 100.0);
   
   if(riskMoney <= 0) return 0;

   // Tick Value Calculation
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Handling valid tick value
   if(tickValue == 0 || tickSize == 0) return 0.01;
   
   // Formula: Risk = Lots * (PriceDiff / TickSize) * TickValue
   // Input 'slPriceDistance' IS the PriceDiff (e.g. 5.00)
   
   double valuePerLot = (slPriceDistance / tickSize) * tickValue;
   
   if(valuePerLot == 0) return 0;
   
   double lotSize = riskMoney / valuePerLot;
   
   // Normalize logic
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / step) * step;
   
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = minLot; // Minimum Execution
   if(lotSize > maxLot) lotSize = maxLot;
   
   // SAFETY CHECK: Verify Risk
   lotSize = CheckRiskSafety(lotSize, slPriceDistance, riskMoney, symbol);
   
   // Max Exposure Check
   double currentLots = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == symbol) currentLots += PositionGetDouble(POSITION_VOLUME);
     }
     
   if(currentLots + lotSize > m_maxExposureLots)
     {
      double allowed = m_maxExposureLots - currentLots;
      if(allowed < 0.01) // Strict check
        {
         // Print("MAX EXPOSURE HIT: Cannot open more trades. Current: ", currentLots, " | Max: ", m_maxExposureLots);
         return 0;
        }
      lotSize = MathFloor(allowed / step) * step;
     }
     
   // MARGIN CHECK (Final Safety)
   double marginRequired = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lotSize, SymbolInfoDouble(symbol, SYMBOL_ASK), marginRequired))
     {
      return 0; // Error calculating margin
     }
     
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(marginRequired > freeMargin * 0.9) // 90% usage buffer
     {
      // Reduce lot size to fit margin
      double maxMarginLots = (freeMargin * 0.9) / (marginRequired / lotSize);
      lotSize = MathFloor(maxMarginLots / step) * step;
      Print("TITAN X RISK: Margin constrained lot size to ", lotSize);
     }
   
   return lotSize;
  }

//+------------------------------------------------------------------+
//| DOUBLE CHECK RISK (Safety Net)                                   |
//+------------------------------------------------------------------+
double CRiskManagerV5::CheckRiskSafety(double proposedLots, double slDistance, double maxRiskMoney, string symbol)
  {
   // Re-Calc Risk using different formula
   double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   double projectedLoss = proposedLots * contractSize * slDistance;
   
   // Print Debug
   PrintFormat("TITAN DEBUG: Lots=%.2f, SL_Dist=%.2f, Contract=%.2f, TickVal=%.2f, TickSize=%.5f, Point=%.5f", 
               proposedLots, slDistance, contractSize, tickValue, tickSize, point);
   
   // If projected loss is significantly higher than maxRiskMoney (use 20% buffer for spread/slip)
   if(projectedLoss > maxRiskMoney * 1.2)
     {
      PrintFormat("CRITICAL RISK ERROR: Proposed %.2f lots risks $%.2f which > Max $%.2f. Clamping.", 
                  proposedLots, projectedLoss, maxRiskMoney);
      
      // Reverse Calc
      // MaxRisk = Lots * Contract * SL
      // Lots = MaxRisk / (Contract * SL)
      
      double safeLots = maxRiskMoney / (contractSize * slDistance);
      
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      safeLots = MathFloor(safeLots / step) * step;
      
      PrintFormat("SAFE LOTS RECALCULATED: %.2f", safeLots);
      return safeLots;
     }
     
   return proposedLots;
  }
