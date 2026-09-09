"""State serialization roundtrip against a byte-addressed MQL file shim."""
import re
import unittest
import test_core

class StateTests(unittest.TestCase):
    run_body=test_core.CoreTests.run_body

    def test_state_roundtrip_preserves_breakers_and_position_plan(self):
        structs=test_core.SOURCE[test_core.SOURCE.index('struct WindowStats\n'):test_core.SOURCE.index('\nstruct BucketStats')]
        self.run_body(["WriteStateText","ReadStateText","SaveState","LoadState"], r'''
        PositionState p{};p.ticket=1;p.positionId=7;p.window=WIN_LONDON;p.setupId="EMA pullback LONG";
        p.tp1=101;p.tp2=102;p.tp3=103;p.initialVolume=.1;p.lots=.1;p.reservedRisk=12;p.direction=1;p.entry=100;p.initialSL=99;
        g_ps.push_back(p);g_stopDay=true;g_stopWeek=true;g_stopMonth=true;
        SaveState();g_ps.clear();g_stopDay=g_stopWeek=g_stopMonth=false;
        LoadState();
        check(g_stopDay&&g_stopWeek&&g_stopMonth,"restart must preserve latched breakers");
        check(g_ps.size()==1,"position plan restored");
        if(g_ps.size()==1){check(g_ps[0].setupId=="EMA pullback LONG"&&g_ps[0].tp1==101,"plan remains aligned after text");
        check(g_ps[0].reservedRisk==12&&g_ps[0].lots==.1,"reservation fields survive restart");}
        ''', r'''
#include <cstring>
using datetime=long;
''' + structs + r'''
enum {FILE_BIN=1,FILE_WRITE=2,FILE_COMMON=4,FILE_READ=8,FILE_REWRITE=16,INVALID_HANDLE=-1,INT_VALUE=4,POSITION_IDENTIFIER,POSITION_SYMBOL,POSITION_MAGIC};
''' + re.search(r'^#define STATE_TAG .*$',test_core.SOURCE,re.M).group() + r'''
std::vector<unsigned char> bytes;size_t pos=0;
int FileOpen(string,int flags){pos=0;if(flags&FILE_WRITE)bytes.clear();return 1;}
void FileClose(int){}void FileFlush(int){}bool FileMove(string,int,string,int){return true;}
bool FileIsEnding(int){return pos>=bytes.size();}unsigned long FileSize(int){return bytes.size();}unsigned long FileTell(int){return pos;}
bool FileSeek(int,long offset,int origin){pos=(origin==SEEK_END?bytes.size():0)+offset;return true;}
template<class T> void put(T n){unsigned char b[sizeof(T)];std::memcpy(b,&n,sizeof n);bytes.insert(bytes.end(),b,b+sizeof n);}
template<class T> T get(){T n{};if(pos+sizeof n<=bytes.size()){std::memcpy(&n,bytes.data()+pos,sizeof n);pos+=sizeof n;}return n;}
void FileWriteInteger(int,int n,int){put<int>(n);}int FileReadInteger(int,int){return get<int>();}
void FileWriteDouble(int,double n){put<double>(n);}double FileReadDouble(int){return get<double>();}
void FileWriteLong(int,long n){put<long>(n);}long FileReadLong(int){return get<long>();}
int StringLen(string s){return s.size();}
void FileWriteString(int,string s,int n=-1){for(char c:s)put<unsigned short>(c);}
string FileReadString(int,int n=-1){string s;for(int i=0;i<n;i++)s+=get<unsigned short>();return s;}
template<class T> void ZeroMemory(T &v){v=T{};}template<class T> int ArraySize(T &v){return v.size();}
template<class T> void ArrayResize(T &v,int n){v.resize(n);}
string StateName(){return "test.bin";}string eaSymbol="XAUUSD";long InpMagicNumber=5;
bool InpPersistState=true,g_initialized=true,g_executionUncertain=false,g_stopDay=false,g_stopWeek=false,g_stopMonth=false;
int g_dayKey=1,g_weekKey=1,g_monthKey=1,g_tradesToday=0,g_perfTrades=0,g_perfWins=0,g_perfLosses=0,g_perfRetN=0;
double g_weekAnchor=10000,g_monthAnchor=10000,g_commissionRTPerLot=0,g_perfNetProfit=0,g_perfGrossProfit=0,g_perfGrossLoss=0,g_perfRetMean=0,g_perfRetM2=0,g_perfCumNet=0,g_perfPeakNet=0,g_perfMaxDDMoney=0;
WindowStats g_ws[WIN_COUNT];std::vector<PositionState> g_ps;
int PositionsTotal(){return 1;}unsigned long PositionGetTicket(int){return 1;}bool PositionSelectByTicket(unsigned long){return true;}
long PositionGetInteger(int p){return p==POSITION_MAGIC?5:7;}string PositionGetString(int){return "XAUUSD";}
int GetLastError(){return 0;}
''')
