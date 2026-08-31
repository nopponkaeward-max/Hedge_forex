//+------------------------------------------------------------------+
//| Config.mqh — รวม input เป็น struct เดียว + validation            |
//| อ้างอิง: Docs/DESIGN.md §10                                      |
//+------------------------------------------------------------------+
#ifndef HEQ_CONFIG_MQH
#define HEQ_CONFIG_MQH

enum ENUM_ACCOUNT_SCOPE
  {
   SCOPE_VIRTUAL,   // คิด Equity/Balance เฉพาะส่วนของ EA (หลาย EA ร่วมบัญชี)
   SCOPE_WHOLE      // ใช้ค่าทั้งบัญชีตรง ๆ ตามหนังสือ (EA ตัวเดียวทั้งพอร์ต)
  };

struct SConfig
  {
   // General
   long              magic;
   string            comment;
   ENUM_ACCOUNT_SCOPE scope;
   double            allocatedCapital;
   // Trend
   ENUM_TIMEFRAMES   majorTF, midTF, entryTF;
   int               maFast, maMid, maSlow;
   ENUM_MA_METHOD    maMethod;
   int               flipConfirmBars, signalFreshBars;
   // Lot & pyramid
   double            baseLot;
   bool              allowPyramid;
   int               pyramidStepPts, maxPositions;
   // Cover Loss Hedge (สูตรหนังสือ บทที่ 3)
   int               coverTPPts;
   double            coverProfitMoney;
   bool              includeCosts;
   // Risk
   double            mlTargetPct, mlFloorPct, mlLockPct;
   double            ddWarnPct, ddLockPct, hardCutPct;
   int               maxLayers, maxSpreadPts;
   // Equity TP
   bool              useBalanceRule;
   double            cycleProfitMoney;
   // Session/News
   bool              useNewsFilter;
   int               newsBlockMin;
   bool              lockOnNews;
   string            rolloverStart, rolloverEnd;
   bool              tradeFriday;
   string            fridayCutoff;
   // Misc
   bool              showPanel, writeCsv, pushAlerts;
   int               retryCount, retryDelayMs;
  };

//+------------------------------------------------------------------+
//| ตรวจความถูกต้องของค่า config — คืน false พร้อมเหตุผลเมื่อไม่ผ่าน   |
//+------------------------------------------------------------------+
bool ConfigValidate(const SConfig &cfg, string &err)
  {
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     { err = "ต้องใช้บัญชีโหมด Hedging เท่านั้น (ระบบถือ Buy/Sell พร้อมกัน)"; return false; }
   if(!(cfg.mlLockPct < cfg.mlFloorPct && cfg.mlFloorPct < cfg.mlTargetPct))
     { err = "ต้องเรียง MLLock < MLFloor < MLTarget"; return false; }
   if(cfg.ddWarnPct >= cfg.ddLockPct)
     { err = "ต้องเรียง DDWarn < DDLock"; return false; }
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(cfg.baseLot < volMin)
     { err = StringFormat("BaseLot %.2f ต่ำกว่า VOLUME_MIN %.2f", cfg.baseLot, volMin); return false; }
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(cfg.coverTPPts <= (int)stopsLevel)
     { err = StringFormat("CoverTPPts %d แคบกว่า stops level %d", cfg.coverTPPts, stopsLevel); return false; }
   if(cfg.scope == SCOPE_VIRTUAL && cfg.allocatedCapital <= 0.0)
     { err = "โหมด VIRTUAL ต้องระบุ AllocatedCapital > 0"; return false; }
   // แจ้งเตือน (ไม่ fail): โบรกคิด margin ตอน fully hedge หรือไม่ (DESIGN §9)
   double hedgedMargin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_HEDGED);
   if(hedgedMargin > 0.0)
      PrintFormat("[HedgeEqEA] คำเตือน: โบรกคิด margin hedged = %.2f ต่อ lot — Zero Hedge จะไม่ฟรี margin", hedgedMargin);
   return true;
  }

#endif // HEQ_CONFIG_MQH
