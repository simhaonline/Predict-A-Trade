"""Macro bootstrap/fallback regressions; HTTP replaced at the quote boundary."""
import unittest
import test_core

class MacroTests(unittest.TestCase):
    run_body=test_core.CoreTests.run_body

    def test_first_success_and_offline_fallback_produce_votes(self):
        self.run_body(["FMPQuoteBatch", "RefreshFMPMacro"], r'''
        RefreshFMPMacro(true);
        check(g_usdAvailable&&g_fmpLastOK==10000,"first successful feed must bootstrap");
        check(g_macroBull>0,"successful bullish data must produce bullish votes");
        tester=true;g_macroBull=0;g_macroBear=0;RefreshFMPMacro(true);
        check(g_eurAvailable&&g_macroBull==1,"tester fallback must refresh macro votes");
        tester=false;key="";calls=0;RefreshFMPMacro(true);
        check(calls==0&&g_macroBull==1,"blank live API key uses broker fallback without HTTP");
        ''', r'''
using datetime=long;
#define FMPUSD_COUNT 7
enum {MQL_TESTER};
bool tester=false,InpUseFMP=true,InpAllowBrokerMacroFallback=true,InpUseEURUSD=true,InpFMPIncludeSPX=true;
string key="test-key",g_eurSymbol="",InpEURUSDSymbol="EURUSD",g_fmpLastErr="";
string g_usdPairs[FMPUSD_COUNT]={"EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD","NZDUSD"};
int InpMacroTF=0,InpMacroMomentumBars=1,InpFMPRefreshSec=3600,g_fmp429Count=0,g_fmpCycle=0,g_fmpErrCount=0;
long g_fmpLastTry=0,g_fmpLastOK=0;
bool g_usdAvailable=false,g_spxAvailable=false,g_eurAvailable=false,g_fmpEverOK=false,g_usdGotSPX=false;
bool g_usdGot[FMPUSD_COUNT];double g_usdMove[FMPUSD_COUNT],g_usdAvg=0,g_spxBatchChg=0;
int g_usdBias=0,g_spxBias=0,g_eurBias=0,g_macroBull=0,g_macroBear=0,calls=0;
double g_eurMovePct=0,g_spxMovePct=0,InpEURUSDMinMovePct=.01,InpFMPUSDPairMinPct=.02,InpFMPSPXMinPct=.3;
bool MQLInfoInteger(int){return tester;} string FMPKey(){return key;}
string ResolveBrokerSymbol(string s,string){return s;}
double SymbolMomentumPct(string,int,int,bool &ok){ok=true;return .1;}
long ServerNow(){return 10000;}
int StringFind(string a,string b){size_t p=a.find(b);return p==string::npos?-1:p;}
string StringSubstr(string s,int pos,int len=-1){return s.substr(pos,len<0?string::npos:len);}
bool FMPQuote(string symbol,double &chg,double &price){calls++;price=100;chg=symbol.substr(0,3)=="USD"?-.1:.1;return true;}
void FMPNewsScan(){}
''')
