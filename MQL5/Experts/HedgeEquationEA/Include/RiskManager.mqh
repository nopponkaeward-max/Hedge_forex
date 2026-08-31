//+------------------------------------------------------------------+
//| RiskManager.mqh — การ์ด 8 ข้อก่อนเปิดทุกออเดอร์ (DESIGN §7)      |
//+------------------------------------------------------------------+
#ifndef HEQ_RISKMANAGER_MQH
#define HEQ_RISKMANAGER_MQH

#include "Config.mqh"
#include "AccountView.mqh"

struct SRiskVerdict
  {
   bool              allowed;
   double            adjustedLot;   // lot หลังถูกลดขนาด (อาจต่ำกว่าที่ขอ)
   int               ruleHit;       // 0 = ผ่านหมด
   string            reason;
  };

class CRiskManager
  {
private:
   SConfig           m_cfg;
   CAccountView     *m_view;
   int               m_layer;       // ตัวนับ layer ปัจจุบัน — HedgeEngine เป็นผู้ increment

public:
   bool              Init(const SConfig &cfg, CAccountView &view)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      m_layer = 0;
      return true;
     }

   void              SetLayer(int l) { m_layer = l; }
   int               Layer(void) const { return m_layer; }

   // เพดาน net lot จาก ML% เป้าหมาย (สมการหนังสือ กรณี D — DESIGN §2.2)
   // NetLotMax = (Equity × 100 / ML_target) / MarginPerLot
   double            NetLotMax(void) const
     {
      double marginPerLot = 0.0;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, ask, marginPerLot) || marginPerLot <= 0.0)
         return 0.0;
      double budget = m_view.EquityEA() * 100.0 / m_cfg.mlTargetPct;
      return budget / marginPerLot;
     }

   SRiskVerdict      CheckOpen(ENUM_ORDER_TYPE type, double lot, bool isZeroHedgeEntry,
                               bool isCounterTrend = false)
     {
      SRiskVerdict v;
      v.allowed = true; v.adjustedLot = lot; v.ruleHit = 0; v.reason = "";

      // ข้อยกเว้นสำคัญ: การเข้า Zero Hedge (LOCKED) ต้องทำได้ทุกสถานการณ์ (DESIGN §7)
      if(isZeroHedgeEntry) return v;

      // 9. กติกาเหล็กของ prompt §4C: Σlot สวนเทรนด์ (รวมไม้ใหม่) ≤ Σlot ฝั่งตามเทรนด์
      if(isCounterTrend)
        {
         double buy, sell;
         m_view.SumLots(buy, sell);
         double trendSide   = (type == ORDER_TYPE_BUY) ? sell : buy;  // ไม้สวน = ตรงข้ามฝั่งเทรนด์
         double counterSide = (type == ORDER_TYPE_BUY) ? buy  : sell;
         if(counterSide + lot > trendSide)
           { v.allowed = false; v.ruleHit = 9;
             v.reason = StringFormat("counter %.2f+%.2f > trend %.2f", counterSide, lot, trendSide); return v; }
        }

      // 1. spread
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > m_cfg.maxSpreadPts)
        { v.allowed = false; v.ruleHit = 1; v.reason = StringFormat("spread %d > %d", spread, m_cfg.maxSpreadPts); return v; }

      // 2-3. rollover / news — TODO(phase-4): เรียก NewsFilter/SessionFilter

      // 4. layer cap (เกณฑ์หนังสือ 1–2 ชั้น)
      if(m_layer >= m_cfg.maxLayers)
        { v.allowed = false; v.ruleHit = 4; v.reason = StringFormat("layer %d ชนเพดาน %d", m_layer, m_cfg.maxLayers); return v; }

      // 5. DD warn — ห้ามเพิ่ม |net lot| เมื่อ DD เกินเส้นเตือน
      double dd = m_view.DrawdownPct();
      double net = m_view.NetLot();
      double signedLot = (type == ORDER_TYPE_BUY) ? lot : -lot;
      bool increasesRisk = MathAbs(net + signedLot) > MathAbs(net);
      if(dd >= m_cfg.ddWarnPct && increasesRisk)
        { v.allowed = false; v.ruleHit = 5; v.reason = StringFormat("DD %.1f%% ≥ warn %.1f%%", dd, m_cfg.ddWarnPct); return v; }

      // 6. NetLotMax — ลดขนาด lot ลงจนผ่าน
      double netMax = NetLotMax();
      double netAfter = MathAbs(net + signedLot);
      if(netAfter > netMax)
        {
         double allowedLot = netMax - MathAbs(net) + ((increasesRisk) ? 0.0 : lot);
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(allowedLot < vmin)
           { v.allowed = false; v.ruleHit = 6; v.reason = StringFormat("net %.2f จะเกิน NetLotMax %.2f", netAfter, netMax); return v; }
         v.adjustedLot = allowedLot;   // caller ต้อง NormalizeLot "ลง" ในกรณีลดขนาด
         v.reason = StringFormat("ลด lot %.2f→%.2f ตาม NetLotMax", lot, allowedLot);
        }

      // 7. simulate ML% หลังเปิด ≥ MLFloor
      // TODO(phase-3): คำนวณ margin หลังเปิดด้วย OrderCalcMargin(net+signedLot) แล้วเทียบ mlFloorPct

      // 8. free margin จริง
      double needMargin = 0.0;
      double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(OrderCalcMargin(type, _Symbol, v.adjustedLot, price, needMargin))
         if(needMargin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
           { v.allowed = false; v.ruleHit = 8; v.reason = "free margin ไม่พอ"; return v; }

      return v;
     }

   // Guard ระดับทุก tick (DESIGN §7 ท้าย) — คืนคำสั่งที่ HedgeEngine ต้องทำทันที
   // 0 = ปกติ, 1 = เข้า LOCKED, 2 = HARD CUT (ปิดทั้งพอร์ต)
   int               TickGuards(void)
     {
      double dd = m_view.DrawdownPct();
      if(m_cfg.hardCutPct > 0.0 && dd >= m_cfg.hardCutPct) return 2;
      double ml = m_view.MarginLevelEA();
      if(ml != DBL_MAX && ml < m_cfg.mlLockPct) return 1;
      if(dd >= m_cfg.ddLockPct) return 1;
      return 0;
     }
  };

#endif // HEQ_RISKMANAGER_MQH
