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
#include "NewsFilter.mqh"
#include "Logger.mqh"

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
   CNewsFilter      *m_news;
   CLogger          *m_log;

   ENUM_HE_STATE     m_state;
   ENUM_TREND        m_rideDir;        // ทิศของ net lot ที่ควรเป็น (ฝั่งเทรนด์)
   int               m_layer;
   double            m_lastEntryPrice; // สำหรับ pyramid step
   bool              m_pyramidOK;      // false เมื่อรอบเข้าแบบ SIDEWAY_MIN_LOT (ห้ามเติมไม้)
   double            m_cycleStartBal;  // BalanceEA ณ ต้นรอบ — baseline ของ EquityTP
   bool              m_hadCover;       // รอบนี้เคย cover/lock แล้ว (recovery mode)
   int               m_bbHandle;       // Bollinger Band บน Entry TF (counter-trend §6.3)
   bool              m_dirty;          // มีการเปลี่ยน state/layer → main บันทึก StateStore
   bool              m_paused;         // ปุ่ม PAUSE บน panel: งดเปิดรอบใหม่
   int               m_lockedCount;    // จำนวนครั้งเข้า LOCKED (สถิติสำหรับ OnTester)
   // cache swing S/R — คำนวณใหม่เฉพาะเมื่อแท่ง Middle TF ใหม่ (ประหยัด CPU ใน real-tick test)
   datetime          m_srBarTime;
   double            m_srSwingLow, m_srSwingHigh;

   void              SetState(ENUM_HE_STATE s, string reason)
     {
      if(s == m_state) return;
      string tr = EnumToString(m_state) + "→" + EnumToString(s);
      m_state = s;
      m_dirty = true;
      m_log.Event("state", tr, m_layer, 0, 0, reason);
      if(s == HE_LOCKED)
        {
         m_lockedCount++;
         m_log.Push(StringFormat("LOCKED (layer %d): %s | DD %.1f%%",
                                 m_layer, reason, m_view.DrawdownPct()));
        }
     }

   ENUM_ORDER_TYPE   DirToOrder(ENUM_TREND dir) const
     { return (dir == TREND_UP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; }
   ENUM_POSITION_TYPE DirToPosition(ENUM_TREND dir) const
     { return (dir == TREND_UP) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL; }

public:
   bool              Init(const SConfig &cfg, CAccountView &view, CTrendEngine &trend,
                          CRiskManager &risk, CTradeManager &tm, CNewsFilter &news,
                          CLogger &log)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      m_trend = GetPointer(trend);
      m_risk = GetPointer(risk);
      m_tm = GetPointer(tm);
      m_news = GetPointer(news);
      m_log = GetPointer(log);
      m_paused = false;
      m_lockedCount = 0;
      m_state = HE_FLAT;
      m_rideDir = TREND_SIDEWAY;
      m_layer = 0;
      m_lastEntryPrice = 0.0;
      m_pyramidOK = true;
      m_cycleStartBal = 0.0;
      m_hadCover = false;
      m_dirty = false;
      m_srBarTime = 0;
      m_srSwingLow = 0.0;
      m_srSwingHigh = 0.0;
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
   double            CycleStartBalance(void) const { return m_cycleStartBal; }
   bool              InRecovery(void) const        { return m_hadCover; }
   void              SetCycleInfo(double startBal, bool hadCover)   // ใช้ตอน restore
     { m_cycleStartBal = startBal; m_hadCover = hadCover; }
   int               LockedCount(void) const { return m_lockedCount; }
   void              SetPaused(bool p)       { m_paused = p; }

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
      if(m_paused) return;              // ปุ่ม PAUSE: งดเปิดรอบใหม่ (รอบค้างยังถูกบริหารปกติ)
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
      SRiskVerdict v = m_risk.CheckOpen(t, lot, OPEN_ENTRY);
      if(!v.allowed) return;
      ulong deal;
      if(m_tm.OpenMarket(t, v.adjustedLot, "entry", deal))
        {
         m_rideDir = dir;
         m_lastEntryPrice = (t == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         m_pyramidOK = !isSideway;               // โหมด sideway-min-lot: ห้ามเติมไม้ (Config §SIDEWAY_MIN_LOT)
         m_cycleStartBal = m_view.BalanceEA();   // baseline ของ EquityTP รอบนี้
         m_hadCover = false;
         m_view.ResetPeak();
         SetState(HE_RIDE, "entry " + EnumToString(dir) + (isSideway ? " (sideway-min-lot)" : ""));
        }
     }

   void              UpdateRide(void)
     {
      // 0) ล็อคเชิงป้องกันตามเวลา (ปิดความเสี่ยง RISK S2) — ไม่นับ layer
      //    (layer สงวนไว้นับการล็อคจากวิกฤตจริงตามนิยามหนังสือ §2.6)
      if(m_news.FridayWantsLock()) { EnterLocked("weekend lock (Friday cutoff)", false); return; }
      if(m_news.NewsWantsLock())   { EnterLocked("news lock (high impact)", false);      return; }

      // 1) เทรนด์ยืนยันกลับทิศ → Cover Loss flow (DESIGN §6.1)
      ENUM_TREND newDir;
      if(m_trend.FlipConfirmed(m_rideDir, newDir))
        {
         if(m_view.FloatingPL() >= 0.0)
           {
            // เทคนิค 1: ไม่มี loss — ปิดฝั่งกำไร (ฝั่งเทรนด์เดิม = สวนเทรนด์ใหม่)
            // เก็บเข้า Balance แล้วให้ net สลับฝั่งตามธรรมชาติ
            if(!m_tm.CloseSide(DirToPosition(m_rideDir)))
              {
               // ปิดไม่ครบ — ห้าม flip ทิศทั้งที่ net ยังอยู่ฝั่งเดิม
               // (สัญญาณ flip จะ re-fire แท่ง Middle ถัดไปเพราะตัวนับไม่ถูก reset)
               Print("[HedgeEqEA] technique-1: CloseSide ไม่สำเร็จ — retry แท่งถัดไป");
               return;
              }
            m_rideDir = newDir;
            m_lastEntryPrice = 0.0;
            m_dirty = true;
            if(m_view.OpenPositions() == 0) SetState(HE_FLAT, "technique-1: basket เคลียร์");
            return;
           }
         double lot = CoverLossLot();
         if(lot <= 0.0) return;
         ENUM_ORDER_TYPE t = DirToOrder(newDir);
         SRiskVerdict v = m_risk.CheckOpen(t, lot, OPEN_COVER);
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
            m_pyramidOK = true;
            m_hadCover = true;         // เข้า recovery mode → EquityTP กติกา 2 ทำงาน
            SetState(HE_RIDE, "cover filled");
           }
         else
            SetState(HE_RIDE, "cover fail — สัญญาณ re-fire แท่ง Middle ถัดไป");
         return;
        }

      // 2) Zero Hedge trigger ของ prompt §5: S/R หลักบน Middle TF แตกสวนทิศ net lot
      if(m_cfg.lockOnSRBreak && CheckSRBreak()) return;   // CheckSRBreak เรียก EnterLocked เอง

      // 3) Counter-Trend Scalping (prompt §4C, DESIGN §6.3) — default ปิด
      if(m_cfg.allowCounterTrend) ManageCounterTrend();

      // 4) เติมไม้ตามเทรนด์ (pyramid, เทคนิค 2) — lot คงที่ ไม่ใช่ martingale
      //    m_pyramidOK=false เมื่อรอบเข้าแบบ sideway-min-lot (ห้ามสะสม lot ใน sideway)
      if(m_cfg.allowPyramid && m_pyramidOK && m_lastEntryPrice > 0.0 &&
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
            SRiskVerdict v = m_risk.CheckOpen(t, m_cfg.baseLot, OPEN_PYRAMID);
            ulong deal;
            if(v.allowed && m_tm.OpenMarket(t, v.adjustedLot, "pyramid", deal))
               m_lastEntryPrice = price;
           }
        }
     }

   //--- S/R break สวนทิศ (prompt §5): net long + ราคาหลุด swing low ⇒ ล็อค (และกลับกัน)
   //    swing level คำนวณใหม่เฉพาะแท่ง Middle TF ใหม่ (cache) — ต่อ tick เทียบค่า cache เท่านั้น
   bool              CheckSRBreak(void)
     {
      datetime bt = iTime(_Symbol, m_cfg.midTF, 0);
      if(bt != m_srBarTime)
        {
         m_srBarTime = bt;
         m_srSwingLow  = LastSwingLow(m_cfg.midTF, m_cfg.swingDepth);
         m_srSwingHigh = LastSwingHigh(m_cfg.midTF, m_cfg.swingDepth);
        }
      if(m_rideDir == TREND_UP)
        {
         if(m_srSwingLow > 0.0 && SymbolInfoDouble(_Symbol, SYMBOL_BID) < m_srSwingLow)
           { EnterLocked(StringFormat("S/R break: bid < swing low %.5f", m_srSwingLow)); return true; }
        }
      else if(m_rideDir == TREND_DOWN)
        {
         if(m_srSwingHigh > 0.0 && SymbolInfoDouble(_Symbol, SYMBOL_ASK) > m_srSwingHigh)
           { EnterLocked(StringFormat("S/R break: ask > swing high %.5f", m_srSwingHigh)); return true; }
        }
      return false;
     }

   //--- Counter-Trend Scalping (prompt §4C): เทรนด์แข็ง + ราคาแตะ BB ขอบตรงข้าม
   //    กติกาเหล็ก Σlot สวน ≤ Σlot ตามเทรนด์ บังคับใน RiskManager rule 9
   void              ManageCounterTrend(void)
     {
      // จัดการไม้สวนที่เปิดอยู่: ปิดเมื่อกำไรถึง counterTPPts
      // active counter = comment มี "counter" และ "อยู่ฝั่งสวนเทรนด์ปัจจุบัน" เท่านั้น —
      // ไม้ counter เก่าที่กลายเป็นฝั่งเทรนด์หลัง flip ถือเป็นสมาชิก basket ปกติ
      // (ข้อจำกัดที่รู้: โบรกบางเจ้าเขียน comment ทับ — DESIGN §12)
      ENUM_POSITION_TYPE counterSide = (m_rideDir == TREND_UP) ? POSITION_TYPE_SELL
                                                               : POSITION_TYPE_BUY;
      bool hasCounter = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magic ||
            PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != counterSide) continue;
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
      SRiskVerdict v = m_risk.CheckOpen(t, m_cfg.baseLot, OPEN_COUNTER);   // rule 9 บังคับที่นี่
      if(!v.allowed) return;
      ulong deal;
      m_tm.OpenMarket(t, v.adjustedLot, "counter", deal);
     }

   //--- Zero Hedge Margin: เปิดไม้ตรงข้าม |net| ให้ net=0 (เทคนิค 6, DESIGN §9)
   //    countLayer=false สำหรับล็อคเชิงป้องกันตามเวลา (weekend/news) — ไม่ใช่วิกฤตจริง
   void              EnterLocked(string reason, bool countLayer = true)
     {
      double net = m_view.NetLot();
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(MathAbs(net) >= step / 2.0)
        {
         ENUM_ORDER_TYPE t = (net > 0) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         ulong deal;
         if(!m_tm.OpenMarket(t, MathAbs(net), "zerohedge", deal))
           {
            m_log.Event("zerohedge-fail", EnumToString(m_state), m_layer, MathAbs(net), 0, reason);
            m_log.Push("วิกฤต: เปิด zero hedge ไม่สำเร็จ — retry tick ถัดไป (" + reason + ")");
            return;
           }
        }
      if(countLayer)
        {
         m_layer++;                    // นับ layer เมื่อเกิด Zero Hedge จากวิกฤต (DESIGN §2.6)
         m_risk.SetLayer(m_layer);
        }
      SetState(HE_LOCKED, reason + StringFormat(" → layer %d", m_layer));
     }

   //--- UNLOCK (เทคนิค 8 + 3): ทยอยปิดไม้ฝั่งสวนเทรนด์ใหม่ที่ขาดทุนน้อยสุด ทีละไม้/tick
   void              TryUnlock(void)
     {
      // ห้ามคลายระหว่างเหตุที่ทำให้ล็อคยังอยู่ (กัน lock/unlock วนใน tick เดียวกัน)
      if(m_news.FridayWantsLock() || m_news.NewsWantsLock()) return;
      // ใช้ AlignedTrend (ไม่ต้อง "สด") — พอร์ตที่ล็อคระหว่างเทรนด์ยาวต้องคลายได้
      // แม้การจัดเรียง MA เกิดมานานแล้ว (เงื่อนไข fresh ใช้เฉพาะการเข้ารอบใหม่)
      ENUM_TREND dir;
      if(!m_trend.AlignedTrend(dir)) return;
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
      m_tm.CloseAllProfitFirst();      // ไม้กำไรมากก่อน (DESIGN §4)
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
         m_tm.CloseAllProfitFirst();   // retry ไม้ที่ค้าง
     }

   //--- เรียกจากปุ่ม panel
   void              UserLock(void)     { if(m_view.OpenPositions() > 0) EnterLocked("user"); }
   void              UserCloseAll(void) { CloseAll("user"); }

   //--- กู้สถานะตอน OnInit (DESIGN §13) — เรียกหลัง StateStore.Load แล้ว
   void              RestoreState(void)
     {
      if(m_view.OpenPositions() == 0) { SetState(HE_FLAT, "restore: ว่าง"); return; }
      // fallback เมื่อไม่มี state file: baseline = ทุนแรกเริ่ม, layer>0 ถือเป็น recovery
      if(m_cycleStartBal <= 0.0) m_cycleStartBal = m_view.InitialCapital();
      if(m_layer > 0) m_hadCover = true;
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
