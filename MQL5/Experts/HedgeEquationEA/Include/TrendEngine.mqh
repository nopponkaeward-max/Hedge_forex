//+------------------------------------------------------------------+
//| TrendEngine.mqh — MTF + MA 3 เส้น (5/21/50) ตามหนังสือบทที่ 8    |
//| DESIGN.md §5                                                     |
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
   int               m_flipCount;         // นับแท่งยืนยันการกลับทิศบน Middle TF
   ENUM_TREND        m_flipDir;

   int               MakeMA(ENUM_TIMEFRAMES tf, int period)
     {
      return iMA(_Symbol, tf, period, 0, m_cfg.maMethod, PRICE_CLOSE);
     }

   // อ่านเทรนด์จากแท่งปิดแล้ว (shift 1) — กติกาหนังสือ:
   // UP: MA5>MA21>MA50 และ Close>MA5 | DOWN: กลับกัน | อื่น ๆ: SIDEWAY
   ENUM_TREND        Read(int tfIdx, ENUM_TIMEFRAMES tf) const
     {
      double fast[1], mid[1], slow[1];
      if(CopyBuffer(m_h[tfIdx][0], 0, 1, 1, fast) != 1 ||
         CopyBuffer(m_h[tfIdx][1], 0, 1, 1, mid)  != 1 ||
         CopyBuffer(m_h[tfIdx][2], 0, 1, 1, slow) != 1)
         return TREND_SIDEWAY;
      double close = iClose(_Symbol, tf, 1);
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
      ENUM_TIMEFRAMES tfs[3];
      tfs[0] = cfg.majorTF; tfs[1] = cfg.midTF; tfs[2] = cfg.entryTF;
      int periods[3];
      periods[0] = cfg.maFast; periods[1] = cfg.maMid; periods[2] = cfg.maSlow;
      for(int t = 0; t < 3; t++)
         for(int p = 0; p < 3; p++)
           {
            m_h[t][p] = MakeMA(tfs[t], periods[p]);
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

   ENUM_TREND        Major(void)  const { return Read(0, m_cfg.majorTF); }
   ENUM_TREND        Middle(void) const { return Read(1, m_cfg.midTF);   }
   ENUM_TREND        Minor(void)  const { return Read(2, m_cfg.entryTF); }

   // สัญญาณเข้า FLAT→RIDE: Major กับ Middle ทิศเดียวกัน + Minor เพิ่งจัดเรียงทิศนั้น
   bool              EntrySignal(ENUM_TREND &dir)
     {
      ENUM_TREND maj = Major(), mid = Middle();
      if(maj == TREND_SIDEWAY || maj != mid) return false;
      if(Minor() != maj) return false;
      // TODO(phase-2): ตรวจความ "สด" ของการจัดเรียงบน entry TF ภายใน signalFreshBars แท่ง
      dir = maj;
      return true;
     }

   // สัญญาณกลับทิศ RIDE→COVER: Middle สวนทิศเดิมติดต่อกัน flipConfirmBars แท่ง
   // และ Major ไม่ค้านทิศใหม่ (Major == ทิศใหม่ หรือ SIDEWAY)
   bool              FlipConfirmed(ENUM_TREND current, ENUM_TREND &newDir)
     {
      ENUM_TREND opposite = (current == TREND_UP) ? TREND_DOWN : TREND_UP;
      // TODO(phase-3): เดินหน้าเฉพาะเมื่อแท่งใหม่ปิดบน Middle TF (ใช้ iTime เทียบแท่งล่าสุด)
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
         if(maj == opposite || maj == TREND_SIDEWAY) { newDir = opposite; return true; }
        }
      return false;
     }
  };

#endif // HEQ_TRENDENGINE_MQH
