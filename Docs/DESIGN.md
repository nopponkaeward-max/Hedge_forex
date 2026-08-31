# เอกสารออกแบบ (Design Document) — "Hedge Equation EA" สำหรับ MQL5

EA อัตโนมัติบน MetaTrader 5 ที่ implement ระบบเทรดจากหนังสือ
**"เทคนิค Forex แก้พอร์ต Hedge ให้ได้กำไรด้วย สมการ Hedge" (สกี เกิดนิยม / โค้ชป้อม, Thai Forex Hedging, ISBN 978-616-588-579-9)**
ตามไฟล์สรุปเนื้อหาที่ผู้ใช้แนบมา (`02137171-smarnhedgeebook.txt`)

> **หมายเหตุแหล่งข้อมูล (ตรวจสอบ 2026-08-31):**
> - Repo `nopponkaeward-max/Hedge_forex` ก่อนหน้านี้ว่างเปล่า — **ไม่พบไฟล์ role และ prompt** ที่อ้างถึง หากมีไฟล์ดังกล่าวให้ push ขึ้น repo แล้ว design นี้จะถูกปรับตามได้
> - พบ FOREX-TRADE JOURNAL ใน Notion ของผู้ใช้ (XAUUSD/GBPUSD: 5-min golden cross, Fib 0.5 retest, 15-min support, CHOCH) — ใช้เป็นบริบทเสริมเรื่อง symbol และ TF ที่ผู้ใช้เทรดจริง
> - แกนกลยุทธ์ทั้งหมดในเอกสารนี้อ้างอิง **ไฟล์แนบ (หนังสือสมการเฮดจ์)** เป็นหลัก

> ⚠️ **คำเตือนความเสี่ยง:** ระบบ hedge ถือไม้ขาดทุนลอยตัว (ไม่ตัดขาดทุนทันที) มีความเสี่ยง drawdown สะสมสูง และอ่อนไหวต่อ spread ถ่าง/swap ข้ามคืนมาก (โดยเฉพาะ XAUUSD ช่วง rollover ตี 4–5 เวลาไทย ตามที่หนังสือระบุ) ต้อง backtest + demo forward test ก่อนใช้เงินจริงเสมอ

---

## สารบัญ

1. หลักการของระบบจากหนังสือ → กติกาที่ EA ต้องทำ
2. สมการ/สูตรคำนวณทั้งหมด (พร้อมที่มาในหนังสือ)
3. สถาปัตยกรรมซอฟต์แวร์และโมดูล
4. State Machine ของวงจรเทรด
5. Trend Engine (สามเหลี่ยมความปลอดภัยเฮดจ์ ด้านที่ 2)
6. Hedge Engine — Cover Loss Hedge และการนับ Layer
7. Risk Manager — ML%, Drawdown, Layer cap, News
8. Equity Take Profit Engine
9. Zero Hedge Margin (โหมดล็อคพอร์ต)
10. Input Parameters ฉบับเต็ม
11. รายละเอียดคลาสและไฟล์
12. ประเด็น implementation เฉพาะของ MQL5
13. การกู้สถานะหลัง restart
14. Panel และ Logging
15. แผนการทดสอบ (Backtest / Optimization / Forward)
16. Mapping เทคนิค 1–8 ของหนังสือ → ฟีเจอร์ EA
17. Roadmap การพัฒนา
18. คำถามเปิดถึงผู้ใช้

---

## 1. หลักการของระบบจากหนังสือ → กติกาที่ EA ต้องทำ

หนังสือสรุประบบเป็น "สามเหลี่ยมความปลอดภัยเฮดจ์" (Triangle Safety Hedge) 3 ด้าน ซึ่งแปลงเป็นกติกาเชิงโปรแกรมได้ดังนี้:

| ด้าน | หลักการในหนังสือ | กติกาที่ EA บังคับใช้ |
|------|------------------|----------------------|
| 1 | ใช้ **ผลรวมผลต่างขนาดลอท** (net lot = ΣBuy − ΣSell) เป็นตัวคุมความเสี่ยง/การเติบโต | ทุกการเปิด/ปิดออเดอร์ต้องคำนวณ net lot ใหม่ และห้ามเกินเพดานที่ผูกกับ ML% เป้าหมาย |
| 2 | **เทรดฝั่งเดียวกับเทรนด์เสมอ** — ฝั่งที่ lot หนักกว่าต้องเป็นฝั่งเทรนด์ | Trend Engine ตัดสินทิศ; ถ้า net lot สวนเทรนด์ที่ยืนยันแล้ว → เข้าโหมดแก้ไม้ (Cover Loss Hedge) |
| 3 | รักษา **Margin Level (%)** ให้สูงตลอด (หนังสือ: >5,000–10,000% = ปลอดภัยมาก) | ก่อนเปิดทุกออเดอร์ simulate ML% หลังเปิด; ต่ำกว่าเกณฑ์ → ไม่เปิด / ลด lot / เข้า Zero Hedge |

กติกาประกอบที่หนังสือระบุชัด:

- **ไม่ใช่ Martingale** — lot แก้ไม้มาจากสูตร Cover Loss (ขนาด "พอดี ไม่ขาด ไม่เกิน") ไม่ใช่การเบิ้ล lot
- **Drawdown ควบคุมไม่เกิน 30%** ของทุน
- **Layer Hedge จำกัด 1–2 ชั้น** (นับหนึ่งชั้นเมื่อเกิด Zero Hedge Margin หนึ่งรอบ)
- **ปิดกำไรด้วยระบบ Equity** (Equity TP): เมื่อ `Equity ≥ Balance` หรือ `Equity > ทุนแรกเริ่ม` ให้ปิดรวบทุกออเดอร์ทันที แม้บางไม้ยังติดลบ
- ใช้ **Economic Calendar** เลี่ยงช่วงข่าวแรง และเลือกคู่เงินสภาพคล่องสูง (EUR/USD, USD/JPY, GBP/USD, XAU/USD) เลี่ยง exotic
- ระวังช่วง **Rollover** (สเปรดถ่าง, ตี 4–5 เวลาไทย)
- เปิด **Leverage สูงสุด** ที่โบรกให้ (ลดการใช้ margin ต่อ lot) — เป็นคำแนะนำระดับบัญชี EA ทำได้แค่ตรวจและเตือน

---

## 2. สมการ/สูตรคำนวณทั้งหมด

### 2.1 Margin Level (หัวใจของระบบ — บทที่ 2)

```
ML% = (Equity / Margin) × 100
```

- ใน MQL5: `AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)` แต่ค่านี้เป็นของ **ทั้งบัญชี** — ถ้าผู้ใช้รัน EA หลายตัว/เทรดมือร่วมด้วย ต้องมีโหมดคำนวณ ML% "เสมือน" เฉพาะ positions ของ EA (Equity ส่วนของ EA = allocated capital + basket P/L, Margin ส่วนของ EA จาก `OrderCalcMargin` ของ net lot)
- กรณี Fully Hedge (net lot = 0) โบรกส่วนใหญ่คิด margin = 0 → ML% ไม่แสดงค่า (หารด้วยศูนย์) — โค้ดต้องกันกรณีนี้ทุกจุด

### 2.2 เพดาน net lot จาก ML% เป้าหมาย (กรณี D ในหนังสือ)

ผู้ใช้กำหนด ML% ขั้นต่ำที่ยอมรับได้ (เช่น 3,000%) → EA คำนวณย้อนกลับ:

```
MarginBudget = Equity × 100 / ML_target
NetLotMax    = MarginBudget / MarginPerLot        // MarginPerLot จาก OrderCalcMargin(symbol, 1.0 lot)
```

ทุกครั้งที่จะเปิดออเดอร์ฝั่งที่ทำให้ |net lot| เพิ่มขึ้น ต้องผ่านเงื่อนไข `|net_lot_after| ≤ NetLotMax`

### 2.3 สูตร Lot Size Hedge (Cover Loss — บทที่ 3)

เมื่อพอร์ตติดลบและเทรนด์ยืนยันกลับทิศ ให้เปิดไม้แก้ฝั่งใหม่ (ฝั่งเดียวกับเทรนด์ใหม่) ขนาด:

```
CoverAmount  = |FloatingLoss ของ basket| + ProfitTarget          // หน่วยเงิน
LotHedge     = CoverAmount / (TP_points × PointValuePerLot)
PointValuePerLot = SYMBOL_TRADE_TICK_VALUE × (_Point / SYMBOL_TRADE_TICK_SIZE)
```

ตัวอย่างจากหนังสือ: Loss ลอยตัว −226.25, Profit อ้างอิง 50, ระยะ TP แก้ไม้ 5,000 จุด → `276.25 / 5000 = 0.05525 → ปัดขึ้น 0.06 lot` ✔ (ตัวอย่างนี้ point value = 1 USD/จุด/lot)

กติกาเพิ่มเติมของ EA:
- ปัด lot **ขึ้น** ตาม `SYMBOL_VOLUME_STEP` (ตามหนังสือปัด 0.05525 → 0.06)
- ก่อนเปิด ตรวจ §2.2 — ถ้า LotHedge ทำให้ ML% หลุดเกณฑ์ → ลดเหลือเพดาน แล้วถ้ายังไม่พอ cover → เข้าโหมด Zero Hedge Margin แทน (ตามเทคนิค 6)
- `ProfitTarget` และ `TP_points` เป็น input; ถ้าเปิด `InpIncludeCosts` ให้บวก swap+commission สะสมของ basket เข้า CoverAmount

### 2.4 Equity Take Profit (บทที่ 8)

```
ปิดรวบทุกออเดอร์เมื่อ:  Equity_EA ≥ max( Balance_EA , InitialCapital_EA + InpCycleProfitMoney )
```

- `Equity_EA / Balance_EA` = ค่าที่คิดเฉพาะส่วนของ EA (ดู §2.1) — มีโหมด `WHOLE_ACCOUNT` สำหรับคนรัน EA ตัวเดียวทั้งพอร์ต ให้ใช้ค่าบัญชีตรง ๆ ตามหนังสือ
- เช็คทุก tick ไม่ผูกกับ state ใด — เป็นทางปิดจบวงจรหลักของระบบ

### 2.5 Drawdown Guard (บทที่ 4)

```
DD% = (PeakEquity_EA − Equity_EA) / PeakEquity_EA × 100
เกณฑ์หนังสือ: ควบคุมให้ < 30%
```

EA แบ่งเป็น 2 เส้น: `InpDDWarnPct` (default 20 — เตือน + หยุดเปิดไม้เพิ่มความเสี่ยง) และ `InpDDLockPct` (default 30 — บังคับ Zero Hedge ล็อคพอร์ตทันที)
หมายเหตุ: หนังสือ **ไม่ใช้ Stop Loss ตัดขาดทุนรวม** — ทางออกยามวิกฤตของหนังสือคือ Zero Hedge + รอ/เติมทุน ดังนั้น default ของ EA คือ "ล็อค ไม่ใช่ล้าง" แต่มี input เสริม `InpHardCutPct` (0 = ปิดใช้) สำหรับผู้ใช้ที่ต้องการ kill-switch จริง ๆ

### 2.6 การนับ Layer Hedge (บทที่ 2 ข้อสังเกต + บทที่ 4)

- Layer เริ่มที่ 0 เมื่อพอร์ตว่าง
- เมื่อเกิดสถานะ **Zero Hedge Margin สมบูรณ์** (ΣBuy == ΣSell โดยทั้งสองฝั่ง > 0) หนึ่งครั้ง → นับเป็น 1 layer
- ขยายไม้ต่อจาก zero-hedge เดิม (คานไปมา) → เข้าสู่ layer ถัดไป
- เกณฑ์หนังสือ: **ไม่เกิน 1–2 layers** → `InpMaxLayers` default 2; แตะเพดานแล้วห้ามเปิดไม้เพิ่มทุกกรณี เหลือเพียง ปิดลด lot / รอ Equity TP

---

## 3. สถาปัตยกรรมซอฟต์แวร์และโมดูล

```
MQL5/Experts/HedgeEquationEA/
├── HedgeEquationEA.mq5      ← entry point: OnInit/OnTick/OnTimer/OnTradeTransaction/OnDeinit
└── Include/
    ├── Config.mqh           ← inputs → SConfig + validation (§10)
    ├── AccountView.mqh      ← Equity/Balance/Margin/ML%/DD% เฉพาะส่วนของ EA (virtual sub-account)
    ├── TrendEngine.mqh      ← MTF + MA 3 เส้น → TREND_UP / TREND_DOWN / TREND_SIDEWAY (§5)
    ├── HedgeEngine.mqh      ← state machine + Cover Loss lot + layer counter (§4, §6)
    ├── RiskManager.mqh      ← ML% guard, NetLotMax, DD guard, layer cap, spread/news guard (§7)
    ├── EquityTP.mqh         ← เงื่อนไขปิดรวบ + ลำดับการปิด (§8)
    ├── TradeManager.mqh     ← ห่อ CTrade: retry, filling mode, normalize lot, close-all
    ├── NewsFilter.mqh       ← MQL5 economic calendar + ช่วง rollover
    ├── StateStore.mqh       ← กู้สถานะจาก open positions (§13)
    ├── Panel.mqh            ← UI บน chart + ปุ่ม (§14)
    └── Logger.mqh           ← journal + CSV (§14)
```

หลักการแยกชั้น: `HedgeEngine` ตัดสินใจ "อยากทำอะไร" → `RiskManager` มีสิทธิ์ veto/ลดขนาด → `TradeManager` เป็นผู้เดียวที่แตะ order API ทำให้ backtest ตรรกะแยกส่วนได้และ log เหตุผลการ veto ได้ครบ

---

## 4. State Machine ของวงจรเทรด

```
                    ┌──────────────────────────────────────────────┐
                    │            (ทุก state, ทุก tick)              │
                    │  EquityTP ผ่าน ──▶ CLOSE_ALL ──▶ FLAT        │
                    └──────────────────────────────────────────────┘

FLAT ──(Trend ยืนยัน + ผ่าน Risk ทุกข้อ)──▶ RIDE          เปิดไม้แรกตามเทรนด์
RIDE ──(เทรนด์เดิมต่อเนื่อง + เงื่อนไขเติมไม้)──▶ RIDE      เติมไม้ตามเทรนด์ (pyramid, คุมด้วย NetLotMax)
RIDE ──(เทรนด์ยืนยันกลับทิศ + basket ติดลบ)──▶ COVER      เปิด LotHedge ตามสูตร §2.3 → net lot สลับไปฝั่งเทรนด์ใหม่
COVER ──(เปิดสำเร็จ)──▶ RIDE                              (ฝั่งหนักคือฝั่งเทรนด์ใหม่แล้ว — กลับไปโหมดขี่เทรนด์)
RIDE/COVER ──(ML% < critical | DD ≥ LockPct | ข่าวแรง+เปิดใช้)──▶ LOCKED   ทำ Zero Hedge Margin
LOCKED ──(เทรนด์ชัด + ML% ฟื้น + พ้นข่าว)──▶ UNLOCK ──▶ RIDE   คลายล็อคฝั่งตามเทรนด์ (เทคนิค 8)
CLOSE_ALL ──(ปิดครบ ยืนยันจาก OnTradeTransaction)──▶ FLAT  บันทึกผลรอบ, PeakEquity reset, Layer reset
```

กติกา state:

- **RIDE**: ฝั่งหนัก (net lot) ต้องตรงกับเทรนด์เสมอ; การเติมไม้ (pyramid) เปิดได้เมื่อ `InpAllowPyramid=true` และราคาเดินตามเทรนด์ครบ `InpPyramidStepPts` และผ่าน NetLotMax
- **COVER**: เปิดได้ 1 คำสั่งต่อการกลับทิศ 1 ครั้ง (กัน re-trigger); ถ้า RiskManager ลด lot จนไม่ถึงขั้นต่ำ → ข้ามไป LOCKED
- **LOCKED**: EA เปิดไม้ฝั่งตรงข้ามขนาด `|net lot|` พอดีเพื่อทำ net = 0 (Fully Hedge); ระหว่างล็อคห้ามเปิดไม้อื่นทุกชนิด; นับ layer ตาม §2.6
- **UNLOCK** (เทคนิค 8): ปิดไม้ฝั่งสวนเทรนด์ที่ **ขาดทุนน้อยที่สุดก่อน** ทีละไม้ (ลด lot สะสม + ผลกระทบต่อ Balance ต่ำสุด) จน net lot กลับมาอยู่ฝั่งเทรนด์ในขนาดที่ผ่าน NetLotMax
- **CLOSE_ALL**: ปิดตามลำดับ "ไม้กำไรมากก่อน → ไม้ขาดทุนทีหลัง" (ระหว่างทยอยปิด Equity จะไม่ร่วงต่ำกว่าตอนตัดสินใจมากนัก และ margin ถูกคืนเร็ว) พร้อม retry ไม้ที่ fail

---

## 5. Trend Engine (ตามบทที่ 8 ของหนังสือ)

### 5.1 Multiple Time Frame

| บทบาท | TF (default) | ใช้ทำอะไร |
|--------|--------------|-----------|
| Major | D1 หรือ H4 (`InpMajorTF`) | ทิศทางหลักของวัน — ฝั่งที่อนุญาตให้ net lot หนัก |
| Middle | H1 หรือ M30 (`InpMidTF`) | ยืนยันการเปลี่ยนเทรนด์ (เงื่อนไขบังคับก่อนเข้า COVER) |
| Minor | M5 หรือ M1 (`InpEntryTF`) | จุดเข้าไม้/จุดเริ่มกลับตัว |

### 5.2 MA 3 เส้น (5 / 21 / 50 ตามหนังสือ)

```
UPTREND   : MA5 > MA21 > MA50  และ  Close > MA5
DOWNTREND : MA5 < MA21 < MA50  และ  Close < MA5
SIDEWAY   : นอกเหนือจากนั้น
```

- คำนวณบนแท่ง **ปิดแล้ว** (shift 1) กัน repaint; ชนิด MA และ applied price เป็น input
- **สัญญาณเข้า (FLAT→RIDE):** Major กับ Middle ต้องทิศเดียวกัน และ Minor เกิดการจัดเรียง MA ทิศนั้นภายใน `InpSignalFreshBars` แท่ง
- **สัญญาณกลับทิศ (RIDE→COVER):** Middle เปลี่ยนทิศเป็นตรงข้ามกับ net lot ปัจจุบันติดต่อกัน `InpFlipConfirmBars` แท่ง (default 2) **และ** Major ไม่ค้านทิศใหม่ (อนุญาตเมื่อ Major = ทิศใหม่ หรือ SIDEWAY)
- **SIDEWAY ทุก TF:** ไม่เปิดรอบใหม่ (หนังสือเตือนว่า sideway คือตัวการสะสม lot/layer)

---

## 6. Hedge Engine — Cover Loss Hedge และการนับ Layer

### 6.1 ขั้นตอนเมื่อเทรนด์ยืนยันกลับทิศ (หัวใจ "การแก้ไม้" ของหนังสือ)

```
1. รวบรวม basket:  FloatingPL = Σ(profit+swap+commission) ทุก position ของ EA
2. ถ้า FloatingPL ≥ 0  → ไม่ต้องแก้ไม้: ใช้เทคนิค 1 คือปิดฝั่งกำไร (ฝั่งสวนเทรนด์ใหม่)
   เก็บเข้า Balance แล้วให้ net lot สลับฝั่งเองโดยธรรมชาติ → กลับ RIDE
3. ถ้า FloatingPL < 0 → คำนวณ LotHedge ตามสูตร §2.3 ด้วย TP_points = InpCoverTPPts
4. ส่ง LotHedge ให้ RiskManager ตรวจ (§7) — ผ่าน/ลดขนาด/veto
5. เปิด market order ฝั่งเทรนด์ใหม่ → ตั้ง virtual TP ของ "แผนแก้ไม้" ไว้ที่
   ราคาเปิด ± InpCoverTPPts (ไม่ตั้ง TP จริงที่ order — การปิดจบทำโดย EquityTP เสมอ)
6. บันทึกแผน: หาก virtual TP ถูกแตะแล้ว EquityTP ยังไม่ผ่าน (spread/swap กัดกิน)
   → log WARN + แจ้ง panel ให้ผู้ใช้ทราบว่าแผน cover คลาดจากประมาณการ
```

### 6.2 การเติมไม้ตามเทรนด์ (RIDE, จากเทคนิค 2)

- เปิดเมื่อราคาวิ่งตามทิศครบ `InpPyramidStepPts` จากไม้ล่าสุด, lot = `InpBaseLot` (คงที่ ไม่ทวีคูณ — หนังสือย้ำไม่ใช่ martingale)
- ทุกไม้ต้องผ่าน NetLotMax และ ML% guard

### 6.3 ตัวนับ Layer

```
เหตุการณ์                                 layer
พอร์ตว่าง (FLAT)                           0
เข้า LOCKED ครั้งแรก (net=0 ทั้งสองฝั่ง>0)   1
UNLOCK แล้วกลับเข้า LOCKED อีกครั้ง          2   ← ชนเพดาน default
ชนเพดาน: ห้ามเปิดไม้ใหม่ทุกชนิด — เหลือเฉพาะการปิด (เทคนิค 3/4/7) และรอ EquityTP
```

---

## 7. Risk Manager — ลำดับการตรวจก่อนเปิดทุกออเดอร์

```
ลำดับ  เงื่อนไข                                          ถ้าไม่ผ่าน
 1     ตลาดเปิด + spread ≤ InpMaxSpreadPts               เลื่อน (รอ tick ถัดไป)
 2     ไม่อยู่ช่วง rollover (InpRolloverStart-End)        เลื่อน
 3     ไม่อยู่หน้าต่างข่าวแรง (NewsFilter)                 เลื่อน — ยกเว้นคำสั่งเข้า LOCKED (ต้องทำได้เสมอ)
 4     layer < InpMaxLayers                              veto ถาวรจนกว่า layer ลด
 5     DD% < InpDDWarnPct                                veto การ "เพิ่มความเสี่ยง" (เปิดฝั่งเพิ่ม |net|)
 6     |net_lot_after| ≤ NetLotMax (จาก ML_target §2.2)  ลดขนาด lot ลงจนผ่าน; ต่ำกว่า VOLUME_MIN → veto
 7     simulate: ML%_after ≥ InpMLFloorPct               ลดขนาด/veto
 8     margin จริงพอ (OrderCalcMargin ≤ FreeMargin×0.9)  veto
```

- ข้อ 3 มีข้อยกเว้นสำคัญ: **การทำ Zero Hedge (เข้า LOCKED) ต้องทำได้ทุกสถานการณ์** เพราะเป็นกลไกป้องกันพอร์ตของระบบ (เทคนิค 6 ใช้ตอนวิกฤต)
- ทุก veto/ลดขนาด ต้อง log เหตุผล (rule number + ค่าที่วัดได้) เพื่อ debug ย้อนหลัง
- Guard ระดับบัญชีที่ทำงานทุก tick (ไม่ใช่แค่ตอนเปิดไม้): `ML% < InpMLLockPct` หรือ `DD ≥ InpDDLockPct` → สั่ง HedgeEngine เข้า LOCKED ทันที; `InpHardCutPct > 0` และ DD แตะ → CLOSE_ALL (kill-switch เสริม นอกเหนือหนังสือ)

---

## 8. Equity Take Profit Engine

```mql5
bool CEquityTP::ShouldCloseAll()
  {
   double eq  = m_view.EquityEA();       // §2.1 — virtual หรือ whole-account ตามโหมด
   double bal = m_view.BalanceEA();
   double cap = m_view.InitialCapital();
   // สูตรหนังสือ: EQUITY >= BALANCE หรือ EQUITY > ทุนแรกเริ่ม (+ เป้ากำไรขั้นต่ำของผู้ใช้)
   bool byBalance = m_cfg.useBalanceRule && eq >= bal              && bal > cap; // กันปิดรวบตอนยังไม่มีกำไรจริง
   bool byCapital = eq >= cap + m_cfg.cycleProfitMoney;
   return (m_view.OpenPositions() > 0 && (byBalance || byCapital));
  }
```

- เงื่อนไข `bal > cap` เพิ่มจากหนังสือเล็กน้อย: ตัวอย่างในหนังสือ (ทุน 100 → Balance 150 → Equity 130 ≥ 100 → ปิดรวบ ได้กำไร 30) ใช้ได้เพราะ Balance โตแล้วจากการเก็บกำไรระหว่างทาง — เงื่อนไขนี้กันกรณี Equity==Balance ตอนเพิ่งเปิดพอร์ตซึ่งไม่ใช่จุดปิด
- หลังปิดรวบสำเร็จ: บันทึกสถิติรอบ (กำไร, จำนวนไม้, layer สูงสุด, DD สูงสุด, ระยะเวลา) ลง CSV → reset วงจร → FLAT

---

## 9. Zero Hedge Margin (โหมดล็อคพอร์ต)

- **เข้าเมื่อ:** ML% < `InpMLLockPct` | DD ≥ `InpDDLockPct` | ข่าวแรง (ถ้า `InpLockOnNews`) | ผู้ใช้กดปุ่ม `[LOCK]` บน panel
- **วิธีทำ:** เปิด market order ฝั่งตรงข้าม net lot ขนาด `|ΣBuy − ΣSell|` หนึ่งคำสั่ง → net = 0
- **ผลตามหนังสือ:** margin ≈ 0 (ต้องตรวจ `SYMBOL_MARGIN_HEDGED` ของโบรกตอน OnInit — ถ้าโบรกคิด margin hedge ≠ 0 ให้แจ้งเตือนบน panel ว่าการล็อคไม่ฟรี), floating P/L ถูกฟรีซ
- **คำเตือนที่ EA ต้องแสดง (จากหนังสือ):** Zero Hedge **ไม่กัน Stop Out เด็ดขาด** — MT5 จะ stop out เมื่อ Equity ≤ 0 และ spread ถ่างทำ Equity ไหลลงได้แม้ net=0 → ระหว่าง LOCKED ให้ EA เฝ้า Equity แล้วเตือน push notification เมื่อ Equity ลดผ่านเกณฑ์
- **ออกเมื่อ:** เงื่อนไข UNLOCK ใน §4 ครบ

---

## 10. Input Parameters ฉบับเต็ม

```mql5
//=== General =================================================
input long   InpMagic            = 990001;   // Magic Number (ต่างกันทุก chart)
input string InpTradeComment     = "HedgeEqEA";
input ENUM_ACCOUNT_SCOPE InpScope = SCOPE_VIRTUAL; // VIRTUAL=คิดเฉพาะส่วน EA / WHOLE=ทั้งบัญชีตามหนังสือ
input double InpAllocatedCapital = 1000.0;   // ทุนที่จัดสรรให้ EA (โหมด VIRTUAL)

//=== Trend Engine (บทที่ 8) =================================
input ENUM_TIMEFRAMES InpMajorTF = PERIOD_H4;
input ENUM_TIMEFRAMES InpMidTF   = PERIOD_H1;
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M5;
input int    InpMAFast           = 5;        // MA เส้นสั้น (หนังสือ: 5)
input int    InpMAMid            = 21;       // MA เส้นกลาง (หนังสือ: 21)
input int    InpMASlow           = 50;       // MA เส้นยาว (หนังสือ: 50)
input ENUM_MA_METHOD InpMAMethod = MODE_EMA;
input int    InpFlipConfirmBars  = 2;        // แท่งยืนยันการกลับเทรนด์ (Middle TF)
input int    InpSignalFreshBars  = 3;        // สัญญาณเข้าต้องสดภายใน N แท่ง

//=== Lot & Pyramid ==========================================
input double InpBaseLot          = 0.01;     // lot ไม้ปกติ (คงที่ — ไม่ใช่ martingale)
input bool   InpAllowPyramid     = true;
input int    InpPyramidStepPts   = 300;      // ระยะเติมไม้ตามเทรนด์ (points)
input int    InpMaxPositions     = 15;       // เพดานจำนวนไม้รวม

//=== Cover Loss Hedge (บทที่ 3) =============================
input int    InpCoverTPPts       = 5000;     // ระยะ TP แผนแก้ไม้ (ตัวอย่างหนังสือ: 5,000 จุด)
input double InpCoverProfitMoney = 50.0;     // Profit อ้างอิงบวกเข้า CoverAmount (ตัวอย่างหนังสือ: 50)
input bool   InpIncludeCosts     = true;     // รวม swap+commission ใน CoverAmount

//=== Risk (บทที่ 2, 4, 5) ===================================
input double InpMLTargetPct      = 3000.0;   // ML% เป้าหมายขั้นต่ำ → เพดาน net lot (กรณี D: 3,000%)
input double InpMLFloorPct       = 1000.0;   // ML% ต่ำสุดหลัง simulate เปิดไม้
input double InpMLLockPct        = 500.0;    // ML% ที่บังคับเข้า Zero Hedge ทันที
input double InpDDWarnPct        = 20.0;     // DD เตือน + งดเพิ่มความเสี่ยง
input double InpDDLockPct        = 30.0;     // DD บังคับ Zero Hedge (เกณฑ์หนังสือ: 30%)
input double InpHardCutPct       = 0.0;      // 0=ปิดใช้ | >0 = DD ที่ตัดขาดทุนทั้งพอร์ต (เสริม นอกหนังสือ)
input int    InpMaxLayers        = 2;        // เพดาน layer (หนังสือ: 1–2)
input int    InpMaxSpreadPts     = 60;

//=== Equity TP (บทที่ 8) ====================================
input bool   InpUseBalanceRule   = true;     // ปิดรวบเมื่อ Equity ≥ Balance (และ Balance > ทุน)
input double InpCycleProfitMoney = 10.0;     // เป้ากำไรขั้นต่ำ/รอบ เหนือทุนแรกเริ่ม

//=== Session / News / Rollover ==============================
input bool   InpUseNewsFilter    = true;
input int    InpNewsBlockMin     = 30;       // งดเปิดไม้ ก่อน/หลังข่าว impact สูง (นาที)
input bool   InpLockOnNews       = false;    // ทำ Zero Hedge อัตโนมัติคร่อมข่าวแรง (เทคนิค 6)
input string InpRolloverStart    = "23:55";  // เวลา server — งดเปิดไม้ช่วง rollover
input string InpRolloverEnd      = "00:20";
input bool   InpTradeFriday      = true;
input string InpFridayCutoff     = "18:00";  // งดเปิดรอบใหม่หลังเวลานี้วันศุกร์

//=== อื่น ๆ ==================================================
input bool   InpShowPanel        = true;
input bool   InpWriteCsv         = true;
input bool   InpPushAlerts       = true;     // แจ้งเตือนมือถือ (LOCKED, DD, EquityTP)
input int    InpRetryCount       = 3;
input int    InpRetryDelayMs     = 400;
```

Validation ใน `OnInit` (ตัวอย่าง): `MLLock < MLFloor < MLTarget`, `DDWarn < DDLock`, `BaseLot ≥ VOLUME_MIN`, `CoverTPPts > SYMBOL_TRADE_STOPS_LEVEL`, TF เรียง Major ≥ Mid ≥ Entry

---

## 11. รายละเอียดคลาสและไฟล์ (สัญญาระหว่างโมดูล)

```mql5
// AccountView.mqh — มุมมองบัญชีเฉพาะส่วน EA
class CAccountView {
public:
   bool     Init(SConfig &cfg);
   double   EquityEA();          // VIRTUAL: capital + closed PL สะสม + floating PL | WHOLE: ACCOUNT_EQUITY
   double   BalanceEA();
   double   InitialCapital();
   double   MarginEA();          // OrderCalcMargin ของ |net lot| ปัจจุบัน
   double   MarginLevelEA();     // §2.1 (คืน DBL_MAX เมื่อ margin==0 — ห้ามหาร 0)
   double   DrawdownPct();       // §2.5 + track peak
   double   NetLot();            // ΣBuy − ΣSell (เฉพาะ magic+symbol)
   double   FloatingPL();        // รวม swap+commission
   int      OpenPositions();
};

// TrendEngine.mqh
enum ENUM_TREND { TREND_UP, TREND_DOWN, TREND_SIDEWAY };
class CTrendEngine {
public:
   bool       Init(SConfig &cfg);              // สร้าง iMA handles 3 เส้น × 3 TF (9 handles)
   ENUM_TREND Major();  ENUM_TREND Middle();  ENUM_TREND Minor();   // อ่านจากแท่งปิดแล้ว
   bool       EntrySignal(ENUM_TREND &dir);    // §5.2 กติกาเข้า
   bool       FlipConfirmed(ENUM_TREND cur);   // §5.2 กติกากลับทิศ
};

// HedgeEngine.mqh
enum ENUM_HE_STATE { HE_FLAT, HE_RIDE, HE_COVER, HE_LOCKED, HE_CLOSING };
class CHedgeEngine {
public:
   bool   Init(SConfig&, CAccountView&, CTrendEngine&, CRiskManager&, CTradeManager&, CLogger&);
   void   OnTickUpdate();            // ขับ state machine §4 — จุดเรียกเดียวจาก OnTick
   void   OnDealAdded(ulong deal);   // sync จาก OnTradeTransaction
   void   RestoreState();            // §13
   void   UserLock();  void UserCloseAll();   // จากปุ่ม panel
   int    Layer();  ENUM_HE_STATE State();
private:
   double CoverLossLot();            // สูตร §2.3
   void   EnterLocked(string reason);
   void   TryUnlock();
};

// RiskManager.mqh
struct SRiskVerdict { bool allowed; double adjustedLot; int ruleHit; string reason; };
class CRiskManager {
public:
   SRiskVerdict CheckOpen(ENUM_ORDER_TYPE type, double lot, bool isZeroHedgeEntry);
   void         TickGuards();        // ML%/DD guards ระดับทุก tick (§7 ท้าย)
   double       NetLotMax();         // §2.2
};
```

`TradeManager` (ห่อ `CTrade`): เลือก filling mode ตาม `SYMBOL_FILLING_MODE`, retry เฉพาะ retcode ชั่วคราว (`REQUOTE, PRICE_OFF, TIMEOUT, CONNECTION, PRICE_CHANGED`), `NormalizeLotUp()`, `CloseAllOrdered(profitFirst)`, `CloseBy()` — ใช้ `PositionCloseBy` จับคู่ปิดไม้ hedge สองฝั่ง (เทคนิค 4) ประหยัด spread หนึ่งขา ถ้าโบรกรองรับ

---

## 12. ประเด็น implementation เฉพาะของ MQL5

| ประเด็น | การจัดการ |
|---------|-----------|
| โหมดบัญชี | `ACCOUNT_MARGIN_MODE` ต้องเป็น `RETAIL_HEDGING` — ไม่ใช่ให้ `INIT_FAILED` พร้อมคำอธิบาย (ระบบนี้ถือ Buy/Sell พร้อมกันโดยนิยาม) |
| Margin hedge ของโบรก | อ่าน `SYMBOL_MARGIN_HEDGED` + `SYMBOL_MARGIN_HEDGED_USE_LEG` ตอน OnInit — แสดงบน panel; ถ้า margin hedge ≠ 0 คำนวณ MarginEA ตามจริง (Zero Hedge จะไม่ฟรี) |
| ML% ของบัญชีตอน net=0 | `ACCOUNT_MARGIN_LEVEL` คืน 0.0 เมื่อไม่มี margin — ห้ามตีความว่า "วิกฤต"; ใช้ `MarginLevelEA()` ที่คืน DBL_MAX แทน |
| จุด (points) ↔ เงิน | `PointValuePerLot = TICK_VALUE × (_Point/TICK_SIZE)` — คำนวณสดทุกครั้ง (tick value ผันตามสกุลบัญชี) |
| ปัด lot | ปัดขึ้นตาม `VOLUME_STEP` (สูตร cover ต้องไม่ขาด) แล้ว clamp `VOLUME_MIN/MAX`; แตก order ถ้าเกิน `SYMBOL_VOLUME_LIMIT` |
| Multi-chart | ทุก loop position กรอง `magic == InpMagic && symbol == _Symbol` เท่านั้น |
| ความจริงจาก server | เชื่อ `OnTradeTransaction(DEAL_ADD)` เป็นแหล่งยืนยัน ไม่เชื่อผล OrderSend อย่างเดียว; state ทุกตัว recompute ได้จาก positions จริง (§13) |
| Economic calendar | `CalendarValueHistory` ใช้ไม่ได้ใน Strategy Tester บางกรณี — ครอบ `MQLInfoInteger(MQL_TESTER)` แล้ว degrade เป็นปิด filter พร้อม log |
| Timer | `EventSetTimer(1)` สำหรับ panel/news/heartbeat — ห้ามทำงานเทรดหลักใน OnTimer (ตลาดปิด tick ไม่มา แต่ timer ยังยิง) |
| Visual backtest | panel วาดด้วย object ธรรมดา (ไม่ใช้ DLL/Canvas) ให้เห็นใน tester visual mode ได้ |

---

## 13. การกู้สถานะหลัง restart

`CStateStore.Restore()` ใน OnInit:

1. รวบรวม positions ของ `magic+symbol` → ถ้าว่าง → `HE_FLAT`
2. คำนวณ `netLot`:
   - `|netLot| < VOLUME_STEP/2` และมีไม้สองฝั่ง → `HE_LOCKED`
   - อื่น ๆ → `HE_RIDE` (ฝั่งหนัก = ฝั่งที่ระบบถือว่าเป็นเทรนด์เดิม — Trend Engine จะประเมินใหม่แท่งถัดไปเองตามกติกาปกติ)
3. ตัวแปรที่กู้จาก positions ไม่ได้ (InitialCapital ของรอบ, PeakEquity, layer, closed-PL สะสมโหมด VIRTUAL) → เก็บใน **ไฟล์ state** `MQL5/Files/HedgeEqEA_<magic>.json` เขียนทับทุกครั้งที่ค่าเปลี่ยน (ใช้ไฟล์ ไม่ใช้ global variables เพื่อรอด backup/ย้ายเครื่องด้วย)
4. ไฟล์ state กับ positions ขัดแย้ง (เช่นผู้ใช้ปิดไม้มือระหว่าง EA หลับ) → ยึด positions จริงเป็นหลัก, ปรับไฟล์ตาม, log WARN + แจ้ง panel
5. พบไม้แปลกปลอม magic เดียวกันที่โครงสร้างผิดคาด → โหมด **manage-only**: ไม่เปิดไม้เพิ่ม เฝ้าเฉพาะ EquityTP + guards จนผู้ใช้เคลียร์

---

## 14. Panel และ Logging

**Panel (มุมซ้ายบน):**

```
┌─ HedgeEq EA ─────────────────────────────┐
│ State: RIDE ▲      Layer: 0/2            │
│ Trend  D1:▲  H1:▲  M5:▲                  │
│ Net Lot: +0.05   (Buy 0.07 / Sell 0.02)  │
│ ML%: 4,120   NetLotMax: 0.38             │
│ Equity: 1,042.10  Balance: 1,050.00      │
│ Float P/L: -7.90   DD: 3.1%  Peak: 1,075 │
│ EquityTP เหลือ: +12.40 → ปิดรวบ           │
│ [ LOCK NOW ]  [ CLOSE ALL ]  [ PAUSE ]   │
└──────────────────────────────────────────┘
```

- ปุ่มทำลายล้าง (`CLOSE ALL`) ต้องกดยืนยัน 2 ครั้งใน 3 วินาที
- สีสถานะ: RIDE เขียว/แดงตามทิศ, LOCKED เหลือง, DD>Warn ส้ม

**Logging:** ทุก state transition, ทุกคำสั่งเทรด (request+result+retcode), ทุก veto ของ RiskManager (rule+ค่า), สรุปจบรอบ → `Print` + CSV `HedgeEqEA_<magic>_<yyyymm>.csv`
คอลัมน์: `time,event,state,layer,trend_major,trend_mid,net_lot,ml_pct,dd_pct,equity,balance,float_pl,lot,price,reason`

---

## 15. แผนการทดสอบ

### 15.1 Unit / Script tests (รันใน tester script ก่อนต่อระบบ)
- `CoverLossLot()`: ทวนตัวอย่างหนังสือ — loss −226.25, target 50, TP 5000 จุด, point value 1 → ต้องได้ 0.06 หลังปัดขึ้น
- `NetLotMax()`: mock Equity/MarginPerLot หลายชุด รวม edge margin==0
- `MarginLevelEA()`: กรณี net=0 ต้องคืน DBL_MAX ไม่ crash
- ตัวนับ layer: ลำดับเหตุการณ์ RIDE→LOCKED→UNLOCK→LOCKED ต้องได้ 1→2 และ veto หลังชนเพดาน

### 15.2 Backtest (Strategy Tester)
- โหมด **Every tick based on real ticks** + spread จริง, ≥ 2 ปี ต่อ symbol: XAUUSD, GBPUSD (ตาม journal), EURUSD (ตามหนังสือ)
- ชุดสถานการณ์บังคับ: เทรนด์ยาวทางเดียว (ทดสอบ pyramid + cover ตอนจบเทรนด์), sideway แรง (ศัตรูของระบบ — ดู layer สะสม), ช่วงข่าวใหญ่ (NFP/FOMC), gap เปิดสัปดาห์
- เมตริก: Max DD% (ต้อง < 30 ตามเกณฑ์หนังสือ), ML% ต่ำสุดที่แตะ, จำนวนครั้งเข้า LOCKED, จำนวนรอบ EquityTP สำเร็จ, กำไรสุทธิหลังหัก swap (รายงานแยก swap ให้เห็นชัด)

### 15.3 Optimization
- ตัวแปรหลัก: `InpCoverTPPts`, `InpFlipConfirmBars`, `InpPyramidStepPts`, `InpMLTargetPct`
- Custom criterion: `NetProfit / MaxDD` และ penalty เมื่อ `layer ชนเพดาน` หรือ `ML%_min < MLLock` — กันชุดพารามิเตอร์ที่ "กำไรสวยแต่เฉียดตายบ่อย"
- Walk-forward: optimize 12 เดือน / ทดสอบนอกตัวอย่าง 3 เดือน เลื่อนหน้าต่างตลอดช่วงข้อมูล

### 15.4 Forward (demo)
- ≥ 4 สัปดาห์ คร่อมข่าวใหญ่อย่างน้อย 1 รอบ, เทียบ CSV log กับ backtest ช่วงเดียวกัน
- ทดสอบ resilience: ปิด terminal กลางรอบ / ระหว่าง LOCKED → เปิดใหม่ → ตรวจการกู้สถานะ §13 ครบทุก field

---

## 16. Mapping เทคนิค 1–8 ของหนังสือ → ฟีเจอร์ EA

| เทคนิคในหนังสือ | สถานะใน EA |
|-----------------|-----------|
| 1. ปิดฝั่งกำไร (สวนเทรนด์ใหม่) แล้วปล่อย Equity โต | ✅ อัตโนมัติ — ขั้นแรกของ flow กลับทิศ (§6.1 ข้อ 2) |
| 2. เทรดฝั่งเดียวกับเทรนด์ | ✅ อัตโนมัติ — กติกาหลักของ RIDE |
| 3. ทยอยปิดกำไรสั้น + ปิดไม้ลบน้อยสุด ลด lot | ✅ ใช้ในลำดับการปิดของ UNLOCK และ CLOSE_ALL |
| 4. จับคู่ไม้บวก-ลบปิดหักล้าง | ✅ ผ่าน `PositionCloseBy` เมื่อโบรกรองรับ (ประหยัด spread) |
| 5. เปิดสวนเทรนด์เก็บสั้น (lot ห้ามเกินฝั่งเทรนด์) | ⏸ เฟสหลัง (v2) — เพิ่มความซับซ้อน/ความเสี่ยงต่อ ML% โดยไม่จำเป็นในเวอร์ชันแรก |
| 6. Zero Hedge Margin ยามวิกฤต | ✅ state LOCKED (§9) |
| 7. ทยอยปิดเพิ่ม ML% แล้วค่อยประเมินทิศใหม่ | ✅ กลไก UNLOCK + TickGuards |
| 8. ล็อคกำไรเป็นขั้นบันไดด้วย Zero Hedge | ✅ option `InpLockOnNews` + ปุ่ม LOCK มือ; ขั้นบันไดอัตโนมัติเป็น v2 |

---

## 17. Roadmap การพัฒนา

| เฟส | ขอบเขต | Definition of Done |
|-----|--------|--------------------|
| 1 | Config, AccountView, TradeManager, Logger | เปิด/ปิดไม้ผ่าน EA + ML%/DD คำนวณถูก (เทียบมือ) |
| 2 | TrendEngine + state FLAT/RIDE | backtest เปิดไม้ตามเทรนด์ + pyramid ทำงาน |
| 3 | Cover Loss + EquityTP + RiskManager ครบ | ผ่าน unit tests §15.1 ทั้งหมด + รอบเทรดจบเองใน tester |
| 4 | LOCKED/UNLOCK + layer + NewsFilter + StateStore | ทดสอบ restart กลางรอบผ่าน |
| 5 | Panel + push alerts + CSV | ใช้งาน demo ได้จริง |
| 6 | Optimization + walk-forward + set files ต่อ symbol | ค่าพร้อมใช้ XAUUSD / GBPUSD |

โครง skeleton code ตามสถาปัตยกรรมนี้อยู่ที่ `MQL5/Experts/HedgeEquationEA/` ใน repo แล้ว (คลาสหลัก + สูตร §2 implement จริง, ส่วน logic เต็มมี `// TODO(phase-N)` กำกับตาม roadmap)

---

## 18. คำถามเปิดถึงผู้ใช้

1. **ไฟล์ role และ prompt** ที่กล่าวถึงยังไม่อยู่ใน repo (repo ว่างก่อน push นี้) — ถ้ามี spec เพิ่มเติมนอกเหนือหนังสือ กรุณา push/แนบ แล้วจะปรับ design ให้ตรง
2. โหมดเริ่มต้นควรเป็น **อัตโนมัติเต็มรูปแบบ** หรือ **กึ่งออโต้** (ผู้ใช้เปิดไม้เอง EA คำนวณ lot แก้ไม้ + Equity TP ให้ — แบบ "โรบอทกึ่งออโต้" ที่หนังสือแจก)? ปัจจุบันออกแบบเป็นอัตโนมัติเต็ม โดยกึ่งออโต้เพิ่มได้เป็นโหมดที่สาม
3. ทุนจริงที่จะใช้ต่อ 1 instance และ leverage ของบัญชี — มีผลต่อ default ของ `InpMLTargetPct`/`InpBaseLot`
4. ต้องการ kill-switch จริง (`InpHardCutPct`) เปิดใช้เป็น default หรือยึดตามหนังสือ (ล็อคอย่างเดียว ไม่ตัดขาดทุน)?
