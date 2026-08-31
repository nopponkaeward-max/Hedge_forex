//+------------------------------------------------------------------+
//| Panel.mqh — สรุปสถานะบน chart + ปุ่ม LOCK / CLOSE ALL / PAUSE    |
//| DESIGN §14 — CLOSE ALL ต้องยืนยัน 2 คลิกใน 3 วินาที               |
//+------------------------------------------------------------------+
#ifndef HEQ_PANEL_MQH
#define HEQ_PANEL_MQH

#include "Config.mqh"
#include "AccountView.mqh"
#include "TrendEngine.mqh"
#include "HedgeEngine.mqh"

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
