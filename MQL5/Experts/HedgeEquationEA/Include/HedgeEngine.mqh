//+------------------------------------------------------------------+
//| HedgeEngine.mqh — state machine + สูตร Cover Loss Hedge          |
//| DESIGN.md §4, §6 | สูตรหนังสือบทที่ 3                            |
//+------------------------------------------------------------------+
#ifndef HEQ_HEDGEENGINE_MQH
#define HEQ_HEDGEENGINE_MQH

#include "Config.mqh"
#include "AccountView.mqh"
#include "TrendEngine.mqh"
#include "RiskManager.mqh"
#include "TradeManager.mqh"

enum ENUM_HE_STATE { HE_FLAT, HE_RIDE, HE_COVER, HE_LOCKED, HE_CLOSING };

class CHedgeEngine
  {
private:
   SConfig           m_cfg;
   CAccountView     *m_view;
   CTrendEngine     *m_trend;
   CRiskManager     *m_risk;
   CTradeManager    *m_tm;

   ENUM_HE_STATE     m_state;
   ENUM_TREND        m_rideDir;       // ทิศของ net lot ที่ควรเป็น (ฝั่งเทรนด์)
   int               m_layer;
   double            m_lastEntryPrice; // สำหรับ pyramid step

   void              SetState(ENUM_HE_STATE s, string reason)
     {
      if(s == m_state) return;
      PrintFormat("[HedgeEqEA] state %d → %d (%s)", m_state, s, reason);
      m_state = s;
      // TODO(phase-4): เขียน StateStore + CSV log ทุก transition
     }

public:
   bool              Init(const SConfig &cfg, CAccountView &view, CTrendEngine &trend,
                          CRiskManager &risk, CTradeManager &tm)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      m_trend = GetPointer(trend);
      m_risk = GetPointer(risk);
      m_tm = GetPointer(tm);
      m_state = HE_FLAT;
      m_rideDir = TREND_SIDEWAY;
      m_layer = 0;
      m_lastEntryPrice = 0.0;
      return true;
     }

   ENUM_HE_STATE     State(void) const { return m_state; }
   int               Layer(void) const { return m_layer; }

   //--- สูตร Lot Size Hedge (Cover Loss) — DESIGN §2.3, Role & Prompt §4B (2 โมเดล)
   //    Model 1 COVER_SIMPLE : |Loss| / (TP_points × PointValuePerLot)
   //    Model 2 COVER_TARGET : (|Loss| + Profit_Reference) / (TP_points × PointValuePerLot)
   double            CoverLossLot(void) const
     {
      double floatingPL = m_view.FloatingPL();          // includeCosts: swap รวมแล้วใน FloatingPL
      if(floatingPL >= 0.0) return 0.0;                 // ไม่มี loss ต้อง cover
      double coverAmount = MathAbs(floatingPL);
      if(m_cfg.coverModel == COVER_TARGET)
         coverAmount += m_cfg.coverProfitMoney;
      double pvpl = CAccountView::PointValuePerLot();
      if(pvpl <= 0.0 || m_cfg.coverTPPts <= 0) return 0.0;
      double raw = coverAmount / (m_cfg.coverTPPts * pvpl);
      double lot = m_tm.NormalizeLotUp(raw);            // ปัดขึ้น: 0.05525 → 0.06 ตามหนังสือ
      // prompt §4B: log ทุกการคำนวณ hedge lot
      PrintFormat("[HedgeEqEA] CoverLossLot model=%s loss=%.2f cover=%.2f tpPts=%d pv/lot=%.5f raw=%.5f lot=%.2f",
                  (m_cfg.coverModel == COVER_SIMPLE ? "SIMPLE" : "TARGET"),
                  floatingPL, coverAmount, m_cfg.coverTPPts, pvpl, raw, lot);
      return lot;
     }

   //--- จุดเรียกเดียวจาก OnTick — ขับ state machine ทั้งหมด (DESIGN §4)
   void              OnTickUpdate(void)
     {
      // Guard ระดับทุก tick มาก่อนทุกอย่าง
      int guard = m_risk.TickGuards();
      if(guard == 2 && m_state != HE_CLOSING) { CloseAll("hard-cut DD"); return; }
      if(guard == 1 && m_state != HE_LOCKED && m_state != HE_CLOSING && m_view.OpenPositions() > 0)
        { EnterLocked("guard: ML%/DD"); return; }

      switch(m_state)
        {
         case HE_FLAT:    UpdateFlat();   break;
         case HE_RIDE:    UpdateRide();   break;
         case HE_COVER:   /* transient — รอ DEAL_ADD ยืนยันแล้วไป RIDE */ break;
         case HE_LOCKED:  TryUnlock();    break;
         case HE_CLOSING: UpdateClosing(); break;
        }
     }

   void              UpdateFlat(void)
     {
      ENUM_TREND dir;
      if(!m_trend.EntrySignal(dir)) return;
      ENUM_ORDER_TYPE t = (dir == TREND_UP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      SRiskVerdict v = m_risk.CheckOpen(t, m_cfg.baseLot, false);
      if(!v.allowed) return;
      ulong deal;
      if(m_tm.OpenMarket(t, v.adjustedLot, "entry", deal))
        {
         m_rideDir = dir;
         m_lastEntryPrice = (t == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         m_view.ResetPeak();
         SetState(HE_RIDE, "entry " + EnumToString(dir));
        }
     }

   void              UpdateRide(void)
     {
      // 1) เทรนด์ยืนยันกลับทิศ → Cover Loss flow (DESIGN §6.1)
      ENUM_TREND newDir;
      if(m_trend.FlipConfirmed(m_rideDir, newDir))
        {
         if(m_view.FloatingPL() >= 0.0)
           {
            // เทคนิค 1: ไม่มี loss — ปิดฝั่งกำไร (ฝั่งสวนเทรนด์ใหม่) ให้ net สลับเอง
            // TODO(phase-3): ปิดเฉพาะไม้ฝั่ง m_rideDir แล้วประเมิน net ใหม่
            m_rideDir = newDir;
            return;
           }
         double lot = CoverLossLot();
         ENUM_ORDER_TYPE t = (newDir == TREND_UP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         SRiskVerdict v = m_risk.CheckOpen(t, lot, false);
         if(!v.allowed)
           {
            // แก้ไม้ไม่ได้ตามสูตร → ล็อคพอร์ตแทน (เทคนิค 6)
            EnterLocked("cover veto: " + v.reason);
            return;
           }
         SetState(HE_COVER, StringFormat("cover lot=%.2f dir=%s", v.adjustedLot, EnumToString(newDir)));
         ulong deal;
         if(m_tm.OpenMarket(t, v.adjustedLot, "cover", deal))
           {
            m_rideDir = newDir;
            SetState(HE_RIDE, "cover filled");
           }
         else
            SetState(HE_RIDE, "cover fail — คงสถานะเดิม");   // จะ re-trigger จาก FlipConfirmed แท่งถัดไป
         return;
        }

      // 2) Zero Hedge trigger เพิ่มเติมของ prompt §5: S/R หลักบน Middle TF แตกสวนทิศ net lot
      // TODO(phase-3): if(m_cfg.lockOnSRBreak && SRBreakAgainst(m_rideDir)) EnterLocked("S/R break");

      // 3) Counter-Trend Scalping (prompt §4C, DESIGN §6.3) — default ปิด
      // TODO(phase-4): เทรนด์แข็ง (strongTrendBars) + ราคาแตะ BB(bbPeriod,bbDev) ขอบตรงข้าม
      //                หรือ swing S/R (swingDepth) → เปิดไม้สวนโดย RiskManager บังคับ
      //                Σlot สวน ≤ Σlot ตามเทรนด์ (กติกาเหล็ก) — ปิดที่ counterTPPts

      // 4) เติมไม้ตามเทรนด์ (pyramid, เทคนิค 2) — lot คงที่ ไม่ใช่ martingale
      if(m_cfg.allowPyramid && m_view.OpenPositions() < m_cfg.maxPositions)
        {
         double price = (m_rideDir == TREND_UP) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double stepMoney = m_cfg.pyramidStepPts * _Point;
         bool stepReached = (m_rideDir == TREND_UP)  ? (price >= m_lastEntryPrice + stepMoney)
                                                     : (price <= m_lastEntryPrice - stepMoney);
         if(stepReached)
           {
            ENUM_ORDER_TYPE t = (m_rideDir == TREND_UP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            SRiskVerdict v = m_risk.CheckOpen(t, m_cfg.baseLot, false);
            ulong deal;
            if(v.allowed && m_tm.OpenMarket(t, v.adjustedLot, "pyramid", deal))
               m_lastEntryPrice = price;
           }
        }
     }

   //--- Zero Hedge Margin: เปิดไม้ตรงข้าม |net| ให้ net=0 (เทคนิค 6, DESIGN §9)
   void              EnterLocked(string reason)
     {
      double net = m_view.NetLot();
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(MathAbs(net) >= step / 2.0)
        {
         ENUM_ORDER_TYPE t = (net > 0) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         ulong deal;
         // isZeroHedgeEntry=true: ต้องทำได้ทุกสถานการณ์ ข้าม guard ข่าว/spread
         SRiskVerdict v = m_risk.CheckOpen(t, MathAbs(net), true);
         if(!m_tm.OpenMarket(t, MathAbs(net), "zerohedge", deal))
           {
            PrintFormat("[HedgeEqEA] วิกฤต: เปิด zero hedge ไม่สำเร็จ (%s)", reason);
            // TODO(phase-5): push notification ทันที
            return;
           }
        }
      m_layer++;                       // นับ layer เมื่อเกิด Zero Hedge (DESIGN §2.6)
      m_risk.SetLayer(m_layer);
      SetState(HE_LOCKED, reason + StringFormat(" → layer %d", m_layer));
     }

   //--- UNLOCK (เทคนิค 8 + เทคนิค 3): ปิดไม้สวนเทรนด์ที่ขาดทุนน้อยสุดก่อน
   void              TryUnlock(void)
     {
      // เงื่อนไข: เทรนด์ชัด + ML% ฟื้น (net=0 → ML=∞ เสมอ ดังนั้นดูเทรนด์กับ DD เป็นหลัก)
      ENUM_TREND dir;
      if(!m_trend.EntrySignal(dir)) return;
      if(m_view.DrawdownPct() >= m_cfg.ddWarnPct) return;
      // TODO(phase-4): ทยอยปิดไม้ฝั่งสวน dir ที่ขาดทุนน้อยสุดทีละไม้ จน net อยู่ฝั่ง dir
      //               ภายในกรอบ NetLotMax แล้ว SetState(HE_RIDE)
     }

   void              CloseAll(string reason)
     {
      SetState(HE_CLOSING, reason);
      m_tm.CloseAllOrdered(true);      // ไม้กำไรมากก่อน (DESIGN §4)
     }

   void              UpdateClosing(void)
     {
      if(m_view.OpenPositions() == 0)
        {
         m_layer = 0;
         m_risk.SetLayer(0);
         m_rideDir = TREND_SIDEWAY;
         m_view.ResetPeak();
         SetState(HE_FLAT, "รอบจบ — reset");
         // TODO(phase-5): บันทึกสถิติรอบลง CSV
        }
      else
         m_tm.CloseAllOrdered(true);   // retry ไม้ที่ค้าง
     }

   //--- เรียกจากปุ่ม panel
   void              UserLock(void)     { if(m_view.OpenPositions() > 0) EnterLocked("user"); }
   void              UserCloseAll(void) { CloseAll("user"); }

   //--- กู้สถานะตอน OnInit (DESIGN §13)
   void              RestoreState(void)
     {
      if(m_view.OpenPositions() == 0) { SetState(HE_FLAT, "restore: ว่าง"); return; }
      double net = m_view.NetLot();
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(MathAbs(net) < step / 2.0)
        {
         m_layer = MathMax(m_layer, 1);   // TODO(phase-4): อ่าน layer จริงจาก state file
         m_risk.SetLayer(m_layer);
         SetState(HE_LOCKED, "restore: fully hedged");
        }
      else
        {
         m_rideDir = (net > 0) ? TREND_UP : TREND_DOWN;
         SetState(HE_RIDE, "restore: net " + DoubleToString(net, 2));
        }
     }
  };

#endif // HEQ_HEDGEENGINE_MQH
