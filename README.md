# Titan X - Trend Surfer (Gold Edition) 🏆

**Repository Name Suggestion:** `Titan-X-Trend-Surfer-Gold`

## 🚀 Project Overview
**Titan X Trend Surfer** is a high-performance **Expert Advisor (EA)** developed for **MetaTrader 5 (MQL5)**. It is specifically optimized for **XAUUSD (Gold)** to capture massive trend moves while strictly protecting capital during consolidation.

This version ("Aggressive Longs Only") is the result of rigorous optimization, achieving a **Profit Factor of 2.57** and a **70% Win Rate** in backtests (Jan-Feb 2026).

## 📊 Key Performance Stats
- **Profit Factor:** 2.57
- **Net Profit:** +$8,704 (on $100k account)
- **Drawdown:** 1.46% (Ultra Low Risk)
- **Win Rate:** 70.27%
- **Strategy:** Longs Only (Trend Following)

## 🛠️ Installation
1.  **Download**: Clone this repository or download the `.mq5` and `.mqh` files.
2.  **Place Files**:
    - Move `Titan_X_HedgeFund.mq5` to `MQL5/Experts/`.
    - Move the `Include` folder contents (`SmartMoneyEngine.mqh`, `TradeOfficer.mqh`, `RiskManagerV5.mqh`) to `MQL5/Include/`.
3.  **Compile**: Open `Titan_X_HedgeFund.mq5` in MetaEditor and click **Compile**.
4.  **Run**: Attach to **XAUUSD** chart (Timeframe **M15**).

## ⚙️ Critical Settings (Do Not Change)
This version is "Hard-Locked" for safety. The following settings are enforced internally:
- **Risk Per Trade**: 0.25%
- **Trading Session**: 12:00 - 18:00 (Server Time)
- **Stop Loss**: Minimum 2.5 ATR
- **Take Profit**: Unlimited (0.0) -> Rides the trend!
- **Trailing Stop**: 3.0 ATR

## ⚠️ Disclaimer
Trading Forex and Commodities involves substantial risk. This bot is provided for educational purposes. Past performance (2.57 PF) does not guarantee future results. Always test on a Demo account first.
