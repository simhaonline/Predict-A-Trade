"""Focused EA regressions using real MQL bodies and simulated terminal boundaries."""
import unittest
import test_core
from test_core import SOURCE


class ExecutionTests(unittest.TestCase):
    run_body = test_core.CoreTests.run_body

    def test_late_history_retries_signal_and_never_arms_stale_signal(self):
        self.run_body(["OnTick"], r'''
        ready=false;newBar=true;OnTick();
        check(signals==0&&arms==0,"unready history must not generate or arm a signal");
        ready=true;newBar=false;OnTick();
        check(signals==1&&arms==1,"late history must evaluate on same bar and allow an entry");
        OnTick();check(signals==1,"closed bar evaluated once");
        bar=120;ready=false;newBar=true;OnTick();
        check(arms==2,"previous bar signal must not arm while new history unavailable");
        check(managed==4,"positions managed even while history is unavailable");
        ''', r'''
using datetime=long;
enum {PERIOD_M1,BREAKER_CLOSE_ALL};
string eaSymbol="XAUUSD",g_gateReason;
bool ready=false,newBar=false,g_indicatorsReady=false,g_paused=false,g_stopDay=false,g_stopWeek=false,g_stopMonth=false;
long bar=60,g_signalBar=0,g_indicatorBar=0,g_lastLossDir=0;
int signals=0,arms=0,managed=0,InpBreakerAction=0;
double g_rsi=50,g_m5e20=1,g_m5e50=1,g_m5adx=1,g_m5adxPlus=1,g_m5adxMinus=1,g_bbMid=1,g_bbUp=1,g_bbLo=1;
int hRSI=0,hM5E20=0,hM5E50=0,hM5ADX=0;
long iTime(string,int,int){return bar;}
void ProcessMobileCommands(){} void RefreshServerOffset(bool){} void UpdateRiskPeriods(){} void UpdateSpreadStats(){}
bool IsNewBar(){return newBar;} void UpdateIndicators(){g_indicatorsReady=ready;if(ready)g_indicatorBar=bar;}
void RefreshFMPMacro(bool){} void SR_Rebuild(){} void RefreshVolumeRatio(){} void UpdateSuperTrend(){} void UpdateVWAP(){}
void DetectFVG(){} void DetectIFVG(){} void DetectPTB(){} void AnalyzeAMD(){} void DetectSMC(){} void EvaluateFilters(){}
void UpdateOpportunityObservations(){} void CheckNews(bool){} void UpdateStructureState(){} void UpdateVolumeEngine(){}
void UpdateDirectionRegime(){} void UpdateEnvironmentRegime(){}
int CopyBuffer(int,int,int,int,double*){return 0;} int CopyClose(string,int,int,int,double*){return 0;}
double MathSqrt(double d){return std::sqrt(d);}
void EvaluateScalpSignal(){signals++;} void EmergencyCloseAll(){} void EnforceSwapFlat(){} void TryRecovery(){}
void TryArm(){arms++;} void ManageAllPositions(){managed++;} void DashUpdate(bool){} void ReportGate(){}
''')

    def test_scalp_state_preserves_broker_target_and_restart_plan(self):
        struct = SOURCE[SOURCE.index('struct PositionState\n'):SOURCE.index('\nstruct BucketStats')]
        self.run_body(["AddPositionState"], r'''
        g_armValid=true;AddPositionState(1,1,1,WIN_LONDON,"scalp",false,false,100,99,.01,0,0);
        check(modifies==0,"filled scalp must not move broker TP farther away");
        check(g_ps[0].tp1==100.55&&g_ps[0].volTP1==.01,"full TP1 plan matches validated trade");
        g_armValid=false;brokerTP=100.45;g_ps.clear();
        AddPositionState(1,1,1,WIN_LONDON,"scalp",false,false,100,99,.01,0,0);
        check(g_ps[0].tp1==100.45&&g_ps[0].volTP1==.01,"restart uses surviving broker TP, not a new ladder");
        check(modifies==0,"restart must preserve broker protection");
        g_ps[0].realizedNet=-.10;
        AddPositionState(1,1,1,WIN_LONDON,"scalp",false,false,100.02,99,.02,0,-.05);
        check(std::abs(g_ps[0].realizedNet+.15)<1e-9,"additional entry fill must preserve earlier commissions");
        check(g_ps[0].initialVolume==.02&&g_ps[0].entry==100.02,"additional fill uses total broker volume and weighted price");
        ''', r'''
#include <vector>
using datetime=long;
''' + struct + r'''
std::vector<PositionState> g_ps;
template<class T> int ArraySize(T &v){return v.size();}
template<class T> void ArrayResize(T &v,int n){v.resize(n);}
template<class T> void ZeroMemory(T &v){v=T{};}
int FindPS(unsigned long t){return g_ps.empty()?-1:0;}
bool InpSimpleScalpMode=true,InpUseThreeTargets=true,InpAB_EnableThreeTP=true,g_armValid=false;
double g_armTp1=100.55,g_armTp2=100.75,g_armTp3=101.15,g_volRatio=1,brokerTP=100.55;
int modifies=0;
enum {POSITION_TP,POSITION_TIME};
double PositionGetDouble(int){return brokerTP;} long PositionGetInteger(int){return 42;}
long ServerNow(){return 50;}
double PriceMoveMoney(double d,double v){return std::abs(d)*v*100;}
double CalculateRealTradeRiskMoney(int,double v,double e,double s){return std::abs(e-s)*v*100;}
double ExpectedAllInCost(double){return 0;} double SpreadPoints(){return 0;} double SpreadPercentile(){return 50;}
double ATRPercentile(){return 50;}
bool ModifyPositionSafe(unsigned long,double,double){modifies++;return true;}
void BuildThreeTargets(int,double,double,double,ENUM_WINDOW_ID,bool,double &a,double &b,double &c){a=101;b=102;c=103;}
void AllocateVolumes(double v,double &a,double &b,double &c){a=v*.75;b=v*.20;c=v*.05;}
''')

    def test_entry_slippage_is_quote_delta_without_subtracting_spread(self):
        self.run_body(["EntrySlippagePoints"], r'''
        check(EntrySlippagePoints(1,2000,2000,.01)==0,"zero slip despite nonzero spread");
        check(std::abs(EntrySlippagePoints(1,2000,2000.05,.01)-5)<1e-7,"buy adverse slip");
        check(std::abs(EntrySlippagePoints(-1,2000,1999.95,.01)-5)<1e-7,"sell adverse slip");
        check(EntrySlippagePoints(1,0,2000,.01)==0,"unknown requested price ignored");
        ''')

    def test_fmp_uses_only_operator_key(self):
        self.run_body(["FMPKey"], r'''
        check(FMPKey()=="","blank user key must not use embedded credentials");
        InpFMPAPIKey="operator-test-key";check(FMPKey()=="operator-test-key","configured API key must be honored");
        ''', r'''string InpFMPAPIKey="", FMP_APIKEY_C="synthetic";
using uchar=unsigned char;
int StringSplit(string,char,std::vector<string> &v){v={"68"};return 1;}
long StringToInteger(string s){return std::stol(s);}
string CharToString(uchar c){return string(1,c);}
''')


if __name__ == '__main__':
    unittest.main()

class BrokerBoundaryTests(unittest.TestCase):
    run_body = test_core.CoreTests.run_body

    def test_scalp_stop_respects_close_quote_and_tick_grid(self):
        self.run_body(["ScalpStopDistance"], r'''
        double sl=0;
        double dist=ScalpStopDistance(1,100.50,sl);
        check(sl<=99.90+1e-9,"buy SL must be below BID by broker minimum, not below ASK");
        check(std::abs(dist-(100.50-sl))<1e-9,"sizing uses actual rounded stop distance");
        ScalpStopDistance(-1,100,sl);
        check(sl>=100.60-1e-9,"sell SL must be above ASK by broker minimum");
        ''', r'''
string eaSymbol="XAUUSD";enum {PERIOD_M1};
double g_atr=.1;int g_scalpSignal=4;
const double SCALP_SL_REV=.45,SCALP_SL_BRK=.85,SCALP_SL_ATR=.8;
double SpreadCompensationFactor(){return 1;}
double iLow(string,int,int){return 100;} double iHigh(string,int,int){return 100.5;}
double Bid(){return 100;} double Ask(){return 100.5;}
double MinTradeDistance(){return .10;}
double PriceNorm(double p){return std::round(p/.01)*.01;}
''')

    def test_close_requires_confirmed_full_requested_volume(self):
        self.run_body(["ClosePartialSafe"], r'''
        retcode=TRADE_RETCODE_PLACED;filled=0;
        check(!ClosePartialSafe(1,.03),"accepted close is not confirmed execution");
        retcode=TRADE_RETCODE_DONE_PARTIAL;filled=.01;
        check(!ClosePartialSafe(1,.03),"partial fill must not complete a TP stage");
        retcode=TRADE_RETCODE_DONE;filled=.03;
        check(ClosePartialSafe(1,.03),"fully filled close completes stage");
        cur=.015;check(!ClosePartialSafe(1,.01),"do not request close leaving untradeable residual");
        ''', r'''
enum ENUM_POSITION_TYPE {POSITION_TYPE_BUY,POSITION_TYPE_SELL};
enum {POSITION_VOLUME,POSITION_TYPE,TRADE_ACTION_DEAL,ORDER_TYPE_SELL,ORDER_TYPE_BUY,TRADE_RETCODE_DONE,TRADE_RETCODE_PLACED,TRADE_RETCODE_DONE_PARTIAL};
struct MqlTradeRequest {int action,type,deviation;unsigned long position,magic;string symbol;double volume,price;};
struct MqlTradeResult {int retcode;double volume;unsigned long order;};
template<class T> void ZeroMemory(T &v){v=T{};}
bool PositionSelectByTicket(unsigned long){return true;}
double cur=.10,filled=.03;int retcode=TRADE_RETCODE_DONE;
double PositionGetDouble(int){return cur;} long PositionGetInteger(int){return POSITION_TYPE_BUY;}
string eaSymbol="XAUUSD";int InpMagicNumber=1,InpMaxSlippagePoints=25;
double FloorVolume(double d){return std::floor((d+1e-12)/.01)*.01;}
double Ask(){return 100;}double Bid(){return 99.9;}
bool SendOrder(MqlTradeRequest &rq,MqlTradeResult &rs){rs.retcode=retcode;rs.volume=filled;return true;}
''')

    def test_binary_state_string_roundtrip_keeps_following_field_aligned(self):
        self.run_body(["WriteStateText", "ReadStateText"], r'''
        string out;
        WriteStateText(1,"EMA pullback LONG");FileWriteInteger(1,12345,INT_VALUE);
        check(ReadStateText(1,out)&&out=="EMA pullback LONG","binary state needs an explicit string length");
        check(FileReadInteger(1,INT_VALUE)==12345,"string read must preserve field alignment");
        bytes.clear();pos=0;WriteStateText(1,"");
        check(ReadStateText(1,out)&&out=="","empty setup supported");
        bytes.clear();pos=0;FileWriteInteger(1,1000000,INT_VALUE);
        check(!ReadStateText(1,out),"corrupt string length rejected");
        bytes.clear();pos=0;WriteStateText(1,"abc");bytes.pop_back();
        check(!ReadStateText(1,out),"truncated UTF16 text rejected");
        ''', r'''
#include <cstring>
enum {INT_VALUE};std::vector<unsigned char> bytes;size_t pos=0;
int StringLen(string s){return s.size();}
void FileWriteInteger(int,int n,int){for(int k=0;k<4;k++)bytes.push_back((n>>(8*k))&255);}
int FileReadInteger(int,int){int n=0;for(int k=0;k<4;k++){if(pos>=bytes.size())return 0;n|=bytes[pos++]<<(8*k);}return n;}
unsigned long FileSize(int){return bytes.size();}unsigned long FileTell(int){return pos;}
void FileWriteString(int,string s,int len=-1){for(char c:s){bytes.push_back(c);bytes.push_back(0);}}
string FileReadString(int,int n=-1){string s;for(int i=0;i<n&&pos+1<bytes.size();i++){s+=bytes[pos];pos+=2;}return s;}
''')
