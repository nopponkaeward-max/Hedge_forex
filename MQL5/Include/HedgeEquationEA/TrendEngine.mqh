//+------------------------------------------------------------------+
//| TrendEngine.mqh — MTF + MA 3 เส้น (5/21/50) ตามหนังสือบทที่ 8    |
//| DESIGN.md §5 | Role & Prompt §3                                  |
//+------------------------------------------------------------------+
#ifndef HEQ_TRENDENGINE_MQH
#define HEQ_TRENDENGINE_MQH

#include "Config.mqh"

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
