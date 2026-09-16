//+------------------------------------------------------------------+
//|                                              VirtualReceiver.mqh |
//|                                 Copyright 2022-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.04"

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CVirtualSymbolReceiver;
class CVirtualInterface;

#include "../Utils/Macros.mqh"
#include "../Base/Receiver.mqh"
#include "VirtualOrder.mqh"
#include "VirtualSymbolReceiver.mqh"
#include "VirtualInterface.mqh"

//+------------------------------------------------------------------+
//| Class for converting open volumes to market positions (receiver) |
//+------------------------------------------------------------------+
class CVirtualReceiver : public CReceiver {
protected:
// Static pointer to a single class instance
   static   CVirtualReceiver *s_instance;

   CVirtualOrder     *m_orders[];         // Array of virtual positions

   CVirtualSymbolReceiver
   *m_symbolReceivers[];                  // Array of recipients for individual symbols

   CVirtualInterface
   *m_interface;                          // Interface object to show the status to the user

//--- Private methods
                     CVirtualReceiver();                    // Closed constructor
   bool              IsTradeAllowed();    // Is trading available?

public:
   static   datetime          s_lastChangeTime;       // Last successful correction time

                    ~CVirtualReceiver();  // Destructor

//--- Static methods
   static
   CVirtualReceiver  *Instance(ulong p_magic = 0);    // Singleton - creating and getting a single instance

   static void       Get(CVirtualStrategy *strategy,
                         CVirtualOrder *&orders[],
                         int n); // Allocate the necessary amount of virtual positions to the strategy

//--- Public methods
   virtual void      Changed()   override;
   void              OnOpen(CVirtualOrder *p_order);  // Handle virtual position opening
   void              OnClose(CVirtualOrder *p_order); // Handle virtual position closing
   void              Tick();     // Handle a tick for the array of virtual orders (positions)

   virtual bool      Correct() override;              // Adjustment of open volumes

   // Operator for receiving a symbolic receiver object
   CVirtualSymbolReceiver*      operator[](const string symbol);

   CVirtualOrder*    Order(int i);
   int               OrdersTotal();
};

// Initializing a static pointer to a single class instance
CVirtualReceiver *CVirtualReceiver::s_instance = NULL;
datetime CVirtualReceiver::s_lastChangeTime = 0;

//+------------------------------------------------------------------+
//| Closed constructor                                               |
//+------------------------------------------------------------------+
CVirtualReceiver::CVirtualReceiver() :
   m_interface(CVirtualInterface::Instance()) {
   CVirtualOrder::Reset();
}

//+------------------------------------------------------------------+
//| Is trading available?                                            |
//+------------------------------------------------------------------+
bool CVirtualReceiver::IsTradeAllowed() {
   return (true
           && MQLInfoInteger(MQL_TRADE_ALLOWED)
           && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
           && AccountInfoInteger(ACCOUNT_TRADE_EXPERT)
           && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
           && TerminalInfoInteger(TERMINAL_CONNECTED)
          );
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CVirtualReceiver::~CVirtualReceiver() {
   FOREACH(m_orders) delete m_orders[i]; // Remove virtual positions
   FOREACH(m_symbolReceivers) delete m_symbolReceivers[i]; // Remove symbol recipients
}

//+------------------------------------------------------------------+
//| Singleton - creating and getting a single instance               |
//+------------------------------------------------------------------+
CVirtualReceiver* CVirtualReceiver::Instance(ulong p_magic = 0) {
   if(!s_instance) {
      s_instance = new CVirtualReceiver();
   }
   if(s_magic == 0 && p_magic != 0) {
      s_magic = p_magic;
   }
   return s_instance;
}

//+------------------------------------------------------------------+
//| Allocate the necessary amount of virtual positions to strategy   |
//+------------------------------------------------------------------+
static void CVirtualReceiver::Get(CVirtualStrategy *strategy,   // Strategy
                                  CVirtualOrder *&orders[],     // Array of strategy positions
                                  int n                         // Required number
                                 ) {
   CVirtualReceiver *self = Instance();   // Receiver singleton
   CVirtualInterface *draw = CVirtualInterface::Instance();
   ArrayResize(orders, n);                // Expand the array of virtual positions
   FOREACH(orders) {
      orders[i] = new CVirtualOrder(strategy); // Fill the array with new objects
      APPEND(self.m_orders, orders[i]);
      draw.Add(orders[i]); // Register the created virtual position
   }
   PrintFormat(__FUNCTION__ + " | OK, Strategy orders: %d from %d total",
               ArraySize(orders),
               ArraySize(self.m_orders));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CVirtualReceiver::Changed() {
   m_isChanged = true;
   FOREACH(m_symbolReceivers) m_symbolReceivers[i].Changed();
}

//+------------------------------------------------------------------+
//| Handle opening a virtual position                                |
//+------------------------------------------------------------------+
void CVirtualReceiver::OnOpen(CVirtualOrder *p_order) {
   m_interface.Changed(p_order);

   if(p_order.IsPendingOrder()) {         // If this is a pending order,
      return;                             // do nothing
   }

   CVirtualSymbolReceiver* symbolReceiver = this[p_order.Symbol()];

   PrintFormat(__FUNCTION__"#%s | OPEN VirtualOrder #%d", p_order.Symbol(),  p_order.Id());
   symbolReceiver.Open(p_order); // Notify the symbol recipient about the new position
   m_isChanged = true;           // Remember that there are changes
}

//+------------------------------------------------------------------+
//| Handle closing a virtual position                                |
//+------------------------------------------------------------------+
void CVirtualReceiver::OnClose(CVirtualOrder *p_order) {
   m_interface.Changed(p_order);
   CVirtualSymbolReceiver* symbolReceiver = this[p_order.Symbol()];

   if(!!symbolReceiver) {
      PrintFormat(__FUNCTION__"#%s | CLOSE VirtualOrder #%d", p_order.Symbol(),  p_order.Id());
      symbolReceiver.Close(p_order);   // Notify the symbol receiver about the position closing
      m_isChanged = true;                    // Remember that there are changes
   }
}

//+------------------------------------------------------------------+
//| Handle a tick for the array of virtual orders (positions)        |
//+------------------------------------------------------------------+
void CVirtualReceiver::Tick() {
   FOREACH(m_orders) m_orders[i].Tick();
}

//+------------------------------------------------------------------+
//| Adjust open volumes                                              |
//+------------------------------------------------------------------+
bool CVirtualReceiver::Correct() {
   bool res = true;
   if(m_isChanged && IsTradeAllowed()) {
      // If there are changes, then we call the adjustment of the recipients of individual symbols
      FOREACH(m_symbolReceivers) res &= m_symbolReceivers[i].Correct();
      if(res) {
         m_isChanged = false;                // Reset the changes flag
         s_lastChangeTime = TimeCurrent();   // Save last successful correction time
      }
   }
   return res;
}

//+------------------------------------------------------------------+
//| Operator for receiving a symbolic receiver object                |
//+------------------------------------------------------------------+
CVirtualSymbolReceiver* CVirtualReceiver::operator[](const string symbol) {
   CVirtualSymbolReceiver* symbolReceiver = NULL;
// Search for the information object for the given symbol in the array
   int i;
   FIND(m_symbolReceivers, symbol, i);

// If found, return it
   if(i != -1) {
      symbolReceiver = m_symbolReceivers[i];
   } else {
      // Otherwise, create a new information object
      // If not found, then create a new recipient for the symbol
      symbolReceiver = new CVirtualSymbolReceiver(symbol);
      // and add it to the array of symbol recipients
      APPEND(m_symbolReceivers, symbolReceiver);
   }
   return symbolReceiver;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
CVirtualOrder* CVirtualReceiver::Order(int i) {
   return m_orders[i];
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CVirtualReceiver::OrdersTotal() {
   return ArraySize(m_orders);
}
//+------------------------------------------------------------------+
