# 🧠 Technical Specifications & Strategy Logic

## 1. Core Philosophy: "The Trend Surfer"
The strategy is built on a simple premise: **Gold trends hard.** Instead of fighting reversals, this bot waits for a confirmed trend and "surfs" it using a loose trailing stop.

**Mode:** Aggressive Longs Only
**Logic:** Breakout / Pullback Confirmation

---

## 2. The Engine: SmartMoneyEngine.mqh
This component is the brain. It decides **IF** a trade can be taken.

### A. Trend Filter (The "Hard Lock")
- **Indicator**: H1 200 EMA (Exponential Moving Average).
- **Rule**:
    - **BUY**: Price MUST be > H1 200 EMA.
    - **SELL**: **BLOCKED**. (Hard-coded to return `SMC_NONE`).
    - *Why?* Statistical analysis showed Shorts were dragging down the win rate. We only trade with the primary BullTrend.

### B. Volatility Gatekeeper
- **Indicator**: ATR (Average True Range) 14.
- **Rule**: Current ATR must be > 80% of the 20-period Average ATR.
- *Why?* We avoid "dead" markets where price goes nowhere.

### C. Entry Signal
- **Setup**: M15 Pullback to the 20 EMA zone.
- **Trigger**: Price touches dynamic pullback zone while Trend is valid.

---

## 3. The Manager: TradeOfficer.mqh
This component manages the open positions.

### A. Risk Management
- **Stop Loss (SL)**: Dynamic, based on **2.5 ATR**.
    - *Constraint*: Hard-coded minimum. If calculated SL < 2.5 ATR, it forces 2.5 ATR.
- **Take Profit (TP)**: **0.0 (Unlimited)**.
    - *Why?* Fixed TPs cap our winners. We want to catch the "Home Run" trades ($1000+).

### B. "Fix & Scale" Execution
- **Step 1: Scale Out**:
    - Trigger: Profit reaches **1R** (1 Risk Unit).
    - Action: Close **50%** of the position.
    - Action: Move Stop Loss to **Breakeven**.
- **Step 2: The "Surfer" Trail**:
    - Trigger: Activates *after* the Scale Out.
    - Distance: **3.0 ATR**.
    - *Why?* A wide trail allows the price to fluctuate without stopping us out, letting us ride the major moves.

---

## 4. The Controller: Titan_X_HedgeFund.mq5
The main inputs and session controls.

- **Risk Per Trade**: Fixed at **0.25%**.
    - *Result*: Ultra-low drawdown (1.46%).
- **Trading Session**: **12:00 - 18:00** Server Time.
    - *Why?* Avoids Asian session chop and late US session reversals.
- **Daily Limit**: Max **2 trades per day**.
    - *Why?* Prevents over-trading / revenge trading.

---

## 5. Summary of "Winning Formula"
`High Win Rate (70%)` + `Unlimited Upside (No TP)` + `Safe Risk (0.25%)` = **Profit Factor 2.57**.
