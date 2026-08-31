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

// Role & Prompt §4B — สองโมเดลคำนวณ lot แก้ไม้
enum ENUM_COVER_MODEL
  {
   COVER_SIMPLE,    // Model 1: |Loss| / TP_points (normalize ด้วย point value)
   COVER_TARGET     // Model 2: (|Loss| + Profit_Reference) / TP_points (default)
  };

// Role & Prompt §3 — พฤติกรรมช่วง SIDEWAY
enum ENUM_SIDEWAY_MODE
  {
   SIDEWAY_PAUSE,   // หยุดเปิดรอบใหม่ (default)
   SIDEWAY_MIN_LOT  // เปิดได้เฉพาะ VOLUME_MIN และปิด pyramid
  };

//--- pure lot utilities (unit-testable — Scripts/HedgeEqEA_Tests.mq5)
// ปัด "ขึ้น" ตาม step แล้ว clamp [vmin, vmax] — ใช้กับ lot แก้ไม้ (สูตร cover ต้องไม่ขาด)
double NormalizeLotUpPure(double lot, double step, double vmin, double vmax)
  {
   if(step <= 0.0) step = 0.01;
   double n = MathCeil(lot / step - 1e-9) * step;
   return MathMin(MathMax(n, vmin), vmax);
  }

// ปัด "ลง" ตาม step + clamp เพดาน (ไม่ clamp ขั้นต่ำ — caller ตรวจ < vmin เอง)
// ใช้กับ lot ที่ถูกการ์ดลดขนาด: ห้ามปัดขึ้นเพราะจะทะลุเพดานที่การ์ดตั้งไว้
double NormalizeLotDownPure(double lot, double step, double vmax)
  {
   if(step <= 0.0) step = 0.01;
   double n = MathFloor(lot / step + 1e-9) * step;
   return MathMin(n, vmax);
  }

// เพดาน lot ที่เปิดได้โดย |net หลังเปิด| ≤ netMax — คิดทั้งกรณีข้ามศูนย์ (cover order)
// ทิศเดียวกับ net: เหลือที่ netMax − |net| | ทิศตรงข้าม: ข้ามศูนย์ได้ถึง |net| + netMax
double MaxLotWithinNetCap(double net, bool orderIsBuy, double netMax)
  {
   bool sameDir = (orderIsBuy ? net >= 0.0 : net <= 0.0);
   if(sameDir) return netMax - MathAbs(net);
   return MathAbs(net) + netMax;
  }

struct SConfig
  {
   // General
   long              magic;
   string            comment;
   ENUM_ACCOUNT_SCOPE scope;
   double            allocatedCapital;   // Initial_Capital
   int               targetLeverage;     // Account_Leverage เป้าหมาย (ตรวจเทียบจริง — EA แก้เองไม่ได้)
   // Trend
   ENUM_TIMEFRAMES   majorTF, midTF, entryTF;
   int               maFast, maMid, maSlow;
   ENUM_MA_METHOD    maMethod;
   int               flipConfirmBars, signalFreshBars;
   // Lot & pyramid
   double            baseLot;
   bool              allowPyramid;
   int               pyramidStepPts, maxPositions;
   // Cover Loss Hedge (สูตรหนังสือ บทที่ 3 + prompt §4B)
   ENUM_COVER_MODEL  coverModel;
   int               coverTPPts;         // Target_TP_Points
   double            coverProfitMoney;   // Target_Profit_Reference
   bool              includeCosts;
   // Counter-Trend Scalping (prompt §4C)
   bool              allowCounterTrend;
   int               strongTrendBars;
   int               bbPeriod;
   double            bbDev;
   int               swingDepth;
   int               counterTPPts;
   // Sideway (prompt §3)
   ENUM_SIDEWAY_MODE sidewayMode;
   // Zero Hedge trigger เพิ่มเติม (prompt §5)
   bool              lockOnSRBreak;
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
   // แจ้งเตือน (ไม่ fail): leverage จริงต่ำกว่าเป้า — margin ต่อ lot จะสูงกว่าที่ระบบคาด (prompt §1)
   long realLev = AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(realLev < cfg.targetLeverage)
      PrintFormat("[HedgeEqEA] คำเตือน: leverage จริง 1:%d ต่ำกว่าเป้า 1:%d — ML%% จะต่ำกว่าที่ตารางหนังสือคาด",
                  (int)realLev, cfg.targetLeverage);
   // แจ้งเตือน (ไม่ fail): โบรกคิด margin ตอน fully hedge หรือไม่ (DESIGN §9)
   double hedgedMargin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_HEDGED);
   if(hedgedMargin > 0.0)
      PrintFormat("[HedgeEqEA] คำเตือน: โบรกคิด margin hedged = %.2f ต่อ lot — Zero Hedge จะไม่ฟรี margin", hedgedMargin);
   return true;
  }

#endif // HEQ_CONFIG_MQH
