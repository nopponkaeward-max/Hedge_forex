//+------------------------------------------------------------------+
//| EquityTP.mqh — ระบบปิดกำไรด้วย Equity (หนังสือบทที่ 8)           |
//| สูตร: EQUITY >= BALANCE หรือ EQUITY > ทุนแรกเริ่ม (DESIGN §2.4, §8)|
//+------------------------------------------------------------------+
#ifndef HEQ_EQUITYTP_MQH
#define HEQ_EQUITYTP_MQH

#include "Config.mqh"
#include "AccountView.mqh"

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

   bool              ShouldCloseAll(string &reason)
     {
      if(m_view.OpenPositions() == 0) return false;
      double eq  = m_view.EquityEA();
      double bal = m_view.BalanceEA();
      double cap = m_view.InitialCapital();

      // กติกา 1 (หนังสือ): Equity ≥ Balance — ใช้เมื่อ Balance โตจากการเก็บกำไรระหว่างทางแล้ว
      //   เงื่อนไข bal > cap กันการปิดรวบตอนเพิ่งเปิดพอร์ต (Equity==Balance ตอนยังไม่มีกำไรจริง)
      if(m_cfg.useBalanceRule && bal > cap && eq >= bal)
        {
         reason = StringFormat("EquityTP: eq %.2f ≥ bal %.2f (ตัวอย่างหนังสือ ทุน 100→ปิดที่ eq 130)", eq, bal);
         return true;
        }
      // กติกา 2: Equity > ทุนแรกเริ่ม + เป้ากำไรขั้นต่ำของรอบ
      if(eq >= cap + m_cfg.cycleProfitMoney)
        {
         reason = StringFormat("EquityTP: eq %.2f ≥ cap %.2f + target %.2f", eq, cap, m_cfg.cycleProfitMoney);
         return true;
        }
      return false;
     }
  };

#endif // HEQ_EQUITYTP_MQH
