//+------------------------------------------------------------------+
//|                                               VirtualAdvisor.mqh |
//|                                 Copyright 2019-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.13"

class CVirtualStrategyGroup;

#include "../Base/Advisor.mqh"
#include "../Utils/NewBarEvent.mqh"
#include "../Utils/SymbolsMonitor.mqh"
#include "VirtualCloseManager.mqh"
#include "VirtualRiskManager.mqh"
#include "VirtualInterface.mqh"
#include "VirtualReceiver.mqh"
#include "VirtualStrategyGroup.mqh"
#include "TesterHandler.mqh"

//+------------------------------------------------------------------+
//| Class of the EA handling virtual positions (orders)              |
//+------------------------------------------------------------------+
class CVirtualAdvisor : public CAdvisor {
protected:
   CSymbolsMonitor      *m_symbols;       // Symbol monitor object
   CVirtualReceiver     *m_receiver;      // Receiver object that brings positions to the market
   CVirtualInterface    *m_interface;     // Interface object to show the status to the user
   CVirtualRiskManager  *m_riskManager;   // Risk manager object
   CVirtualCloseManager *m_closeManager;  // Closing manager object

   string            m_fileName;          // Name of the file with the EA database
   datetime          m_lastSaveTime;      // Last save time
   bool              m_useOnlyNewBar;     // Handle only new bar ticks
   
   bool              m_force;             // Forced tick processing and saving

   datetime          m_fromDate;          // Operation start date
   string            m_paramsNorm;        // Strategy group parameters after normalization

   virtual void      Add(CVirtualStrategyGroup *p_group);   // Method for adding a group of strategies

   static int        s_groupId;           // ID of the strategy group loaded from the database
   CVirtualAdvisor(string p_param);    // Constructor
public:
   STATIC_CONSTRUCTOR(CVirtualAdvisor);
   ~CVirtualAdvisor();         // Destructor

   virtual string    operator~() override;      // Convert object to string

   virtual void      Tick() override;           // OnTick event handler
   virtual double    Tester() override;         // OnTester event handler

   // OnChartEvent event handler (not used yet)
   virtual void      ChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam);

   virtual void      Close();          // Close positions of all strategies
   virtual string    Text();           // Information about the current EA state

   virtual bool      Save();           // Save status
   virtual bool      Load();           // Load status

   // Replace symbol names
   bool              SymbolsReplace(const string p_symbolsReplace);

   // Check the presence of a new strategy group in the EA database
   bool              CheckUpdate();

   // Export the current strategy group to the specified EA database
   void              Export(string p_groupName, string p_advFileName);

   // OnTesterInit event handler
   static int        TesterInit(ulong p_idTask = 0, string p_fileName = NULL);
   static void       TesterPass();     // OnTesterDeinit event handler
   static void       TesterDeinit();   // OnTesterDeinit event handler

   // Name of the file with the EA database
   static string     FileName(string p_name, ulong p_magic = 1);

   // Get the strategy group initialization string
   // from the EA database with the given ID
   static string     Import(string p_fileName, int p_groupId = 0);
};

int CVirtualAdvisor::s_groupId = 0;

REGISTER_FACTORABLE_CLASS(CVirtualAdvisor);


//+------------------------------------------------------------------+
//| Method for adding a group of strategies                          |
//+------------------------------------------------------------------+
void CVirtualAdvisor::Add(CVirtualStrategyGroup *p_group) {
// If this group contains other groups, add each of them
   FOREACH(p_group.m_groups) {
      CVirtualAdvisor::Add(p_group.m_groups[i]);
      delete p_group.m_groups[i];
   }
// If this group contains strategies, add each of them
   FOREACH(p_group.m_strategies) CAdvisor::Add(p_group.m_strategies[i]);
}

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CVirtualAdvisor::CVirtualAdvisor(string p_params) {
// Save the initialization string
   m_params = p_params;

// Read the initialization string of the strategy group object
   string groupParams = ReadObject(p_params);

// Read the initialization string of the risk manager object
   string riskManagerParams = NULL;

   if(IsObjectOf(p_params, "CVirtualRiskManager")) {
      riskManagerParams = ReadObject(p_params);
   }

// Read the initialization string of the closing manager object
   string closeManagerParams = NULL;
   if(IsObjectOf(p_params, "CVirtualCloseManager")) {
      closeManagerParams = ReadObject(p_params);
   }

// Read the magic number
   ulong p_magic = ReadLong(p_params);

// Read the EA name
   string p_name = ReadString(p_params);

// Read the work flag only at the bar opening
   m_useOnlyNewBar = (bool) ReadLong(p_params);

   m_force = true;

// If there are no read errors,
   if(IsValid()) {
// Create a strategy group
      CREATE(CVirtualStrategyGroup, p_group, groupParams);

      // Initialize the symbol monitor with a static symbol monitor
      m_symbols = CSymbolsMonitor::Instance();

      // Initialize the receiver with a static receiver
      m_receiver = CVirtualReceiver::Instance(p_magic);

      // Initialize the interface with the static interface
      m_interface = CVirtualInterface::Instance(p_magic);

      // Form the name of the EA database file for saving the state from the EA name and parameters
      m_fileName = FileName(p_name, p_magic);

      // Save the work (test) start time
      m_fromDate = TimeCurrent();

      // Reset the last save time
      m_lastSaveTime = 0;

      // Add the contents of the group to the EA
      Add(p_group);

      // Remove the group object
      delete p_group;

      // Create the risk manager object
      if(riskManagerParams != NULL) {
         m_riskManager = NEW(riskManagerParams);

         // If the risk manager is inactive, delete its object
         if(!m_riskManager.IsActive()) {
            delete m_riskManager;
         }
      }

      // Create the closing manager object
      if(closeManagerParams != NULL) {
         m_closeManager = NEW(closeManagerParams);

         // Bind the EA to the closing manager
         m_closeManager.Expert(&this);

         // If the risk manager is inactive, delete its object
         if(!m_closeManager.IsActive()) {
            delete m_closeManager;
         }

      }
   }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
void CVirtualAdvisor::~CVirtualAdvisor() {
   if(!!m_symbols)      delete m_symbols;       // Remove the symbol monitor
   if(!!m_receiver)     delete m_receiver;      // Remove the recipient
   if(!!m_interface)    delete m_interface;     // Remove the interface
   if(!!m_riskManager)  delete m_riskManager;   // Remove the risk manager
   if(!!m_closeManager) delete m_closeManager;  // Remove the closing manager
   DestroyNewBar();           // Remove the new bar tracking objects
}

//+------------------------------------------------------------------+
//| Convert an object to a string                                    |
//+------------------------------------------------------------------+
string CVirtualAdvisor::operator~() {
   return StringFormat("%s(%s)", typename(this), m_params);
}

//+------------------------------------------------------------------+
//| OnTick event handler                                             |
//+------------------------------------------------------------------+
void CVirtualAdvisor::Tick(void) {
// Define a new bar for all required symbols and timeframes
   bool isNewBar = UpdateNewBar();

// If there is no new bar anywhere, and we only work on new bars 
// and forced execution is not set, exit
   if(!isNewBar && m_useOnlyNewBar && !m_force) {
      return;
   }

// Symbol monitor updates quotes
   m_symbols.Tick();

// Receiver handles virtual positions
   m_receiver.Tick();

// Start handling in strategies
   CAdvisor::Tick();

// Risk manager handles virtual positions
   if(!!m_riskManager) m_riskManager.Tick();

// Risk manager handles virtual positions
   if(!!m_closeManager) m_closeManager.Tick();

// Adjusting market volumes
   m_receiver.Correct();

// Save status
   Save();

// Render the interface
   m_interface.Redraw();
}

//+------------------------------------------------------------------+
//| OnTester event handler                                           |
//+------------------------------------------------------------------+
double CVirtualAdvisor::Tester() {
// Maximum absolute drawdown
   double balanceDrawdown = TesterStatistics(STAT_EQUITY_DD);

// Profit
   double profit = TesterStatistics(STAT_PROFIT);

// Fixed balance for trading from settings
   double fixedBalance = CMoney::FixedBalance();

// The ratio of possible increase in position sizes for the drawdown of 10% of fixedBalance_
   double coeff = fixedBalance * 0.1 / MathMax(1, balanceDrawdown);

// Calculate the profit in annual terms
   long totalSeconds = TimeCurrent() - m_fromDate;
   double totalYears = totalSeconds / (365.0 * 24 * 3600);
   double fittedProfit = profit * coeff / totalYears;

// If it is not specified, then take the initial balance (although this will give a distorted result)
   if(fixedBalance < 1) {
      fixedBalance = TesterStatistics(STAT_INITIAL_DEPOSIT);
      balanceDrawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
      coeff = 0.1 / MathMax(1, balanceDrawdown);
      fittedProfit = fixedBalance * MathPow(1 + profit * coeff / fixedBalance, 1 / totalYears);
   }

// Re-create the group of used strategies for subsequent normalization
   CVirtualStrategyGroup* group = NEW(ReadObject(m_params));

   if(!!group) {
      // Normalized group initialization string
      m_paramsNorm = group.ToStringNorm(coeff);

      FOREACH(m_strategies) ((CVirtualStrategy*)m_strategies[i]).Scale(coeff);

      // Perform data frame generation on the test agent
      CTesterHandler::Tester(fittedProfit,   // Normalized profit
                             m_paramsNorm     // Normalized group initialization string
                            );

      PrintFormat(__FUNCTION__" | Scale = %.2f\nParams:\n%s", coeff, m_paramsNorm);
      PrintFormat(__FUNCTION__" | Scale = %.2f", coeff);

      delete group;
   }

   PrintFormat(__FUNCTION__" |\n%s = %.2f\n%s = %.2f\n%s = %.2f\n%s = %.2f\n%s = %.2f\n",
               EnumToString(STAT_BALANCE_DD), TesterStatistics(STAT_BALANCE_DD),
               EnumToString(STAT_BALANCE_DD_RELATIVE), TesterStatistics(STAT_BALANCE_DD_RELATIVE),
               EnumToString(STAT_EQUITY_DD), TesterStatistics(STAT_EQUITY_DD),
               EnumToString(STAT_EQUITY_DD_RELATIVE), TesterStatistics(STAT_EQUITY_DD_RELATIVE),
               EnumToString(STAT_EQUITY_DDREL_PERCENT), TesterStatistics(STAT_EQUITY_DDREL_PERCENT)
              );

   return fittedProfit;
}

//+------------------------------------------------------------------+
//| Export the current strategy group to the specified EA database   |
//+------------------------------------------------------------------+
void CVirtualAdvisor::Export(string p_groupName, string p_advFileName) {
   CTesterHandler::Export(m_strategies, p_groupName, p_advFileName);
}

//+------------------------------------------------------------------+
//| ChartEvent event handler                                         |
//+------------------------------------------------------------------+
void CVirtualAdvisor::ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   m_interface.ChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| Close positions of all strategies                                |
//+------------------------------------------------------------------+
void CVirtualAdvisor::Close(void) {
// For all strategies, we call the method for closing virtual positions
   FOREACH(m_strategies) ((CVirtualStrategy *)m_strategies[i]).Close();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string CVirtualAdvisor::Text() {
   string s = "";

//string symbols[];
//FOREACH(m_strategies) { APPEND(symbols, ((CVirtualStrategy *)m_strategies[i]).m_symbol); }

   s += StringFormat("Symbols: %s\n", m_symbols.SymbolsNames());
   s += StringFormat("Strategies: %5d total\n", ArraySize(m_strategies));

   if(!!m_closeManager)
      s += m_closeManager.Text();

   if(!!m_riskManager)
      s += m_riskManager.Text();

   return s;
}

//+------------------------------------------------------------------+
//| Initialization before starting optimization                      |
//+------------------------------------------------------------------+
int CVirtualAdvisor::TesterInit(ulong p_idTask, string p_fileName) {
   return CTesterHandler::TesterInit(p_idTask, p_fileName);
}

//+------------------------------------------------------------------+
//| Actions after completing the next optimization pass              |
//+------------------------------------------------------------------+
void CVirtualAdvisor::TesterPass() {
   CTesterHandler::TesterPass();
}


//+------------------------------------------------------------------+
//| Actions after optimization is complete                           |
//+------------------------------------------------------------------+
void CVirtualAdvisor::TesterDeinit() {
   CTesterHandler::TesterDeinit();
}


//+------------------------------------------------------------------+
//| Save status                                                      |
//+------------------------------------------------------------------+
bool CVirtualAdvisor::Save() {
// Save status if:
   if(true
// later changes appeared or this is a forced save
         && (m_lastSaveTime < CVirtualReceiver::s_lastChangeTime || m_force)
// currently, there is no optimization
         && !MQLInfoInteger(MQL_OPTIMIZATION)
// and there is no testing at the moment or there is a visual test at the moment
         && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     ) {
      // If the connection to the EA database is established
      if(CStorage::Connect(m_fileName)) {
         // Save the last modification time
         CStorage::Set("CVirtualReceiver::s_lastChangeTime", CVirtualReceiver::s_lastChangeTime);
         CStorage::Set("CVirtualAdvisor::s_groupId", CVirtualAdvisor::s_groupId);

         // Save all strategies
         FOREACH(m_strategies) ((CVirtualStrategy*) m_strategies[i]).Save();

         // Save the risk manager
         if (!!m_riskManager) m_riskManager.Save();

         // Save the closing manager
         if (!!m_closeManager) m_closeManager.Save();

         // Update the last save time
         m_lastSaveTime = CVirtualReceiver::s_lastChangeTime;
         PrintFormat(__FUNCTION__" | OK at %s to %s",
                     TimeToString(m_lastSaveTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                     m_fileName);

         // Close the connection
         CStorage::Close();
         
         // Disable forced saving after successful saving
         if (m_force) m_force = false;

         // Return the result
         return CStorage::Res();
      } else {
         PrintFormat(__FUNCTION__" | ERROR: Can't open database [%s], LastError=%d",
                     m_fileName, GetLastError());
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Load status                                                      |
//+------------------------------------------------------------------+
bool CVirtualAdvisor::Load() {
   bool res = true;
   ulong groupId = 0;

// Load status if:
   if(true
// file exists
         && FileIsExist(m_fileName, FILE_COMMON)
// currently, there is no optimization
         && !MQLInfoInteger(MQL_OPTIMIZATION)
// and there is no testing at the moment or there is a visual test at the moment
         && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     ) {
      // If the connection to the EA database is established
      if(CStorage::Connect(m_fileName)) {
         // If the last modified time is loaded and less than the current time
         if(CStorage::Get("CVirtualReceiver::s_lastChangeTime", m_lastSaveTime)
               && m_lastSaveTime <= TimeCurrent()) {

            PrintFormat(__FUNCTION__" | LAST SAVE at %s",
                        TimeToString(m_lastSaveTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));

            // If the saved strategy group ID is loaded
            if(CStorage::Get("CVirtualAdvisor::s_groupId", groupId)) {
               // Load all strategies ignoring possible errors
               FOREACH(m_strategies) {
                  res &= ((CVirtualStrategy*) m_strategies[i]).Load();
               }

               if(groupId != s_groupId) {
                  // Actions when launching an EA with a new group of strategies.
                  PrintFormat(__FUNCTION__" | UPDATE Group ID: %I64u -> %I64u", groupId, s_groupId);

                  // Reset a possible error flag when loading strategies
                  res = true;

                  string symbols[]; // Array for symbol names

                  // Get the list of all symbols used by the previous group
                  CStorage::GetSymbols(symbols);

                  // For all symbols, create a symbolic receiver.
                  // This is necessary for the correct closing of virtual positions
                  // of the old strategy group immediately after loading the new one
                  FOREACH(symbols) m_receiver[symbols[i]];
               }

               if(res) {
                  // Download the risk manager
                  if(!!m_riskManager) {
                     res &= m_riskManager.Load();

                     if(!res) {
                        PrintFormat(__FUNCTION__" | ERROR loading risk manager from DB [%s]", m_fileName);
                     }
                  }

                  // Load the closing manager
                  if(!!m_closeManager) {
                     res &= m_closeManager.Load();

                     if(!res) {
                        PrintFormat(__FUNCTION__" | ERROR loading close manager from DB [%s]", m_fileName);
                     }
                  }
               } else {
                  PrintFormat(__FUNCTION__" | ERROR loading strategies from DB [%s]", m_fileName);
               }
            }
         } else {
            // If the last modified time is not found or is in the future,
            // then start work from scratch
            PrintFormat(__FUNCTION__" | NO LAST SAVE [%s] - Clear Storage",
                        TimeToString(m_lastSaveTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
            CStorage::Clear();
            m_lastSaveTime = 0;
         }

         // Close the connection
         CStorage::Close();
      }
   }

   return res;
}

//+------------------------------------------------------------------+
//| Replace symbol names                                             |
//+------------------------------------------------------------------+
bool CVirtualAdvisor::SymbolsReplace(string p_symbolsReplace) {
// Get rid of spaces in the replacement string
   StringReplace(p_symbolsReplace, " ", "");

// If the replacement string is empty, then do nothing
   if(p_symbolsReplace == "") {
      return true;
   }

// Variable for the result
   bool res = true;

   string symbolKeyValuePairs[]; // Array for individual replacements
   string symbolPair[];          // Array for two names in one replacement

// Split the replacement string into parts representing one separate replacement
   StringSplit(p_symbolsReplace, ';', symbolKeyValuePairs);

// Glossary for mapping target symbol to source symbol
   CHashMap<string, string> symbolsMap;

// For all individual replacements
   FOREACH(symbolKeyValuePairs) {
      // Get the source and target symbols as two array elements
      StringSplit(symbolKeyValuePairs[i], '=', symbolPair);

      // Check if the target symbol is in the list of available non-custom symbols
      bool custom = false;
      res &= SymbolExist(symbolPair[1], custom);

      // If the target symbol is not found, then report an error and exit
      if(!res) {
         PrintFormat(__FUNCTION__" | ERROR: Target symbol %s for mapping %s not found", symbolPair[1], symbolKeyValuePairs[i]);
         return res;
      }

      // Add a new element to the glossary: key is the source symbol, while value is the target symbol
      res &= symbolsMap.Add(symbolPair[0], symbolPair[1]);

      // If failed to add the target symbol to the glossary, report an error and exit
      if(!res) {
         PrintFormat(__FUNCTION__" | ERROR: Can't add symbol map pair %s to HashMap. Check your parameter:\n%s",
                     symbolKeyValuePairs[i], p_symbolsReplace);
         return res;
      }
   }

// If no errors occurred, then for all strategies we call the corresponding replacement method
   FOREACH(m_strategies) res &= ((CVirtualStrategy*) m_strategies[i]).SymbolsReplace(symbolsMap);

   return res;
}

//+------------------------------------------------------------------+
//| Check the presence of a new strategy group in the EA database    |
//+------------------------------------------------------------------+
bool CVirtualAdvisor::CheckUpdate() {
// Request to get strategies of a given group or the last group
   string query = StringFormat("SELECT MAX(id_group) FROM strategy_groups"
                               " WHERE to_date <= '%s'",
                               TimeToString(TimeCurrent(), TIME_DATE));

// Open the EA database
   if(DB::Connect(m_fileName, DB_TYPE_ADV)) {
// Execute the request
      int request = DatabasePrepare(DB::Id(), query);

      // If there is no error
      if(request != INVALID_HANDLE) {
         // Data structure for reading a single string of a query result
         struct Row {
            int      groupId;
         } row;

         // Read data from the first result string
         while(DatabaseReadBind(request, row)) {
            // Remember the strategy group ID
            // in the static property of the EA class
            return s_groupId < row.groupId;
         }
      } else {
         // Report an error if necessary
         PrintFormat(__FUNCTION__" | ERROR: request \n%s\nfailed with code %d", query, GetLastError());
      }

      // Close the EA database
      DB::Close();
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get the strategy group initialization string                     |
//| from the EA database with the given ID                           |
//+------------------------------------------------------------------+
string CVirtualAdvisor::Import(string p_fileName, int p_groupId = 0) {
   string params[];   // Array for strategy initialization strings

// Request to get strategies of a given group or the last group
   string query = StringFormat("SELECT id_group, params "
                               "  FROM strategies"
                               " WHERE id_group = %s;",
                               (p_groupId > 0 ? (string) p_groupId
                                : "(SELECT MAX(id_group) FROM strategy_groups WHERE to_date <= '"
                                + TimeToString(TimeCurrent(), TIME_DATE) +
                                "')"));


// Open the EA database
   if(DB::Connect(p_fileName, DB_TYPE_ADV)) {
      // Execute the request
      int request = DatabasePrepare(DB::Id(), query);

      // If there is no error
      if(request != INVALID_HANDLE) {
         // Data structure for reading a single string of a query result
         struct Row {
            int      groupId;
            string   params;
         } row;

         // Read data from the first result string
         while(DatabaseReadBind(request, row)) {
            // Remember the strategy group ID
            // in the static property of the EA class
            s_groupId = row.groupId;

            // Add another strategy initialization string to the array
            APPEND(params, row.params);
         }
      } else {
         // Report an error if necessary
         PrintFormat(__FUNCTION__" | ERROR: request \n%s\nfailed with code %d", query, GetLastError());
      }

      // Close the EA database
      DB::Close();
   }

// Strategy group initialization string
   string groupParams = NULL;

// Total number of strategies in the group
   int totalStrategies = ArraySize(params);

// If there are strategies, then
   if(totalStrategies > 0) {
      // Concatenate their initialization strings with commas
      JOIN(params, groupParams, ",");

      // Create a strategy group initialization string
      groupParams = StringFormat("class CVirtualStrategyGroup([%s], %.5f)",
                                 groupParams,
                                 totalStrategies);
   }

// Return the strategy group initialization string
   return groupParams;
}

//+------------------------------------------------------------------+
//| Name of the file with the EA database                            |
//+------------------------------------------------------------------+
string CVirtualAdvisor::FileName(string p_name, ulong p_magic = 1) {
   return StringFormat("%s-%d%s.db.sqlite",
                       (p_name != "" ? p_name : "Expert"),
                       p_magic,
                       (MQLInfoInteger(MQL_TESTER) ? ".test" : "")
                      );
}
//+------------------------------------------------------------------+
