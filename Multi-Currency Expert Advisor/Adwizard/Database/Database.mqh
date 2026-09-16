//+------------------------------------------------------------------+
//|                                                     Database.mqh |
//|                                      Copyright 2024, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.12"

// Import SQL files for creating database structures of different types
#resource "db.opt.schema.sql" as string dbOptSchema
#resource "db.cut.schema.sql" as string dbCutSchema
#resource "db.adv.schema.sql" as string dbAdvSchema

// Database type
enum ENUM_DB_TYPE {
   DB_TYPE_OPT,   // Optimization database
   DB_TYPE_CUT,   // Database for group selection (stripped down optimization database)
   DB_TYPE_ADV,   // EA (final EA) database
};

#include "../Utils/Macros.mqh"

#define DB CDatabase

//+------------------------------------------------------------------+
//| Class for handling the database                                  |
//+------------------------------------------------------------------+
class CDatabase {
   static int        s_db;          // DB connection handle
   static string     s_fileName;    // DB file name
   static int        s_common;      // Flag for using shared data folder
   static bool       s_res;         // Query execution result

public:
   static int        Id();          // Database connection handle
   static bool       Res();         // Query execution result

   // Full or short name of the DB file
   static string     FileName(bool full = false);

   static bool       IsOpen();      // Is the DB open?

   // Create an empty database using the given structure
   static void       Create(string p_schema);

   // Connect to the database with a given name and type
   static bool       Connect(string p_fileName,
                             ENUM_DB_TYPE p_dbType = DB_TYPE_OPT
                            );

   static void       Close();       // Closing DB

   // Execute one query to the DB
   static bool       Execute(string query, int attempt = 0);

   // Execute multiple DB queries in one transaction
   static bool       ExecuteTransaction(string &queries[], int attempt = 0);

   // Execute a query to the database for insertion with return of the new entry ID
   static ulong      Insert(string query);

   static string     GetValue(string query);
};

int    CDatabase::s_db       =  INVALID_HANDLE;
string CDatabase::s_fileName = "database.sqlite";
int    CDatabase::s_common   =  DATABASE_OPEN_COMMON;
bool   CDatabase::s_res      =  true;


//+------------------------------------------------------------------+
//| Database connection handle                                       |
//+------------------------------------------------------------------+
int CDatabase::Id() {
   return s_db;
}

//+------------------------------------------------------------------+
//| Query execution result                                           |
//+------------------------------------------------------------------+
bool CDatabase::Res() {
   return s_res;
}

//+------------------------------------------------------------------+
//| Full or short name of the DB file                                |
//+------------------------------------------------------------------+
string CDatabase::FileName(bool full = false) {
   string path = "";
   if(full) {
      path = (s_common == DATABASE_OPEN_COMMON ?
              TerminalInfoString(TERMINAL_COMMONDATA_PATH) :
              TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5")
             + "\\Files\\";
   }
   return path + s_fileName;
}

//+------------------------------------------------------------------+
//| Is the DB open?                                                  |
//+------------------------------------------------------------------+
bool CDatabase::IsOpen() {
   return (s_db != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Create an empty DB                                               |
//+------------------------------------------------------------------+
void CDatabase::Create(string p_schema) {
   s_res = Execute(p_schema);
   if(s_res) {
      PrintFormat(__FUNCTION__" | Database successfully created from %s", "db.*.schema.sql");
   }
}

//+------------------------------------------------------------------+
//| Close DB                                                         |
//+------------------------------------------------------------------+
void CDatabase::Close() {
   if(s_db != INVALID_HANDLE) {
      DatabaseClose(s_db);
      //PrintFormat(__FUNCTION__" | Close database %s with handle %d",
      //            s_fileName, s_db);
      s_db = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Check connection to the database with the given name             |
//+------------------------------------------------------------------+
bool CDatabase::Connect(string p_fileName, ENUM_DB_TYPE p_dbType = DB_TYPE_OPT) {
// If the database is open, close it
   Close();

   s_res = true;

// If a file name is specified, save it
   s_fileName = p_fileName;

// Set the shared folder flag for the optimization and EA databases
   s_common = (p_dbType != DB_TYPE_CUT ? DATABASE_OPEN_COMMON : 0);

// Open the database
// Try to open an existing DB file
   s_db = DatabaseOpen(s_fileName, DATABASE_OPEN_READWRITE | s_common);

// If the DB file is not found, try to create it when opening
   if(!IsOpen()) {
      s_db = DatabaseOpen(s_fileName,
                          DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | s_common);

      // Report an error in case of failure
      if(!IsOpen()) {
         PrintFormat(__FUNCTION__" | ERROR: %s Connect failed with code %d",
                     s_fileName, GetLastError());
         return false;
      }
      if(p_dbType == DB_TYPE_OPT) {
         Create(dbOptSchema);
      } else if(p_dbType == DB_TYPE_CUT) {
         Create(dbCutSchema);
      } else {
         Create(dbAdvSchema);
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Execute one query to the DB                                      |
//+------------------------------------------------------------------+
bool CDatabase::Execute(string query, int attempt = 0) {
   s_res = DatabaseExecute(s_db, query);
   if(!s_res) {
      if((_LastError == ERR_DATABASE_LOCKED || _LastError == ERR_DATABASE_BUSY) && attempt < 20) {
         PrintFormat(__FUNCTION__" | ERROR: ERR_DATABASE_LOCKED. Repeat Transaction in DB [%s]",
                     s_fileName);
         Execute(query, attempt + 1);

      } else {
         // Report it
         PrintFormat(__FUNCTION__" | ERROR: Execution failed in DB [%s], query:\n"
                     "%s\n"
                     "error code = %d",
                     s_fileName, query, _LastError);
      }
   }
   return s_res;
}

//+------------------------------------------------------------------+
//| Execute multiple DB queries in one transaction                   |
//+------------------------------------------------------------------+
bool CDatabase::ExecuteTransaction(string &queries[], int attempt = 0) {
// Open a transaction
   DatabaseTransactionBegin(s_db);

   s_res = true;
// Send all execution requests
   FOREACH(queries) {
      s_res &= DatabaseExecute(s_db, queries[i]);
      if(!s_res) break;
   }

// If an error occurred in any request, then
   if(!s_res) {
// Cancel transaction
      DatabaseTransactionRollback(s_db);
      if((_LastError == ERR_DATABASE_LOCKED || _LastError == ERR_DATABASE_BUSY) && attempt < 20) {
         PrintFormat(__FUNCTION__" | ERROR: ERR_DATABASE_LOCKED. Repeat Transaction in DB [%s]",
                     s_fileName);
         Sleep(rand() % 50);
         ExecuteTransaction(queries, attempt + 1);

      } else {
         // Report it
         PrintFormat(__FUNCTION__" | ERROR: Transaction failed in DB [%s], error code=%d",
                     s_fileName, _LastError);
      }

   } else {
// Otherwise, confirm transaction
      DatabaseTransactionCommit(s_db);
//PrintFormat(__FUNCTION__" | Transaction done successfully");
   }
   return s_res;
}

//+------------------------------------------------------------------+
//| Execute a query to the database for insertion returning the      |
//| new entry ID                                                     |
//+------------------------------------------------------------------+
ulong CDatabase::Insert(string query) {
   ulong res = 0;

   if(StringFind(query, "RETURNING rowid;") == -1) {
      StringReplace(query, ";", "");
      query += " RETURNING rowid;";
   }

// Execute the request
   int request = DatabasePrepare(s_db, query);

// If there is no error
   if(request != INVALID_HANDLE) {
      // Data structure for reading a single string of a query result
      struct Row {
         int         rowid;
      } row;

      // Read data from the first result string
      if(DatabaseReadBind(request, row)) {
         res = row.rowid;
      } else {
         // Report an error if necessary
         PrintFormat(__FUNCTION__" | ERROR: Reading row in DB [%s] for request \n%s\nfailed with code %d",
                     s_fileName, query, GetLastError());
         s_res = false;
      }
      DatabaseFinalize(request);
   } else {
      // Report an error if necessary
      PrintFormat(__FUNCTION__" | ERROR: Request in DB [%s] \n%s\nfailed with code %d",
                  s_fileName, query, GetLastError());
      s_res = false;
   }
   return res;
}


//+------------------------------------------------------------------+
//| Get the value as a string for the given key                      |
//+------------------------------------------------------------------+
string CDatabase::GetValue(string query) {
   string value = NULL; // Return value

// Execute the request
   int request = DatabasePrepare(DB::Id(), query);

// If there is no error
   if(request != INVALID_HANDLE) {
      // Read data from the first result string
      DatabaseRead(request);

      if(!DatabaseColumnText(request, 0, value)) {
         // Report an error if necessary
         PrintFormat(__FUNCTION__" | ERROR: Reading row in DB [adv] for request \n%s\n"
                     "failed with code %d",
                     query, GetLastError());
         s_res = false;
      }
      DatabaseFinalize(request);
   } else {
      // Report an error if necessary
      PrintFormat(__FUNCTION__" | ERROR: Request in DB [adv] \n%s\nfailed with code %d",
                  query, GetLastError());
      s_res = false;
   }

   return value;
}

//+------------------------------------------------------------------+
