//+------------------------------------------------------------------+
//| HedgeEquationEA.mq5                                              |
//| EA ตามระบบ "สมการเฮดจ์" — Cover Loss Hedge + Follow Trend        |
//| + Margin Level % guard + Equity Take Profit                      |
//| อ้างอิงหนังสือ: เทคนิค Forex แก้พอร์ต Hedge ให้ได้กำไรด้วย        |
//| สมการ Hedge (สกี เกิดนิยม, ISBN 978-616-588-579-9)               |
//| เอกสารออกแบบ: Docs/DESIGN.md                                     |
//+------------------------------------------------------------------+
#property copyright "Hedge_forex project"
#property version   "0.10"
#property strict

#include "Include/Config.mqh"
#include "Include/AccountView.mqh"
#include "Include/TrendEngine.mqh"
#include "Include/TradeManager.mqh"
#include "Include/RiskManager.mqh"
#include "Include/HedgeEngine.mqh"
#include "Include/EquityTP.mqh"
#include "Include/StateStore.mqh"

//=== General =================================================
input long   InpMagic            = 990001;   // Magic Number (ต่างกันทุก chart)
input string InpTradeComment     = "HedgeEqEA";
input ENUM_ACCOUNT_SCOPE InpScope = SCOPE_VIRTUAL; // VIRTUAL=เฉพาะส่วน EA / WHOLE=ทั้งบัญชีตามหนังสือ
input double InpAllocatedCapital = 1000.0;   // Initial_Capital (prompt §1)
input int    InpTargetLeverage   = 2000;     // Account_Leverage เป้าหมาย (prompt §1) — เตือนถ้าจริงต่ำกว่า

//=== Trend Engine (หนังสือบทที่ 8 + prompt §3) ==============
input ENUM_TIMEFRAMES InpMajorTF = PERIOD_D1;   // Macro (H4 ทางเลือกตาม prompt)
input ENUM_TIMEFRAMES InpMidTF   = PERIOD_H1;
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M5;
input int    InpMAFast           = 5;
input int    InpMAMid            = 21;
input int    InpMASlow           = 50;
input ENUM_MA_METHOD InpMAMethod = MODE_EMA;
input int    InpFlipConfirmBars  = 2;        // แท่งยืนยันกลับเทรนด์ (Middle TF)
input int    InpSignalFreshBars  = 3;

//=== Lot & Pyramid ==========================================
input double InpBaseLot          = 0.01;     // lot คงที่ — ไม่ใช่ martingale
input bool   InpAllowPyramid     = true;
input int    InpPyramidStepPts   = 300;
input int    InpMaxPositions     = 15;

//=== Cover Loss Hedge (หนังสือบทที่ 3 + prompt §4B) =========
input ENUM_COVER_MODEL InpCoverModel = COVER_TARGET; // SIMPLE=Model1 | TARGET=Model2 (default)
input int    InpCoverTPPts       = 5000;     // Target_TP_Points
input double InpCoverProfitMoney = 50.0;     // Target_Profit_Reference (Model 2)
input bool   InpIncludeCosts     = true;

//=== Counter-Trend Scalping (prompt §4C) ====================
input bool   InpAllowCounterTrend = false;   // เปิดหลัง backtest ยืนยันเท่านั้น
input int    InpStrongTrendBars  = 6;
input int    InpBBPeriod         = 20;
input double InpBBDev            = 2.0;
input int    InpSwingDepth       = 12;
input int    InpCounterTPPts     = 300;

//=== Sideway (prompt §3) ====================================
input ENUM_SIDEWAY_MODE InpSidewayMode = SIDEWAY_PAUSE;

//=== Risk (ML% / DD / Layer) ================================
input double InpMLTargetPct      = 3000.0;   // ML% เป้าหมาย → เพดาน net lot (กรณี D)
input double InpMLFloorPct       = 1000.0;
input double InpMLLockPct        = 500.0;    // ต่ำกว่านี้ → Zero Hedge ทันที
input double InpDDWarnPct        = 20.0;
input double InpDDLockPct        = 30.0;     // เกณฑ์หนังสือ: DD < 30%
input double InpHardCutPct       = 0.0;      // 0=ปิดใช้ (ตามหนังสือ: ล็อค ไม่ตัดขาดทุน)
input int    InpMaxLayers        = 2;        // เกณฑ์หนังสือ: 1–2 ชั้น
input int    InpMaxSpreadPts     = 60;

//=== Equity TP (หนังสือบทที่ 8 + prompt §6) =================
input bool   InpUseBalanceRule   = true;
input double InpCycleProfitMoney = 0.0;      // 0 = สูตร prompt ตรงตัว: Equity > Initial_Capital

//=== Zero Hedge Triggers เพิ่มเติม (prompt §5) ===============
input bool   InpLockOnSRBreak    = true;     // S/R หลัก Middle TF แตก → ล็อค

//=== Session / News =========================================
input bool   InpUseNewsFilter    = true;
input int    InpNewsBlockMin     = 30;
input bool   InpLockOnNews       = false;
input string InpRolloverStart    = "23:55";
input string InpRolloverEnd      = "00:20";
input bool   InpTradeFriday      = true;
input string InpFridayCutoff     = "18:00";

//=== Misc ===================================================
input bool   InpShowPanel        = true;
input bool   InpWriteCsv         = true;
input bool   InpPushAlerts       = true;
input int    InpRetryCount       = 3;
input int    InpRetryDelayMs     = 400;

//--- โมดูลหลัก
SConfig        g_cfg;
CAccountView   g_view;
CTrendEngine   g_trend;
CTradeManager  g_tm;
CRiskManager   g_risk;
CHedgeEngine   g_engine;
CEquityTP      g_etp;
CStateStore    g_store;

// บันทึกตัวแปรที่กู้จาก positions ไม่ได้ (DESIGN §13)
void PersistState(void)
  {
   SPersistState st;
   st.layer             = g_engine.Layer();
   st.peakEquity        = g_view.PeakEquity();
   st.closedPL          = g_view.ClosedPL();
   st.initialCapital    = g_view.InitialCapital();
   st.cycleStartBalance = g_engine.CycleStartBalance();
   st.hadCover          = g_engine.InRecovery() ? 1 : 0;
   g_store.Save(st);
  }

//+------------------------------------------------------------------+
void FillConfig(void)
  {
   g_cfg.magic = InpMagic;                     g_cfg.comment = InpTradeComment;
   g_cfg.scope = InpScope;                     g_cfg.allocatedCapital = InpAllocatedCapital;
   g_cfg.targetLeverage = InpTargetLeverage;
   g_cfg.majorTF = InpMajorTF;                 g_cfg.midTF = InpMidTF;
   g_cfg.entryTF = InpEntryTF;
   g_cfg.maFast = InpMAFast;                   g_cfg.maMid = InpMAMid;
   g_cfg.maSlow = InpMASlow;                   g_cfg.maMethod = InpMAMethod;
   g_cfg.flipConfirmBars = InpFlipConfirmBars; g_cfg.signalFreshBars = InpSignalFreshBars;
   g_cfg.baseLot = InpBaseLot;                 g_cfg.allowPyramid = InpAllowPyramid;
   g_cfg.pyramidStepPts = InpPyramidStepPts;   g_cfg.maxPositions = InpMaxPositions;
   g_cfg.coverModel = InpCoverModel;
   g_cfg.coverTPPts = InpCoverTPPts;           g_cfg.coverProfitMoney = InpCoverProfitMoney;
   g_cfg.includeCosts = InpIncludeCosts;
   g_cfg.allowCounterTrend = InpAllowCounterTrend;
   g_cfg.strongTrendBars = InpStrongTrendBars; g_cfg.bbPeriod = InpBBPeriod;
   g_cfg.bbDev = InpBBDev;                     g_cfg.swingDepth = InpSwingDepth;
   g_cfg.counterTPPts = InpCounterTPPts;
   g_cfg.sidewayMode = InpSidewayMode;         g_cfg.lockOnSRBreak = InpLockOnSRBreak;
   g_cfg.mlTargetPct = InpMLTargetPct;         g_cfg.mlFloorPct = InpMLFloorPct;
   g_cfg.mlLockPct = InpMLLockPct;
   g_cfg.ddWarnPct = InpDDWarnPct;             g_cfg.ddLockPct = InpDDLockPct;
   g_cfg.hardCutPct = InpHardCutPct;
   g_cfg.maxLayers = InpMaxLayers;             g_cfg.maxSpreadPts = InpMaxSpreadPts;
   g_cfg.useBalanceRule = InpUseBalanceRule;   g_cfg.cycleProfitMoney = InpCycleProfitMoney;
   g_cfg.useNewsFilter = InpUseNewsFilter;     g_cfg.newsBlockMin = InpNewsBlockMin;
   g_cfg.lockOnNews = InpLockOnNews;
   g_cfg.rolloverStart = InpRolloverStart;     g_cfg.rolloverEnd = InpRolloverEnd;
   g_cfg.tradeFriday = InpTradeFriday;         g_cfg.fridayCutoff = InpFridayCutoff;
   g_cfg.showPanel = InpShowPanel;             g_cfg.writeCsv = InpWriteCsv;
   g_cfg.pushAlerts = InpPushAlerts;
   g_cfg.retryCount = InpRetryCount;           g_cfg.retryDelayMs = InpRetryDelayMs;
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   FillConfig();
   string err;
   if(!ConfigValidate(g_cfg, err))
     {
      Alert("[HedgeEqEA] config ไม่ผ่าน: " + err);
      return INIT_FAILED;
     }
   if(!g_view.Init(g_cfg))            return INIT_FAILED;
   if(!g_trend.Init(g_cfg))           { Alert("[HedgeEqEA] สร้าง MA handles ไม่สำเร็จ"); return INIT_FAILED; }
   if(!g_tm.Init(g_cfg))              return INIT_FAILED;
   if(!g_risk.Init(g_cfg, g_view))    return INIT_FAILED;
   if(!g_engine.Init(g_cfg, g_view, g_trend, g_risk, g_tm)) return INIT_FAILED;
   if(!g_etp.Init(g_cfg, g_view))     return INIT_FAILED;

   // กู้ตัวแปรจากไฟล์ state ก่อน แล้วจึง reconstruct จาก positions จริง (positions เป็นหลัก)
   g_store.Init(g_cfg);
   SPersistState st;
   st.layer = 0; st.peakEquity = 0.0; st.closedPL = 0.0; st.initialCapital = 0.0;
   st.cycleStartBalance = 0.0; st.hadCover = 0;
   if(g_store.Load(st))
     {
      g_view.SetInitialCapital(st.initialCapital);   // สำคัญใน SCOPE_WHOLE: balance ปัจจุบันเพี้ยนจากทุนจริง
      g_view.SetClosedPL(st.closedPL);
      if(st.peakEquity > 0.0) g_view.SetPeak(st.peakEquity);
      g_engine.SetLayer(st.layer);
      g_engine.SetCycleInfo(st.cycleStartBalance, st.hadCover != 0);
      PrintFormat("[HedgeEqEA] state restored: layer=%d peak=%.2f closedPL=%.2f cap=%.2f cycleBase=%.2f recovery=%d",
                  st.layer, st.peakEquity, st.closedPL, st.initialCapital,
                  st.cycleStartBalance, st.hadCover);
     }
   g_engine.RestoreState();

   EventSetTimer(1);   // panel / news / heartbeat เท่านั้น — ห้ามทำงานเทรดใน OnTimer
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_trend.Deinit();
   g_engine.Deinit();
   // ไม่ปิดออเดอร์ — รอบเทรดต้องอยู่ข้าม restart ได้ (DESIGN §13)
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   // Equity TP เช็คก่อนทุกอย่าง ทุก state (DESIGN §4 กรอบบน) — baseline รายรอบ
   string reason;
   if(g_etp.ShouldCloseAll(g_engine.CycleStartBalance(), g_engine.InRecovery(), reason))
     {
      Print("[HedgeEqEA] " + reason);
      g_engine.UserCloseAll();
      return;
     }
   g_engine.OnTickUpdate();
   if(g_engine.ConsumeDirty()) PersistState();   // state/layer เปลี่ยน → บันทึกทันที
  }

//+------------------------------------------------------------------+
// Snapshot ตาม deliverables ของ prompt: Balance / Equity / ML% / Layers / State ทุก step
void LogSnapshot(string context)
  {
   double ml = g_view.MarginLevelEA();
   PrintFormat("[HedgeEqEA] %s | bal=%.2f eq=%.2f ML=%s (%s) DD=%.1f%% net=%.2f layer=%d state=%d",
               context, g_view.BalanceEA(), g_view.EquityEA(),
               (ml == DBL_MAX ? "—" : DoubleToString(ml, 0)),
               EnumToString(g_view.MLSafetyState()),
               g_view.DrawdownPct(), g_view.NetLot(), g_engine.Layer(), g_engine.State());
  }

void OnTimer(void)
  {
   static datetime lastHeartbeat = 0;
   if(TimeCurrent() - lastHeartbeat >= 60)     // heartbeat ทุก 1 นาที
     {
      lastHeartbeat = TimeCurrent();
      if(g_view.OpenPositions() > 0) LogSnapshot("heartbeat");
     }
   // TODO(phase-5): อัปเดต panel, ตรวจ news window
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_cfg.magic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   // deal ปิด position → สะสม closed PL เข้ามุมมอง VIRTUAL (DESIGN §2.1)
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
     {
      double pl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      g_view.AddClosedPL(pl);
      PersistState();                  // sync ไฟล์ state ทุกครั้งที่มี deal ปิด
     }
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // TODO(phase-5): ปุ่ม panel — [LOCK NOW] → g_engine.UserLock(),
   //                [CLOSE ALL] (ยืนยัน 2 คลิกใน 3 วิ) → g_engine.UserCloseAll()
  }
