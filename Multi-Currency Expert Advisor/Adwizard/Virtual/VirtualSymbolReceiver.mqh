//+------------------------------------------------------------------+
//|                                        VirtualSymbolReceiver.mqh |
//|                                 Copyright 2022-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.00"

#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>

#include "../Base/Receiver.mqh"
#include "../Utils/Macros.mqh"
#include "Money.mqh"
#include "VirtualOrder.mqh"

//+------------------------------------------------------------------+
//| Symbol receiver class                                            |
//+------------------------------------------------------------------+
class CVirtualSymbolReceiver : public CReceiver {
   string            m_symbol;         // Symbol
   CVirtualOrder     *m_orders[];      // Array of open virtual positions
   
   bool              m_isNetting;      // Is this a netting account?

   double            m_minMargin;      // Minimum margin for opening

   CPositionInfo     m_position;       // Object for obtaining properties of market positions
   CSymbolInfo       m_symbolInfo;     // Object for getting symbol properties
   CTrade            m_trade;          // Object for performing trading operations

   double            MarketVolume();   // Volume of open market positions
   double            VirtualVolume();  // Volume of open virtual positions
   bool              IsTradeAllowed(); // Is trading by symbol available?

   // Required volume difference
   double            DiffVolume(double marketVolume, double virtualVolume);

   // Volume correction for the required difference
   bool              Correct(double oldVolume, double diffVolume);

   // Auxiliary opening methods
   bool              ClearOpen(double diffVolume);
   bool              AddBuy(double volume);
   bool              AddSell(double volume);

   // Auxiliary closing methods
   bool              CloseBuyPartial(double volume);
   bool              CloseSellPartial(double volume);
   bool              CloseHedgingPartial(double volume, ENUM_POSITION_TYPE type);
   bool              CloseFull();

   // Check margin requirements
   bool              FreeMarginCheck(double volume, ENUM_ORDER_TYPE type);

public:
                     CVirtualSymbolReceiver(string p_symbol);  // Constructor
   bool              operator==(const string symbol) {// Operator for comparing by a symbol name
      return m_symbol == symbol;
   }
   void              Open(CVirtualOrder *p_order);    // Register opening a virtual position
   void              Close(CVirtualOrder *p_order);   // Register closing a virtual position

   virtual bool      Correct() override;              // Adjustment of open volumes
};


//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CVirtualSymbolReceiver::CVirtualSymbolReceiver(string p_symbol) :
   m_symbol(p_symbol),
   m_minMargin(100) {
   if(!m_symbolInfo.Name(m_symbol)) {
      PrintFormat(__FUNCTION__"#%s | ERROR: This symbol not found. Trade operations are disabled.", m_symbol);
      m_minMargin = -1;
   }
   ArrayResize(m_orders, 0, 128);
   m_trade.SetExpertMagicNumber(s_magic);
}

//+------------------------------------------------------------------+
//| Register opening a virtual position                              |
//+------------------------------------------------------------------+
void CVirtualSymbolReceiver::Open(CVirtualOrder *p_order) {
   APPEND(m_orders, p_order); // Add a position to the array
   m_isChanged = true;        // Set the changes flag
}

//+------------------------------------------------------------------+
//| Register closing a virtual position                              |
//+------------------------------------------------------------------+
void CVirtualSymbolReceiver::Close(CVirtualOrder *p_order) {
   REMOVE(m_orders, p_order); // Remove a position from the array
   m_isChanged = true;        // Set the changes flag
}

//+------------------------------------------------------------------+
//| Adjust open volumes                                              |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::Correct() {
   bool res = true;
   if(m_isChanged && IsTradeAllowed()) {
      double marketVolume = MarketVolume();
      double virtualVolume = VirtualVolume();
      double diffVolume = DiffVolume(marketVolume, virtualVolume);

      // If there is a need to adjust the volume, then do that
      if(MathAbs(diffVolume) > 0.001) {
         res = Correct(marketVolume, diffVolume);
         if(res) {
            PrintFormat(__FUNCTION__"#%s | CORRECTED %.2f -> %.2f", m_symbol, marketVolume, virtualVolume);
         }
      }
      m_isChanged = !res;
   }
   return res;
}

//+------------------------------------------------------------------+
//| Volume of open market positions                                  |
//+------------------------------------------------------------------+
double CVirtualSymbolReceiver::MarketVolume() {
   double volume = 0;
   string symbol;
   ulong magic;
   int type;

   CPositionInfo p;

   for(int i = 0; i < PositionsTotal(); i++) {
      if(p.SelectByIndex(i)) {
         symbol = p.Symbol();
         magic = p.Magic();
         type = (int) p.PositionType();

         if(magic == s_magic && symbol == m_symbol) {
            volume += p.Volume() * (-(type) * 2 + 1);
         }
      }
   }
   return volume;
}

//+------------------------------------------------------------------+
//| Volume of open virtual positions                                 |
//+------------------------------------------------------------------+
double CVirtualSymbolReceiver::VirtualVolume() {
   double volume = 0;
   FOREACH(m_orders) volume += CMoney::Volume(m_orders[i]);
   return volume;
}

//+------------------------------------------------------------------+
//| Is trading by symbol available?                                  |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::IsTradeAllowed() {
   return (true
           && m_minMargin > 0
           && m_symbolInfo.TradeMode() == SYMBOL_TRADE_MODE_FULL
          );
}

//+------------------------------------------------------------------+
//| Required volume difference                                       |
//+------------------------------------------------------------------+
double CVirtualSymbolReceiver::DiffVolume(double marketVolume, double virtualVolume) {
// Get the limit values of permissible volumes
   double minLot = MathMax(0.01, m_symbolInfo.LotsMin());
   double maxLot = m_symbolInfo.LotsMax();
   double lotStep = MathMax(0.01, m_symbolInfo.LotsStep());

// Define how much the volume of open positions for the symbol should be changed
   double oldVolume = marketVolume;
   double newVolume = virtualVolume;
   int ratio = 0;

// Check that the new volume is within acceptable limits
   if(MathAbs(newVolume) > maxLot) {
      newVolume = maxLot * MathAbs(newVolume) / newVolume;
   }

   if(MathAbs(newVolume) < minLot && MathAbs(newVolume) > 0) {
      if(MathAbs(newVolume) < 0.5 * minLot) {
         newVolume = 0;
      } else {
         newVolume = minLot * MathAbs(newVolume) / newVolume;
      }
   }
// How much should we change the open volume?
   double diffVolume = newVolume - oldVolume;
   int digits = 2;

   if (lotStep >= 0.1 && lotStep < 1.0) {
      digits = 1;
   } else if (lotStep >= 1.0) {
      digits = 0;
   }

   if(oldVolume == 0) {
      if (minLot >= 0.1 && lotStep < 1.0) {
         digits = 1;
      } else if (minLot >= 1.0) {
         digits = 0;
      }
   }

   diffVolume = NormalizeDouble(diffVolume, digits);

   ratio = (int) MathRound(MathAbs(diffVolume) / lotStep);
   if(MathAbs(ratio * lotStep - MathAbs(diffVolume)) > 0.0000001) {
      diffVolume = ratio * lotStep * MathAbs(diffVolume) / diffVolume;
   }

   return diffVolume;
}

//+------------------------------------------------------------------+
//| Volume correction for the required difference                    |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::Correct(double oldVolume, double diffVolume) {
   bool res = false;

   double volume = MathAbs(diffVolume);

   if(oldVolume > 0) { // Have BUY position
      if(diffVolume > 0) { // New BUY position
         res = AddBuy(volume);
      } else if(diffVolume < 0) { // New SELL position
         if(volume < oldVolume) {
            res = CloseBuyPartial(volume);
         } else {
            res = CloseFull();

            if(res && volume > oldVolume) {
               res = AddSell(volume - oldVolume);
            }
         }
      }
   } else if(oldVolume < 0) { // Have SELL position
      if(diffVolume < 0) { // New SELL position
         res = AddSell(volume);
      } else if(diffVolume > 0) { // New BUY position
         if(volume < -oldVolume) {
            res = CloseSellPartial(volume);
         } else {
            res = CloseFull();

            if(res && volume > -oldVolume) {
               res = AddBuy(volume + oldVolume);
            }
         }
      }
   } else { // No old position
      res = ClearOpen(diffVolume);
   }

   return res;
}

//+------------------------------------------------------------------+
//| Open BUY or SELL market position                                 |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::ClearOpen(double diffVolume) {
   double volume = MathAbs(diffVolume);
   double minLot = MathAbs(m_symbolInfo.LotsMin());

   if(minLot < 1e-12 || volume < minLot) {
      return true;
   }

   bool res = true;
   ENUM_ORDER_TYPE type = (diffVolume > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   if(FreeMarginCheck(volume, type)) {
      PrintFormat(__FUNCTION__"#%s | OPEN %s %.2f", m_symbol, (diffVolume > 0 ? "BUY" : "SELL"), volume);

      if(diffVolume > 0) {
         res = m_trade.Buy(volume, m_symbol);
      } else {
         res = m_trade.Sell(volume, m_symbol);
      }

      if(!res) {
         PrintFormat(__FUNCTION__"#%s | ERROR: %d, Result Code: %d", m_symbol, _LastError, m_trade.ResultRetcode());
      }
   }

   return res;
}

//+------------------------------------------------------------------+
//| Open additional BUY volume                                       |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::AddBuy(double volume) {
   return ClearOpen(volume);
}

//+------------------------------------------------------------------+
//| Open additional SELL volume                                      |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::AddSell(double volume) {
   return ClearOpen(-volume);
}

//+------------------------------------------------------------------+
//| Partial closure of BUY volume by symbol                          |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::CloseBuyPartial(double volume) {
   bool res = true;

   PrintFormat(__FUNCTION__"#%s | CLOSE BUY partial | volume = %.2f", m_symbol, volume);

   if(volume > 0) {
      if(m_isNetting) {
         res = m_trade.Sell(volume, m_symbol, 0, 0, 0);
      } else {
         res = CloseHedgingPartial(volume, POSITION_TYPE_BUY);
      }
   }

   if(!res) {
      PrintFormat(__FUNCTION__"#%s | ERROR: %d, Result Code: %d", m_symbol, _LastError, m_trade.ResultRetcode());
      ResetLastError();
   }
   return res;
}

//+------------------------------------------------------------------+
//| Partial closure of SELL volume by symbol                         |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::CloseSellPartial(double volume) {
   bool res = true;

   PrintFormat(__FUNCTION__"#%s | CLOSE SELL partial | volume = %.2f", m_symbol, volume);

   if(volume > 0) {
      if(m_isNetting) {
         res &= m_trade.Buy(volume, m_symbol, 0, 0, 0);
      } else {
         res &= CloseHedgingPartial(volume, POSITION_TYPE_SELL);
      }
   }

   if(!res) {
      PrintFormat(__FUNCTION__"#%s | ERROR: %d, Result Code: %d", m_symbol, _LastError, m_trade.ResultRetcode());
      ResetLastError();
   }
   return res;
}

//+------------------------------------------------------------------+
//| Partial closure of BUY or SELL by symbol on the Hedge account    |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::CloseHedgingPartial(double volume, ENUM_POSITION_TYPE type) {
   bool res = true;

   ulong ticket;
   double positionVolume;

   for(int i = 0; i < PositionsTotal(); i++) {
      if (m_position.SelectByIndex(i)) {
         ticket = m_position.Ticket();

         if(m_position.Magic() == s_magic && m_position.Symbol() == m_symbol && m_position.PositionType() == type) {
            positionVolume = m_position.Volume();

            if(volume > 0) {
               if(positionVolume <= volume) {
                  res &= m_trade.PositionClose(ticket);
                  volume -= positionVolume;
               } else {
                  res &= m_trade.PositionClosePartial(ticket, volume);
                  volume = 0;
                  break;
               }
            } else {
               break;
            }
         }
      }
   }

   if(volume > 0) {
      res = false;
   }
   return res;
}

//+------------------------------------------------------------------+
//| Complete volume closure by symbol                                |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::CloseFull() {
   bool res = true;

   ulong ticket;
   bool found = true;

   while(found && !IsStopped()) {
      found = false;
      for(int i = 0; i < PositionsTotal(); i++) {
         if (m_position.SelectByIndex(i)) {
            if(m_position.Magic() == s_magic && (m_position.Symbol() == m_symbol)) {
               found = true;
               ticket = m_position.Ticket();
               res &= m_trade.PositionClose(ticket);
               break;
            }
         }
      }
      if(!res) {
         found = false;
      }
   }
   return res;
}

//+------------------------------------------------------------------+
//| Check margin requirements                                        |
//+------------------------------------------------------------------+
bool CVirtualSymbolReceiver::FreeMarginCheck(double volume, ENUM_ORDER_TYPE type) {
   double freeMarginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   if (freeMarginLevel != 0 && freeMarginLevel < m_minMargin) {
      PrintFormat(__FUNCTION__" | Margin level (%.2f) is less than minimum required (%.2f)",
                  freeMarginLevel, m_minMargin);
      return false;
   }

#ifdef __MQL4__
   double free_margin = AccountFreeMarginCheck(m_symbol, type, volume);
//-- if there is not enough money
   if(free_margin < 0) {
      PrintFormat(__FUNCTION__" | ERROR: Not enough money for %s %.2f, %s",
                  (type == OP_BUY) ? "BUY" : "SELL", volume, m_symbol);
      return(false);
   }
//--- checking successful
   return(true);
#endif

#ifdef __MQL5__
//--- get the open price
   MqlTick mqltick;
   SymbolInfoTick(m_symbol, mqltick);
   double price = mqltick.ask;
   if(type == ORDER_TYPE_SELL) {
      price = mqltick.bid;
   }
//--- values of the required and free margin
   double margin, free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
//--- call the verification function
   if(!OrderCalcMargin(type, m_symbol, volume, price, margin)) {
      //--- something is wrong, report and return 'false'
      PrintFormat(__FUNCTION__" | ERROR: Can't calc margin via OrderCalcMargin(), code=%d", GetLastError());
      return(false);
   }
//--- if there are insufficient funds to perform the operation
   if(margin > free_margin) {
      //--- report the error and return 'false'
      PrintFormat(__FUNCTION__" | ERROR: Not enough money for %s %.2f, %s",
                  (type == ORDER_TYPE_BUY) ? "BUY" : "SELL", volume, m_symbol);
      return(false);
   }
//--- verification successful
   return(true);
#endif
}
//+------------------------------------------------------------------+
