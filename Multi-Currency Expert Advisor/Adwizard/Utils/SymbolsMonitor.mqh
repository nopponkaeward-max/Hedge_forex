//+------------------------------------------------------------------+
//|                                               SymbolsMonitor.mqh |
//|                                 Copyright 2022-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.01"


#include <Trade\SymbolInfo.mqh>
#include "Macros.mqh"
#include "NewBarEvent.mqh"

//+----------------------------------------------------------------------+
//| Class for obtaining information about trading instruments (symbols)  |
//+----------------------------------------------------------------------+
class CSymbolsMonitor {
protected:
// Static pointer to a single class instance
   static   CSymbolsMonitor *s_instance;

// Array of information objects for different symbols
   CSymbolInfo       *m_symbols[];

   string            m_symbolsNames[];

//--- Private methods
   CSymbolsMonitor() {} // Closed constructor

public:
   ~CSymbolsMonitor();   // Destructor

//--- Static methods
   static
   CSymbolsMonitor   *Instance();   // Singleton - creating and getting a single instance

   // Tick handling for objects of different symbols
   void              Tick();

   // A string with the names of all symbols used
   string            SymbolsNames();

   // Operator for getting an object with information about a specific symbol
   CSymbolInfo*      operator[](const string &symbol);
};

// Initializing a static pointer to a single class instance
CSymbolsMonitor *CSymbolsMonitor::s_instance = NULL;


//+------------------------------------------------------------------+
//| Singleton - creating and getting a single instance               |
//+------------------------------------------------------------------+
CSymbolsMonitor* CSymbolsMonitor::Instance() {
   if(!s_instance) {
      s_instance = new CSymbolsMonitor();
   }
   return s_instance;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSymbolsMonitor::~CSymbolsMonitor() {
// Delete all created information objects for symbols
   FOREACH(m_symbols) if(!!m_symbols[i]) delete m_symbols[i];
}

//+------------------------------------------------------------------+
//| Handle a tick for the array of virtual orders (positions)        |
//+------------------------------------------------------------------+
void CSymbolsMonitor::Tick() {
// Update quotes every minute and specification once a day
   FOREACH(m_symbols) {
      if(IsNewBar(m_symbols[i].Name(), PERIOD_D1)) {
         m_symbols[i].Refresh();
      }
      if(IsNewBar(m_symbols[i].Name(), PERIOD_M1)) {
         m_symbols[i].RefreshRates();
      }
   }
}

//+------------------------------------------------------------------+
//| A string with the names of all symbols used                      |
//+------------------------------------------------------------------+
string CSymbolsMonitor::SymbolsNames() {
   string names = "";
   
   JOIN(m_symbolsNames, names, ", ");
   
   return names;
}

//+----------------------------------------------------------------------------+
//| Operator for getting an object with information about a specific symbol    |
//+----------------------------------------------------------------------------+
CSymbolInfo* CSymbolsMonitor::operator[](const string &name) {
// Search for the information object for the given symbol in the array
   int i;
   SEARCH(m_symbols, m_symbols[i].Name() == name, i);

// If found, return it
   if(i != -1) {
      return m_symbols[i];
   } else if (name != "") {
      // Otherwise, create a new information object
      CSymbolInfo *s = new CSymbolInfo();
      // Select the desired symbol for it
      if(s.Name(name)) {
         // If the selection is successful, update the quotes
         s.RefreshRates();
         // Add to the array of information objects and return it
         APPEND(m_symbols, s);

         APPEND(m_symbolsNames, name);

         // Register the event handler for a new bar on the minimum timeframe
         IsNewBar(name, PERIOD_M1);
         return s;
      } else {
         PrintFormat(__FUNCTION__" | ERROR: can't create symbol with name [%s]", name);
         delete s;
      }
   }
   return NULL;
}
//+------------------------------------------------------------------+
