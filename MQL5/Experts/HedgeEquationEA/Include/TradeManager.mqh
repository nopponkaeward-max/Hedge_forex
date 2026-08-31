//+------------------------------------------------------------------+
//| TradeManager.mqh — ผู้เดียวที่แตะ order API (DESIGN §11)         |
//+------------------------------------------------------------------+
#ifndef HEQ_TRADEMANAGER_MQH
#define HEQ_TRADEMANAGER_MQH

#include <Trade/Trade.mqh>
#include "Config.mqh"

// pure function แยกไว้ให้ unit test ได้ (Scripts/HedgeEqEA_Tests.mq5)
double NormalizeLotUpPure(double lot, double step, double vmin, double vmax)
  {
   if(step <= 0.0) step = 0.01;
   double n = MathCeil(lot / step - 1e-9) * step;
   return MathMin(MathMax(n, vmin), vmax);
  }

class CTradeManager
  {
private:
   CTrade            m_trade;
   SConfig           m_cfg;

   bool              IsOurs(void) const
     {
      return (PositionGetInteger(POSITION_MAGIC) == m_cfg.magic &&
              PositionGetString(POSITION_SYMBOL) == _Symbol);
     }

   // retry เฉพาะ error ชั่วคราว — error ถาวร (NO_MONEY, INVALID_VOLUME) fail ทันที
   static bool       IsTransient(uint retcode)
     {
      return (retcode == TRADE_RETCODE_REQUOTE       ||
              retcode == TRADE_RETCODE_PRICE_OFF     ||
              retcode == TRADE_RETCODE_PRICE_CHANGED ||
              retcode == TRADE_RETCODE_TIMEOUT       ||
              retcode == TRADE_RETCODE_CONNECTION);
     }

public:
   bool              Init(const SConfig &cfg)
     {
      m_cfg = cfg;
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(30);
      // เลือก filling mode ตามที่ symbol รองรับ
      long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0) m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else                                          m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      return true;
     }

   // ปัด lot "ขึ้น" ตาม step (สูตร cover ต้องไม่ขาด — ตามหนังสือ 0.05525→0.06) แล้ว clamp
   double            NormalizeLotUp(double lot) const
     {
      return NormalizeLotUpPure(lot,
                                SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
                                SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                                SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
     }

   // ปิดทุกไม้ของฝั่งเดียว (เทคนิค 1: ปิดฝั่งกำไรสวนเทรนด์ใหม่)
   bool              CloseSide(ENUM_POSITION_TYPE side)
     {
      bool allOk = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurs()) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != side) continue;
         if(!ClosePosition(tk)) allOk = false;
        }
      return allOk;
     }

   // ปิด "หนึ่งไม้" ของฝั่งที่กำหนดที่ขาดทุนน้อยที่สุด (ใช้ใน UNLOCK — เทคนิค 3/8)
   // คืน false เมื่อไม่มีไม้ฝั่งนั้นเหลือ หรือปิดไม่สำเร็จ
   bool              CloseOneLeastLosing(ENUM_POSITION_TYPE side)
     {
      ulong bestTicket = 0;
      double bestProfit = -DBL_MAX;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurs()) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != side) continue;
         double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(p > bestProfit) { bestProfit = p; bestTicket = tk; }
        }
      if(bestTicket == 0) return false;
      return ClosePosition(bestTicket);
     }

   bool              OpenMarket(ENUM_ORDER_TYPE type, double lot, string tag, ulong &dealTicket)
     {
      dealTicket = 0;
      string comment = m_cfg.comment + "|" + tag;
      for(int attempt = 0; attempt <= m_cfg.retryCount; attempt++)
        {
         bool ok = (type == ORDER_TYPE_BUY)
                   ? m_trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, comment)
                   : m_trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, comment);
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
           {
            dealTicket = m_trade.ResultDeal();
            return true;
           }
         if(!IsTransient(rc))
           {
            PrintFormat("[HedgeEqEA] OpenMarket fail ถาวร rc=%u (%s)", rc, m_trade.ResultRetcodeDescription());
            return false;
           }
         Sleep(m_cfg.retryDelayMs);
        }
      PrintFormat("[HedgeEqEA] OpenMarket fail หลัง retry %d ครั้ง", m_cfg.retryCount);
      return false;
     }

   bool              ClosePosition(ulong ticket)
     {
      for(int attempt = 0; attempt <= m_cfg.retryCount; attempt++)
        {
         if(m_trade.PositionClose(ticket)) return true;
         if(!IsTransient(m_trade.ResultRetcode())) return false;
         Sleep(m_cfg.retryDelayMs);
        }
      return false;
     }

   // ปิดทั้ง basket — profitFirst=true: ไม้กำไรมากก่อน (ลำดับ CLOSE_ALL, DESIGN §4)
   //                 profitFirst=false: ไม้ขาดทุนน้อยสุดก่อน (ลำดับ UNLOCK, เทคนิค 3)
   bool              CloseAllOrdered(bool profitFirst)
     {
      // เก็บ (ticket, profit) แล้ว sort ก่อนปิด
      ulong  tickets[];
      double profits[];
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurs()) continue;
         ArrayResize(tickets, n + 1);
         ArrayResize(profits, n + 1);
         tickets[n] = tk;
         profits[n] = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         n++;
        }
      // selection sort ตามทิศที่ต้องการ (n เล็ก — maxPositions)
      for(int a = 0; a < n - 1; a++)
        {
         int best = a;
         for(int b = a + 1; b < n; b++)
            if(profitFirst ? (profits[b] > profits[best]) : (profits[b] > profits[best]))
               best = b; // ทั้งสองโหมดเริ่มจากค่ามาก (กำไรมาก / ขาดทุนน้อย = ค่ามากกว่า)
         if(best != a)
           {
            ulong  tt = tickets[a]; tickets[a] = tickets[best]; tickets[best] = tt;
            double pp = profits[a]; profits[a] = profits[best]; profits[best] = pp;
           }
        }
      bool allOk = true;
      for(int i = 0; i < n; i++)
         if(!ClosePosition(tickets[i])) allOk = false;
      return allOk;
     }

   // เทคนิค 4: จับคู่ปิดหักล้างสองไม้ตรงข้าม (ประหยัด spread) — โบรกต้องรองรับ
   bool              CloseBy(ulong ticket, ulong oppositeTicket)
     {
      return m_trade.PositionCloseBy(ticket, oppositeTicket);
     }
  };

#endif // HEQ_TRADEMANAGER_MQH
