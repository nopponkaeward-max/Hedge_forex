//+------------------------------------------------------------------+
//|                                             OptimizationTask.mqh |
//|                                      Copyright 2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/articles/17328"
#property version   "1.01"

//#include <antekov/Advisor/Database/Database.mqh>

class COptimizationJob;

#include "OptimizationJob.mqh"

//+------------------------------------------------------------------+
//| Optimization task class                                          |
//+------------------------------------------------------------------+
class COptimizationTask {
public:
   ulong             id_task;       // task ID
   ulong             id_job;        // job ID
   int               optimization;  // Optimization criterion
   long              maxDuration;   // Max duration
   string            status;        // Task status

   COptimizationJob* job;           // The job for the task will be launched for

   // Constructor
                     COptimizationTask(ulong p_taskId = 0, COptimizationJob* p_job = NULL,
                     int p_optimization = 6,
                     long p_maxDuration = 0,
                     string p_status = "Done");

   // Create a task in the database
   void              Insert();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COptimizationTask::COptimizationTask(ulong p_taskId = 0,
                                     COptimizationJob* p_job = NULL,
                                     int p_optimization = 6,
                                     long p_maxDuration = 0,
                                     string p_status = "Done") :
   id_task(p_taskId),
   job(p_job),
   id_job(!!p_job ? p_job.id_job : 0),
   optimization(p_optimization),
   maxDuration(p_maxDuration),
   status(p_status) {}

//+------------------------------------------------------------------+
//| Create a task in the database                                    |
//+------------------------------------------------------------------+
void COptimizationTask::Insert() {
   string query = StringFormat("INSERT INTO tasks "
                               " VALUES (NULL,%I64u,%d,NULL,NULL,%I64d,'%s');",
                               id_job, optimization, maxDuration, status);

   id_task = DB::Insert(query);
   PrintFormat(__FUNCTION__" | %s -> %I64u", query, id_task);
}
//+------------------------------------------------------------------+
