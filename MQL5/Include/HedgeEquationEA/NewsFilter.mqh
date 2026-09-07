//+------------------------------------------------------------------+
//| NewsFilter.mqh — การ์ดข่าวแรง / rollover / วันศุกร์ (DESIGN §7)  |
//| ปิดความเสี่ยง S2 (gap สุดสัปดาห์) และช่วงข่าว/สภาพคล่องต่ำ        |
//+------------------------------------------------------------------+
#ifndef HEQ_NEWSFILTER_MQH
#define HEQ_NEWSFILTER_MQH

#include "Config.mqh"

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
