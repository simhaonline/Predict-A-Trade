"""Run actual, extracted MQL function bodies with a small C++ terminal shim.

This checks business logic, not MQL compilation or broker integration.
Run: python3 -m unittest discover -s tests -v
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOURCE = Path(os.environ.get("PAT_SOURCE", Path(__file__).resolve().parents[1] / "Predict-A-Trade-Ultra.mq5")).read_text()


def function(name):
    matches = list(re.finditer(r"^\w+ " + name + r"\([^;]*?\)\s*\{", SOURCE, re.M))
    if not matches:
        raise AssertionError(f"Missing function {name}")
    start = matches[-1].start()
    brace = SOURCE.index("{", matches[-1].start())
    depth = 1
    end = brace + 1
    # These selected functions do not contain braces in strings/comments.
    while depth:
        depth += (SOURCE[end] == "{") - (SOURCE[end] == "}")
        end += 1
    return SOURCE[start:end]


SHIM = r'''
#include <cmath>
#include <vector>
#include <iostream>
#include <string>
using string=std::string;
template<class A,class B> double MathMin(A a,B b){return a<b?a:b;}
template<class A,class B> double MathMax(A a,B b){return a>b?a:b;}
double MathAbs(double x){return std::abs(x);}
double MathFloor(double x){return std::floor(x);}
double MathPow(double a,double b){return std::pow(a,b);}
double NormalizeDouble(double x,int d){double p=std::pow(10,d);return std::round(x*p)/p;}
bool MathIsValidNumber(double x){return std::isfinite(x);}
template<class... T> void Print(T... args){}
string DoubleToString(double x,int d){return std::to_string(x);}
enum ENUM_WINDOW_ID {WIN_NONE,WIN_LONDON,WIN_COUNT};
enum {ACCOUNT_EQUITY,LADDER_FAVOR_TP1,LADDER_FAVOR_RUNNER,LADDER_PROPORTIONAL};
double eq=10000,baseRisk=.35,regime=1,windowMult=1,mobile=0;
double g_dayAnchor=10000,InpMaxFloatingDDPercent=3,InpRiskStepDownOnDD=.15;
int g_consecutiveLosses=0;
double InpRiskFloorPct=.10,InpHVExtraSignalRiskMult=.5,InpRiskPercent=.35,g_riskOverrideRequested=0;
bool InpAutoCapitalProfile=true,InpAutoRiskSizing=true;
double AccountInfoDouble(int p){return eq;}
double GetProfileBaseRiskPct(){return baseRisk;}
double RegimeRiskMultiplier(){return regime;}
double WindowRiskMultiplier(ENUM_WINDOW_ID w){return windowMult;}
double GetMobileRiskRequestPct(){return mobile;}
struct {int digits=2;double point=.01,volumeMin=.01,volumeMax=100,volumeStep=.01;} broker;
double g_tp1PctEff=.75,g_tp2PctEff=.20,g_tp3PctEff=.05;
bool InpAutoDegradeTPLadder=true;
int InpLadderRoundingMode=LADDER_FAVOR_TP1;
int failures=0;
void check(bool ok,const char* msg){if(!ok){std::cerr<<msg<<"\n";failures++;}}
'''


class CoreTests(unittest.TestCase):
    def run_body(self, names, body, prelude=""):
        code = SHIM + prelude + "\n".join(function(n) for n in names)
        code = re.sub(r"string (\w+)\[\];", r"std::vector<string> \1;", code)
        # 'auto' is an existing MQL local name, reserved in C++.
        code = re.sub(r"\bauto\b", "autoMode", code)
        code = re.sub(r"(string|double) &(\w+)\[\]", r"\1 *\2", code)
        code += "\nint main(){" + body + "\nreturn failures?1:0;}"
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "test.cpp"
            src.write_text(code)
            exe = Path(temp) / "test"
            built = subprocess.run(["g++", "-std=c++17", "-O0", str(src), "-o", str(exe)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(exe)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)

    def test_definitions_are_unique(self):
        names = re.findall(r"^\w+ (\w+)\([^;]*?\)\s*\{", SOURCE, re.M)
        duplicates = {n for n in names if names.count(n) > 1}
        self.assertEqual(duplicates, set(), "Duplicate function definitions prevent compilation")

    def test_mobile_request_caps_risk(self):
        self.run_body(["GetEffectiveTradeRiskPct"], '''
        mobile=.02;
        check(std::abs(GetEffectiveTradeRiskPct(WIN_LONDON,false)-.02)<1e-10,"mobile .02% must cap .35% base below floor");
        ''')

    def test_environment_and_window_reductions_are_not_undone(self):
        self.run_body(["GetEffectiveTradeRiskPct"], '''
        regime=0;
        check(GetEffectiveTradeRiskPct(WIN_LONDON,false)==0,"blocked environment must have zero risk");
        regime=.5;windowMult=.5;g_consecutiveLosses=10;
        check(GetEffectiveTradeRiskPct(WIN_LONDON,false)<=.025+1e-10,"floor must not undo environment/window reductions");
        windowMult=0;
        check(GetEffectiveTradeRiskPct(WIN_LONDON,true)==0,"disabled window must stay zero");
        ''')

    def test_reward_must_be_in_trade_direction(self):
        self.run_body(["RRValid"], '''
        check(!RRValid(1,100,99,98,1),"losing buy target cannot pass RR");
        check(!RRValid(-1,100,101,102,1),"losing sell target cannot pass RR");
        check(!RRValid(1,100,101,102,1),"stop on profit side is not initial risk");
        check(RRValid(1,100,99,102,1.5),"valid buy reward");
        ''')

    def test_ladder_conserves_volume_and_valid_residuals(self):
        self.run_body(["VolDigits", "FloorVolume", "AllocateVolumes"], '''
        for(int mode=LADDER_FAVOR_TP1;mode<=LADDER_PROPORTIONAL;mode++){
          InpLadderRoundingMode=mode;
          for(int i=1;i<=1000;i++){
            double total=i*.01,a,b,c;AllocateVolumes(total,a,b,c);
            check(std::abs(a+b+c-total)<1e-9,"ladder creates or drops volume");
            check(a>=0&&b>=0&&c>=0,"negative allocation");
            check(a<=total+1e-9&&b<=total-a+1e-9,"partial exceeds remaining volume");
          }
        }
        broker.volumeStep=.25;broker.volumeMin=.25;
        check(std::abs(FloorVolume(.74)-.5)<1e-10,"non-power-of-ten lot step must floor");
        check(FloorVolume(.24)==0,"sub-min lot must not round up");
        ''')


if __name__ == "__main__":
    unittest.main()
