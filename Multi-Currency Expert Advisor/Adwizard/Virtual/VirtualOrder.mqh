//+------------------------------------------------------------------+
//|                                                 VirtualOrder.mqh |
//|                                 Copyright 2019-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.09"

#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Preliminary class definitions                                    |
//+------------------------------------------------------------------+
class CVirtualOrder;
class CVirtualReceiver;
class CVirtualStrategy;

#include "../Utils/SymbolsMonitor.mqh"
#include "VirtualReceiver.mqh"
#include "VirtualStrategy.mqh"

// Structure for reading/writing 
// basic properties of a virtual order/position from the database
struct VirtualOrderStruct {
   string            strategyHash;
   int               strategyIndex;
   ulong             ticket;
   string            symbol;
   double            lot;
   ENUM_ORDER_TYPE   type;
   datetime          openTime;
   double            openPrice;
   double            stopLoss;
   double            takeProfit;
   datetime          closeTime;
   double            closePrice;
   datetime          expiration;
   string            comment;
   double            point;
};

//+------------------------------------------------------------------+
//| Class of virtual orders and positions                            |
//+------------------------------------------------------------------+
class CVirtualOrder {
private:
//--- Static fields
   static ulong      s_count;          // Counter of all created CVirtualOrder objects
   static ulong      s_ticket;
   CSymbolInfo       *m_symbolInfo;    // Object for getting symbol properties

//--- Related recipient objects and strategies
   CSymbolsMonitor   *m_symbols;
   CVirtualReceiver  *m_receiver;
   CVirtualStrategy  *m_strategy;

//--- Order (position) properties
   ulong             m_id;             // ID
   ulong             m_ticket;         // Ticket
   string            m_symbol;         // Symbol
   double            m_lot;            // Volume
   ENUM_ORDER_TYPE   m_type;           // Type
   double            m_openPrice;      // Open price
   double            m_stopLoss;       // StopLoss level
   double            m_takeProfit;     // TakeProfit level
   string            m_comment;        // Comment
   datetime          m_expiration;     // Expiration time

   datetime          m_openTime;       // Open time

//--- Closed order (position) properties
   double            m_closePrice;     // Close price
   datetime          m_closeTime;      // Close time
   string            m_closeReason;    // Closure reason

   double            m_point;          // Point value

   bool              m_isStopLoss;     // StopLoss activation property
   bool              m_isTakeProfit;   // TakeProfit activation property
   bool              m_isExpired;      // Expiration flag

//--- Private methods
   bool              CheckClose();     // Check closure conditions
   bool              CheckTrigger();   // Check for pending order trigger

public:
                     CVirtualOrder(
      CVirtualStrategy *p_strategy
   );                                  // Constructor

                    ~CVirtualOrder() {
      if(!!m_symbolInfo) delete m_symbolInfo;
   }

//--- Methods for checking the position (order) status
   bool              IsOpen() {        // Is the order open?
      return(this.m_openTime > 0 && this.m_closeTime == 0);
   };
   bool              IsClosed() {      // Is the order closed?
      return(this.m_openTime > 0 && this.m_closeTime > 0);
   };
   bool              IsMarketOrder() { // Is this a market position?
      return IsOpen() && (m_type == ORDER_TYPE_BUY || m_type == ORDER_TYPE_SELL);
   }
   bool              IsPendingOrder() {// Is it a pending order?
      return IsOpen() && (m_type == ORDER_TYPE_BUY_LIMIT
                          || m_type == ORDER_TYPE_BUY_STOP
                          || m_type == ORDER_TYPE_SELL_LIMIT
                          || m_type == ORDER_TYPE_SELL_STOP);
   }
   bool              IsBuyOrder() {    // Is this an open BUY position?
      return IsOpen() && (m_type == ORDER_TYPE_BUY
                          || m_type == ORDER_TYPE_BUY_LIMIT
                          || m_type == ORDER_TYPE_BUY_STOP);
   }
   bool              IsSellOrder() {   // Is this an open SELL position?
      return IsOpen() && (m_type == ORDER_TYPE_SELL
                          || m_type == ORDER_TYPE_SELL_LIMIT
                          || m_type == ORDER_TYPE_SELL_STOP);
   }
   bool              IsStopOrder() {   // Is it a pending STOP order?
      return IsOpen() && (m_type == ORDER_TYPE_BUY_STOP || m_type == ORDER_TYPE_SELL_STOP);
   }
   bool              IsLimitOrder() {  // Is it a pending LIMIT order?
      return IsOpen() && (m_type == ORDER_TYPE_BUY_LIMIT || m_type == ORDER_TYPE_SELL_LIMIT);
   }

//--- Methods for receiving position (order) properties
   ulong             Id() {            // ID
      return m_id;
   }
   ulong             Ticket() {        // Ticket
      return m_ticket;
   }
   CStrategy         *Strategy() {
      return m_strategy;
   }
   ENUM_ORDER_TYPE   Type() {
      return m_type;
   }
   string            TypeName() {
      string s = StringSubstr(EnumToString(m_type), 11);
      StringReplace(s, "_", " ");
      return s;
   }
   double            Lot() {
      return m_lot;
   }
   double            Volume() {        // Volume with direction
      return IsBuyOrder() ? m_lot : (IsSellOrder() ? -m_lot : 0);
   }
   double            Profit();         // Current profit
   double            ClosedProfit();

   string            Symbol() {        // Symbol
      return m_symbol;
   }
   double            OpenPrice() {
      return m_openPrice;
   }
   datetime          OpenTime() {
      return m_openTime;
   }
   double            ClosePrice() {
      return m_closePrice;
   }
   datetime          CloseTime() {
      return m_closeTime;
   }
   double            FittedBalance() {
      return m_strategy.FittedBalance();
   }
   double            StopLoss() {
      return m_stopLoss;
   }
   void              StopLoss(double value) {
      m_stopLoss = value;
   }
   double            TakeProfit() {
      return m_takeProfit;
   }
   void              TakeProfit(double value) {
      m_takeProfit = value;
   }

//--- Methods for handling positions (orders)
   bool              CVirtualOrder::Open(string symbol,
                                         ENUM_ORDER_TYPE type,
                                         double lot,
                                         double price,
                                         double sl = 0,
                                         double tp = 0,
                                         string comment = "",
                                         datetime expiration = 0,
                                         bool inPoints = false); // Open a position (order)

   void              Expiration(datetime p_expiration) {
      if(IsOpen()) {
         m_expiration = p_expiration;
      }
   }

   void              Tick();     // Handle tick for position (order)
   void              Close();    // Close position (order)
   void              Clear() {
      m_lot = 0;
   }

   virtual void      Load(const VirtualOrderStruct &o);   // Load status
   virtual void      Save(VirtualOrderStruct &o);   // Save status

   static void       Reset() {
      s_count = 0;
   }

   // Are there any open market virtual positions?
   static bool       HasMarket(CVirtualOrder* &p_orders[]);

   string            operator~();         // Convert object to string
};

// Initialize class static fields
ulong                CVirtualOrder::s_count = 0;
ulong                CVirtualOrder::s_ticket = 0;

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CVirtualOrder::CVirtualOrder(CVirtualStrategy *p_strategy) :
// Initialization list
   m_id(++s_count),  // New ID = object counter + 1
   m_ticket(0),
   m_receiver(CVirtualReceiver::Instance()),
   m_strategy(p_strategy),
   m_symbol(""),
   m_lot(0),
   m_type(-1),
   m_openPrice(0),
   m_stopLoss(0),
   m_takeProfit(0),
   m_openTime(0),
   m_comment(""),
   m_expiration(0),
   m_closePrice(0),
   m_closeTime(0),
   m_closeReason(""),
   m_point(0) {
   PrintFormat(__FUNCTION__ + "#%d | CREATED VirtualOrder", m_id);
   m_symbolInfo = NULL;
   m_symbols = CSymbolsMonitor::Instance();
}

//+------------------------------------------------------------------+
//| Open a virtual position (order)                                  |
//+------------------------------------------------------------------+
bool CVirtualOrder::Open(string symbol,         // Symbol
                         ENUM_ORDER_TYPE type,  // Type (BUY or SELL)
                         double lot,            // Volume
                         double price = 0,      // Open price
                         double sl = 0,         // StopLoss level (price or points)
                         double tp = 0,         // TakeProfit level (price or points)
                         string comment = "",   // Comment
                         datetime expiration = 0,  // Expiration time
                         bool inPoints = false  // Are the SL and TP levels set in points?
                        ) {
   if(IsOpen()) { // If the position is already open, then do nothing
      PrintFormat(__FUNCTION__ "#%d | ERROR: Order is opened already!", m_id);
      return false;
   }

// Get a pointer to the information object for the desired symbol from the symbol monitor
   m_symbolInfo = m_symbols[symbol];

   if(!!m_symbolInfo) {
      //m_symbolInfo.RefreshRates();  // Update information about current prices

      // Initialize position properties
      m_ticket = ++s_ticket;
      m_openPrice = price;
      m_symbol = symbol;
      m_lot = lot;
      m_openTime = TimeCurrent();
      m_closeTime = 0;
      m_type = type;
      m_comment = comment;
      m_expiration = expiration;

      // The position (order) being opened is not closed by SL, TP or expiration
      m_isStopLoss = false;
      m_isTakeProfit = false;
      m_isExpired = false;

      m_point = m_symbolInfo.Point();

      double bid = m_symbolInfo.Bid();
      double ask = m_symbolInfo.Ask();
      double spread = ((ask - bid) / m_point);

      //m_symbolInfo.Spread();

      // Depending on the direction, set the opening price, as well as the SL and TP levels.
      // If SL and TP are specified in points, then we first calculate their price levels
      // relative to the open price
      if(IsBuyOrder()) {
         if(type == ORDER_TYPE_BUY) {
            m_openPrice = ask;
         }
         m_stopLoss = (sl > 0 ? (inPoints ? m_openPrice - sl * m_point - spread * m_point : sl) : 0);
         m_takeProfit = (tp > 0 ? (inPoints ? m_openPrice + tp * m_point : tp) : 0);
      } else if(IsSellOrder()) {
         if(type == ORDER_TYPE_SELL) {
            m_openPrice = bid;
         }
         m_stopLoss = (sl > 0 ? (inPoints ? m_openPrice + sl * m_point : sl) : 0);
         m_takeProfit = (tp > 0 ? (inPoints ? m_openPrice - tp * m_point - spread * m_point : tp) : 0);
      }

      // Notify the recipient and the strategy that the position (order) is open
      m_receiver.OnOpen(&this);
      m_strategy.OnOpen(&this);

      PrintFormat(__FUNCTION__"#%d | OPEN %s: %s %s %.2f | Price=%.5f | SL=%.5f | TP=%.5f | %s | %s",
                  m_id, (IsMarketOrder() ? "Market" : "Pending"), StringSubstr(EnumToString(type), 11),
                  m_symbol, m_lot, m_openPrice, m_stopLoss, m_takeProfit, m_comment,
                  (m_expiration ? TimeToString(m_expiration) : "-"));

      return true;
   } else {
      PrintFormat(__FUNCTION__"#%d | ERROR: Can't find symbol %s for "
                  "OPEN %s: %s %s %.2f | Price=%.5f | SL=%.5f | TP=%.5f | %s | %s",
                  m_id, m_symbol, (IsMarketOrder() ? "Market" : "Pending"), StringSubstr(EnumToString(type), 11),
                  m_symbol, m_lot, m_openPrice, m_stopLoss, m_takeProfit, m_comment,
                  (m_expiration ? TimeToString(m_expiration) : "-"));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Close a position                                                 |
//+------------------------------------------------------------------+
void CVirtualOrder::Close() {
   if(IsOpen()) { // If the position is open
      // Define the closure reason to be displayed in the log
      string closeReason = "";

      if(m_isStopLoss) {
         closeReason += "[SL]";
      } else if(m_isTakeProfit) {
         closeReason += "[TP]";
      } else if(m_isExpired) {
         closeReason += "[EX]";
      } else {
         closeReason += "[CL]";
      }

      PrintFormat(__FUNCTION__ + "#%d | CLOSE %s: %s %s %.2f | Profit=%.2f %s | %s",
                  m_id, (IsMarketOrder() ? "Market" : "Pending"), StringSubstr(EnumToString(m_type), 11),
                  m_symbol, m_lot, Profit(), closeReason, m_comment);

      m_closeTime = TimeCurrent();  // Position closing time

      // Save the close price depending on the type
      if(m_type == ORDER_TYPE_BUY) {
         m_closePrice = m_symbolInfo.Bid();
      } else if(m_type == ORDER_TYPE_SELL) {
         m_closePrice = m_symbolInfo.Ask();
      } else {
         m_closePrice = 0;
      }

      // Notify the recipient and the strategy that the position (order) is closed
      m_receiver.OnClose(&this);
      m_strategy.OnClose(&this);
   }
}

//+------------------------------------------------------------------+
//| Calculate the current profit                                     |
//+------------------------------------------------------------------+
double CVirtualOrder::Profit() {
   double profit = 0;
   if(IsMarketOrder()) {   // If this is a market virtual position
      //m_symbolInfo.Name(m_symbol);     // Select the desired symbol
      //m_symbolInfo.RefreshRates();     // Update information about current prices

      // Current price, at which the position can be closed
      double closePrice = (m_type == ORDER_TYPE_BUY) ? m_symbolInfo.Bid() : m_symbolInfo.Ask();

      // Profit in the form of the difference between open and close
      if(m_type == ORDER_TYPE_BUY) {
         profit = closePrice - m_openPrice;
      } else {
         profit = m_openPrice - closePrice;
      }

      if(m_point > 1e-10) {   // If the point size is known, then
         // Recalculate the profit from the price difference into monetary terms for a volume of 1 lot
         if(profit > 0) {
            profit = profit / m_point * m_symbolInfo.TickValueProfit();
         } else {
            profit = profit / m_point * m_symbolInfo.TickValueLoss();
         }
      } else {
         PrintFormat(__FUNCTION__ + "#%d | ERROR: Point for %s is undefined", m_id, m_symbol);
         m_point = m_symbolInfo.Point();
      }
      // Recalculate profit for position volume
      profit *= m_lot;
   }

   return profit;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CVirtualOrder::ClosedProfit() {
   double profit = 0;
   if(IsClosed()) {

      // If this is a market virtual position
      //s_symbolInfo.Name(m_symbol);     // Select the desired symbol
      //s_symbolInfo.RefreshRates();     // Update information about current prices

      // Current price, at which the position can be closed
      double closePrice = m_closePrice;

      // Profit in the form of the difference between open and close
      if(m_type == ORDER_TYPE_BUY) {
         profit = closePrice - m_openPrice;
      } else if(m_type == ORDER_TYPE_SELL) {
         profit = m_openPrice - closePrice;
      }

      if(m_point > 1e-10) {   // If the point size is known, then
         // Recalculate the profit from the price difference into monetary terms for a volume of 1 lot
         if(profit > 0) {
            profit = profit / m_point * m_symbolInfo.TickValueProfit();
         } else {
            profit = profit / m_point * m_symbolInfo.TickValueLoss();
         }
      } else {
         PrintFormat(__FUNCTION__ + "#%d | ERROR: Point for %s is undefined", m_id, m_symbol);
         m_point = m_symbolInfo.Point();
      }
      // Recalculate profit for position volume
      profit *= m_lot;
   }

   return profit;
}

//+------------------------------------------------------------------+
//| Check the need to close by SL, TP or EX                          |
//+------------------------------------------------------------------+
bool CVirtualOrder::CheckClose() {
   if(IsMarketOrder()) {               // If this is a market virtual position,
      //s_symbolInfo.Name(m_symbol);     // Select the desired symbol
      //s_symbolInfo.RefreshRates();     // Update information about current prices

      // Current price, at which the position can be closed
      double closePrice = (m_type == ORDER_TYPE_BUY) ? m_symbolInfo.Bid() : m_symbolInfo.Ask();
      //double spread = m_symbolInfo.Spread();
      //double lastHigh = iHigh(m_symbol, PERIOD_M1, 1);
      //double lastLow = iLow(m_symbol, PERIOD_M1, 1) + spread;

      bool res = false;
      // Check that the price has reached SL or TP
      if(m_type == ORDER_TYPE_BUY) {
         m_isStopLoss = (m_stopLoss > 0 && closePrice <= m_stopLoss);
         m_isTakeProfit = (m_takeProfit > 0 && (closePrice >= m_takeProfit
                                                //|| lastHigh >= m_takeProfit
                                               ));
      } else if(m_type == ORDER_TYPE_SELL) {
         m_isStopLoss = (m_stopLoss > 0 && closePrice >= m_stopLoss);
         m_isTakeProfit = (m_takeProfit > 0 && (closePrice <= m_takeProfit
                                                // || lastLow <= m_takeProfit
                                               ));
      }

      // Has SL or TP been reached?
      res = (m_isStopLoss || m_isTakeProfit);

      if(res) {
         PrintFormat(__FUNCTION__ + "#%d | %s REACHED at %.5f: %.5f | %.5f, Profit=%.2f | %s",
                     m_id, (m_isStopLoss ? "SL" : "TP"), closePrice, m_stopLoss, m_takeProfit,
                     Profit(), m_comment);
         return true;
      }
   } else if(IsPendingOrder()) {    // If this is a pending order
      // Check if the expiration time has been reached, if one is specified
      if(m_expiration > 0 && m_expiration < TimeCurrent()) {
         m_isExpired = true;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Handle a tick of a single virtual order (position)               |
//+------------------------------------------------------------------+
void CVirtualOrder::Tick() {
   if(IsOpen()) {  // If this is an open virtual position or order
      if(CheckClose()) {  // Check if SL or TP levels have been reached
         Close();         // Close when reached
      } else if (IsPendingOrder()) {   // If this is a pending order
         CheckTrigger();  // Check if it is triggered
      }
   }
}

//+------------------------------------------------------------------+
//| Check whether a pending order is triggered                       |
//+------------------------------------------------------------------+
bool CVirtualOrder::CheckTrigger() {
   if(IsPendingOrder()) {
      //m_symbolInfo.Name(m_symbol);     // Select the desired symbol
      //m_symbolInfo.RefreshRates();     // Update information about current prices
      double bid = m_symbolInfo.Bid();
      double ask = m_symbolInfo.Ask();
      double spread = ((ask - bid) / m_point);

      double price = (IsBuyOrder()) ? ask : bid;


      // If the price has reached the opening levels, turn the order into a position
      if(false
            || (m_type == ORDER_TYPE_BUY_LIMIT && price <= m_openPrice)
            || (m_type == ORDER_TYPE_BUY_STOP  && price >= m_openPrice)
        ) {
         PrintFormat(__FUNCTION__"#%d | OPEN %s at %.5f -> BUY at %.5f (Spread: %.0f)",
                     m_id, StringSubstr(EnumToString(m_type), 11), m_openPrice, price, spread);
         m_type = ORDER_TYPE_BUY;
      } else if(false
                || (m_type == ORDER_TYPE_SELL_LIMIT && price >= m_openPrice)
                || (m_type == ORDER_TYPE_SELL_STOP  && price <= m_openPrice)
               ) {
         PrintFormat(__FUNCTION__"#%d | OPEN %s at %.5f -> SELL at %.5f (Spread: %.0f)",
                     m_id, StringSubstr(EnumToString(m_type), 11), m_openPrice, price, spread);
         m_type = ORDER_TYPE_SELL;
      }

      // If the order turned into a position
      if(IsMarketOrder()) {
         m_openPrice = price; // Remember the open price

         // Notify the recipient and the strategy of the position opening
         m_receiver.OnOpen(&this);
         m_strategy.OnOpen(&this);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Save status                                                      |
//+------------------------------------------------------------------+
void CVirtualOrder::Save(VirtualOrderStruct &o) {
   o.ticket = m_ticket;
   o.symbol = m_symbol;
   o.lot = m_lot;
   o.type = m_type;
   o.openPrice = m_openPrice;
   o.stopLoss = m_stopLoss;
   o.takeProfit = m_takeProfit;
   o.openTime = m_openTime;
   o.closePrice = m_closePrice;
   o.closeTime = m_closeTime;
   o.expiration = m_expiration;
   o.comment = m_comment;
   o.point = m_point;
}


//+------------------------------------------------------------------+
//| Load status                                                      |
//+------------------------------------------------------------------+
void CVirtualOrder::Load(const VirtualOrderStruct &o) {
   m_ticket = o.ticket;
   m_symbol = o.symbol;
   m_lot = o.lot;
   m_type = o.type;
   m_openPrice = o.openPrice;
   m_stopLoss = o.stopLoss;
   m_takeProfit = o.takeProfit;
   m_openTime = o.openTime;
   m_closePrice = o.closePrice;
   m_closeTime = o.closeTime;
   m_expiration = o.expiration;
   m_comment = o.comment;
   m_point = o.point;

   PrintFormat(__FUNCTION__" | %s", ~this);

   s_ticket = MathMax(s_ticket, m_ticket);
   
   m_symbolInfo = m_symbols[m_symbol];

// Notify the recipient and the strategy that the position (order) is open
   if(IsOpen()) {
      m_receiver.OnOpen(&this);
      m_strategy.OnOpen(&this);
   } else {
      m_receiver.OnClose(&this);
      m_strategy.OnClose(&this);
   }
}

//+------------------------------------------------------------------+
//| Are there any open market virtual positions?                     |
//+------------------------------------------------------------------+
bool CVirtualOrder::HasMarket(CVirtualOrder *&p_orders[]) {
   FOREACH(p_orders) if (p_orders[i].IsMarketOrder()) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Convert an object to a string                                    |
//+------------------------------------------------------------------+
string CVirtualOrder::operator~() {
   if(IsOpen()) {
      return StringFormat("#%d %s %s %.2f in %s at %.5f (%.5f, %.5f). %s, %f",
                          m_id, TypeName(), m_symbol, m_lot,
                          TimeToString(m_openTime), m_openPrice,
                          m_stopLoss, m_takeProfit,
                          TimeToString(m_closeTime), m_closePrice);
   } else {
      return StringFormat("#%d --- ", m_id);
   }

}
//+------------------------------------------------------------------+
