//+------------------------------------------------------------------+
//| AccountView.mqh — มุมมองบัญชี "เฉพาะส่วนของ EA"                  |
//| implement สมการหลักของหนังสือ: ML% = Equity/Margin×100 (DESIGN §2)|
//+------------------------------------------------------------------+
#ifndef HEQ_ACCOUNTVIEW_MQH
#define HEQ_ACCOUNTVIEW_MQH

#include "Config.mqh"

// ระดับความปลอดภัย ML% ตาม Role & Prompt §2
// (ช่วง 1000–2000 ที่ prompt เว้นไว้ นิยามเป็น ELEVATED — DESIGN §2.1)
enum ENUM_ML_SAFETY
  {
   ML_CRITICAL,    // < 1,000%
   ML_ELEVATED,    // 1,000 – 2,000%
   ML_MODERATE,    // 2,000 – 3,000%
   ML_SAFE,        // 3,000 – 10,000%
   ML_VERY_SAFE    // ≥ 10,000% (รวมกรณี net=0 → ML=∞)
  };

class CAccountView
  {
private:
   SConfig           m_cfg;
   double            m_closedPL;      // กำไร/ขาดทุนปิดแล้วสะสมของ EA (โหมด VIRTUAL, กู้จาก state file)
   double            m_peakEquity;    // สำหรับ DD% — track สูงสุดตั้งแต่เริ่มรอบ

   // วนทุก position ของ EA (magic+symbol) — จุดกรองเดียวของทั้งระบบ
   bool              IsOurs(void) const
     {
      return (PositionGetInteger(POSITION_MAGIC) == m_cfg.magic &&
              PositionGetString(POSITION_SYMBOL) == _Symbol);
     }

public:
   bool              Init(const SConfig &cfg)
     {
      m_cfg = cfg;
      m_closedPL = 0.0;
      m_peakEquity = InitialCapital();
      return true;
     }

   double            InitialCapital(void) const
     {
      return (m_cfg.scope == SCOPE_VIRTUAL) ? m_cfg.allocatedCapital
                                            : AccountInfoDouble(ACCOUNT_BALANCE); // TODO(phase-4): เก็บทุนแรกเริ่มจริงลง StateStore
     }

   void              AddClosedPL(double v) { m_closedPL += v; }   // เรียกจาก OnTradeTransaction (deal out)
   void              SetClosedPL(double v) { m_closedPL = v; }    // ใช้ตอน restore
   double            ClosedPL(void) const  { return m_closedPL; }

   double            FloatingPL(void) const
     {
      double pl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetTicket(i) == 0 || !IsOurs()) continue;
         pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         // commission ต่อ position: MT5 บันทึกที่ deal — รวมผ่าน HistorySelectByPosition
         // TODO(phase-1): cache commission ตอน DEAL_ADD แทนการ query ทุก tick
        }
      return pl;
     }

   double            BalanceEA(void) const
     {
      return (m_cfg.scope == SCOPE_VIRTUAL) ? InitialCapital() + m_closedPL
                                            : AccountInfoDouble(ACCOUNT_BALANCE);
     }

   double            EquityEA(void) const
     {
      return (m_cfg.scope == SCOPE_VIRTUAL) ? BalanceEA() + FloatingPL()
                                            : AccountInfoDouble(ACCOUNT_EQUITY);
     }

   // net lot = ΣBuy − ΣSell (สามเหลี่ยมความปลอดภัยเฮดจ์ ด้านที่ 1)
   double            NetLot(void) const
     {
      double buy = 0.0, sell = 0.0;
      SumLots(buy, sell);
      return buy - sell;
     }

   void              SumLots(double &buy, double &sell) const
     {
      buy = 0.0; sell = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetTicket(i) == 0 || !IsOurs()) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            buy += PositionGetDouble(POSITION_VOLUME);
         else
            sell += PositionGetDouble(POSITION_VOLUME);
        }
     }

   int               OpenPositions(void) const
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetTicket(i) != 0 && IsOurs()) n++;
      return n;
     }

   // margin ของ EA = margin ของ |net lot| (โบรกส่วนใหญ่คิดเฉพาะส่วนต่าง — DESIGN §2.1)
   double            MarginEA(void) const
     {
      double net = MathAbs(NetLot());
      if(net < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) / 2.0) return 0.0;
      double margin = 0.0;
      ENUM_ORDER_TYPE t = (NetLot() > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double price = (t == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!OrderCalcMargin(t, _Symbol, net, price, margin)) return 0.0;
      // TODO(phase-1): บวก SYMBOL_MARGIN_HEDGED ของฝั่งที่คานกัน เมื่อโบรกคิดไม่เป็น 0
      return margin;
     }

   // ML% — คืน DBL_MAX เมื่อ margin==0 (Fully Hedge): "ไม่แสดงค่า" ตามหนังสือ ห้ามตีความว่าวิกฤต
   double            MarginLevelEA(void) const
     {
      double m = MarginEA();
      if(m <= 0.0) return DBL_MAX;
      return EquityEA() / m * 100.0;
     }

   ENUM_ML_SAFETY    MLSafetyState(void) const
     {
      double ml = MarginLevelEA();
      if(ml >= 10000.0) return ML_VERY_SAFE;   // รวม DBL_MAX (net=0)
      if(ml >= 3000.0)  return ML_SAFE;
      if(ml >= 2000.0)  return ML_MODERATE;
      if(ml >= 1000.0)  return ML_ELEVATED;
      return ML_CRITICAL;
     }

   // สูตรหลักตาม Role & Prompt §2: DD% = |Floating P/L| / Balance × 100 (เฉพาะเมื่อติดลบ)
   double            DrawdownPct(void)
     {
      double eq = EquityEA();
      if(eq > m_peakEquity) m_peakEquity = eq;   // track peak ไว้สำหรับสถิติ
      double fpl = FloatingPL();
      double bal = BalanceEA();
      if(fpl >= 0.0 || bal <= 0.0) return 0.0;
      return MathAbs(fpl) / bal * 100.0;
     }

   // สูตรเสริม (สถิติรายงานเท่านั้น — ไม่ใช้เป็น trigger): peak-equity drawdown
   double            PeakDrawdownPct(void) const
     {
      if(m_peakEquity <= 0.0) return 0.0;
      return (m_peakEquity - EquityEA()) / m_peakEquity * 100.0;
     }

   double            PeakEquity(void) const { return m_peakEquity; }
   void              ResetPeak(void)        { m_peakEquity = EquityEA(); }
   void              SetPeak(double v)      { m_peakEquity = v; }   // ใช้ตอน restore

   // มูลค่าเงินต่อ 1 จุด ต่อ 1 lot — ใช้ในสูตร Cover Loss (DESIGN §2.3)
   static double     PointValuePerLot(void)
     {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0) return 0.0;
      return tickValue * (_Point / tickSize);
     }
  };

#endif // HEQ_ACCOUNTVIEW_MQH
