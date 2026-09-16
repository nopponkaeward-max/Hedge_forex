//+------------------------------------------------------------------+
//|                                                        Money.mqh |
//|                                 Copyright 2022-2025, Yuriy Bykov |
//|                            https://www.mql5.com/en/users/antekov |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022-2025, Yuriy Bykov"
#property link      "https://www.mql5.com/en/users/antekov"
#property version   "1.01"

#include "VirtualOrder.mqh"
//+------------------------------------------------------------------+
//| Basic money management class                                     |
//+------------------------------------------------------------------+
class CMoney {
   static double     s_depoPart;       // Used part of the total balance
   static double     s_fixedBalance;   // Total balance used
   
   // Calculate the scaling factor of the virtual position volume
   static double     Coeff(CVirtualOrder *p_order);

public:
   CMoney() = delete;                  // Disable the constructor
   
   // Determine the calculated size of the virtual position
   static double     Volume(CVirtualOrder *p_order);
   
   // Determine the calculated profit of a virtual position  
   static double     Profit(CVirtualOrder *p_order);  

   // Set and read the used part of the total balance
   static void       DepoPart(double p_depoPart) {
      s_depoPart = p_depoPart;
   }
   static double     DepoPart() {
      return s_depoPart;
   }
   
   // Set and read the total balance used
   static void       FixedBalance(double p_fixedBalance) {
      s_fixedBalance = p_fixedBalance;
   }
   static double     FixedBalance() {
      return s_fixedBalance;
   }
};


double CMoney::s_depoPart = 1.0;
double CMoney::s_fixedBalance = 0;


//+------------------------------------------------------------------+
//| Calculate the virtual position volume scaling factor             |
//+------------------------------------------------------------------+
double CMoney::Coeff(CVirtualOrder *p_order) {
   // Request the normalized strategy balance for the virtual position
   double fittedBalance = p_order.FittedBalance();

   // If it is 0, then the scaling factor is 1
   if(fittedBalance == 0.0) {
      return 1;
   }

   // Otherwise, find the value of the total balance for trading
   double totalBalance = s_fixedBalance > 0 ? s_fixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);

   // Return the volume scaling factor
   return totalBalance * s_depoPart / fittedBalance;
}

//+------------------------------------------------------------------+
//| Determine the calculated size of the virtual position            |
//+------------------------------------------------------------------+
double CMoney::Volume(CVirtualOrder *p_order) {
   return p_order.Volume() * Coeff(p_order);
}

//+------------------------------------------------------------------+
//| Determine the calculated profit of a virtual position            |
//+------------------------------------------------------------------+
double CMoney::Profit(CVirtualOrder *p_order) {
   return p_order.Profit() * Coeff(p_order);
}
//+------------------------------------------------------------------+
