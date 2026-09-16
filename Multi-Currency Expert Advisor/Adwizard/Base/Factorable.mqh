//+------------------------------------------------------------------+
//|                                                   Factorable.mqh |
//|                                      Copyright 2024, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019-2024, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.06"

#include "FactorableCreator.mqh"

// Declare a static constructor inside the class
#define STATIC_CONSTRUCTOR(C) static CFactorable* Create(string p) { return new C(p); }

// Add a static constructor for the new CFactorable descendant class
// to a special array by creating a global object of the CFactorableCreator class
#define REGISTER_FACTORABLE_CLASS(C) CFactorableCreator C##Creator(#C, C::Create);

// Create an object in the factory from a string
#define NEW(P) CFactorable::Create(P)

// Creating a child object in the factory from a string with verification.
// Called only from the current object constructor.
// If the object is not created, the current object becomes invalid
// and exit from the constructor is performed
#define CREATE(C, O, P) C *O = NULL; if (IsValid()) { O = dynamic_cast<C*> (NEW(P)); if(!O) { SetInvalid(__FUNCTION__, StringFormat("Expected Object of class %s() at line %d in Params:\n%s", #C, __LINE__, P)); return; }}


//+------------------------------------------------------------------+
//| Base class of objects created from a string                      |
//+------------------------------------------------------------------+
class CFactorable {
private:
   bool              m_isValid;  // Is the object valid?

   // Clear empty characters from left and right in the initialization string
   static void       Trim(string &p_params);

   // Find a matching closing bracket in the initialization string
   static int        FindCloseBracket(string &p_params, char closeBraket = ')');

   // Clear the initialization string with a check for the current object validity
   bool              CheckTrimParams(string &p_params);

protected:
   string            m_params;   // Current object initialization string
   bool              m_isActive; // Is the object active?

   // Set the current object to the invalid state
   void              SetInvalid(string function = NULL, string message = NULL);

public:
   CFactorable() :
      m_isValid(true),
      m_isActive(true) {}  // Constructor

   bool              IsValid();                          // Is the object valid?
   bool              IsActive();                         // Is the object active?

   // Convert object to string
   virtual string    operator~() = 0;

   // Does the initialization string start with the object definition?
   static bool       IsObject(string &p_params, const string className = "");

   // Does the initialization string start with defining an object of the desired class?
   static bool       IsObjectOf(string &p_params, const string className);

   // Read the object class name from the initialization string
   static string     ReadClassName(string &p_params, bool p_removeClassName = true);

   // Read an object from the initialization string
   string            ReadObject(string &p_params);

   // Read an array from the initialization string as a string
   string            ReadArrayString(string &p_params);

   // Read a string from the initialization string
   string            ReadString(string &p_params);

   // Read a number from the initialization string as a string
   string            ReadNumber(string &p_params);

   // Read a real number from the initialization string
   double            ReadDouble(string &p_params);

   // Read an integer from the initialization string
   long              ReadLong(string &p_params);

   // Calculate the MD5 hash of a string
   static string     Hash(string p_params, string delimeter = "");
   virtual string    Hash() {
      return CFactorable::Hash(m_params);
   }

   // Create an object from the initialization string
   static CFactorable* Create(string p_params);
};


//+----------------------------------------------------------------------------+
//| Clear empty characters from left and right in the initialization string    |
//+----------------------------------------------------------------------------+
void CFactorable::Trim(string &p_params) {
// The position on the left where the initialization string content starts
   int posBeg = 0;

// If there is one comma at the beginning, shift to the right
   if(p_params[posBeg] == ',') posBeg++;

// While there are space characters, shift to the right
   while(false
         || p_params[posBeg] == '\r'
         || p_params[posBeg] == '\n'
         || p_params[posBeg] == '\t'
         || p_params[posBeg] == ' ') {
      posBeg++;
   }

// If there is one comma further, move to the right again
   if(p_params[posBeg] == ',') posBeg++;

// Cut out the insignificant left part of the initialization string
   p_params = StringSubstr(p_params, posBeg);

// The position on the right where the significant
// part of the initialization string ends
   int posEnd = StringLen(p_params) - 1;

// If there is a comma at the end, shift to the left
   if(p_params[posEnd] == ',') posEnd--;

// While there are space characters, shift to the left
// but not beyond the beginning of the string
   while(posEnd >= 0 && (false
                         || p_params[posEnd] == '\r'
                         || p_params[posEnd] == '\n'
                         || p_params[posEnd] == '\t'
                         || p_params[posEnd] == ' ')) {
      posEnd--;
   }

// If there is one comma further, move to the left again
   if(p_params[posEnd] == ',') posEnd--;

// Cut out the insignificant right part of the initialization string
   p_params = StringSubstr(p_params, 0, posEnd + 1);
}

//+------------------------------------------------------------------+
//| Find a matching closing bracket in the initialization string     |
//+------------------------------------------------------------------+
int CFactorable::FindCloseBracket(string &p_params, char closeBraket) {
// Bracket counter
   int count = 0;
// Matching bracket
   char openBraket = (closeBraket == ')' ? '(' : '[');

// Find the first opening bracket
   int pos;
   for(pos = 0; pos < StringLen(p_params); pos++) {
      if(p_params[pos] == openBraket) break;
   }

// Next, increase the counter for opening ones and decrease it for closing ones
   for(; pos < StringLen(p_params); pos++) {
      if(p_params[pos] == openBraket ) count++;
      if(p_params[pos] == closeBraket) count--;

      // When the counter became equal to 0, a matching closing bracket is found
      if(count == 0) {
         return pos;
      }
   }
// Otherwise, the bracket is not found
   return -1;
}

//+------------------------------------------------------------------+
//| Clear the initialization string with a check for the             |
//| current object validity                                          |
//+------------------------------------------------------------------+
bool CFactorable::CheckTrimParams(string &p_params) {
// If the current object is already in the invalid state, return 'false'
   if(!IsValid()) return false;
// Clear the initialization string
   Trim(p_params);
// Return the result of checking that the initialization string is not empty
   return (p_params != NULL && p_params != "");
}

//+------------------------------------------------------------------+
//| Set the current object to the invalid state                      |
//+------------------------------------------------------------------+
void CFactorable::SetInvalid(string function, string message) {
// If the object is still valid,
   if(IsValid()) {
      // set it to the invalid state
      m_isValid = false;
      if(function != NULL) {
         // Report an error if the name of the calling function is passed
         PrintFormat("%s | ERROR: %s", function, message);
      }
   } else {
      // Otherwise, just report an error if the name of the calling function is passed
      if(function != NULL) {
         PrintFormat("%s | ERROR: Object is invalid already", function);
      }
   }
}

//+------------------------------------------------------------------+
//|  Is the object valid?                                            |
//+------------------------------------------------------------------+
bool CFactorable::IsValid() {
   return m_isValid;
}

//+------------------------------------------------------------------+
//|  Is the object active?                                           |
//+------------------------------------------------------------------+
bool CFactorable::IsActive() {
   return m_isActive;
}

//+------------------------------------------------------------------+
//| Does the initialization string start with the object definition? |
//+------------------------------------------------------------------+
bool CFactorable::IsObject(string &p_params, const string className = "") {
// Return the result of checking that the word 'class' comes at the beginning
// with a possible class name after a space
   Trim(p_params);
   return (StringFind(p_params, "class " + className) == 0);
}

//+------------------------------------------------------------------+
//| Does the initialization string start with the definition of the  |
//| necessary class object?                                          |
//+------------------------------------------------------------------+
bool CFactorable::IsObjectOf(string &p_params, const string className) {
   return IsObject(p_params, className);
}

//+------------------------------------------------------------------+
//| Read the object class name from the initialization string        |
//+------------------------------------------------------------------+
string CFactorable::ReadClassName(string &p_params,
                                  bool p_removeClassName = true) {
// Clear blank characters at the beginning and end
   Trim(p_params);

// If the initialization string is empty, do nothing
   if(p_params == NULL || p_params == "") {
      return NULL;
   }

   string res = NULL;
// Initial position - 'class ' word length
   int posBeg = 6;
// The final position is the opening bracket after the class name
   int posEnd = StringFind(p_params, "(");

// If the string contains a class name and parameters in brackets
   if(IsObject(p_params) && posEnd != -1) {
      // Cut the class name as a result
      res = StringSubstr(p_params, posBeg, posEnd - posBeg);
      // If we only need to leave parameters in the initialization string,
      if(p_removeClassName) {
         // Remove the class name with brackets from the initialization string
         p_params = StringSubstr(p_params, posEnd + 1, StringLen(p_params) - posEnd - 2);
      }
   }
// Return the result
   return res;
}


//+------------------------------------------------------------------+
//| Read an object from the initialization string                    |
//+------------------------------------------------------------------+
string CFactorable::ReadObject(string &p_params) {
// If the initialization string is not empty and the current object is still valid
   if(CheckTrimParams(p_params)) {
      // If the initialization string contains an object description
      if(IsObject(p_params)) {
         // Find the position of the bracket that closes the description of the object parameters
         int posEnd = FindCloseBracket(p_params, ')');
         if(posEnd != -1) {
            // Take everything up to and including this bracket as a result
            string res = StringSubstr(p_params, 0, posEnd + 1);
            // Remove the return part from the initialization string
            p_params = StringSubstr(p_params, posEnd + 1);
            if(p_params == "") p_params = NULL;
            // Return the result
            return res;
         }
      }
   }
// Otherwise, set the current object to the invalid state and report an error
   SetInvalid(__FUNCTION__, StringFormat("Expected Object in Params:\n%s", p_params));

   return NULL;
}

//+------------------------------------------------------------------+
//| Read an array from the initialization string as a string         |
//+------------------------------------------------------------------+
string CFactorable::ReadArrayString(string &p_params) {
// If the initialization string is not empty and the current object is still valid
   if(CheckTrimParams(p_params)) {
      // Array description end position
      int posEnd = -1;

      // If there is a bracket opening an array at the beginning
      if(p_params[0] == '[') {
         // Find the position of the closing bracket
         posEnd = FindCloseBracket(p_params, ']');
         // If found, then
         if(posEnd != -1) {
            // Take everything up to this bracket as a result
            string res = StringSubstr(p_params, 1, posEnd - 1);
            // Clear blank characters at the beginning and end
            Trim(res);
            if(res == "") res = NULL;

            // Remove the return part from the initialization string along with the bracket
            p_params = StringSubstr(p_params, posEnd + 1);
            if(p_params == "") p_params = NULL;

            // Return the result
            return res;
         }
      }
   }
// Otherwise, set the current object to the invalid state and report an error
   SetInvalid(__FUNCTION__, StringFormat("Expected Array in Params:\n%s", p_params));

   return NULL;
}

//+------------------------------------------------------------------+
//| Read a string from the initialization string                     |
//+------------------------------------------------------------------+
string CFactorable::ReadString(string &p_params) {
// If the initialization string is not empty and the current object is still valid
   if(CheckTrimParams(p_params)) {
      // If this is not an array description or an object description
      if(p_params[0] != '[' && !IsObject(p_params)) {
         // Read string end position
         int posEnd = -1;
         // Is the string in quotes?
         int quoted = (p_params[0] == '"' ? 1 : 0);

         // If in quotes, then
         if(quoted) {
            // Find the next quote character
            posEnd = StringFind(p_params, "\"", 1);
            // If not found, then set the current object to the invalid state with an error message
            if(posEnd == -1) {
               SetInvalid(__FUNCTION__, StringFormat("Closed quote not found in Params:\n%s", p_params));
               return NULL;
            }
            // Move left from the closing quote
            posEnd--;
         } else {
            // Otherwise, find the first next comma
            posEnd = StringFind(p_params, ",");
         }
         // Take everything between the two found positions as a result
         string res = StringSubstr(p_params, 0 + quoted, posEnd);
         // Remove the return part from the initialization string along with the quotes
         p_params = StringSubstr(p_params, posEnd + quoted + 1);
         if(p_params == "") {
            p_params = NULL;
         }
         // Return the result
         return res;
      }
   }

// Otherwise, set the current object to the invalid state and report an error
   SetInvalid(__FUNCTION__, StringFormat("Expected String in Params:\n%s", p_params));

   return NULL;
}

//+------------------------------------------------------------------+
//| Read a number from the initialization string as a string         |
//+------------------------------------------------------------------+
string CFactorable::ReadNumber(string &p_params) {
// If the initialization string is not empty and the current object is still valid
   if(CheckTrimParams(p_params)) {
      // If this is not an array, string or object description
      if(p_params[0] != '['
            && p_params[0] != '"'
            && !IsObject(p_params)) {
         // Find the end position of the read number by the next comma
         int posEnd = StringFind(p_params, ",");
         // Take everything from the beginning to the found position as a result
         string res = StringSubstr(p_params, 0, posEnd);
         // Remove the return part from the initialization string
         p_params = StringSubstr(p_params, posEnd + 1);
         if(posEnd == -1) {
            p_params = NULL;
         }
         // Return the result
         return res;
      }
   }

// Otherwise, set the current object to the invalid state and report an error
   SetInvalid(__FUNCTION__, StringFormat("Expected Number in Params:\n%s", p_params));

   return NULL;
}

//+------------------------------------------------------------------+
//| Read a real number from the initialization string                |
//+------------------------------------------------------------------+
double CFactorable::ReadDouble(string &p_params) {
   return StringToDouble(ReadNumber(p_params));
}

//+------------------------------------------------------------------+
//| Read an integer from the initialization string                   |
//+------------------------------------------------------------------+
long CFactorable::ReadLong(string &p_params) {
   return StringToInteger(ReadNumber(p_params));
}

//+------------------------------------------------------------------+
//| Calculate the MD5 hash of a string                               |
//+------------------------------------------------------------------+
string CFactorable::Hash(string p_params, string p_delimeter = "") {
   uchar hash[], key[], data[];

// Calculate the hash from the initialization string
   StringToCharArray(p_params, data);
   CryptEncode(CRYPT_HASH_MD5, data, key, hash);

// Convert it from the array of numbers to a string with hexadecimal notation
   string res = "";
   FOREACH(hash) {
      res += StringFormat("%X", hash[i]);
      if(i % 4 == 3 && i < 15) res += p_delimeter;
   }

   return res;
}

//+------------------------------------------------------------------+
//| Create an object from the initialization string                  |
//+------------------------------------------------------------------+
CFactorable* CFactorable::Create(string p_params) {
// Pointer to the object being created
   CFactorable* object = NULL;

// Read the object class name
   string className = CFactorable::ReadClassName(p_params);

// Find and call the corresponding constructor depending on the class name
   int i;
   SEARCH(CFactorableCreator::creators, className == CFactorableCreator::creators[i].m_className, i);
   if(i != -1) {
      object = CFactorableCreator::creators[i].m_creator(p_params);
   }

// If the object is not created or is created in the invalid state, report an error
   if(!object) {
      PrintFormat(__FUNCTION__" | ERROR: Constructor not found for:\n%s",
                  p_params);
   } else if(!object.IsValid()) {
      PrintFormat(__FUNCTION__
                  " | ERROR: Created object is invalid for:\n%s",
                  p_params);
      delete object; // Remove the invalid object
      object = NULL;
   }

   return object;
}
//+------------------------------------------------------------------+
