//+------------------------------------------------------------------+
//| HedgeEqEA_Tests.mq5 — unit tests ของ pure functions (DESIGN §15.1)|
//| ลากลง chart ใดก็ได้ → ดูผลใน Experts log (ต้องได้ ALL PASSED)     |
//+------------------------------------------------------------------+
#property strict

#include <HedgeEquationEA/HedgeEngine.mqh>

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
