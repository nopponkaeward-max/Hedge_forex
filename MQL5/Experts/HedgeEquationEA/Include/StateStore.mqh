//+------------------------------------------------------------------+
//| StateStore.mqh — เก็บ/กู้ตัวแปรที่อ่านจาก positions ไม่ได้        |
//| (layer, peakEquity, closedPL, initialCapital) — DESIGN §13      |
//| รูปแบบไฟล์: key=value ต่อบรรทัด ใน MQL5/Files                    |
//+------------------------------------------------------------------+
#ifndef HEQ_STATESTORE_MQH
#define HEQ_STATESTORE_MQH

#include "Config.mqh"

struct SPersistState
  {
   int               layer;
   double            peakEquity;
   double            closedPL;
   double            initialCapital;
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
        }
      FileClose(h);
      return true;
     }

   void              Clear(void) { if(FileIsExist(m_file)) FileDelete(m_file); }
  };

#endif // HEQ_STATESTORE_MQH
