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

//=== General =================================================
input long   InpMagic            = 990001;   // Magic Number (ต่างกันทุก chart)
input string InpTradeComment     = "HedgeEqEA";
input ENUM_ACCOUNT_SCOPE InpScope = SCOPE_VIRTUAL; // VIRTUAL=เฉพาะส่วน EA / WHOLE=ทั้งบัญชีตามหนังสือ
input double InpAllocatedCapital = 1000.0;   // ทุนที่จัดสรรให้ EA (โหมด VIRTUAL)

//=== Trend Engine (หนังสือบทที่ 8: MTF + MA 5/21/50) =========
input ENUM_TIMEFRAMES InpMajorTF = PERIOD_H4;
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

//=== Cover Loss Hedge (หนังสือบทที่ 3) ======================
input int    InpCoverTPPts       = 5000;     // ระยะ TP แผนแก้ไม้ (ตัวอย่างหนังสือ 5,000 จุด)
input double InpCoverProfitMoney = 50.0;     // Profit อ้างอิง (ตัวอย่างหนังสือ 50)
input bool   InpIncludeCosts     = true;

//=== Risk (ML% / DD / Layer) ================================
input double InpMLTargetPct      = 3000.0;   // ML% เป้าหมาย → เพดาน net lot (กรณี D)
input double InpMLFloorPct       = 1000.0;
input double InpMLLockPct        = 500.0;    // ต่ำกว่านี้ → Zero Hedge ทันที
input double InpDDWarnPct        = 20.0;
input double InpDDLockPct        = 30.0;     // เกณฑ์หนังสือ: DD < 30%
input double InpHardCutPct       = 0.0;      // 0=ปิดใช้ (ตามหนังสือ: ล็อค ไม่ตัดขาดทุน)
input int    InpMaxLayers        = 2;        // เกณฑ์หนังสือ: 1–2 ชั้น
input int    InpMaxSpreadPts     = 60;

//=== Equity TP (หนังสือบทที่ 8) =============================
input bool   InpUseBalanceRule   = true;
input double InpCycleProfitMoney = 10.0;

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

//+------------------------------------------------------------------+
void FillConfig(void)
  {
   g_cfg.magic = InpMagic;                     g_cfg.comment = InpTradeComment;
   g_cfg.scope = InpScope;                     g_cfg.allocatedCapital = InpAllocatedCapital;
   g_cfg.majorTF = InpMajorTF;                 g_cfg.midTF = InpMidTF;
   g_cfg.entryTF = InpEntryTF;
   g_cfg.maFast = InpMAFast;                   g_cfg.maMid = InpMAMid;
   g_cfg.maSlow = InpMASlow;                   g_cfg.maMethod = InpMAMethod;
   g_cfg.flipConfirmBars = InpFlipConfirmBars; g_cfg.signalFreshBars = InpSignalFreshBars;
   g_cfg.baseLot = InpBaseLot;                 g_cfg.allowPyramid = InpAllowPyramid;
   g_cfg.pyramidStepPts = InpPyramidStepPts;   g_cfg.maxPositions = InpMaxPositions;
   g_cfg.coverTPPts = InpCoverTPPts;           g_cfg.coverProfitMoney = InpCoverProfitMoney;
   g_cfg.includeCosts = InpIncludeCosts;
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

   // TODO(phase-4): StateStore.Restore() — อ่าน layer/peak/closedPL จากไฟล์ state ก่อน
   g_engine.RestoreState();

   EventSetTimer(1);   // panel / news / heartbeat เท่านั้น — ห้ามทำงานเทรดใน OnTimer
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_trend.Deinit();
   // ไม่ปิดออเดอร์ — รอบเทรดต้องอยู่ข้าม restart ได้ (DESIGN §13)
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   // Equity TP เช็คก่อนทุกอย่าง ทุก state (DESIGN §4 กรอบบน)
   string reason;
   if(g_etp.ShouldCloseAll(reason))
     {
      Print("[HedgeEqEA] " + reason);
      g_engine.UserCloseAll();
      return;
     }
   g_engine.OnTickUpdate();
  }

//+------------------------------------------------------------------+
void OnTimer(void)
  {
   // TODO(phase-5): อัปเดต panel, ตรวจ news window, เขียน heartbeat
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
     }
   // TODO(phase-4): sync state file ทุกครั้งที่มี deal
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // TODO(phase-5): ปุ่ม panel — [LOCK NOW] → g_engine.UserLock(),
   //                [CLOSE ALL] (ยืนยัน 2 คลิกใน 3 วิ) → g_engine.UserCloseAll()
  }
