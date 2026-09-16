//+------------------------------------------------------------------+
//|                                                OptimizerTask.mqh |
//|                                      Copyright 2024, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.06"

// Function to launch an executable file in the operating system
#import "shell32.dll"
int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

#include "../Database/Database.mqh"
#include "../Utils/MTTester.mqh" // https://www.mql5.com/en/code/26132

//+------------------------------------------------------------------+
//| Optimization task class                                          |
//+------------------------------------------------------------------+
class COptimizerTask {
protected:
   enum {
      TASK_TYPE_UNKNOWN,
      TASK_TYPE_EX5,
      TASK_TYPE_PY
   }                 m_type;        // Task type (MQL5 or Python)
   ulong             m_id;          // Task ID
   string            m_setting;     // String for initializing the EA parameters for the current task

   string            m_fileName;    // Database file name
   string            m_pythonPath;  // Full path to the Python interpreter

   // Get the full or relative path to a given file in the current folder
   string            GetProgramPath(string name, bool rel = true);

   // Get initialization string from task parameters
   void              Parse();

   // Get task type from task parameters
   void              ParseType();

   static string     s_criterionNames[];

public:
   // Data structure for reading a single string of a query result
   struct params {
      string         expert;
      int            optimization;
      string         from_date;
      string         to_date;
      int            forward_mode;
      string         forward_date;
      double         deposit;
      string         symbol;
      string         period;
      string         tester_inputs;
      ulong          id_task;
      int            optimization_criterion;
      long           max_duration;
   } m_params;

   // Constructor
   COptimizerTask(string p_fileName, string p_pythonPath = NULL) :
      m_id(0), m_fileName(p_fileName), m_pythonPath(p_pythonPath) {}

   // Task ID
   ulong             Id() {
      return m_id;
   }

   // Main method
   void              Process();

   // Load task parameters from the database
   void              Load(ulong p_id);

   // Start the task
   void              Start();

   // Task stop
   void              Stop();

   // Complete the task
   void              Finish();

   // Task completed?
   bool              IsDone();

   // Current task info
   string            Text();
};


string COptimizerTask::s_criterionNames[] = {
   "Balance max",
   "Profit Factor max",
   "Expected Payoff max",
   "Drawdown min",
   "Recovery Factor max",
   "Sharpe Ratio max",
   "Custom max",
};


//+------------------------------------------------------------------+
//| Get initialization string from task parameters                   |
//+------------------------------------------------------------------+
void COptimizerTask::Parse() {
// Get the task type from the task parameters
   ParseType();

// If this is the EA optimization task
   if(m_type == TASK_TYPE_EX5) {
      // Generate a parameter string for the tester
      m_setting =  StringFormat(
                      "[Tester]\r\n"
                      "Expert=%s\r\n"
                      "Symbol=%s\r\n"
                      "Period=%s\r\n"
                      "Optimization=%d\r\n"
                      "Model=1\r\n"
                      "FromDate=%s\r\n"
                      "ToDate=%s\r\n"
                      "ForwardMode=%d\r\n"
                      "%s"
                      "Deposit=%.2f\r\n"
                      "Currency=USD\r\n"
                      "ProfitInPips=0\r\n"
                      "Leverage=200\r\n"
                      "ExecutionMode=0\r\n"
                      "OptimizationCriterion=%d\r\n"
                      "[TesterInputs]\r\n"
                      "idTask_=%d\r\n"
                      "fileName_=%s\r\n"
                      "%s\r\n",
                      GetProgramPath(m_params.expert),
                      m_params.symbol,
                      m_params.period,
                      m_params.optimization,
                      m_params.from_date,
                      m_params.to_date,
                      m_params.forward_mode,
                      (m_params.forward_mode == 4 ?
                       StringFormat("ForwardDate=%s\r\n", m_params.forward_date) : ""),
                      m_params.deposit,
                      m_params.optimization_criterion,
                      m_params.id_task,
                      DB::FileName(),
                      m_params.tester_inputs
                   );

      // If this is a task to launch a Python program
   } else if (m_type == TASK_TYPE_PY) {
      // Form a program launch string on Python with parameters
      m_setting = StringFormat("\"%s\" \"%s\" %I64u %s",
                               GetProgramPath(m_params.expert, false),  // Python program file
                               DB::FileName(true),    // Path to the database file
                               m_id,                  // Task ID
                               m_params.tester_inputs // Launch parameters
                              );
   }
}

//+------------------------------------------------------------------+
//| Get task type from task parameters                               |
//+------------------------------------------------------------------+
void COptimizerTask::ParseType() {
   string ext = StringSubstr(m_params.expert, StringLen(m_params.expert) - 3);
   if(ext == ".py") {
      m_type = TASK_TYPE_PY;
   } else if (ext == "ex5") {
      m_type = TASK_TYPE_EX5;
   } else {
      m_type = TASK_TYPE_UNKNOWN;
   }
}

//+------------------------------------------------------------------+
//| Get the full or relative path to a given file                    |
//| in the current folder                                            |
//+------------------------------------------------------------------+
string COptimizerTask::GetProgramPath(string name, bool rel = true) {
   string path = MQLInfoString(MQL_PROGRAM_PATH);
   string programName = MQLInfoString(MQL_PROGRAM_NAME) + ".ex5";
   string terminalPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Experts\\";
   if(rel) {
      path =  StringSubstr(path,
                           StringLen(terminalPath),
                           StringLen(path) - (StringLen(terminalPath) + StringLen(programName)));
   } else {
      path = StringSubstr(path, 0, StringLen(path) - (0 + StringLen(programName)));
   }

   return path + name;
}


//+------------------------------------------------------------------+
//| Get the next optimization task from the queue                    |
//+------------------------------------------------------------------+
void COptimizerTask::Load(ulong p_id) {
// Save task ID
   m_id = p_id;

// Request to get optimization task from queue by ID
   string query = StringFormat(
                     "SELECT s.expert,"
                     "       s.optimization,"
                     "       s.from_date,"
                     "       s.to_date,"
                     "       s.forward_mode,"
                     "       s.forward_date,"
                     "       s.deposit,"
                     "       j.symbol,"
                     "       j.period,"
                     "       j.tester_inputs,"
                     "       t.id_task,"
                     "       t.optimization_criterion,"
                     "       t.max_duration"
                     "  FROM tasks t"
                     "       JOIN"
                     "       jobs j ON t.id_job = j.id_job"
                     "       JOIN"
                     "       stages s ON j.id_stage = s.id_stage"
                     " WHERE t.id_task=%I64u;", m_id);

// Open the database
   if(DB::Connect(m_fileName)) {
      // Execute the request
      int request = DatabasePrepare(DB::Id(), query);

      // If there is no error
      if(request != INVALID_HANDLE) {
         // Read data from the first result string
         if(DatabaseReadBind(request, m_params)) {
            Parse();
         } else {
            // Report an error if necessary
            PrintFormat(__FUNCTION__" | ERROR: Reading row for request \n%s\nfailed with code %d",
                        query, GetLastError());
         }
      } else {
         // Report an error if necessary
         PrintFormat(__FUNCTION__" | ERROR: request \n%s\nfailed with code %d", query, GetLastError());
      }

      // Close the database
      DB::Close();
   }
}

//+------------------------------------------------------------------+
//| Start task                                                       |
//+------------------------------------------------------------------+
void COptimizerTask::Start() {
   PrintFormat(__FUNCTION__" | Task ID = %d\n%s", m_id, m_setting);

// If this is the EA optimization task
   if(m_type == TASK_TYPE_EX5) {
      // Launch a new optimization task in the tester
      MTTESTER::CloseNotChart();
      MTTESTER::SetSettings2(m_setting);
      MTTESTER::ClickStart();

      // Update the task status in the database
      DB::Connect(m_fileName);
      string query = StringFormat(
                        "UPDATE tasks SET "
                        "    status='Process' "
                        " WHERE id_task=%d",
                        m_id);
      DB::Execute(query);
      DB::Close();

      // If this is a task to launch a Python program
   } else if (m_type == TASK_TYPE_PY) {
      PrintFormat(__FUNCTION__" | SHELL EXEC: %s", m_pythonPath);
      // Call the system function to launch the program with parameters
      ShellExecuteW(NULL, NULL, m_pythonPath, m_setting, NULL, 1);
   }
}

//+------------------------------------------------------------------+
//| Stop task                                                        |
//+------------------------------------------------------------------+
void COptimizerTask::Stop() {
   PrintFormat(__FUNCTION__" | Task ID = %d", m_id);

// If this is the EA optimization task
   if(m_type == TASK_TYPE_EX5) {
      // Stop optimization in the tester
      MTTESTER::ClickStart(false);

      // If this is a task to launch a Python program
   } else if (m_type == TASK_TYPE_PY) {
      PrintFormat(__FUNCTION__" | STOP SHELL EXEC: %s", m_pythonPath);
      // TODO: Add task interruption to Python with this launch:
      // ShellExecuteW(NULL, NULL, m_pythonPath, m_setting, NULL, 1);
   }
}

//+------------------------------------------------------------------+
//| Task completion                                                  |
//+------------------------------------------------------------------+
void COptimizerTask::Finish() {
   PrintFormat(__FUNCTION__" | Task ID = %d", m_id);

// Update the task status in the database
   DB::Connect(m_fileName);
   string query = StringFormat(
                     "UPDATE tasks SET "
                     "    status='Done' "
                     " WHERE id_task=%d",
                     m_id);
   DB::Execute(query);
   DB::Close();

// Reset the current task ID
   m_id = 0;
}

//+------------------------------------------------------------------+
//| Task completed?                                                  |
//+------------------------------------------------------------------+
bool COptimizerTask::IsDone() {
// If there is no current task, then everything is done
   if(m_id == 0) {
      return true;
   }

// Result
   bool res = false;

// If this is the EA optimization task
   if(m_type == TASK_TYPE_EX5) {
      // Check if the strategy tester has finished its work
      res |= MTTESTER::IsReady();

      // If the tester is running and the maximum duration is specified,
      if(!res && m_params.max_duration > 0) {
         // Request to get the elapsed execution time of the current task
         string query = StringFormat("SELECT unixepoch(datetime()) - unixepoch(start_date) AS duration"
                                     "  FROM tasks"
                                     " WHERE id_task=%I64u;", m_id);

         // Get the execution time in seconds
         DB::Connect(m_fileName);
         long duration = StringToInteger(DB::GetValue(query));
         DB::Close();

         // If the execution time is greater than the maximum allowed,
         if(duration > m_params.max_duration) {
            // Stop the task
            Stop();
         }
      }

      // If this is a task to run a Python program, then
   } else if(m_type == TASK_TYPE_PY) {
      // Request to get the status of the current task
      string query = StringFormat("SELECT status "
                                  "  FROM tasks"
                                  " WHERE id_task=%I64u;", m_id);
      // Open the database
      if(DB::Connect(m_fileName)) {
         // Execute the request
         int request = DatabasePrepare(DB::Id(), query);

         // If there is no error
         if(request != INVALID_HANDLE) {
            // Data structure for reading a single string of a query result
            struct Row {
               string status;
            } row;

            // Read data from the first result string
            if(DatabaseReadBind(request, row)) {
               // Check if the status is Done
               res = (row.status == "Done");
            } else {
               // Report an error if necessary
               PrintFormat(__FUNCTION__" | ERROR: Reading row for request \n%s\nfailed with code %d",
                           query, GetLastError());
            }
         } else {
            // Report an error if necessary
            PrintFormat(__FUNCTION__" | ERROR: request \n%s\nfailed with code %d", query, GetLastError());
         }

         // Close the database
         DB::Close();
      }
   } else {
      res = true;
   }

   return res;
}

//+------------------------------------------------------------------+
//| Current task info                                                |
//+------------------------------------------------------------------+
string COptimizerTask::Text() {
   string text = "";

   // If there is an active task
   if(m_params.id_task) {
      DB::Connect(m_fileName);

      // Add information about the project
      text += StringFormat("═════════════════════════════════════════════════════════════════════════\n"
                           "PROJECT: %s v. %s\n%s\n\n",
                           DB::GetValue("SELECT name FROM projects WHERE status = 'Process' LIMIT 1"),
                           DB::GetValue("SELECT version FROM projects WHERE status = 'Process'  LIMIT 1"),
                           DB::GetValue("SELECT description FROM projects WHERE status = 'Process'  LIMIT 1")
                          );

      // Request to get all information about the task
      string query = "SELECT s.name, s.expert, s.from_date, s.to_date, "
                     "  j.symbol, j.period, t.optimization_criterion, t.start_date, "
                     "  time(max_duration, 'unixepoch') AS max_duration,"
                     "  time(unixepoch('now') - unixepoch(t.start_date), 'unixepoch') AS elapsed_time,"
                     "  time(MAX(0, max_duration - (unixepoch('now') - unixepoch(t.start_date))), 'unixepoch') AS remaining_time"
                     "  FROM stages s"
                     "       JOIN"
                     "       projects p ON s.id_project = p.id_project AND"
                     "                     p.status = 'Process' AND"
                     "                     s.expert IS NOT NULL"
                     "     JOIN jobs j ON j.id_stage = s.id_stage"
                     "     JOIN tasks t ON t.id_job = j.id_job AND t.status = 'Process';";

      // Execute the request
      int request = DatabasePrepare(DB::Id(), query);

      struct Row {
         string stage_name;
         string expert_name;
         string from_date;
         string to_date;
         string symbol;
         string timeframe;
         int optimization_criterion;
         string start_date;
         string max_duration;
         string elapsed_time;
         string remainig_time;
      } row;

      // If there is no error
      if(request != INVALID_HANDLE) {

         // Read data from the first line of the result and add it to the text
         if(DatabaseReadBind(request, row)) {
            text += StringFormat("TASK #%I64u:\n"
                                 " %10.10s │ %14.14s │ %-23s │ %6.6s │ %-3.3s │ %15.15s │ %-10.10s │ %-10.10s\n"
                                 "────────────┼────────────────┼─────────────────────────┼────────┼─────┼─────────────────┼────────────┼─────────────\n"
                                 " %10.10s │ %14.14s │ %s - %s │ %6.6s │ %-3.3s │ %15.15s │ %-10.10s │ %-10.10s \n\n"
                                 "═════════════════════════════════════════════════════════════════════════\n",
                                 m_id,
                                 "Stage",
                                 "Expert",
                                 "Testing period",
                                 "Symbol",
                                 "TF",
                                 "Criterion",
                                 "Max Durat.",
                                 "Remaining",
                                 row.stage_name,
                                 row.expert_name,
                                 row.from_date,
                                 row.to_date,
                                 row.symbol,
                                 row.timeframe,
                                 s_criterionNames[row.optimization_criterion],
                                 m_params.max_duration ? row.max_duration : "Unlimited",
                                 row.remainig_time
                                );
         }
      }
      DatabaseFinalize(request);

      DB::Close();
   }

   return text;
}
//+------------------------------------------------------------------+
