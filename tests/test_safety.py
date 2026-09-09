import unittest
import test_core

class SafetyTests(unittest.TestCase):
    run_body=test_core.CoreTests.run_body

    def test_recovery_and_normal_entries_share_pause_caps_and_session_gates(self):
        self.run_body(["EntrySafetyAllowed"], r'''
        string why;ENUM_WINDOW_ID w=WIN_NONE;
        check(EntrySafetyAllowed(w,why),"normal eligible account");
        g_executionUncertain=true;check(!EntrySafetyAllowed(w,why),"uncertain order outcome blocks all entries");g_executionUncertain=false;
        enabled=0;check(!EntrySafetyAllowed(w,why),"mobile pause also blocks recovery");enabled=1;
        g_consecutiveLosses=10;check(!EntrySafetyAllowed(w,why),"loss halt also blocks recovery");g_consecutiveLosses=0;
        g_tradesToday=100;check(!EntrySafetyAllowed(w,why),"daily cap also blocks recovery");g_tradesToday=0;
        session=false;check(!EntrySafetyAllowed(w,why),"disabled session also blocks recovery");
        ''', r'''
enum {MQL_TESTER,MQL_TRADE_ALLOWED,TERMINAL_TRADE_ALLOWED,ACCOUNT_TRADE_ALLOWED,ACCOUNT_TRADE_EXPERT};
bool g_indicatorsReady=true,g_executionUncertain=false,g_paused=false,InpEnableMobileCommands=true,InpUseSessionFilter=true,session=true;
int g_tradesToday=0,InpMaxTradesPerDay=100,InpMaxConsecutiveLosses=10;
int enabled=1;bool MQLInfoInteger(int p){return p!=MQL_TESTER;}bool TerminalInfoInteger(int){return true;}bool AccountInfoInteger(int){return true;}
string ControlKey(string s){return s;}bool GlobalVariableCheck(string){return true;}double GlobalVariableGet(string){return enabled;}
bool ShouldStopTrading(){return false;}bool WeekendOrRollover(){return false;}
ENUM_WINDOW_ID CurrentWindow(bool &tr){tr=session;return WIN_LONDON;}
''')

    def test_directional_entry_distance_is_zero(self):
        self.run_body(["PlannedEntryDistance"], r'''
        check(PlannedEntryDistance(true,2)==0,"market plan must use executable quote");
        check(PlannedEntryDistance(false,2)==.5,"pending plan retains configured ATR offset");
        InpSimpleScalpMode=true;check(PlannedEntryDistance(false,2)==0,"simple mode always market");
        ''', r'''
bool InpSimpleScalpMode=false,InpUseATRForDistance=true;
double InpATRMultiplier=.25,InpDistance=20,g_ptScale=1;
double MinTradeDistance(){return .1;}
''')
