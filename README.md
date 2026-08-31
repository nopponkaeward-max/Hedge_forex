# Hedge_forex — Hedge Equation EA (MQL5)

EA สำหรับ MetaTrader 5 ตามระบบ "สมการเฮดจ์": **Cover Loss Hedge + Follow Trend + Margin Level % guard + Equity Take Profit**

| ส่วน | ที่อยู่ |
|------|--------|
| 📐 เอกสารออกแบบฉบับเต็ม | [`Docs/DESIGN.md`](Docs/DESIGN.md) |
| 🤖 Skeleton code EA | [`MQL5/Experts/HedgeEquationEA/`](MQL5/Experts/HedgeEquationEA/) |

## สรุประบบ

1. **Trend Engine** — Multi-timeframe (H4/H1/M5) + MA 3 เส้น (5/21/50): net lot ต้องอยู่ฝั่งเทรนด์เสมอ
2. **Cover Loss Hedge** — เมื่อเทรนด์ยืนยันกลับทิศและพอร์ตติดลบ เปิดไม้แก้ฝั่งเทรนด์ใหม่ด้วยสูตร
   `LotHedge = (|FloatingLoss| + ProfitTarget) / (TP_points × PointValue)` — ขนาดพอดี ไม่ใช่ martingale
3. **Risk guards** — เพดาน net lot ผูกกับ Margin Level % เป้าหมาย, Drawdown < 30%, Layer Hedge ≤ 2 ชั้น
4. **Zero Hedge Margin** — ล็อคพอร์ต (net lot = 0) อัตโนมัติยามวิกฤต ML%/DD/ข่าวแรง
5. **Equity Take Profit** — ปิดรวบทุกไม้เมื่อ `Equity ≥ Balance` หรือ `Equity ≥ ทุนแรกเริ่ม + เป้ากำไร`

> ⚠️ ระบบ hedge ถือขาดทุนลอยตัว มีความเสี่ยง drawdown สูง — ต้อง backtest และทดสอบบน demo ก่อนใช้เงินจริงเสมอ (แผนทดสอบอยู่ใน DESIGN.md §15)

## สถานะโปรเจกต์

- [x] เอกสารออกแบบละเอียด + traceability กับไฟล์ Role & Prompt (DESIGN.md §0)
- [x] Core logic ครบวงจร (เฟส 1–4): Trend MTF, Cover Loss 2 โมเดล, Risk guards 9 ข้อ,
      Zero Hedge lock/unlock, S/R break, counter-trend, Equity TP, StateStore กู้สถานะข้าม restart
- [x] Unit tests สูตรสมการ: `MQL5/Scripts/HedgeEqEA_Tests.mq5` (รันใน MT5 ต้องได้ ALL PASSED)
- [ ] เฟส 5–6: Panel UI, NewsFilter/rollover, CSV log, push alerts, optimization + set files

**ขั้นตอนแรกสำหรับผู้ใช้:** เปิดโปรเจกต์ใน MetaEditor → compile (F7) → รัน `HedgeEqEA_Tests`
→ backtest บน XAUUSD/GBPUSD M5 โหมด real ticks ก่อนใช้ demo
