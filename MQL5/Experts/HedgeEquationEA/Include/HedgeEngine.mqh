//+------------------------------------------------------------------+
//| HedgeEngine.mqh — state machine + สูตร Cover Loss Hedge          |
//| DESIGN.md §4, §6 | สูตรหนังสือบทที่ 3 | Role & Prompt §4-§5      |
//+------------------------------------------------------------------+
#ifndef HEQ_HEDGEENGINE_MQH
#define HEQ_HEDGEENGINE_MQH

#include "Config.mqh"
#include "AccountView.mqh"
#include "TrendEngine.mqh"
#include "RiskManager.mqh"
#include "TradeManager.mqh"
#include "Levels.mqh"

enum ENUM_HE_STATE { HE_FLAT, HE_RIDE, HE_COVER, HE_LOCKED, HE_CLOSING };

// pure function ของสมการ Cover Loss — แยกไว้ให้ unit test ได้ (DESIGN §2.3)
// Model 1 (SIMPLE):  |loss| / (tpPts × pvpl)
// Model 2 (TARGET): (|loss| + profitRef) / (tpPts × pvpl)
double CoverLotMath(double floatingLoss, double profitRef, int tpPts, double pvpl,
                    ENUM_COVER_MODEL model)
  {
   if(floatingLoss >= 0.0 || tpPts <= 0 || pvpl <= 0.0) return 0.0;
   double coverAmount = MathAbs(floatingLoss);
   if(model == COVER_TARGET) coverAmount += profitRef;
   return coverAmount / (tpPts * pvpl);
  }

class CHedgeEngine
  {
private:
   SConfig           m_cfg;
   CAccountView     *m_view;
   CTrendEngine     *m_trend;
   CRiskManager     *m_risk;
   CTradeManager    *m_tm;

   ENUM_HE_STATE     m_state;
   ENUM_TREND        m_rideDir;        // ทิศของ net lot ที่ควรเป็น (ฝั่งเทรนด์)
   int               m_layer;
   double            m_lastEntryPrice; // สำหรับ pyramid step
   int               m_bbHandle;       // Bollinger Band บน Entry TF (counter-trend §6.3)
   bool              m_dirty;          // มีการเปลี่ยน state/layer → main บันทึก StateStore

   void              SetState(ENUM_HE_STATE s, string reason)
     {
      if(s == m_state) return;
      PrintFormat("[HedgeEqEA] state %s → %s (%s)",
                  EnumToString(m_state), EnumToString(s), reason);
      m_state = s;
      m_dirty = true;
     }

   ENUM_ORDER_TYPE   DirToOrder(ENUM_TREND dir) const
     { return (dir == TREND_UP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; }
   ENUM_POSITION_TYPE DirToPosition(ENUM_TREND dir) const
     { return (dir == TREND_UP) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL; }

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
      m_dirty = false;
      m_bbHandle = INVALID_HANDLE;
      if(m_cfg.allowCounterTrend)
        {
         m_bbHandle = iBands(_Symbol, m_cfg.entryTF, m_cfg.bbPeriod, 0, m_cfg.bbDev, PRICE_CLOSE);
         if(m_bbHandle == INVALID_HANDLE) return false;
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_bbHandle != INVALID_HANDLE) IndicatorRelease(m_bbHandle);
     }

   ENUM_HE_STATE     State(void) const { return m_state; }
   int               Layer(void) const { return m_layer; }
   void              SetLayer(int l)   { m_layer = l; m_risk.SetLayer(l); }
   bool              ConsumeDirty(void) { bool d = m_dirty; m_dirty = false; return d; }

   //--- สูตร Lot Size Hedge (Cover Loss) — DESIGN §2.3, Role & Prompt §4B (2 โมเดล)
   double            CoverLossLot(void) const
     {
      double floatingPL = m_view.FloatingPL();          // includeCosts: swap รวมแล้วใน FloatingPL
      double pvpl = CAccountView::PointValuePerLot();
      double raw = CoverLotMath(floatingPL, m_cfg.coverProfitMoney, m_cfg.coverTPPts, pvpl,
                                m_cfg.coverModel);
      if(raw <= 0.0) return 0.0;
      double lot = m_tm.NormalizeLotUp(raw);            // ปัดขึ้น: 0.05525 → 0.06 ตามหนังสือ
      // prompt §4B: log ทุกการคำนวณ hedge lot
      PrintFormat("[HedgeEqEA] CoverLossLot model=%s loss=%.2f tpPts=%d pv/lot=%.5f raw=%.5f lot=%.2f",
                  (m_cfg.coverModel == COVER_SIMPLE ? "SIMPLE" : "TARGET"),
                  floatingPL, m_cfg.coverTPPts, pvpl, raw, lot);
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
         case HE_FLAT:    UpdateFlat();    break;
         case HE_RIDE:    UpdateRide();    break;
         case HE_COVER:   /* transient */  break;
         case HE_LOCKED:  TryUnlock();     break;
         case HE_CLOSING: UpdateClosing(); break;
        }
     }

   void              UpdateFlat(void)
     {
      ENUM_TREND dir;
      bool isSideway;
      if(!m_trend.EntrySignal(dir, isSideway)) return;
      // prompt §3: SIDEWAY → PAUSE (default) หรือ MIN_LOT
      double lot = m_cfg.baseLot;
      if(isSideway)
        {
         if(m_cfg.sidewayMode == SIDEWAY_PAUSE) return;
         lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);   // SIDEWAY_MIN_LOT
        }
      ENUM_ORDER_TYPE t = DirToOrder(dir);
      SRiskVerdict v = m_risk.CheckOpen(t, lot, false);
      if(!v.allowed) return;
      ulong deal;
      if(m_tm.OpenMarket(t, v.adjustedLot, "entry", deal))
        {
         m_rideDir = dir;
         m_lastEntryPrice = (t == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         m_view.ResetPeak();
         SetState(HE_RIDE, "entry " + EnumToString(dir) + (isSideway ? " (sideway-min-lot)" : ""));
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
            // เทคนิค 1: ไม่มี loss — ปิดฝั่งกำไร (ฝั่งเทรนด์เดิม = สวนเทรนด์ใหม่)
            // เก็บเข้า Balance แล้วให้ net สลับฝั่งตามธรรมชาติ
            m_tm.CloseSide(DirToPosition(m_rideDir));
            m_rideDir = newDir;
            m_lastEntryPrice = 0.0;
            m_dirty = true;
            if(m_view.OpenPositions() == 0) SetState(HE_FLAT, "technique-1: basket เคลียร์");
            return;
           }
         double lot = CoverLossLot();
         if(lot <= 0.0) return;
         ENUM_ORDER_TYPE t = DirToOrder(newDir);
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
            m_lastEntryPrice = (t == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            SetState(HE_RIDE, "cover filled");
           }
         else
            SetState(HE_RIDE, "cover fail — รอสัญญาณแท่งถัดไป");
         return;
        }

      // 2) Zero Hedge trigger ของ prompt §5: S/R หลักบน Middle TF แตกสวนทิศ net lot
      if(m_cfg.lockOnSRBreak && CheckSRBreak()) return;   // CheckSRBreak เรียก EnterLocked เอง

      // 3) Counter-Trend Scalping (prompt §4C, DESIGN §6.3) — default ปิด
      if(m_cfg.allowCounterTrend) ManageCounterTrend();

      // 4) เติมไม้ตามเทรนด์ (pyramid, เทคนิค 2) — lot คงที่ ไม่ใช่ martingale
      if(m_cfg.allowPyramid && m_lastEntryPrice > 0.0 &&
         m_view.OpenPositions() < m_cfg.maxPositions)
        {
         double price = (m_rideDir == TREND_UP) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double stepMoney = m_cfg.pyramidStepPts * _Point;
         bool stepReached = (m_rideDir == TREND_UP)  ? (price >= m_lastEntryPrice + stepMoney)
                                                     : (price <= m_lastEntryPrice - stepMoney);
         if(stepReached)
           {
            ENUM_ORDER_TYPE t = DirToOrder(m_rideDir);
            SRiskVerdict v = m_risk.CheckOpen(t, m_cfg.baseLot, false);
            ulong deal;
            if(v.allowed && m_tm.OpenMarket(t, v.adjustedLot, "pyramid", deal))
               m_lastEntryPrice = price;
           }
        }
     }

   //--- S/R break สวนทิศ (prompt §5): net long + ราคาหลุด swing low ⇒ ล็อค (และกลับกัน)
   bool              CheckSRBreak(void)
     {
      if(m_rideDir == TREND_UP)
        {
         double sl = LastSwingLow(m_cfg.midTF, m_cfg.swingDepth);
         if(sl > 0.0 && SymbolInfoDouble(_Symbol, SYMBOL_BID) < sl)
           { EnterLocked(StringFormat("S/R break: bid < swing low %.5f", sl)); return true; }
        }
      else if(m_rideDir == TREND_DOWN)
        {
         double sh = LastSwingHigh(m_cfg.midTF, m_cfg.swingDepth);
         if(sh > 0.0 && SymbolInfoDouble(_Symbol, SYMBOL_ASK) > sh)
           { EnterLocked(StringFormat("S/R break: ask > swing high %.5f", sh)); return true; }
        }
      return false;
     }

   //--- Counter-Trend Scalping (prompt §4C): เทรนด์แข็ง + ราคาแตะ BB ขอบตรงข้าม
   //    กติกาเหล็ก Σlot สวน ≤ Σlot ตามเทรนด์ บังคับใน RiskManager rule 9
   void              ManageCounterTrend(void)
     {
      // จัดการไม้สวนที่เปิดอยู่: ปิดเมื่อกำไรถึง counterTPPts
      ENUM_POSITION_TYPE counterSide = (m_rideDir == TREND_UP) ? POSITION_TYPE_SELL
                                                               : POSITION_TYPE_BUY;
      bool hasCounter = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magic ||
            PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(StringFind(PositionGetString(POSITION_COMMENT), "counter") < 0) continue;
         hasCounter = true;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double gainPts;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            gainPts = (entry - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / _Point;
         else
            gainPts = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - entry) / _Point;
         if(gainPts >= m_cfg.counterTPPts)
           { m_tm.ClosePosition(tk); hasCounter = false; }
        }
      if(hasCounter) return;                       // ถือทีละไม้เดียว

      // เงื่อนไขเข้า: เทรนด์แข็ง + ราคาแตะ BB ขอบตรงข้ามเทรนด์
      if(!m_trend.StrongTrend(m_rideDir)) return;
      double upper[1], lower[1];
      if(CopyBuffer(m_bbHandle, 1, 1, 1, upper) != 1 ||
         CopyBuffer(m_bbHandle, 2, 1, 1, lower) != 1) return;
      bool trigger = (m_rideDir == TREND_UP)
                     ? (SymbolInfoDouble(_Symbol, SYMBOL_BID) >= upper[0])   // ขาขึ้นชนขอบบน → SELL สวน
                     : (SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= lower[0]);  // ขาลงชนขอบล่าง → BUY สวน
      if(!trigger) return;
      ENUM_ORDER_TYPE t = (counterSide == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      SRiskVerdict v = m_risk.CheckOpen(t, m_cfg.baseLot, false, true);   // rule 9 บังคับที่นี่
      if(!v.allowed) return;
      ulong deal;
      m_tm.OpenMarket(t, v.adjustedLot, "counter", deal);
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
         if(!m_tm.OpenMarket(t, MathAbs(net), "zerohedge", deal))
           {
            PrintFormat("[HedgeEqEA] วิกฤต: เปิด zero hedge ไม่สำเร็จ (%s) — จะลองใหม่ tick ถัดไป", reason);
            return;
           }
        }
      m_layer++;                       // นับ layer เมื่อเกิด Zero Hedge (DESIGN §2.6)
      m_risk.SetLayer(m_layer);
      SetState(HE_LOCKED, reason + StringFormat(" → layer %d", m_layer));
     }

   //--- UNLOCK (เทคนิค 8 + 3): ทยอยปิดไม้ฝั่งสวนเทรนด์ใหม่ที่ขาดทุนน้อยสุด ทีละไม้/tick
   void              TryUnlock(void)
     {
      ENUM_TREND dir;
      bool isSideway;
      if(!m_trend.EntrySignal(dir, isSideway) || isSideway) return;   // ต้องการเทรนด์ชัดเท่านั้น
      if(m_view.DrawdownPct() >= m_cfg.ddWarnPct) return;             // รอพอร์ตฟื้นก่อน

      double net = m_view.NetLot();
      bool netOnTrend = (dir == TREND_UP) ? (net > 0) : (net < 0);
      if(netOnTrend)
        {
         // net อยู่ฝั่งเทรนด์แล้ว → กลับเข้าโหมดขี่เทรนด์
         m_rideDir = dir;
         m_lastEntryPrice = (dir == TREND_UP) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         SetState(HE_RIDE, "unlock → " + EnumToString(dir));
         return;
        }
      // ตรวจว่า NetLotMax รองรับการคลายหนึ่งไม้หรือไม่ แล้วปิดไม้ฝั่งสวนเทรนด์ที่เจ็บน้อยสุด
      ENUM_POSITION_TYPE closeSide = (dir == TREND_UP) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      if(!m_tm.CloseOneLeastLosing(closeSide))
        {
         // ไม่มีไม้ฝั่งนั้นแล้วแต่ net ยังไม่อยู่ฝั่งเทรนด์ → โครงสร้างผิดคาด: log ไว้
         Print("[HedgeEqEA] unlock: ไม่มีไม้ฝั่ง " + EnumToString(closeSide) + " ให้ปิด");
        }
      m_dirty = true;
      // ไม้ถัดไปปิดใน tick ถัดไป — ทยอยทีละไม้เพื่อคุมผลกระทบต่อ Equity (เทคนิค 3)
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
         m_lastEntryPrice = 0.0;
         m_view.ResetPeak();
         SetState(HE_FLAT, "รอบจบ — reset");
        }
      else
         m_tm.CloseAllOrdered(true);   // retry ไม้ที่ค้าง
     }

   //--- เรียกจากปุ่ม panel
   void              UserLock(void)     { if(m_view.OpenPositions() > 0) EnterLocked("user"); }
   void              UserCloseAll(void) { CloseAll("user"); }

   //--- กู้สถานะตอน OnInit (DESIGN §13) — เรียกหลัง StateStore.Load แล้ว
   void              RestoreState(void)
     {
      if(m_view.OpenPositions() == 0) { SetState(HE_FLAT, "restore: ว่าง"); return; }
      double net = m_view.NetLot();
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(MathAbs(net) < step / 2.0)
        {
         if(m_layer < 1) SetLayer(1);   // มีไม้สองฝั่งเท่ากัน = ผ่าน zero hedge มาอย่างน้อย 1 ชั้น
         SetState(HE_LOCKED, "restore: fully hedged");
        }
      else
        {
         m_rideDir = (net > 0) ? TREND_UP : TREND_DOWN;
         m_lastEntryPrice = 0.0;        // งด pyramid จนกว่าจะมีไม้ใหม่ (กันเติมไม้จากข้อมูลเก่า)
         SetState(HE_RIDE, "restore: net " + DoubleToString(net, 2));
        }
     }
  };

#endif // HEQ_HEDGEENGINE_MQH
