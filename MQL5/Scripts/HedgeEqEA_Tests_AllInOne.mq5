//+------------------------------------------------------------------+
//| HedgeEqEA_Tests.mq5 — unit tests ของ pure functions (DESIGN §15.1)|
//| ลากลง chart ใดก็ได้ → ดูผลใน Experts log (ต้องได้ ALL PASSED)     |
//+------------------------------------------------------------------+
#property strict

// ALL-IN-ONE BUILD: copy ไฟล์นี้ไฟล์เดียวไปที่ MQL5\Scripts\ แล้ว compile ได้เลย
// สร้างโดย tools/build_single.py — แก้โค้ดที่ไฟล์ต้นทางแล้ว build ใหม่ อย่าแก้ไฟล์นี้ตรง ๆ

//==================================================================
//=== [inlined] Include/HedgeEquationEA/Config.mqh
//==================================================================
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

// ชนิดของออเดอร์ที่ขอเปิด — RiskManager ใช้เลือกชุดการ์ด (DESIGN §7)
// ออเดอร์ "ป้องกัน" (COVER/ZEROHEDGE) ไม่ถูกบล็อกด้วย news/rollover/friday
enum ENUM_OPEN_KIND
  {
   OPEN_ENTRY,      // ไม้แรกของรอบ
   OPEN_PYRAMID,    // เติมไม้ตามเทรนด์
   OPEN_COUNTER,    // ไม้สวนเทรนด์ (prompt §4C)
   OPEN_COVER,      // ไม้แก้พอร์ต Cover Loss — ป้องกัน
   OPEN_ZEROHEDGE   // ล็อคพอร์ต — ต้องทำได้ทุกสถานการณ์
  };

// พฤติกรรมเย็นวันศุกร์ (ปิดความเสี่ยง gap สุดสัปดาห์ — RISK S2)
enum ENUM_FRIDAY_MODE
  {
   FRIDAY_TRADE,      // เทรดปกติ
   FRIDAY_BLOCK_NEW,  // งดเปิดไม้เพิ่มความเสี่ยงหลัง cutoff (default)
   FRIDAY_LOCK        // Zero Hedge ล็อคพอร์ตก่อนปิดตลาด แล้วคลายจันทร์ตามเงื่อนไขปกติ
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
   ENUM_FRIDAY_MODE  fridayMode;
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

//==================================================================
//=== [inlined] Include/HedgeEquationEA/AccountView.mqh
//==================================================================
//+------------------------------------------------------------------+
//| AccountView.mqh — มุมมองบัญชี "เฉพาะส่วนของ EA"                  |
//| implement สมการหลักของหนังสือ: ML% = Equity/Margin×100 (DESIGN §2)|
//+------------------------------------------------------------------+
#ifndef HEQ_ACCOUNTVIEW_MQH
#define HEQ_ACCOUNTVIEW_MQH


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
   double            m_closedPL;        // กำไร/ขาดทุนปิดแล้วสะสมของ EA (โหมด VIRTUAL, กู้จาก state file)
   double            m_peakEquity;      // สำหรับสถิติ peak DD
   double            m_initialCapital;  // ทุนแรกเริ่ม — คงที่ (SCOPE_WHOLE จับจาก balance ครั้งแรก แล้วกู้จาก state file)

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
      // SCOPE_WHOLE: จับ balance ตอนเริ่มเป็นทุนแรก — ถ้ามี state file ค่าจริงจะถูก
      // SetInitialCapital ทับตอน restore (balance ปัจจุบันเพี้ยนได้จากกำไร/ขาดทุนสะสม)
      m_initialCapital = (cfg.scope == SCOPE_VIRTUAL) ? cfg.allocatedCapital
                                                      : AccountInfoDouble(ACCOUNT_BALANCE);
      m_peakEquity = m_initialCapital;
      return true;
     }

   double            InitialCapital(void) const { return m_initialCapital; }
   void              SetInitialCapital(double v) { if(v > 0.0) m_initialCapital = v; }

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

//==================================================================
//=== [inlined] Include/HedgeEquationEA/TrendEngine.mqh
//==================================================================
//+------------------------------------------------------------------+
//| TrendEngine.mqh — MTF + MA 3 เส้น (5/21/50) ตามหนังสือบทที่ 8    |
//| DESIGN.md §5 | Role & Prompt §3                                  |
//+------------------------------------------------------------------+
#ifndef HEQ_TRENDENGINE_MQH
#define HEQ_TRENDENGINE_MQH


enum ENUM_TREND { TREND_UP, TREND_DOWN, TREND_SIDEWAY };

class CTrendEngine
  {
private:
   SConfig           m_cfg;
   // handles [tf][ma]: tf 0=major 1=mid 2=entry, ma 0=fast 1=mid 2=slow
   int               m_h[3][3];
   ENUM_TIMEFRAMES   m_tfs[3];
   int               m_flipCount;         // นับแท่งยืนยันการกลับทิศบน Middle TF
   ENUM_TREND        m_flipDir;
   datetime          m_lastMidBar;        // gating: ประเมิน flip แท่งละครั้งเดียว

   int               MakeMA(ENUM_TIMEFRAMES tf, int period)
     {
      return iMA(_Symbol, tf, period, 0, m_cfg.maMethod, PRICE_CLOSE);
     }

   // อ่านเทรนด์จากแท่งปิดแล้ว shift ใด ๆ — กติกาหนังสือ:
   // UP: MA5>MA21>MA50 และ Close>MA5 | DOWN: กลับกัน | อื่น ๆ: SIDEWAY
   ENUM_TREND        ReadAt(int tfIdx, int shift) const
     {
      double fast[1], mid[1], slow[1];
      if(CopyBuffer(m_h[tfIdx][0], 0, shift, 1, fast) != 1 ||
         CopyBuffer(m_h[tfIdx][1], 0, shift, 1, mid)  != 1 ||
         CopyBuffer(m_h[tfIdx][2], 0, shift, 1, slow) != 1)
         return TREND_SIDEWAY;
      double close = iClose(_Symbol, m_tfs[tfIdx], shift);
      if(fast[0] > mid[0] && mid[0] > slow[0] && close > fast[0]) return TREND_UP;
      if(fast[0] < mid[0] && mid[0] < slow[0] && close < fast[0]) return TREND_DOWN;
      return TREND_SIDEWAY;
     }

public:
   bool              Init(const SConfig &cfg)
     {
      m_cfg = cfg;
      m_flipCount = 0;
      m_flipDir = TREND_SIDEWAY;
      m_lastMidBar = 0;
      m_tfs[0] = cfg.majorTF; m_tfs[1] = cfg.midTF; m_tfs[2] = cfg.entryTF;
      int periods[3];
      periods[0] = cfg.maFast; periods[1] = cfg.maMid; periods[2] = cfg.maSlow;
      for(int t = 0; t < 3; t++)
         for(int p = 0; p < 3; p++)
           {
            m_h[t][p] = MakeMA(m_tfs[t], periods[p]);
            if(m_h[t][p] == INVALID_HANDLE) return false;
           }
      return true;
     }

   void              Deinit(void)
     {
      for(int t = 0; t < 3; t++)
         for(int p = 0; p < 3; p++)
            if(m_h[t][p] != INVALID_HANDLE) IndicatorRelease(m_h[t][p]);
     }

   ENUM_TREND        Major(void)  const { return ReadAt(0, 1); }
   ENUM_TREND        Middle(void) const { return ReadAt(1, 1); }
   ENUM_TREND        Minor(void)  const { return ReadAt(2, 1); }

   // สัญญาณเข้า FLAT→RIDE: Major กับ Middle ทิศเดียวกัน (prompt: align 1H กับ Day)
   // + Minor เพิ่งจัดเรียงทิศนั้น "สด" ภายใน signalFreshBars แท่ง
   // คืนค่าผ่าน isSideway เมื่อ Major เป็น sideway (ให้ HedgeEngine ใช้กับ InpSidewayMode)
   bool              EntrySignal(ENUM_TREND &dir, bool &isSideway)
     {
      ENUM_TREND maj = Major(), mid = Middle();
      isSideway = (maj == TREND_SIDEWAY);
      // โหมด MIN_LOT: ยอมรับ Middle+Minor align โดย Major เป็น sideway
      ENUM_TREND ref = isSideway ? mid : maj;
      if(ref == TREND_SIDEWAY) return false;
      if(!isSideway && maj != mid) return false;
      if(Minor() != ref) return false;
      // ความสด: การจัดเรียงบน Entry TF ต้องเพิ่งเริ่ม — แท่งก่อนหน้าช่วง fresh ยังไม่ align
      if(ReadAt(2, m_cfg.signalFreshBars + 1) == ref) return false;
      dir = ref;
      return true;
     }

   // สัญญาณกลับทิศ RIDE→COVER: Middle สวนทิศเดิมติดต่อกัน flipConfirmBars "แท่งปิด"
   // และ Major ไม่ค้านทิศใหม่ (Major == ทิศใหม่ หรือ SIDEWAY)
   bool              FlipConfirmed(ENUM_TREND current, ENUM_TREND &newDir)
     {
      if(current == TREND_SIDEWAY) return false;
      // gating: ประเมินเฉพาะเมื่อแท่งใหม่ของ Middle TF ปิดแล้ว
      datetime curBar = iTime(_Symbol, m_cfg.midTF, 0);
      if(curBar == m_lastMidBar) return false;
      m_lastMidBar = curBar;

      ENUM_TREND opposite = (current == TREND_UP) ? TREND_DOWN : TREND_UP;
      if(Middle() == opposite)
        {
         if(m_flipDir != opposite) { m_flipDir = opposite; m_flipCount = 0; }
         m_flipCount++;
        }
      else
        {
         m_flipCount = 0;
         m_flipDir = TREND_SIDEWAY;
        }
      if(m_flipCount >= m_cfg.flipConfirmBars)
        {
         ENUM_TREND maj = Major();
         if(maj == opposite || maj == TREND_SIDEWAY)
           {
            newDir = opposite;
            // ไม่ reset ตัวนับที่นี่ — ถ้า cover เปิดไม่สำเร็จ สัญญาณต้อง re-fire แท่งถัดไป
            // หลัง cover สำเร็จ rideDir สลับฝั่ง → การเรียกครั้งถัดไป opposite เปลี่ยน
            // และ Middle ไม่ตรงกับ opposite ใหม่ ตัวนับจะ reset เองใน else-branch
            return true;
           }
        }
      return false;
     }

   // เทรนด์ align โดยไม่ต้อง "สด" (Major==Middle ทิศเดียวกัน) — ใช้ในเงื่อนไข UNLOCK:
   // พอร์ตที่ล็อคระหว่างเทรนด์ยาวต้องคลายได้แม้การจัดเรียง MA เกิดมานานแล้ว
   bool              AlignedTrend(ENUM_TREND &dir) const
     {
      ENUM_TREND maj = Major();
      if(maj == TREND_SIDEWAY || maj != Middle()) return false;
      dir = maj;
      return true;
     }

   // เทรนด์แข็ง (counter-trend §6.3): Major ทิศ dir และ Middle align ทิศเดียวกัน
   // ต่อเนื่องย้อนหลัง strongTrendBars แท่งปิดบน Middle TF
   bool              StrongTrend(ENUM_TREND dir) const
     {
      if(dir == TREND_SIDEWAY || Major() != dir) return false;
      for(int s = 1; s <= m_cfg.strongTrendBars; s++)
         if(ReadAt(1, s) != dir) return false;
      return true;
     }
  };

#endif // HEQ_TRENDENGINE_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/Levels.mqh
//==================================================================
//+------------------------------------------------------------------+
//| Levels.mqh — swing Support/Resistance แบบ fractal               |
//| ใช้โดย: S/R-break trigger (DESIGN §9) และ Counter-Trend (§6.3)  |
//+------------------------------------------------------------------+
#ifndef HEQ_LEVELS_MQH
#define HEQ_LEVELS_MQH

// swing high = แท่งที่ high สูงกว่าเพื่อนบ้าน wing แท่งทั้งสองข้าง (fractal)
// คืน 0.0 เมื่อไม่พบภายใน lookback
double LastSwingHigh(ENUM_TIMEFRAMES tf, int depth)
  {
   int wing = 2;
   int lookback = MathMax(depth * 4, 20);
   for(int i = wing + 1; i <= lookback; i++)   // เริ่มหลังแท่งปิดล่าสุด + wing
     {
      double h = iHigh(_Symbol, tf, i);
      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
         if(iHigh(_Symbol, tf, i - k) >= h || iHigh(_Symbol, tf, i + k) >= h)
            isSwing = false;
      if(isSwing) return h;
     }
   return 0.0;
  }

double LastSwingLow(ENUM_TIMEFRAMES tf, int depth)
  {
   int wing = 2;
   int lookback = MathMax(depth * 4, 20);
   for(int i = wing + 1; i <= lookback; i++)
     {
      double l = iLow(_Symbol, tf, i);
      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
         if(iLow(_Symbol, tf, i - k) <= l || iLow(_Symbol, tf, i + k) <= l)
            isSwing = false;
      if(isSwing) return l;
     }
   return 0.0;
  }

#endif // HEQ_LEVELS_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/TradeManager.mqh
//==================================================================
//+------------------------------------------------------------------+
//| TradeManager.mqh — ผู้เดียวที่แตะ order API (DESIGN §11)         |
//+------------------------------------------------------------------+
#ifndef HEQ_TRADEMANAGER_MQH
#define HEQ_TRADEMANAGER_MQH

#include <Trade/Trade.mqh>


class CTradeManager
  {
private:
   CTrade            m_trade;
   SConfig           m_cfg;

   bool              IsOurs(void) const
     {
      return (PositionGetInteger(POSITION_MAGIC) == m_cfg.magic &&
              PositionGetString(POSITION_SYMBOL) == _Symbol);
     }

   // retry เฉพาะ error ชั่วคราว — error ถาวร (NO_MONEY, INVALID_VOLUME) fail ทันที
   static bool       IsTransient(uint retcode)
     {
      return (retcode == TRADE_RETCODE_REQUOTE       ||
              retcode == TRADE_RETCODE_PRICE_OFF     ||
              retcode == TRADE_RETCODE_PRICE_CHANGED ||
              retcode == TRADE_RETCODE_TIMEOUT       ||
              retcode == TRADE_RETCODE_CONNECTION);
     }

public:
   bool              Init(const SConfig &cfg)
     {
      m_cfg = cfg;
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(30);
      // เลือก filling mode ตามที่ symbol รองรับ
      long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0) m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else                                          m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      return true;
     }

   // ปัด lot "ขึ้น" ตาม step (สูตร cover ต้องไม่ขาด — ตามหนังสือ 0.05525→0.06) แล้ว clamp
   double            NormalizeLotUp(double lot) const
     {
      return NormalizeLotUpPure(lot,
                                SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
                                SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                                SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
     }

   // ปิดทุกไม้ของฝั่งเดียว (เทคนิค 1: ปิดฝั่งกำไรสวนเทรนด์ใหม่)
   bool              CloseSide(ENUM_POSITION_TYPE side)
     {
      bool allOk = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurs()) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != side) continue;
         if(!ClosePosition(tk)) allOk = false;
        }
      return allOk;
     }

   // ปิด "หนึ่งไม้" ของฝั่งที่กำหนดที่ขาดทุนน้อยที่สุด (ใช้ใน UNLOCK — เทคนิค 3/8)
   // คืน false เมื่อไม่มีไม้ฝั่งนั้นเหลือ หรือปิดไม่สำเร็จ
   bool              CloseOneLeastLosing(ENUM_POSITION_TYPE side)
     {
      ulong bestTicket = 0;
      double bestProfit = -DBL_MAX;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurs()) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != side) continue;
         double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(p > bestProfit) { bestProfit = p; bestTicket = tk; }
        }
      if(bestTicket == 0) return false;
      return ClosePosition(bestTicket);
     }

   bool              OpenMarket(ENUM_ORDER_TYPE type, double lot, string tag, ulong &dealTicket)
     {
      dealTicket = 0;
      string comment = m_cfg.comment + "|" + tag;
      for(int attempt = 0; attempt <= m_cfg.retryCount; attempt++)
        {
         bool ok = (type == ORDER_TYPE_BUY)
                   ? m_trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, comment)
                   : m_trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, comment);
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
           {
            dealTicket = m_trade.ResultDeal();
            return true;
           }
         if(!IsTransient(rc))
           {
            PrintFormat("[HedgeEqEA] OpenMarket fail ถาวร rc=%u (%s)", rc, m_trade.ResultRetcodeDescription());
            return false;
           }
         Sleep(m_cfg.retryDelayMs);
        }
      PrintFormat("[HedgeEqEA] OpenMarket fail หลัง retry %d ครั้ง", m_cfg.retryCount);
      return false;
     }

   bool              ClosePosition(ulong ticket)
     {
      for(int attempt = 0; attempt <= m_cfg.retryCount; attempt++)
        {
         if(m_trade.PositionClose(ticket)) return true;
         if(!IsTransient(m_trade.ResultRetcode())) return false;
         Sleep(m_cfg.retryDelayMs);
        }
      return false;
     }

   // ปิดทั้ง basket จากไม้กำไรมาก → ขาดทุนมาก (ลำดับ CLOSE_ALL, DESIGN §4):
   // Equity ไม่ร่วงระหว่างทยอยปิด และ margin ถูกคืนเร็ว
   bool              CloseAllProfitFirst(void)
     {
      // เก็บ (ticket, profit) แล้ว sort ก่อนปิด
      ulong  tickets[];
      double profits[];
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurs()) continue;
         ArrayResize(tickets, n + 1);
         ArrayResize(profits, n + 1);
         tickets[n] = tk;
         profits[n] = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         n++;
        }
      // selection sort กำไรมาก → น้อย (n เล็ก — maxPositions)
      for(int a = 0; a < n - 1; a++)
        {
         int best = a;
         for(int b = a + 1; b < n; b++)
            if(profits[b] > profits[best])
               best = b;
         if(best != a)
           {
            ulong  tt = tickets[a]; tickets[a] = tickets[best]; tickets[best] = tt;
            double pp = profits[a]; profits[a] = profits[best]; profits[best] = pp;
           }
        }
      bool allOk = true;
      for(int i = 0; i < n; i++)
         if(!ClosePosition(tickets[i])) allOk = false;
      return allOk;
     }

   // เทคนิค 4: จับคู่ปิดหักล้างสองไม้ตรงข้าม (ประหยัด spread) — โบรกต้องรองรับ
   bool              CloseBy(ulong ticket, ulong oppositeTicket)
     {
      return m_trade.PositionCloseBy(ticket, oppositeTicket);
     }
  };

#endif // HEQ_TRADEMANAGER_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/NewsFilter.mqh
//==================================================================
//+------------------------------------------------------------------+
//| NewsFilter.mqh — การ์ดข่าวแรง / rollover / วันศุกร์ (DESIGN §7)  |
//| ปิดความเสี่ยง S2 (gap สุดสัปดาห์) และช่วงข่าว/สภาพคล่องต่ำ        |
//+------------------------------------------------------------------+
#ifndef HEQ_NEWSFILTER_MQH
#define HEQ_NEWSFILTER_MQH


class CNewsFilter
  {
private:
   SConfig           m_cfg;
   string            m_curBase, m_curProfit;
   bool              m_calendarOK;      // calendar ใช้ได้จริงหรือไม่ (tester: ไม่ได้)
   datetime          m_lastCheck;       // cache ผลเช็คข่าว 60 วิ (calendar call แพง)
   bool              m_lastResult;

   // "HH:MM" → นาทีของวัน; คืน -1 เมื่อ parse ไม่ได้
   static int        TimeOfDayMin(string hhmm)
     {
      string parts[];
      if(StringSplit(hhmm, ':', parts) != 2) return -1;
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
      return h * 60 + m;
     }

   static int        NowMin(void)
     {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      return dt.hour * 60 + dt.min;
     }

public:
   bool              Init(const SConfig &cfg)
     {
      m_cfg = cfg;
      m_curBase   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      m_curProfit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      m_lastCheck = 0;
      m_lastResult = false;
      // economic calendar ใช้ไม่ได้ใน Strategy Tester — degrade พร้อมแจ้ง (DESIGN §12)
      m_calendarOK = !MQLInfoInteger(MQL_TESTER);
      if(!m_calendarOK && cfg.useNewsFilter)
         Print("[HedgeEqEA] NewsFilter: calendar ใช้ไม่ได้ใน tester — ข้ามการเช็คข่าว (rollover/friday ยังทำงาน)");
      return true;
     }

   // อยู่ในหน้าต่างข่าว impact สูงของสกุลเงิน symbol นี้ ±newsBlockMin นาที
   bool              InNewsWindow(void)
     {
      if(!m_cfg.useNewsFilter || !m_calendarOK) return false;
      datetime now = TimeTradeServer();
      if(now - m_lastCheck < 60) return m_lastResult;   // cache 60 วิ
      m_lastCheck = now;
      m_lastResult = false;
      datetime from = now - m_cfg.newsBlockMin * 60;
      datetime to   = now + m_cfg.newsBlockMin * 60;
      MqlCalendarValue values[];
      if(CalendarValueHistory(values, from, to) <= 0) return false;
      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
         MqlCalendarCountry country;
         if(!CalendarCountryById(ev.country_id, country)) continue;
         if(country.currency == m_curBase || country.currency == m_curProfit)
           {
            m_lastResult = true;
            return true;
           }
        }
      return false;
     }

   // ช่วง rollover (สเปรดถ่าง สภาพคล่องต่ำ — หนังสือเตือนตี 4–5 เวลาไทย)
   bool              InRollover(void)
     {
      int s = TimeOfDayMin(m_cfg.rolloverStart);
      int e = TimeOfDayMin(m_cfg.rolloverEnd);
      if(s < 0 || e < 0) return false;
      int nowM = NowMin();
      if(s <= e) return (nowM >= s && nowM <= e);
      return (nowM >= s || nowM <= e);      // ช่วงคร่อมเที่ยงคืน
     }

   // วันศุกร์หลังเวลา cutoff (ตามเวลา server)
   bool              FridayAfterCutoff(void)
     {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      if(dt.day_of_week != FRIDAY) return false;
      int cut = TimeOfDayMin(m_cfg.fridayCutoff);
      if(cut < 0) return false;
      return (NowMin() >= cut);
     }

   // งดเปิดไม้เพิ่มความเสี่ยง (entry/pyramid/counter) ตามโหมดวันศุกร์
   bool              FridayBlocksNew(void)
     {
      if(m_cfg.fridayMode == FRIDAY_TRADE) return false;
      return FridayAfterCutoff();          // BLOCK_NEW และ LOCK ต่างงดเปิดเพิ่มทั้งคู่
     }

   // ต้อง Zero Hedge ล็อคก่อนปิดตลาดศุกร์ (ปิดความเสี่ยง gap สุดสัปดาห์ — RISK S2)
   bool              FridayWantsLock(void)
     {
      return (m_cfg.fridayMode == FRIDAY_LOCK && FridayAfterCutoff());
     }

   // ข่าวแรงและผู้ใช้เลือกล็อคคร่อมข่าว (เทคนิค 6)
   bool              NewsWantsLock(void)
     {
      return (m_cfg.lockOnNews && InNewsWindow());
     }
  };

#endif // HEQ_NEWSFILTER_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/Logger.mqh
//==================================================================
//+------------------------------------------------------------------+
//| Logger.mqh — CSV log ต่อเดือน + push notification (DESIGN §14)   |
//| deliverables ของ prompt: log Balance/Equity/ML%/Layers/State ทุก step |
//+------------------------------------------------------------------+
#ifndef HEQ_LOGGER_MQH
#define HEQ_LOGGER_MQH




class CLogger
  {
private:
   SConfig           m_cfg;
   CAccountView     *m_view;
   CTrendEngine     *m_trend;

   string            FileName(void) const
     {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      return StringFormat("HedgeEqEA_%I64d_%04d%02d.csv", m_cfg.magic, dt.year, dt.mon);
     }

   static string     TrendStr(ENUM_TREND t)
     {
      return (t == TREND_UP) ? "UP" : (t == TREND_DOWN) ? "DOWN" : "SIDEWAY";
     }

public:
   bool              Init(const SConfig &cfg, CAccountView &view, CTrendEngine &trend)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      m_trend = GetPointer(trend);
      return true;
     }

   // เขียน 1 แถว — เปิด/ปิดไฟล์ต่อแถว (append) เพื่อรอด crash; คอลัมน์ตาม DESIGN §14
   void              Event(string event, string state, int layer,
                           double lot, double price, string reason)
     {
      // journal เสมอ (prompt deliverables: ทุก step)
      double ml = m_view.MarginLevelEA();
      string mlStr = (ml == DBL_MAX) ? "-" : DoubleToString(ml, 0);
      PrintFormat("[HedgeEqEA] %s | %s layer=%d ML=%s DD=%.1f%% eq=%.2f bal=%.2f net=%.2f %s",
                  event, state, layer, mlStr, m_view.DrawdownPct(),
                  m_view.EquityEA(), m_view.BalanceEA(), m_view.NetLot(), reason);
      if(!m_cfg.writeCsv) return;
      string fname = FileName();
      bool isNew = !FileIsExist(fname);
      int h = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE) return;
      FileSeek(h, 0, SEEK_END);
      if(isNew)
         FileWriteString(h, "time,event,state,layer,trend_major,trend_mid,net_lot,ml_pct,dd_pct,equity,balance,float_pl,lot,price,reason\n");
      FileWriteString(h, StringFormat("%s,%s,%s,%d,%s,%s,%.2f,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.5f,\"%s\"\n",
                      TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS),
                      event, state, layer,
                      TrendStr(m_trend.Major()), TrendStr(m_trend.Middle()),
                      m_view.NetLot(), mlStr, m_view.DrawdownPct(),
                      m_view.EquityEA(), m_view.BalanceEA(), m_view.FloatingPL(),
                      lot, price, reason));
      FileClose(h);
     }

   // แจ้งเตือนมือถือเหตุการณ์สำคัญ (LOCKED, DD, EquityTP, วิกฤต) — ไม่ทำงานใน tester
   void              Push(string msg)
     {
      if(!m_cfg.pushAlerts || MQLInfoInteger(MQL_TESTER)) return;
      if(!SendNotification("[HedgeEqEA " + _Symbol + "] " + msg))
         Print("[HedgeEqEA] push ล้มเหลว (ตั้งค่า MetaQuotes ID ใน terminal?): " + msg);
     }
  };

#endif // HEQ_LOGGER_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/RiskManager.mqh
//==================================================================
//+------------------------------------------------------------------+
//| RiskManager.mqh — การ์ด 8 ข้อก่อนเปิดทุกออเดอร์ (DESIGN §7)      |
//+------------------------------------------------------------------+
#ifndef HEQ_RISKMANAGER_MQH
#define HEQ_RISKMANAGER_MQH




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
   CNewsFilter      *m_news;
   int               m_layer;       // ตัวนับ layer ปัจจุบัน — HedgeEngine เป็นผู้ increment

public:
   bool              Init(const SConfig &cfg, CAccountView &view, CNewsFilter &news)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      m_news = GetPointer(news);
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

   SRiskVerdict      CheckOpen(ENUM_ORDER_TYPE type, double lot, ENUM_OPEN_KIND kind)
     {
      SRiskVerdict v;
      v.allowed = true; v.adjustedLot = lot; v.ruleHit = 0; v.reason = "";

      // ข้อยกเว้นสำคัญ: การเข้า Zero Hedge (LOCKED) ต้องทำได้ทุกสถานการณ์ (DESIGN §7)
      if(kind == OPEN_ZEROHEDGE) return v;

      // 9. กติกาเหล็กของ prompt §4C: Σlot สวนเทรนด์ (รวมไม้ใหม่) ≤ Σlot ฝั่งตามเทรนด์
      if(kind == OPEN_COUNTER)
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

      // 2-3. rollover / news / friday — เฉพาะไม้ "เพิ่มความเสี่ยง" (entry/pyramid/counter)
      //      ไม้ COVER เป็นกลไกป้องกัน ต้องเปิดได้แม้ช่วงข่าว (DESIGN §6 หมายเหตุ)
      if(kind != OPEN_COVER)
        {
         if(m_news.InRollover())
           { v.allowed = false; v.ruleHit = 2; v.reason = "ช่วง rollover"; return v; }
         if(m_news.InNewsWindow())
           { v.allowed = false; v.ruleHit = 3; v.reason = "หน้าต่างข่าว impact สูง"; return v; }
         if(m_news.FridayBlocksNew())
           { v.allowed = false; v.ruleHit = 3; v.reason = "ศุกร์หลัง cutoff"; return v; }
        }

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

      // 6. NetLotMax — ใช้เฉพาะออเดอร์ที่เพิ่ม |net| (ออเดอร์ลดความเสี่ยงผ่านเสมอ)
      //    เพดานคิดถูกทั้งกรณีทิศเดียวกับ net และ cover order ที่ข้ามศูนย์ (|net|+netMax)
      double netMax = NetLotMax();
      double netAfter = MathAbs(net + signedLot);
      if(increasesRisk && netAfter > netMax)
        {
         double cap = MaxLotWithinNetCap(net, type == ORDER_TYPE_BUY, netMax);
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         // ปัด "ลง" ตาม step ก่อนส่ง — ค่าดิบเช่น 0.0333 จะโดนโบรก reject INVALID_VOLUME
         double allowedLot = NormalizeLotDownPure(MathMin(lot, cap), step, vmax);
         if(allowedLot < vmin)
           { v.allowed = false; v.ruleHit = 6; v.reason = StringFormat("net %.2f จะเกิน NetLotMax %.2f", netAfter, netMax); return v; }
         v.adjustedLot = allowedLot;
         v.reason = StringFormat("ลด lot %.2f→%.2f ตาม NetLotMax", lot, allowedLot);
        }

      // 7. simulate ML% หลังเปิด ≥ MLFloor (สมการ ML% = Equity/Margin×100 กับ margin ของ net ใหม่)
      double signedAdj = (type == ORDER_TYPE_BUY) ? v.adjustedLot : -v.adjustedLot;
      double netAfterSigned = net + signedAdj;
      double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(MathAbs(netAfterSigned) >= volStep / 2.0)
        {
         ENUM_ORDER_TYPE netType = (netAfterSigned > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double netPrice = (netType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                       : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double marginAfter = 0.0;
         if(OrderCalcMargin(netType, _Symbol, MathAbs(netAfterSigned), netPrice, marginAfter) &&
            marginAfter > 0.0)
           {
            double mlAfter = m_view.EquityEA() / marginAfter * 100.0;
            if(mlAfter < m_cfg.mlFloorPct)
              { v.allowed = false; v.ruleHit = 7;
                v.reason = StringFormat("ML%% หลังเปิดจะเหลือ %.0f < floor %.0f", mlAfter, m_cfg.mlFloorPct); return v; }
           }
        }

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

//==================================================================
//=== [inlined] Include/HedgeEquationEA/HedgeEngine.mqh
//==================================================================
//+------------------------------------------------------------------+
//| HedgeEngine.mqh — state machine + สูตร Cover Loss Hedge          |
//| DESIGN.md §4, §6 | สูตรหนังสือบทที่ 3 | Role & Prompt §4-§5      |
//+------------------------------------------------------------------+
#ifndef HEQ_HEDGEENGINE_MQH
#define HEQ_HEDGEENGINE_MQH









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

//==================================================================
//=== [inlined] Include/HedgeEquationEA/EquityTP.mqh
//==================================================================
//+------------------------------------------------------------------+
//| EquityTP.mqh — ระบบปิดกำไรด้วย Equity (หนังสือบทที่ 8, prompt §6)|
//| สูตร: EQUITY >= BALANCE หรือ EQUITY > ทุนแรกเริ่ม                 |
//|                                                                  |
//| หมายเหตุ semantics (DESIGN §8): baseline ใช้ "Balance ณ ต้นรอบ"  |
//| ไม่ใช่ทุนแรกเริ่มตลอดชีพ — baseline ตลอดชีพทำให้ (ก) หลังมีกำไร  |
//| สะสม เงื่อนไข eq ≥ ทุน จริงทันทีที่เปิดรอบใหม่ → ปิดรวบทิ้งทุกรอบ  |
//| ขาดทุน spread สะสม (ข) หลังขาดทุนสะสม ไม่ปิดรอบเลยจนกู้ครบทุนเดิม |
//| สูตรของหนังสือเขียนในบริบท "แก้พอร์ตหนึ่งครั้ง" = หนึ่งรอบพอดี     |
//|                                                                  |
//| กติกา 2 ใช้เมื่อรอบเป็น "recovery" (เคย cover/lock แล้ว) หรือ     |
//| ผู้ใช้ตั้งเป้ากำไรขั้นต่ำ > 0 — รอบขี่เทรนด์ปกติออกด้วยกลไกเทรนด์   |
//| (technique-1/cover) ไม่ใช่ปิดทันทีที่ floating เป็นบวกหนึ่งจุด      |
//+------------------------------------------------------------------+
#ifndef HEQ_EQUITYTP_MQH
#define HEQ_EQUITYTP_MQH



class CEquityTP
  {
private:
   SConfig           m_cfg;
   CAccountView     *m_view;

public:
   bool              Init(const SConfig &cfg, CAccountView &view)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      return true;
     }

   // cycleStartBalance: BalanceEA ณ ตอนเปิดรอบ (HedgeEngine เป็นเจ้าของค่า)
   // inRecovery: รอบนี้เคยเกิด cover หรือ zero-hedge lock แล้ว
   bool              ShouldCloseAll(double cycleStartBalance, bool inRecovery, string &reason)
     {
      if(m_view.OpenPositions() == 0) return false;
      double eq   = m_view.EquityEA();
      double bal  = m_view.BalanceEA();
      double base = (cycleStartBalance > 0.0) ? cycleStartBalance : m_view.InitialCapital();

      // กติกา 1 (หนังสือ: Equity ≥ Balance): ใช้เมื่อรอบนี้มีกำไรเก็บเข้า Balance แล้ว
      // (bal > base) — คือกรณีตัวอย่างหนังสือ ทุน 100 → Balance 150 → ปิดที่ eq 130
      if(m_cfg.useBalanceRule && bal > base && eq >= bal)
        {
         reason = StringFormat("EquityTP-1: eq %.2f ≥ bal %.2f (base %.2f)", eq, bal, base);
         return true;
        }
      // กติกา 2 (หนังสือ: Equity > ทุนแรกเริ่ม + เป้า): เฉพาะรอบ recovery
      // หรือเมื่อผู้ใช้ตั้งเป้ากำไรขั้นต่ำ > 0
      if((inRecovery || m_cfg.cycleProfitMoney > 0.0) &&
         eq >= base + m_cfg.cycleProfitMoney)
        {
         reason = StringFormat("EquityTP-2: eq %.2f ≥ base %.2f + target %.2f%s",
                               eq, base, m_cfg.cycleProfitMoney,
                               (inRecovery ? " (recovery)" : ""));
         return true;
        }
      return false;
     }
  };

#endif // HEQ_EQUITYTP_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/StateStore.mqh
//==================================================================
//+------------------------------------------------------------------+
//| StateStore.mqh — เก็บ/กู้ตัวแปรที่อ่านจาก positions ไม่ได้        |
//| (layer, peakEquity, closedPL, initialCapital) — DESIGN §13      |
//| รูปแบบไฟล์: key=value ต่อบรรทัด ใน MQL5/Files                    |
//+------------------------------------------------------------------+
#ifndef HEQ_STATESTORE_MQH
#define HEQ_STATESTORE_MQH


struct SPersistState
  {
   int               layer;
   double            peakEquity;
   double            closedPL;
   double            initialCapital;
   double            cycleStartBalance;   // baseline ของ EquityTP รอบปัจจุบัน
   int               hadCover;            // 1 = รอบนี้เข้า recovery mode แล้ว
  };

class CStateStore
  {
private:
   string            m_file;

public:
   bool              Init(const SConfig &cfg)
     {
      m_file = StringFormat("HedgeEqEA_%I64d_%s.state", cfg.magic, _Symbol);
      return true;
     }

   bool              Save(const SPersistState &st)
     {
      int h = FileOpen(m_file, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         PrintFormat("[HedgeEqEA] StateStore: เขียน %s ไม่ได้ (err %d)", m_file, GetLastError());
         return false;
        }
      FileWriteString(h, StringFormat("layer=%d\n", st.layer));
      FileWriteString(h, StringFormat("peakEquity=%.2f\n", st.peakEquity));
      FileWriteString(h, StringFormat("closedPL=%.2f\n", st.closedPL));
      FileWriteString(h, StringFormat("initialCapital=%.2f\n", st.initialCapital));
      FileWriteString(h, StringFormat("cycleStartBalance=%.2f\n", st.cycleStartBalance));
      FileWriteString(h, StringFormat("hadCover=%d\n", st.hadCover));
      FileClose(h);
      return true;
     }

   // คืน false เมื่อไม่มีไฟล์ (รันครั้งแรก) — caller ใช้ค่า default
   bool              Load(SPersistState &st)
     {
      if(!FileIsExist(m_file)) return false;
      int h = FileOpen(m_file, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE) return false;
      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         int eq = StringFind(line, "=");
         if(eq <= 0) continue;
         string key = StringSubstr(line, 0, eq);
         double val = StringToDouble(StringSubstr(line, eq + 1));
         if(key == "layer")               st.layer = (int)val;
         else if(key == "peakEquity")     st.peakEquity = val;
         else if(key == "closedPL")       st.closedPL = val;
         else if(key == "initialCapital") st.initialCapital = val;
         else if(key == "cycleStartBalance") st.cycleStartBalance = val;
         else if(key == "hadCover")       st.hadCover = (int)val;
        }
      FileClose(h);
      return true;
     }

   void              Clear(void) { if(FileIsExist(m_file)) FileDelete(m_file); }
  };

#endif // HEQ_STATESTORE_MQH

//==================================================================
//=== [inlined] Include/HedgeEquationEA/Panel.mqh
//==================================================================
//+------------------------------------------------------------------+
//| Panel.mqh — สรุปสถานะบน chart + ปุ่ม LOCK / CLOSE ALL / PAUSE    |
//| DESIGN §14 — CLOSE ALL ต้องยืนยัน 2 คลิกใน 3 วินาที               |
//+------------------------------------------------------------------+
#ifndef HEQ_PANEL_MQH
#define HEQ_PANEL_MQH





class CPanel
  {
private:
   SConfig           m_cfg;
   CAccountView     *m_view;
   CTrendEngine     *m_trend;
   CHedgeEngine     *m_engine;
   string            m_prefix;
   datetime          m_closeArmTime;    // เวลาคลิก CLOSE ALL ครั้งแรก (0 = ยังไม่ arm)
   bool              m_paused;

   void              Label(string name, int x, int y, string text, color clr)
     {
      string obj = m_prefix + name;
      if(ObjectFind(0, obj) < 0)
        {
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
        }
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
     }

   void              Button(string name, int x, int y, int w, string text, color bg)
     {
      string obj = m_prefix + name;
      if(ObjectFind(0, obj) < 0)
        {
         ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
         ObjectSetInteger(0, obj, OBJPROP_YSIZE, 22);
         ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
        }
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
      ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, obj, OBJPROP_STATE, false);
     }

   static string     TrendMark(ENUM_TREND t)
     { return (t == TREND_UP) ? "▲" : (t == TREND_DOWN) ? "▼" : "–"; }

public:
   bool              Init(const SConfig &cfg, CAccountView &view, CTrendEngine &trend,
                          CHedgeEngine &engine)
     {
      m_cfg = cfg;
      m_view = GetPointer(view);
      m_trend = GetPointer(trend);
      m_engine = GetPointer(engine);
      m_prefix = StringFormat("HEQ%I64d_", cfg.magic);
      m_closeArmTime = 0;
      m_paused = false;
      return true;
     }

   bool              Paused(void) const { return m_paused; }

   void              Update(void)
     {
      if(!m_cfg.showPanel) return;
      ENUM_HE_STATE st = m_engine.State();
      color stClr = (st == HE_LOCKED)  ? clrGold :
                    (st == HE_CLOSING) ? clrOrange :
                    (st == HE_RIDE)    ? clrLimeGreen : clrSilver;
      double ml = m_view.MarginLevelEA();
      string mlStr = (ml == DBL_MAX) ? "—" : DoubleToString(ml, 0);
      double dd = m_view.DrawdownPct();
      color ddClr = (dd >= m_cfg.ddWarnPct) ? clrOrange : clrSilver;
      double buy, sell;
      m_view.SumLots(buy, sell);

      int y = 20;
      Label("l1", 10, y, StringFormat("HedgeEq EA  %s  %s", EnumToString(st),
            (m_paused ? "[PAUSED]" : "")), stClr);                       y += 16;
      Label("l2", 10, y, StringFormat("Trend %s:%s %s:%s %s:%s   Layer %d/%d",
            EnumToString(m_cfg.majorTF), TrendMark(m_trend.Major()),
            EnumToString(m_cfg.midTF),   TrendMark(m_trend.Middle()),
            EnumToString(m_cfg.entryTF), TrendMark(m_trend.Minor()),
            m_engine.Layer(), m_cfg.maxLayers), clrSilver);              y += 16;
      Label("l3", 10, y, StringFormat("Net %+.2f (B %.2f / S %.2f)  ML%% %s (%s)",
            m_view.NetLot(), buy, sell, mlStr,
            EnumToString(m_view.MLSafetyState())), clrSilver);           y += 16;
      Label("l4", 10, y, StringFormat("Eq %.2f  Bal %.2f  Float %+.2f  DD %.1f%%",
            m_view.EquityEA(), m_view.BalanceEA(), m_view.FloatingPL(), dd), ddClr);
      y += 20;

      // ปลด arm ของ CLOSE ALL เมื่อเกิน 3 วินาที
      if(m_closeArmTime > 0 && TimeCurrent() - m_closeArmTime > 3) m_closeArmTime = 0;
      Button("btnLock",  10,  y, 90, "LOCK NOW", clrDarkGoldenrod);
      Button("btnClose", 105, y, 100,
             (m_closeArmTime > 0 ? "CONFIRM?" : "CLOSE ALL"),
             (m_closeArmTime > 0 ? clrRed : clrFireBrick));
      Button("btnPause", 210, y, 90, (m_paused ? "RESUME" : "PAUSE NEW"), clrDarkSlateGray);
      ChartRedraw();
     }

   // คืน true เมื่อ event ถูกจัดการแล้ว — เรียกจาก OnChartEvent
   bool              OnClick(string objName)
     {
      if(StringFind(objName, m_prefix) != 0) return false;
      string btn = StringSubstr(objName, StringLen(m_prefix));
      if(btn == "btnLock")
        {
         m_engine.UserLock();
        }
      else if(btn == "btnClose")
        {
         if(m_closeArmTime > 0 && TimeCurrent() - m_closeArmTime <= 3)
           {
            m_closeArmTime = 0;
            m_engine.UserCloseAll();      // คลิกที่ 2 ภายใน 3 วิ → ปิดจริง
           }
         else
            m_closeArmTime = TimeCurrent();   // คลิกแรก: arm รอยืนยัน
        }
      else if(btn == "btnPause")
        {
         m_paused = !m_paused;
        }
      Update();
      return true;
     }

   void              Deinit(void)
     {
      ObjectsDeleteAll(0, m_prefix);
      ChartRedraw();
     }
  };

#endif // HEQ_PANEL_MQH



int g_pass = 0, g_fail = 0;

void AssertEq(string name, double got, double expected, double tol = 1e-9)
  {
   if(MathAbs(got - expected) <= tol)
     { g_pass++; PrintFormat("PASS  %s (%.6f)", name, got); }
   else
     { g_fail++; PrintFormat("FAIL  %s: got %.6f expected %.6f", name, got, expected); }
  }

void OnStart(void)
  {
   Print("=== HedgeEqEA unit tests ===");

   // --- CoverLotMath: ตัวอย่างหนังสือบทที่ 3 (point value 1 USD/จุด/lot)
   // Loss -226.25 + Profit อ้างอิง 50 → 276.25 / 5000 = 0.05525
   AssertEq("book example Model2", CoverLotMath(-226.25, 50.0, 5000, 1.0, COVER_TARGET), 0.05525);
   // Model 1 (prompt §4B): |Loss| / TP = 226.25 / 5000 = 0.04525
   AssertEq("Model1 simple",       CoverLotMath(-226.25, 50.0, 5000, 1.0, COVER_SIMPLE), 0.04525);
   // point value ≠ 1 (เช่น XAUUSD บางโบรก): หาร pvpl เพิ่ม
   AssertEq("pvpl scaling",        CoverLotMath(-226.25, 50.0, 5000, 10.0, COVER_TARGET), 0.005525);
   // ไม่มี loss → ไม่ต้อง cover
   AssertEq("no loss",             CoverLotMath(100.0, 50.0, 5000, 1.0, COVER_TARGET), 0.0);
   AssertEq("zero loss",           CoverLotMath(0.0, 50.0, 5000, 1.0, COVER_TARGET), 0.0);
   // input เสีย → 0 (กันหารศูนย์ตาม prompt §2)
   AssertEq("bad tpPts",           CoverLotMath(-100.0, 50.0, 0, 1.0, COVER_TARGET), 0.0);
   AssertEq("bad pvpl",            CoverLotMath(-100.0, 50.0, 5000, 0.0, COVER_TARGET), 0.0);

   // --- NormalizeLotUpPure: ปัดขึ้นตาม step + clamp (หนังสือ: 0.05525 → 0.06)
   AssertEq("round up book",  NormalizeLotUpPure(0.05525, 0.01, 0.01, 100.0), 0.06);
   AssertEq("exact multiple", NormalizeLotUpPure(0.06,    0.01, 0.01, 100.0), 0.06);
   AssertEq("clamp min",      NormalizeLotUpPure(0.001,   0.01, 0.01, 100.0), 0.01);
   AssertEq("clamp max",      NormalizeLotUpPure(150.0,   0.01, 0.01, 100.0), 100.0);
   AssertEq("step 0.1",       NormalizeLotUpPure(0.05525, 0.10, 0.10, 100.0), 0.10);

   // --- NormalizeLotDownPure: ปัดลงตาม step (ใช้กับ lot ที่การ์ดลดขนาด — ห้ามปัดขึ้นทะลุเพดาน)
   AssertEq("down 0.0333→0.03", NormalizeLotDownPure(0.0333, 0.01, 100.0), 0.03);
   AssertEq("down exact",       NormalizeLotDownPure(0.05,   0.01, 100.0), 0.05);
   AssertEq("down below min→0", NormalizeLotDownPure(0.004,  0.01, 100.0), 0.0);
   AssertEq("down clamp max",   NormalizeLotDownPure(150.0,  0.01, 100.0), 100.0);

   // --- MaxLotWithinNetCap: เพดาน lot ตาม NetLotMax (RiskManager rule 6)
   // ทิศเดียวกับ net: เหลือ netMax − |net|
   AssertEq("cap same dir",     MaxLotWithinNetCap(0.30, true, 0.3333), 0.0333, 1e-6);
   // cover ข้ามศูนย์ (net +0.01, ขาย): เปิดได้ถึง |net| + netMax = 0.04
   AssertEq("cap cross zero",   MaxLotWithinNetCap(0.01, false, 0.03), 0.04);
   // net ติดลบ + ขาย = ทิศเดียวกัน
   AssertEq("cap short same",   MaxLotWithinNetCap(-0.02, false, 0.05), 0.03);
   // net เกินเพดานอยู่แล้ว ทิศเดียวกัน → ติดลบ (caller veto)
   AssertEq("cap over neg",     MaxLotWithinNetCap(0.10, true, 0.05), -0.05);
   // net = 0: ทั้งสองทิศได้ netMax เต็ม
   AssertEq("cap net zero",     MaxLotWithinNetCap(0.0, true, 0.05), 0.05);

   // --- chain: สูตรหนังสือครบวงจร = CoverLotMath → NormalizeLotUp = 0.06
   AssertEq("book chain 0.06",
            NormalizeLotUpPure(CoverLotMath(-226.25, 50.0, 5000, 1.0, COVER_TARGET),
                               0.01, 0.01, 100.0),
            0.06);

   PrintFormat("=== ผล: %d passed, %d failed %s ===",
               g_pass, g_fail, (g_fail == 0 ? "— ALL PASSED" : "— มี FAIL ต้องแก้"));
  }
