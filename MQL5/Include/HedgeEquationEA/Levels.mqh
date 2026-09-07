//+------------------------------------------------------------------+
//| Levels.mqh — swing Support/Resistance แบบ fractal               |
//| ใช้โดย: S/R-break trigger (DESIGN §9) และ Counter-Trend (§6.3)  |
//+------------------------------------------------------------------+
#ifndef HEQ_LEVELS_MQH
#define HEQ_LEVELS_MQH

// swing high = แท่งที่ high สูงกว่าเพื่อนบ้าน wing แท่งทั้งสองข้าง (fractal)
// คืน 0.0 เมื่อไม่พบภายใน lookback
double LastSwingHigh(ENUM_TIMEFRAMES tf, int depth)
  {
   int wing = 2;
   int lookback = MathMax(depth * 4, 20);
   for(int i = wing + 1; i <= lookback; i++)   // เริ่มหลังแท่งปิดล่าสุด + wing
     {
      double h = iHigh(_Symbol, tf, i);
      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
         if(iHigh(_Symbol, tf, i - k) >= h || iHigh(_Symbol, tf, i + k) >= h)
            isSwing = false;
      if(isSwing) return h;
     }
   return 0.0;
  }

double LastSwingLow(ENUM_TIMEFRAMES tf, int depth)
  {
   int wing = 2;
   int lookback = MathMax(depth * 4, 20);
   for(int i = wing + 1; i <= lookback; i++)
     {
      double l = iLow(_Symbol, tf, i);
      bool isSwing = true;
      for(int k = 1; k <= wing && isSwing; k++)
         if(iLow(_Symbol, tf, i - k) <= l || iLow(_Symbol, tf, i + k) <= l)
            isSwing = false;
      if(isSwing) return l;
     }
   return 0.0;
  }

#endif // HEQ_LEVELS_MQH
