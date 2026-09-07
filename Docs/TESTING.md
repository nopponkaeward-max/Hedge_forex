# คู่มือทดสอบและ Optimize — Hedge Equation EA (เฟส 6)

ทำตามลำดับ ห้ามข้ามขั้น — แต่ละขั้นมีเกณฑ์ "ผ่าน" ชัดเจน ไม่ผ่านให้หยุดแก้ก่อน

## ขั้น 0: ติดตั้งไฟล์ + Compile + Unit tests (ทำครั้งแรกและทุกครั้งที่แก้โค้ด)

**0.1 วางไฟล์ — วิธีง่าย (แนะนำ): ใช้ไฟล์ all-in-one ไฟล์เดียว**

| จาก repo | ไปที่ Data Folder (`MT5 → File → Open Data Folder → MQL5\`) |
|----------|--------------------------------------------------------------|
| `MQL5/Experts/HedgeEquationEA_AllInOne.mq5` | `MQL5\Experts\` (วางที่ไหน/เปลี่ยนชื่อก็ได้) |
| `MQL5/Scripts/HedgeEqEA_Tests_AllInOne.mq5` | `MQL5\Scripts\` |
| `MQL5/Presets/*.set` | `MQL5\Presets\` |

ไฟล์ all-in-one รวมโค้ดทุกโมดูลไว้แล้ว ไม่ต้อง copy โฟลเดอร์ Include ใด ๆ — compile ได้ทันที
(สร้างจากไฟล์ต้นทางด้วย `python3 tools/build_single.py` — ถ้าแก้โค้ดต้นทาง ให้ build ใหม่)

**0.1-ทางเลือก: แบบแยกโมดูล (สำหรับพัฒนาต่อ)** — copy จาก repo ตามนี้:

| จาก repo | ไปที่ Data Folder | หมายเหตุ |
|----------|-------------------|----------|
| `MQL5/Include/HedgeEquationEA/` (ทั้งโฟลเดอร์ 12 ไฟล์ .mqh) | `MQL5\Include\HedgeEquationEA\` | **บังคับ** — include ทั้งหมดอ้างแบบ `<HedgeEquationEA/...>` จากที่นี่ |
| `MQL5/Experts/HedgeEquationEA/HedgeEquationEA.mq5` | `MQL5\Experts\` (ที่ไหนก็ได้ใต้ Experts, เปลี่ยนชื่อไฟล์ได้) | ตัว EA |
| `MQL5/Scripts/HedgeEqEA_Tests.mq5` | `MQL5\Scripts\` | unit tests |
| `MQL5/Presets/*.set` | `MQL5\Presets\` | preset สำหรับ tester |

> ถ้าเจอ `file '...Config.mqh' not found` แปลว่าโฟลเดอร์ `Include\HedgeEquationEA` ยังไม่อยู่ในตำแหน่งข้างบน

**0.2 Compile:** MetaEditor → เปิดไฟล์ EA → **F7**
   - เกณฑ์ผ่าน: 0 errors (warnings อ่านทุกตัวแล้วตัดสินใจ)

**0.3 Unit tests:** Compile `HedgeEqEA_Tests.mq5` แล้วลากลง chart ใดก็ได้
   - เกณฑ์ผ่าน: Experts log แสดง **ALL PASSED** (22 assertions)

## ขั้น 1: Smoke test ใน Strategy Tester

- Settings: Symbol XAUUSD, TF M5, โหมด **Every tick based on real ticks**, ช่วง 3 เดือนล่าสุด
- โหลด preset `MQL5/Presets/HedgeEqEA_XAUUSD_conservative.set`
- เปิด Visual mode ดูพฤติกรรม: เปิดไม้ตามเทรนด์, cover เมื่อ flip, ล็อคเมื่อ DD/S-R break
- เกณฑ์ผ่าน: ไม่มี error ใน journal (INVALID_VOLUME, array out of range ฯลฯ),
  ทุก state transition มีเหตุผลใน log, รอบเทรดจบเองได้อย่างน้อย 1 รอบ

## ขั้น 2: Backtest เต็ม (ต่อ symbol)

| รายการ | ค่า |
|--------|-----|
| ช่วงข้อมูล | ≥ 2 ปี (ครอบทั้งปีเทรนด์แรงและปี sideway) |
| โหมด | Every tick based on real ticks + spread จริง |
| Deposit | ตาม preset (2,000 XAU / 1,000 GBP), Leverage 1:2000 (หรือของโบรกจริง) |
| ชุดทดสอบบังคับ | ช่วง NFP/FOMC, เปิดตลาดจันทร์หลัง gap ใหญ่, ช่วง sideway ยาว |

**เกณฑ์ผ่าน (จาก DESIGN §15 + RISK.md):**
- Max Equity DD < 30% ตลอดช่วง
- `locked=` ใน OnTester log: เข้า LOCKED ≤ 2 ครั้ง/ปี และทุกครั้งคลายล็อคได้ (ไม่จบ backtest ใน LOCKED)
- `minML=` ไม่ต่ำกว่า `InpMLLockPct` (500)
- กำไรสุทธิ > 0 **หลังหัก swap** (ดูรายงาน swap แยก — ระบบถือไม้ข้ามคืนเยอะ)
- ไม่มีรอบที่ชน `InpMaxLayers` แล้วค้าง

## ขั้น 3: Optimization

- Criterion: **Custom max** (EA มี `OnTester()` แล้ว: Profit/MaxDD × penalty เมื่อ LOCKED บ่อย/ML หลุด)
- พารามิเตอร์ที่เปิด optimize (ช่วงอยู่ใน .set แล้ว): `InpCoverTPPts`, `InpFlipConfirmBars`,
  `InpPyramidStepPts`, `InpMLTargetPct`
- **ห้าม** optimize `InpDDLockPct`/`InpMaxLayers` ให้หลวมขึ้นเพื่อไล่กำไร — สองตัวนี้คือเพดานความเสี่ยง ไม่ใช่ตัวจูน
- Walk-forward: optimize 12 เดือน → ทดสอบนอกตัวอย่าง 3 เดือนถัดไป → เลื่อนหน้าต่าง 3 เดือน ทำให้ครบช่วงข้อมูล
  - เกณฑ์ผ่าน: ชุดพารามิเตอร์ที่ชนะ in-sample ยังกำไร (score > 0) ใน out-of-sample ≥ 70% ของหน้าต่าง

## ขั้น 4: Demo forward (≥ 4 สัปดาห์)

Checklist ก่อนเริ่ม:
- [ ] โบรก: `Margin Hedge = 0` ใน symbol specification (EA เตือนตอน OnInit ถ้าไม่ใช่ — **ห้ามใช้ต่อ**)
- [ ] Leverage บัญชี ≥ 1:500 (EA เตือนถ้าต่ำกว่า `InpTargetLeverage`)
- [ ] ตั้ง MetaQuotes ID ใน terminal → ทดสอบ push notification (ปุ่ม LOCK NOW แล้วดูมือถือ)
- [ ] Algo Trading เปิด + EA ยิ้ม

ระหว่างรัน:
- คร่อมข่าวใหญ่อย่างน้อย 1 รอบ (NFP/FOMC) — ยืนยัน NewsFilter บล็อกไม้ใหม่จริง (ดู rule 3 ใน log)
- ศุกร์เย็น: ยืนยันพฤติกรรมตาม `InpFridayMode` (BLOCK_NEW: ไม่มีไม้ใหม่ / LOCK: เข้า LOCKED ไม่นับ layer)
- **ทดสอบ restart กลางรอบ**: ปิด terminal ขณะมี positions → เปิดใหม่ → ตรวจ log
  `state restored:` ค่า layer/cycleBase/recovery ตรงกับก่อนปิด
- เทียบ CSV log (`MQL5/Files/HedgeEqEA_<magic>_<yyyymm>.csv`) กับ backtest ช่วงเดียวกัน

เกณฑ์ผ่าน: พฤติกรรมตรง backtest, ไม่มี zerohedge-fail, ไม่มี order error สะสม

## ขั้น 5: เงินจริง (ถ้าจะไป)

- เริ่มด้วยทุนที่**พร้อมแช่แข็ง 30% ได้เป็นเดือน**เท่านั้น (ธรรมชาติของระบบ — RISK.md §1)
- ใช้ preset conservative (MaxLayers=1, FridayMode=LOCK, HardCut 50%)
- สัปดาห์แรก: `InpBaseLot` ต่ำสุด + เฝ้า panel ทุกวัน
- ทบทวน CSV ทุกสัปดาห์: จำนวน veto ต่อ rule, ครั้งที่เข้า LOCKED, swap สะสม
