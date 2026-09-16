//+------------------------------------------------------------------+
//|                                                TesterHandler.mqh |
//|                                 Copyright 2024-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.07"

#include "../Database/Database.mqh"
#include "VirtualStrategy.mqh"
//#include "VirtualFactory.mqh"
#include "../Optimization/OptimizerTask.mqh"

//+------------------------------------------------------------------+
//| Optimization event handling class                                |
//+------------------------------------------------------------------+
class CTesterHandler {
   static string     s_fileName;                   // Optimization database name
   static string     s_frameFileName;              // File name for writing frame data
   static void       ProcessFrame(string values);  // Handle single pass data
   static void       ProcessFrames();              // Handle incoming frames
   static string     GetFrameInputs(ulong pass);   // Get pass inputs

   // Generate SQL query to insert pass results
   static string     GetInsertQuery(string values, string inputs, ulong pass = 0);
public:
   static int        TesterInit(ulong p_idTask = 0, string p_fileName = NULL);   // Handle the optimization start in the main terminal
   static void       TesterDeinit();   // Handle the optimization completion in the main terminal
   static void       TesterPass();     // Handle the completion of a pass on an agent in the main terminal

   static void       Tester(const double OnTesterValue,
                            const string params);  // Handle completion of tester pass for agent

   // Export an array of strategies to the specified EA database as a new group of strategies
   static void       Export(CStrategy* &p_strategies[], string p_groupName, string p_advFileName);

   static ulong      s_idTask;   // Optimization task ID
   static ulong      s_idPass;   // Current optimization pass ID
};

string CTesterHandler::s_fileName = "";   // Optimization database name
string CTesterHandler::s_frameFileName = "data.bin";    // File name for writing frame data
ulong CTesterHandler::s_idTask = 0;
ulong CTesterHandler::s_idPass = 0;


//+------------------------------------------------------------------+
//| Handling the optimization start in the main terminal             |
//+------------------------------------------------------------------+
int CTesterHandler::TesterInit(ulong p_idTask, string p_fileName) {
// Set task ID
   s_idTask = p_idTask;

   s_fileName = p_fileName;

// Open the existing database
   DB::Connect(s_fileName);

// If failed to open it, we do not start optimization
   if(!DB::IsOpen()) {
      return INIT_FAILED;
   }

// Close a successfully opened database
   DB::Close();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Handling the optimization completion in the main terminal        |
//+------------------------------------------------------------------+
void CTesterHandler::TesterDeinit(void) {
// Handle the latest data frames received from agents
   ProcessFrames();

// Close the chart with the EA running in frame collection mode
   ChartClose();
}

//+--------------------------------------------------------------------+
//| Handling the completion of a pass on an agent in the main terminal |
//+--------------------------------------------------------------------+
void CTesterHandler::TesterPass(void) {
// Handle data frames received from the agent
   ProcessFrames();
}

//+------------------------------------------------------------------+
//| Handling completion of tester pass for agent                     |
//+------------------------------------------------------------------+
void CTesterHandler::Tester(double custom,   // Custom criteria
                            string params    // Description of EA parameters in the current pass
                           ) {
// Array of names of saved statistical characteristics of the pass
   ENUM_STATISTICS statNames[] = {
      STAT_INITIAL_DEPOSIT,
      STAT_WITHDRAWAL,
      STAT_PROFIT,
      STAT_GROSS_PROFIT,
      STAT_GROSS_LOSS,
      STAT_MAX_PROFITTRADE,
      STAT_MAX_LOSSTRADE,
      STAT_CONPROFITMAX,
      STAT_CONPROFITMAX_TRADES,
      STAT_MAX_CONWINS,
      STAT_MAX_CONPROFIT_TRADES,
      STAT_CONLOSSMAX,
      STAT_CONLOSSMAX_TRADES,
      STAT_MAX_CONLOSSES,
      STAT_MAX_CONLOSS_TRADES,
      STAT_BALANCEMIN,
      STAT_BALANCE_DD,
      STAT_BALANCEDD_PERCENT,
      STAT_BALANCE_DDREL_PERCENT,
      STAT_BALANCE_DD_RELATIVE,
      STAT_EQUITYMIN,
      STAT_EQUITY_DD,
      STAT_EQUITYDD_PERCENT,
      STAT_EQUITY_DDREL_PERCENT,
      STAT_EQUITY_DD_RELATIVE,
      STAT_EXPECTED_PAYOFF,
      STAT_PROFIT_FACTOR,
      STAT_RECOVERY_FACTOR,
      STAT_SHARPE_RATIO,
      STAT_MIN_MARGINLEVEL,
      STAT_DEALS,
      STAT_TRADES,
      STAT_PROFIT_TRADES,
      STAT_LOSS_TRADES,
      STAT_SHORT_TRADES,
      STAT_LONG_TRADES,
      STAT_PROFIT_SHORTTRADES,
      STAT_PROFIT_LONGTRADES,
      STAT_PROFITTRADES_AVGCON,
      STAT_LOSSTRADES_AVGCON,
      STAT_COMPLEX_CRITERION
   };

// Array for values of statistical characteristics of the pass as strings
   string stats[];
   ArrayResize(stats, ArraySize(statNames));

// Fill the array of values of statistical characteristics of the pass
   FOREACH(statNames) stats[i] = DoubleToString(TesterStatistics(statNames[i]), 2);

// Add the custom criterion value to it
   APPEND(stats, DoubleToString(custom, 2));

// Combine statistical characteristics into a string
   string data = "";
   JOIN(stats, data, ",");

// Screen the quotes in the description of parameters just in case
   StringReplace(params, "'", "\\'");

// Generate a string with pass data
   data = StringFormat("%d, %d, %s,'%s'",
                       MQLInfoInteger(MQL_OPTIMIZATION),
                       MQLInfoInteger(MQL_FORWARD),
                       data, params);

// If this is a pass within the optimization,
   if(MQLInfoInteger(MQL_OPTIMIZATION)) {
      // Open the file to write data for the frame
      int f = FileOpen(s_frameFileName, FILE_WRITE | FILE_TXT | FILE_ANSI);

      // Write a description of the EA parameters
      FileWriteString(f, data);

      // Close the file
      FileClose(f);

      // Create a frame with data from the recorded file and send it to the main terminal
      if(!FrameAdd("", 0, 0, s_frameFileName)) {
         PrintFormat(__FUNCTION__" | ERROR: Frame add error: %d", GetLastError());
      }
   } else {
      // Otherwise, it is a single pass, call the method to add its results
      // to the optimization database (if specified)
      if (s_fileName != "") {
         CTesterHandler::ProcessFrame(data);
      }
   }
}

//+------------------------------------------------------------------+
//| Export an array of strategies to the specified EA database       |
//| as a new group of strategies                                     |
//+------------------------------------------------------------------+
void CTesterHandler::Export(CStrategy* &p_strategies[], string p_groupName, string p_advFileName) {
// Create an optimization task object
   COptimizerTask task(s_fileName);
// Load the data of the current optimization task into it
   task.Load(CTesterHandler::s_idTask);

// Connect to the required EA database
   if(DB::Connect(p_advFileName, DB_TYPE_ADV)) {
      string fromDate = task.m_params.from_date; // Start date of the optimization interval
      string toDate = task.m_params.to_date;     // End date of the optimization interval

      // Create an entry for a new strategy group
      string query = StringFormat("INSERT INTO strategy_groups VALUES(NULL, '%s', '%s', '%s', NULL)"
                                  " RETURNING rowid;",
                                  p_groupName, fromDate, toDate);
      ulong groupId = DB::Insert(query);

      PrintFormat(__FUNCTION__" | Export %d strategies into new group [%s] with ID=%I64u",
                  ArraySize(p_strategies), p_groupName, groupId);

      // For each strategy
      FOREACH(p_strategies) {
         CVirtualStrategy *strategy = p_strategies[i];
         // Form an initialization string as a group of one strategy with a normalizing factor
         string params = StringFormat("class CVirtualStrategyGroup([%s],%0.5f)",
                                      ~strategy,
                                      strategy.Scale());

         // Save it in the EA database with the new group ID specified
         string query = StringFormat("INSERT INTO strategies "
                                     "VALUES (NULL, %I64u, '%s', '%s')",
                                     groupId, strategy.Hash(~strategy), params);
         DB::Execute(query);
      }

      // Close the database
      DB::Close();
   }
   
   // TODO: Add group saving to the optimization database
}

//+------------------------------------------------------------------+
//| Generate SQL query to insert pass results                        |
//+------------------------------------------------------------------+
string CTesterHandler::GetInsertQuery(string values, string inputs, ulong pass) {
   return StringFormat("INSERT INTO passes "
                       "VALUES (NULL, %d, %I64u, %s,\n'%s',\nNULL) RETURNING rowid;",
                       s_idTask, pass, values, inputs);
}

//+------------------------------------------------------------------+
//| Handle single pass data                                          |
//+------------------------------------------------------------------+
void CTesterHandler::ProcessFrame(string values) {
// Open the database
   DB::Connect(s_fileName);

// Form an SQL query from the received data
   string query = GetInsertQuery(values, "", 0);

// Execute the request
   s_idPass = DB::Insert(query);

// Close the database
   DB::Close();
}


//+------------------------------------------------------------------+
//| Handling incoming frames                                         |
//+------------------------------------------------------------------+
void CTesterHandler::ProcessFrames(void) {
// Open the database
   DB::Connect(s_fileName);

// Variables for reading data from frames
   string   name;      // Frame name (not used)
   ulong    pass;      // Frame pass index
   long     id;        // Frame type ID (not used)
   double   value;     // Single frame value (not used)
   uchar    data[];    // Frame data array as a character array

   string   values;    // Frame data as a string
   string   inputs;    // String with names and values of pass parameters
   string   query;     // A single SQL query string
   string   queries[]; // SQL queries for adding records to the database


// Go through frames and read data from them
   while(FrameNext(pass, name, id, value, data)) {
      // Convert the array of characters read from the frame into a string
      values = CharArrayToString(data);

      // Form a string with names and values of the pass parameters
      inputs = GetFrameInputs(pass);

      // Form an SQL query from the received data
      query = GetInsertQuery(values, inputs, pass);

      // Add it to the SQL query array
      APPEND(queries, query);
   }

// Execute all requests
   DB::ExecuteTransaction(queries);

// Close the database
   DB::Close();
}

//+------------------------------------------------------------------+
//| Form a string with names and values of the pass inputs           |
//+------------------------------------------------------------------+
string CTesterHandler::GetFrameInputs(ulong pass) {
   string  params[];    // Array of input variable descriptions
   uint    count;       // Number of input variables
   string  inputs = ""; // Result string

   if(FrameInputs(pass, params, count)) {
      // collect optimized parameters and their values
      for(uint i = 0; i < count; i++) {
         string name2value[];
         string delimeter = (i == count - 1 ? "" : ",");
         // Divide the description of the next input variable by '=' symbol
         int n = StringSplit(params[i], '=', name2value);
         if(n == 2) {
            // Get value by name in pvalue
            double pvalue, pstart, pstep, pstop;
            bool enabled = false;
            if(ParameterGetRange(name2value[0],
                                 enabled, pvalue, pstart, pstep, pstop)) {
               // Add the name and value of the input variable to the output string
               if(MathAbs(pvalue - (long) pvalue) < 1e-6) {
                  // as an integer
                  inputs += StringFormat("%s=%d%s", name2value[0], (long) pvalue, delimeter);
               } else {
                  // as a real number
                  inputs += StringFormat("%s=%.2f%s", name2value[0], pvalue, delimeter);
               }
            }
         }
      }
   }
//PrintFormat(__FUNCTION__" | pass %d: %s", pass, inputs);

   return inputs;
}

//+------------------------------------------------------------------+
