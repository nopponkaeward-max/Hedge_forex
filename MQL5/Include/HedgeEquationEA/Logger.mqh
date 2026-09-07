//+------------------------------------------------------------------+
//| Logger.mqh — CSV log ต่อเดือน + push notification (DESIGN §14)   |
//| deliverables ของ prompt: log Balance/Equity/ML%/Layers/State ทุก step |
//+------------------------------------------------------------------+
#ifndef HEQ_LOGGER_MQH
#define HEQ_LOGGER_MQH

#include "Config.mqh"
#include "AccountView.mqh"
#include "TrendEngine.mqh"

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
