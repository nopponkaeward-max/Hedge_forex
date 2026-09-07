#!/usr/bin/env python3
"""รวมโค้ด EA เป็นไฟล์ .mq5 เดียว (all-in-one) — ตัดปัญหา include path ใน MT5
รันจาก root ของ repo:  python3 tools/build_single.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INC = ROOT / "MQL5/Include/HedgeEquationEA"
OUT_EA = ROOT / "MQL5/Experts/HedgeEquationEA_AllInOne.mq5"
OUT_TEST = ROOT / "MQL5/Scripts/HedgeEqEA_Tests_AllInOne.mq5"

# ลำดับตาม dependency (ไฟล์หลังพึ่งไฟล์ก่อนได้เท่านั้น)
ORDER = ["Config", "AccountView", "TrendEngine", "Levels", "TradeManager",
         "NewsFilter", "Logger", "RiskManager", "HedgeEngine", "EquityTP",
         "StateStore", "Panel"]

# include ภายในโปรเจกต์ (ตัดทิ้ง — โค้ดถูกรวมแล้ว); มาตรฐาน MT5 เช่น <Trade/Trade.mqh> คงไว้
RE_LOCAL_INC = re.compile(r'^\s*#include\s+("[^"]+"|<HedgeEquationEA/[^>]+>)[^\n]*$', re.M)


def merged_includes() -> str:
    parts = []
    for name in ORDER:
        src = (INC / f"{name}.mqh").read_text(encoding="utf-8")
        src = RE_LOCAL_INC.sub("", src)
        parts.append(f"//{'='*66}\n//=== [inlined] Include/HedgeEquationEA/{name}.mqh\n//{'='*66}\n{src}")
    return "\n".join(parts)


def build(main_path: Path, out_path: Path, banner: str) -> None:
    main = main_path.read_text(encoding="utf-8")
    body = RE_LOCAL_INC.sub("", main)
    # แทรกโค้ดรวมหลังบรรทัด #property สุดท้าย
    lines = body.splitlines(keepends=True)
    last_prop = max(i for i, l in enumerate(lines) if l.startswith("#property"))
    text = ("".join(lines[: last_prop + 1])
            + f"\n// {banner}\n// สร้างโดย tools/build_single.py — แก้โค้ดที่ไฟล์ต้นทางแล้ว build ใหม่ อย่าแก้ไฟล์นี้ตรง ๆ\n\n"
            + merged_includes() + "\n"
            + "".join(lines[last_prop + 1:]))
    out_path.write_text(text, encoding="utf-8")
    print(f"wrote {out_path.relative_to(ROOT)} ({len(text.splitlines())} lines)")


build(ROOT / "MQL5/Experts/HedgeEquationEA/HedgeEquationEA.mq5", OUT_EA,
      "ALL-IN-ONE BUILD: copy ไฟล์นี้ไฟล์เดียวไปที่ MQL5\\Experts\\ แล้ว compile ได้เลย")
build(ROOT / "MQL5/Scripts/HedgeEqEA_Tests.mq5", OUT_TEST,
      "ALL-IN-ONE BUILD: copy ไฟล์นี้ไฟล์เดียวไปที่ MQL5\\Scripts\\ แล้ว compile ได้เลย")
