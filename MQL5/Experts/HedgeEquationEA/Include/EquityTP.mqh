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
