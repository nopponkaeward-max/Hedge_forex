# วิเคราะห์เฟรมเวิร์ก Multi-Currency Expert Advisor (Adwizard)

> ที่มา: ซีรีส์บทความ **"Developing a Multi-Currency Expert Advisor"** โดย Yuriy Bykov (antekov) บน mql5.com
> โฟลเดอร์นี้คือ snapshot จาก **Part 30/32** ([mql5.com/en/articles/19684](https://www.mql5.com/en/articles/19684), เผยแพร่ 2026-09-16)
> เพิ่มเข้า repo เป็น **ไฟล์อ้างอิง/ศึกษา** — เป็นคนละระบบกับ HedgeEquationEA ที่เราพัฒนาใน `MQL5/`
>
> **สงวนลิขสิทธิ์:** โค้ดทั้งหมดเป็นของ Yuriy Bykov (ประกาศ `#property copyright` ในทุกไฟล์) — ใช้เพื่อศึกษา ไม่ใช่ผลงานของโปรเจกต์นี้
> **การเข้ารหัสไฟล์:** ไฟล์ส่วนใหญ่เป็น **UTF-16LE** ตามมาตรฐาน MetaEditor (บางไฟล์ UTF-8) — เปิดใน MetaEditor ได้ปกติ

---

## 1. ภาพรวม — เฟรมเวิร์กนี้ทำอะไร

Adwizard เป็น **ไลบรารีสำหรับสร้าง EA แบบหลายสกุลเงิน/หลายกลยุทธ์** ที่แยกชัดเจนระหว่าง:

- **โค้ดไลบรารี (Adwizard/)** — โครงสร้างพื้นฐานที่ไม่เปลี่ยน: การจัดการ virtual position, money management, risk manager, optimization pipeline, ฐานข้อมูล
- **โค้ดโปรเจกต์ (SimpleCandles/)** — เฉพาะกลยุทธ์: ตรรกะเข้าเทรด + ไฟล์ .mq5 ที่ประกอบ EA จริง

ปรัชญาหลัก: **รวมหลาย instance ของกลยุทธ์เดียว (ต่างพารามิเตอร์/สกุลเงิน/TF) เข้าเป็นพอร์ตเดียว** แล้วปรับขนาด lot ให้ drawdown รวมอยู่ในกรอบที่ต้องการ — กระจายความเสี่ยงด้วยจำนวน instance แทนการพึ่งกลยุทธ์เดียว

เทียบกับ HedgeEquationEA ของเรา: คนละแนวคิดโดยสิ้นเชิง — ของเราคือ hedge/recovery กลยุทธ์เดียว, ของ Bykov คือ **portfolio ของหลายกลยุทธ์ที่ optimize + normalize อัตโนมัติ**

---

## 2. เสาหลัก 4 อย่างของสถาปัตยกรรม

### 2.1 CFactorable — สร้าง object จาก "string" (หัวใจของทั้งเฟรมเวิร์ก)

`Base/Factorable.mqh` (482 บรรทัด) คือกลไกที่ทำให้ทุกอย่างเป็นไปได้ ทุก object (กลยุทธ์, advisor, receiver) สร้างจาก **initialization string** เช่น:

```
class CSimpleCandlesStrategy("EURUSD",16408,6,0,25000,3630,9,100)
```

- macro `STATIC_CONSTRUCTOR` / `REGISTER_FACTORABLE_CLASS` / `NEW()` / `CREATE()` = ระบบ factory + registry
- `operator~()` แปลง object กลับเป็น string (serialize) — ใช้บันทึกสถานะและประกอบกลุ่มกลยุทธ์
- มี parser ในตัว: `ReadString/ReadLong/ReadDouble/ReadObject/ReadArrayString` อ่านค่าจาก string แบบ recursive (รองรับ object ซ้อน object)
- `Hash()` = MD5 ของ init string → ใช้เป็น key เก็บ/โหลดสถานะ

**ทำไมสำคัญ:** กลุ่มกลยุทธ์ 8–16 ตัวถูกอธิบายด้วย string เดียว เก็บลง DB ได้ ส่งเข้า EA ได้ผ่าน input เดียว — นี่คือกาวที่เชื่อม optimization pipeline กับ EA จริง

### 2.2 Virtual Positions — แยก "สัญญาณกลยุทธ์" ออกจาก "ออเดอร์จริง"

- `Virtual/VirtualOrder.mqh` (636) — virtual position: กลยุทธ์ "เปิด/ปิด" ออเดอร์เสมือน ไม่ใช่ออเดอร์ตลาดจริง
- `Virtual/VirtualReceiver.mqh` + `VirtualSymbolReceiver.mqh` — **netting engine**: รวม virtual order ของทุกกลยุทธ์ต่อ symbol แล้วเปิด position จริง "สุทธิ" ตัวเดียว → ลดจำนวนออเดอร์จริง, ประหยัด margin, กลยุทธ์ที่สวนกันหักลบกันเอง
- `Virtual/VirtualStrategy.mqh` — base class กลยุทธ์: ถือ `m_orders[]` (array ของ virtual order), มี `m_fittedBalance` (balance นอร์มัลไลซ์) + `Scale()` สำหรับปรับขนาด
- `Virtual/VirtualAdvisor.mqh` (690) — EA orchestrator: ถือกลุ่มกลยุทธ์, เรียก Tick, save/load state, จัดการ receiver/risk/close manager

### 2.3 Money & Risk Management (แยก 3 ชั้น)

- `Virtual/Money.mqh` — สูตร scaling หัวใจ:
  ```
  Coeff = totalBalance × depoPart / fittedBalance
  Volume จริง = virtualOrder.Volume() × Coeff
  ```
  แต่ละกลยุทธ์มี "fitted balance" จาก optimization (balance ที่ทำให้ DD = เป้า) → ปรับ lot ตามทุนจริงอัตโนมัติ
- `Virtual/VirtualRiskManager.mqh` (618) — จำกัดความเสี่ยง 3 ระดับ: **daily loss / overall loss / overall profit** พร้อมโหมดคำนวณหลายแบบ (% ของ base balance, % ของ high-water balance ฯลฯ) + waiting time สำหรับหาจังหวะเข้าใหม่ตอน drawdown
- `Virtual/VirtualCloseManager.mqh` (286) — ปิดทั้งกลุ่มเมื่อถึง loss limit หรือ profit target มี state machine: `CM_STATE_OK / LOSS / PROFIT / TRAIL_PROFIT` (มี profit trailing)

### 2.4 Optimization Pipeline อัตโนมัติ 3 ขั้น + ฐานข้อมูล SQLite

- `Database/` — 3 schema: `db.opt` (ผล optimization: jobs/tasks/passes + สถิติเต็ม ~40 คอลัมน์), `db.adv` (พารามิเตอร์กลุ่มสำหรับ EA จริง), `db.cut` (ผลบีบอัด)
- `Experts/Stage1/2/3.mqh` + `Optimization/`:
  - **Stage 1** — optimize กลยุทธ์ทีละ instance บนหลายชุดพารามิเตอร์ กรองด้วย normalized profit
  - **Stage 2** — เลือกกลุ่ม 8–16 instance ที่ perform ดีที่สุดร่วมกัน
  - **Stage 3** — รวมทุกกลุ่มจาก Stage 2 เป็นชุดสุดท้าย normalize ขนาด position
- `Experts/CreateProject.mqh` + `SimpleCandles/Optimization/CreateProject.196840X.mq5` — เติม DB ด้วย config/jobs/tasks ของโปรเจกต์ (สังเกต 3 ไฟล์ = 3 บัญชี/แมจิกต่างกัน: 1968401/02/03)
- `Utils/MTTester.mqh` (1861) — wrapper ควบคุม Strategy Tester แบบ programmatic (รัน optimization job อัตโนมัติ)

---

## 3. กลยุทธ์ตัวอย่าง: SimpleCandles

`SimpleCandles/Strategies/SimpleCandlesStrategy.mqh` — ตรรกะเรียบง่ายมาก (ตั้งใจ เพื่อโชว์ว่าพลังมาจากการรวม instance):

- **สัญญาณ:** ดูแท่งปิด `signalSeqLen` แท่งล่าสุด ถ้าไปทางเดียวกันหมด → เปิด **สวนทาง** (แท่งขึ้นติดกัน → SELL, แท่งลงติดกัน → BUY) — เป็น mean-reversion
- **SL/TP:** ถ้า `periodATR=0` ใช้ระยะเป็น points ตรง ๆ; ถ้า >0 ใช้ ATR รายวัน × ตัวคูณ
- **กรอง:** จำนวน position เปิดพร้อมกัน ≤ `maxCountOfOrders`, spread ≤ `maxSpread`
- **ปิด:** ด้วย SL/TP เท่านั้น (ไม่มีเงื่อนไขปิดอื่นในกลยุทธ์ — การปิดกลุ่มเป็นหน้าที่ CloseManager/RiskManager)

ไฟล์ EA จริง `SimpleCandles-MQ-{100K-10, 200K-07, 300K-05}.mq5` = 3 โปรไฟล์ทุน/ความเสี่ยงต่างกัน (100K@10%, 200K@7%, 300K@5%) แต่ละไฟล์ดึงกลุ่มกลยุทธ์จาก DB ผ่าน `groupId_` แล้วรันด้วย money/risk/close manager ชุดเดียวกัน

---

## 4. โครงสร้างไฟล์ (56 ไฟล์)

```
Multi-Currency Expert Advisor/
├── Adwizard/                    ← ไลบรารี (ไม่แก้)
│   ├── Base/         Factorable, FactorableCreator, Advisor, Strategy, Receiver, Interface
│   ├── Virtual/      VirtualAdvisor, VirtualStrategy, VirtualOrder, VirtualReceiver,
│   │                 VirtualSymbolReceiver, VirtualRiskManager, VirtualCloseManager,
│   │                 Money, TesterHandler, VirtualChartOrder, VirtualStrategyGroup, ...
│   ├── Database/     Database, Storage, db.{opt,adv,cut}.schema.sql
│   ├── Experts/      Expert (template), CreateProject, Optimization, Stage1/2/3
│   ├── Optimization/ Optimizer, OptimizerTask, Optimization{Project,Job,Stage,Task}
│   └── Utils/        MTTester, Dialog, ConsoleDialog, Trailing, SymbolsMonitor,
│                     NewBarEvent, ExpertHistory, Macros
└── SimpleCandles/               ← โปรเจกต์ (กลยุทธ์)
    ├── Strategies/   SimpleCandlesStrategy.mqh
    ├── Optimization/ CreateProject.196840{1,2,3}.mq5, Stage1/2/3.mq5, Optimization.mq5
    └── SimpleCandles-MQ-{100K-10,200K-07,300K-05}.mq5   ← EA จริง 3 โปรไฟล์
```

---

## 5. บทเรียนที่นำมาใช้กับ HedgeEquationEA ได้

แนวคิดจากเฟรมเวิร์กนี้ที่คุ้มค่าพิจารณานำมาปรับใช้ (ถ้าจะยกระดับ EA ของเรา):

| แนวคิด Adwizard | นำมาใช้กับ HedgeEquationEA อย่างไร |
|-----------------|-----------------------------------|
| **Virtual position + netting** | รันหลาย hedge instance (หลาย symbol/TF) รวม netting เป็น position จริง ลด margin |
| **Fitted balance / auto-scaling** | ปรับ `InpBaseLot` อัตโนมัติตามทุนจริง แทนตั้งค่าคงที่ (เราตั้งเองใน RISK.md ว่าเสี่ยง config ผิด) |
| **Optimization pipeline + DB** | เก็บผล backtest หลายชุดลง SQLite แล้วเลือกกลุ่มพารามิเตอร์อัตโนมัติ (ตอนนี้เราทำมือใน TESTING.md) |
| **Factorable (object จาก string)** | เก็บ/โหลดสถานะรอบ hedge ที่ซับซ้อนได้ยืดหยุ่นกว่าไฟล์ key=value ของ StateStore |
| **แยก daily/overall loss + profit trailing** | RiskManager ของเรามีแค่ DD รวม — เพิ่ม daily loss limit + profit trailing ได้ |

> ⚠️ แต่ระวัง: เฟรมเวิร์กนี้ใหญ่และซับซ้อนมาก (13,000+ บรรทัด) — เหมาะกับพอร์ตหลายกลยุทธ์ ไม่จำเป็นสำหรับ EA กลยุทธ์เดียวอย่างของเรา นำมา **เฉพาะแนวคิด** ไม่ใช่ยกโค้ดมาทั้งก้อน

---

## 6. หมายเหตุลิขสิทธิ์และการใช้งาน

- โค้ดนี้เป็นของ **Yuriy Bykov** เผยแพร่ประกอบบทความเพื่อการศึกษา — เก็บไว้ใน repo เป็นเอกสารอ้างอิงเท่านั้น
- ถ้าจะนำแนวคิดไปใช้จริง ควรอ่านบทความครบทั้งซีรีส์ (Part 1–32) เพราะแต่ละคลาสถูกอธิบายทีละส่วน
- ไม่ควร merge โค้ดนี้เข้า HedgeEquationEA โดยตรง (คนละสถาปัตยกรรม, คนละลิขสิทธิ์)
