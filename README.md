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

- [x] เอกสารออกแบบละเอียด (สถาปัตยกรรม, สูตร, state machine, inputs, แผนทดสอบ)
- [x] Skeleton code: Config / AccountView / TrendEngine / TradeManager / RiskManager / HedgeEngine / EquityTP
- [ ] เฟส 1–6 ตาม roadmap ใน DESIGN.md §17 (NewsFilter, StateStore, Panel, Logger, unit tests, optimization)
