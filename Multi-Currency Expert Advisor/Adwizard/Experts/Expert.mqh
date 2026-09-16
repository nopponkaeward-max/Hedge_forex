//+------------------------------------------------------------------+
//|                                                       Expert.mq5 |
//|                                      Copyright 2024, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Yuriy Bykov"
#property link      "https://www.mql5.com/en/articles/17608"
#property version "1.25"

#include "../Virtual/VirtualAdvisor.mqh"
#include "../Utils/ExpertHistory.mqh"
#include "../Utils/ConsoleDialog.mqh"

// If the constant with the name of the final EA is not specified, then
#ifndef __NAME__
// Set it equal to the name of the EA file
#define  __NAME__ MQLInfoString(MQL_PROGRAM_NAME)

//+------------------------------------------------------------------+
//| Function for generating the strategy initialization string       |
//| from the default inputs (if no name was specified).              |
//| Import the initialization string from the EA database            |
//| by the strategy group ID                                         |
//+------------------------------------------------------------------+
string GetStrategyParams() {
// Take the initialization string from the new library for the selected group
// (from the EA database)
   string strategiesParams = CVirtualAdvisor::Import(
                                CVirtualAdvisor::FileName(__NAME__, magic_),
                                groupId_
                             );

// If the strategy group from the library is not specified, then we interrupt the operation
   if(strategiesParams == NULL && useAutoUpdate_) {
      strategiesParams = "";
   }

   return strategiesParams;
}
#endif

// If in the external file where this file is included, 
// there is a constant __INPUT_PARAMS__, then the inputs should:
//  - be fully declared in an external file
//  - repeat all parameters listed below
 
// If the __INPUT_PARAMS__ constant is not declared, 
// then the inputs are taken from the block below
#ifndef __INPUT_PARAMS__
//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "::: Use a strategy group"
sinput int        groupId_       = 0;     // - ID of the group from the new library (0 - last)
sinput bool       useAutoUpdate_ = true;  // - Use auto update?

input group "::: Money management"
sinput double expectedDrawdown_  = 10;    // - Maximum risk (%)
sinput double fixedBalance_      = 10000; // - Used deposit (0 - use all) in the account currency
input  double scale_             = 1.00;  // - Group scaling multiplier

input group ":::  Closing manager"
input bool        cmIsActive_                = true;  // - Active?
input double      cmStartBaseBalance_        = 0;     // - Basic balance
input ENUM_CM_CALC_LOSS
cmCalcLossLimit_           = CM_CALC_LOSS_MONEY_BB;   // - Loss calculation method
input double      cmLossLimit_       = 100;           // - Threshold loss value
input ENUM_CM_CALC_PROFIT
cmCalcProfitLimit_                    = CM_CALC_PROFIT_MONEY_BB;  // - Method for calculating total profit
input double      cmProfitLimit_   = 1000000;                     // - Profit target

input group ":::  Risk manager"
input bool        rmIsActive_                = true;     // - Active?
input double      rmStartBaseBalance_        = 10000;    // - Base balance
input ENUM_RM_CALC_DAILY_LOSS
rmCalcDailyLossLimit_                        = RM_CALC_DAILY_LOSS_MONEY_BB;      // - Method of calculating the daily loss
input double      rmMaxDailyLossLimit_       = 500;                              // - Daily loss
input double      rmCloseDailyPart_          = 1.0;                              // - Threshold part of the daily loss
input ENUM_RM_CALC_OVERALL_LOSS
rmCalcOverallLossLimit_                      = RM_CALC_OVERALL_LOSS_MONEY_BB;    // - Method of calculating the daily loss
input double      rmMaxOverallLossLimit_     = 1000;                             // - Overall loss
input double      rmCloseOverallPart_        = 1.0;                              // - Threshold part of the overall loss
input ENUM_RM_CALC_OVERALL_PROFIT
rmCalcOverallProfitLimit_                    = RM_CALC_OVERALL_PROFIT_MONEY_BB;  // - Method for calculating total profit
input double      rmMaxOverallProfitLimit_   = 1000000;                          // - Overall profit
input int         rmMaxOverallProfitDate_    = 0;                                // - Maximum time of waiting for the total profit (days)

input double      rmMaxRestoreTime_           = 0;                                // - Waiting time for the best entry on a drawdown
input double      rmLastVirtualProfitFactor_  = 1;                                // - Initial best drawdown multiplier

input group "::: Other parameters"
input ulong    magic_            = 27183;    // - Magic
input bool     useOnlyNewBars_   = true;     // - Work only at bar opening
input bool     usePrevState_     = true;     // - Load the previous state

input string   symbolsReplace_   = "";       // - Symbol replacement rules
#endif

CVirtualAdvisor     *expert;             // EA object

CConsoleDialog      *dialog;             // Dialog for displaying text with results

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
// Create and launch a dialog to display the results
   dialog = new CConsoleDialog();
   dialog.Create(__NAME__ + " | " + (string) magic_);
   dialog.Run();
   dialog.Text("Initialization...");

// Set parameters in the money management class
   CMoney::DepoPart(expectedDrawdown_ / 10.0);
   CMoney::FixedBalance(fixedBalance_);

// Initialization string with strategy parameter sets
   string strategiesParams = NULL;

// Take the initialization string from the new library for the selected group
// (from the EA database)
   strategiesParams = GetStrategyParams();

// If the strategy group from the library is not specified, then we interrupt the operation
   if(strategiesParams == NULL) {
      return INIT_FAILED;
   }

// Prepare the initialization string for an EA with a group of several strategies
   string expertParams = StringFormat(
                            "class CVirtualAdvisor(\n"
                            "    class CVirtualStrategyGroup(\n"
                            "       [\n"
                            "        %s\n"
                            "       ],%f\n"
                            "    ),\n"
                            "    class CVirtualRiskManager(\n"
                            "       %d,%.2f,%d,%.2f,%.2f,%d,%.2f,%.2f,%d,%.2f,%d,%.2f,%.2f"
                            "    ),\n"
                            "    class CVirtualCloseManager(\n"
                            "       %d,%.2f,%d,%.2f,%d,%.2f"
                            "    )\n"
                            "    ,%d,%s,%d\n"
                            ")",
                            strategiesParams, scale_,

                            rmIsActive_, rmStartBaseBalance_,
                            rmCalcDailyLossLimit_, rmMaxDailyLossLimit_, rmCloseDailyPart_,
                            rmCalcOverallLossLimit_, rmMaxOverallLossLimit_, rmCloseOverallPart_,
                            rmCalcOverallProfitLimit_, rmMaxOverallProfitLimit_, rmMaxOverallProfitDate_,
                            rmMaxRestoreTime_, rmLastVirtualProfitFactor_,

                            cmIsActive_, cmStartBaseBalance_,
                            cmCalcLossLimit_, cmLossLimit_,
                            cmCalcProfitLimit_, cmProfitLimit_,

                            magic_, __NAME__, useOnlyNewBars_
                         );

   PrintFormat(__FUNCTION__" | Expert Params:\n%s", expertParams);

// Create an EA handling virtual positions
   expert = NEW(expertParams);

// If the EA is not created, then return an error
   if(!expert) return INIT_FAILED;

// If an error occurred while replacing symbols, then return an error
   if(!expert.SymbolsReplace(symbolsReplace_)) return INIT_FAILED;


// If we need to restore the state,
   if(usePrevState_) {
      // Load the previous state if available
      if(!expert.Load()) return INIT_FAILED;
   }
   
   expert.Tick();

   dialog.Text(expert.Text());

// Successful initialization
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   expert.Tick();

// If both are executed at the same time:
   if(groupId_ == 0                       // - no specific group ID specified
         && useAutoUpdate_                // - auto update enabled
         && IsNewBar(Symbol(), PERIOD_D1) // - a new day has arrived
         && expert.CheckUpdate()          // - a new group of strategies discovered
     ) {
      // Save the current EA state
      expert.Save();

      // Delete the EA object
      OnDeinit(REASON_RECOMPILE);

      // Call the EA initialization function to load a new strategy group
      OnInit();
   }

   if (IsNewBar(Symbol(), PERIOD_M1) && !!dialog) {
      dialog.Text(expert.Text());
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   PrintFormat(__FUNCTION__" : Reason: %d", reason);
   if(!!expert) delete expert;
   if(!!dialog) {
      dialog.Destroy(reason);
      delete dialog;
   }
}

//+------------------------------------------------------------------+
//| Test results                                                     |
//+------------------------------------------------------------------+
double OnTester(void) {
   CExpertHistory::Export();
   return expert.Tester();
}

//+------------------------------------------------------------------+
//| Event handling                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,         // event ID
                  const long & lparam,  // event parameter of the long type
                  const double & dparam, // event parameter of the double type
                  const string & sparam) { // event parameter of the string type

   if(!!dialog) {
      dialog.ChartEvent(id, lparam, dparam, sparam);
   }
}
//+------------------------------------------------------------------+
