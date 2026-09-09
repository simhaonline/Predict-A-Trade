You are modifying my EXISTING production MQL5 Expert Advisor:

Predict-A-Trade-Ultra.mq5

The file has ALREADY been upgraded with the broker-native adaptive capital/risk engine from prompt.md.

DO NOT undo, weaken, replace, bypass or reimplement that work.

This task is ONLY to add the remaining high-value MARKET ANALYSIS / SIGNAL QUALITY / REGIME / CONFIDENCE features identified in the latest audit.

======================================================================
0. PRIMARY RULE
===============

DO NOT rebuild the EA from scratch.

DO NOT create a new/simple EA.

DO NOT remove existing working modules.

DO NOT change existing strategy behavior unnecessarily.

Perform a SURGICAL ADDITIVE UPGRADE.

The EXISTING Predict-A-Trade-Ultra.mq5 is the primary source of truth.

Preserve all current functionality including:

* Adaptive capital profiles
* Auto risk sizing
* OrderCalcProfit
* OrderCalcMargin
* OrderCheck
* Adaptive spread/slippage logic
* Aggregate/directional/window risk controls
* Sydney/Tokyo/London/New York sessions
* Session overlaps
* High Volatility engine
* SMC
* BOS
* CHOCH
* FVG
* IFVG
* PTB
* VWAP
* EMA20
* EMA50
* SuperTrend
* ADX
* RSI
* ATR
* Bollinger calculations
* volume filter
* relative volume
* liquidity filter
* support/resistance engine
* macro/FMP
* EURUSD intermarket logic
* TP1/TP2/TP3
* structure-aware SL/TP
* cost-adjusted BE
* trailing
* recovery
* no martingale
* no averaging down
* news protection
* disorder protection
* swap protection
* licensing
* mobile commands
* dashboard
* logging
* persistence
* broker-server-time synchronization.

======================================================================

1. MISSION
   ======================================================================

Add the following missing/improved components:

1. Explicit HH / HL / LH / LL market-structure classifier
2. EMA 9
3. EMA 200
4. Proper MACD implementation
5. Volume Spike / Volume Percentile classification
6. Unified Direction Regime Engine
7. Unified Environment Regime Engine
8. Weighted 0-100 Confidence Engine
9. Configurable minimum confidence threshold
10. BUY / SELL / NO_TRADE centralized decision
11. Central SignalDecision telemetry structure
12. Setup-specific NET R:R validation
13. Optional Gold Options/OI architecture, but advisory and fail-open
14. Detailed Signal Reasons / Gate Reasons
15. Dashboard + CSV integration for all new telemetry.

Do NOT add ROC at this stage.

Do NOT duplicate Bollinger Bands because the existing EA already computes them.

Do NOT add Theta/Vega as direct trade-entry votes.

======================================================================
2. FIRST AUDIT EXISTING SOURCE
==============================

Before modifying anything, search the ENTIRE EA for:

EMA
EMA20
EMA50
SuperTrend
VWAP
RSI
MACD
ATR
ADX
Bollinger
g_bbUp
g_bbLo
g_bbMid
volume
g_volRatio
SMC
BOS
CHOCH
swing
liquidity
FVG
IFVG
PTB
g_score
g_scoreMax
g_dirBias
InpMinFilterScore
EvaluateFilters
EvaluateScalpSignal
CanEnter
TryArm
BuildThreeTargets
RiskRoom
ScalpStopDistance
ScalpTarget
SR_
HighVolatility
IsDisorder
CandleDisplacementATR
RollingBreakout
Window
Macro
FMP
EURUSD.

Do NOT add duplicate data when equivalent telemetry already exists.

Reuse existing handles, buffers and cached values whenever possible.

======================================================================
3. EXPLICIT MARKET STRUCTURE CLASSIFIER
=======================================

Add an explicit structural state rather than relying only on scattered BOS/CHOCH votes.

Create:

enum ENUM_STRUCTURE_STATE
{
STRUCTURE_UNKNOWN=0,
STRUCTURE_HH_HL,
STRUCTURE_LH_LL,
STRUCTURE_TRANSITION_BULL,
STRUCTURE_TRANSITION_BEAR,
STRUCTURE_RANGE
};

Track recent confirmed swing points from the existing swing/SMC logic.

Prefer reusing existing swing-high/swing-low detection instead of creating an entirely separate expensive subsystem.

Explicitly determine:

Higher High
Higher Low
Lower High
Lower Low.

Required concepts:

Bullish structure:
HH + HL sequence

Bearish structure:
LH + LL sequence

Bullish transition:
bearish/range structure followed by bullish CHOCH/BOS confirmation

Bearish transition:
bullish/range structure followed by bearish CHOCH/BOS confirmation

Range:
alternating/overlapping swings without directional progression.

Add telemetry such as:

g_lastSwingHigh
g_prevSwingHigh
g_lastSwingLow
g_prevSwingLow
g_structureState
g_structureBullStrength
g_structureBearStrength.

Avoid using forming-bar pivots that repaint.

Use CLOSED bars / confirmed swings.

======================================================================
4. EMA 9
========

Add:

input bool InpUseEMA9=true;
input int InpEMA9Period=9;

Create/cached handle following the existing EMA architecture.

Add global:

g_ema9.

Use EMA9 as SHORT-TERM MICRO-MOMENTUM / ENTRY TIMING.

It must NOT become an unconditional hard gate.

Examples:

Bullish:
EMA9 > EMA20

Bearish:
EMA9 < EMA20.

Bonus alignment:

EMA9 > EMA20 > EMA50

or

EMA9 < EMA20 < EMA50.

Do not require perfect EMA stacking on every valid mean-reversion setup.

======================================================================
5. EMA 200
==========

Add:

input bool InpUseEMA200=true;
input int InpEMA200Period=200;

Add:

g_ema200.

EMA200 is a REGIME / MAJOR TREND CONTEXT indicator.

Use:

price > EMA200
as bullish major bias.

price < EMA200
as bearish major bias.

EMA200 should contribute confidence and regime information.

It should NOT automatically veto every counter-trend VWAP mean-reversion scalp.

Instead reduce confidence or apply setup-specific rules.

======================================================================
6. PROPER MACD
==============

The existing source contains references/comments about MACD voting but does not have a complete real MACD implementation.

Add native MQL5 MACD.

Inputs:

input bool InpUseMACD=true;
input int InpMACDFast=12;
input int InpMACDSlow=26;
input int InpMACDSignal=9;

Use:

iMACD()

for M1.

Optionally add M5 MACD only if it can be reused efficiently and materially helps regime scoring.

Cache:

g_macdMain
g_macdSignal
g_macdHist.

Define:

hist =
main - signal.

Bullish momentum evidence:

main > signal
hist > 0
hist increasing where practical.

Bearish:

main < signal
hist < 0
hist decreasing.

Do NOT make MACD mandatory on every setup.

It is a momentum confidence contributor.

======================================================================
7. VOLUME SPIKE / PERCENTILE ENGINE
===================================

The EA already has:

g_volRatio
volume moving average
InpMinVolumeRatio
InpHVMinVolumeRatio.

Do NOT duplicate them.

Extend with a rolling volume distribution.

Add a fixed-size ring buffer such as:

VOLUME_SAMPLES = 256.

Track:

relative volume
or
tick volume normalized by rolling average.

Create:

double VolumePercentile();
ENUM_VOLUME_STATE GetVolumeState();

Enum:

enum ENUM_VOLUME_STATE
{
VOLUME_LOW=0,
VOLUME_NORMAL,
VOLUME_ELEVATED,
VOLUME_SPIKE,
VOLUME_EXTREME
};

Suggested classification:

LOW:
percentile < 25

NORMAL:
25-65

ELEVATED:
65-85

SPIKE:
85-97

EXTREME:

> 97.

Do not treat these exact numbers as immutable hidden constants; expose key thresholds as inputs if practical.

Use volume percentile together with relative volume.

Volume Spike should increase confidence ONLY when:

directional candle quality
market structure
trend
or breakout

supports the same direction.

An isolated volume spike without directional confirmation should NOT automatically create a trade.

Extreme volume combined with abnormal ATR/spread/displacement should contribute to DISORDER or EXTREME_VOLATILITY classification.

======================================================================
8. TWO-DIMENSION MARKET REGIME ENGINE
=====================================

Do NOT force trend and volatility into one mutually-exclusive enum.

Create TWO independent regime dimensions.

A. DIRECTION REGIME

enum ENUM_DIRECTION_REGIME
{
REGIME_STRONG_BULLISH=0,
REGIME_BULLISH,
REGIME_SIDEWAYS,
REGIME_BEARISH,
REGIME_STRONG_BEARISH
};

B. ENVIRONMENT REGIME

enum ENUM_ENVIRONMENT_REGIME
{
ENV_NORMAL=0,
ENV_HIGH_VOLATILITY,
ENV_EXTREME_VOLATILITY,
ENV_LOW_LIQUIDITY,
ENV_DISORDER
};

Direction Regime should use weighted evidence from:

* explicit HH/HL/LH/LL structure
* BOS/CHOCH
* EMA9
* EMA20
* EMA50
* EMA200
* M5 EMA20/50
* M15/H1 EMA20/50 where already available
* VWAP relationship
* ADX
* DI+/DI-
* SuperTrend
* optionally macro direction as a SMALL contextual input.

Environment Regime should use:

* ATR percentile
* current ATR / rolling ATR
* spread percentile
* spread/ATR
* volume percentile
* relative volume
* candle displacement ATR
* slippage quality
* liquidity ratio
* existing IsDisorder()
* existing High Volatility engine.

Required behavior:

SIDEWAYS:
risk multiplier <= 1
prefer reduced risk or stricter confidence requirement.

HIGH_VOLATILITY:
reduce risk using existing HV risk architecture.

EXTREME_VOLATILITY:
BLOCK NEW ENTRIES.

LOW_LIQUIDITY:
BLOCK NEW ENTRIES.

DISORDER:
BLOCK NEW ENTRIES.

Do NOT interfere with position management / emergency exits.

======================================================================
9. CENTRAL 0-100 CONFIDENCE ENGINE
==================================

Upgrade the existing g_score/g_scoreMax architecture into a normalized confidence engine while preserving backward compatibility.

Add:

input bool InpUseConfidenceEngine=true;
input double InpMinConfidenceScore=75.0;

Use weighted categories:

PRICE ACTION / SMC ................. 20
TREND / MTF ALIGNMENT .............. 15
VOLUME / LIQUIDITY ................. 15
MOMENTUM ........................... 10
VWAP / PRICE LOCATION .............. 10
VOLATILITY / ENVIRONMENT ........... 10
MACRO / INTERMARKET ................ 10
OPTIONS / OI ....................... 5
RISK/REWARD + COST QUALITY ......... 5

TOTAL AVAILABLE = 100.

Create:

struct ConfidenceBreakdown
{
double priceAction;
double trend;
double volumeLiquidity;
double momentum;
double vwapLocation;
double volatility;
double macro;
double options;
double riskReward;
double rawScore;
double possibleScore;
double normalizedScore;
};

Do not allocate points merely because an indicator exists.

Points must reflect directional agreement with the proposed trade.

Compute independently for LONG and SHORT:

ConfidenceBreakdown longConfidence;
ConfidenceBreakdown shortConfidence.

Then:

NormalizedScore =
rawScore / possibleScore * 100.

======================================================================
10. MISSING DATA RENORMALIZATION
================================

This is MANDATORY.

If an external category is unavailable:

OPTIONS
MACRO

do NOT automatically score zero unless the user explicitly configures fail-closed behavior.

Instead remove that category's weight from possibleScore.

Example:

available raw = 82
available possible = 90

normalized =
82/90*100
=========

91.11.

Use:

input bool InpNormalizeMissingExternalData=true;

Preserve existing:

InpRequireExternalData

behavior.

If InpRequireExternalData=true:
existing external-data hard blocking may remain.

Otherwise:
fail-open with confidence renormalization.

======================================================================
11. CONFIDENCE THRESHOLD BY ENVIRONMENT
=======================================

Base:

InpMinConfidenceScore=75.

Add optional:

input bool InpUseAdaptiveConfidenceThreshold=true;
input double InpConfidenceHighVol=80.0;
input double InpConfidenceSideways=82.0;
input double InpConfidenceLowLiquidity=100.0;
input double InpConfidenceExtremeVol=100.0;

Logic:

NORMAL:

> =75

HIGH VOLATILITY:

> =80

SIDEWAYS:

> =82

EXTREME VOLATILITY:
NO TRADE regardless of score

LOW LIQUIDITY:
NO TRADE regardless of score

DISORDER:
NO TRADE.

Do not accidentally block the four primary sessions simply because their session expectancy is weak; keep existing session behavior.

Regime gates and session gating are separate concerns.

======================================================================
12. BUY / SELL / NO_TRADE DECISION ENGINE
=========================================

Add:

enum ENUM_SIGNAL_DECISION
{
SIGNAL_NO_TRADE=0,
SIGNAL_BUY=1,
SIGNAL_SELL=-1
};

Create ONE centralized decision function:

ENUM_SIGNAL_DECISION BuildSignalDecision(...);

Avoid scattered contradictory direction logic.

Final LONG requires:

* proposed long setup exists
* structure compatible
* trend confirmation appropriate to setup
* momentum confirmation
* volume/liquidity acceptable
* environment not blocked
* confidence >= adaptive threshold
* setup valid
* risk/reward valid
* risk budget available
* spread valid
* slippage valid
* margin valid
* news/disorder/swap/session gates valid.

SHORT symmetrical.

If both BUY and SELL confidence exceed threshold simultaneously:

do NOT blindly pick one.

Require minimum confidence separation:

input double InpMinDirectionalConfidenceGap=5.0;

Example:

LONG=84
SHORT=81

gap=3

=> NO_TRADE unless the setup itself supplies a strong directional override.

This prevents ambiguous market entries.

======================================================================
13. CENTRAL SIGNALDECISION STRUCT
=================================

Create a central structure similar to:

struct SignalDecision
{
string instrument;

ENUM_SIGNAL_DECISION decision;
int direction;

double entry;
double stopLoss;
double tp1;
double tp2;
double tp3;

double quantity;

double riskMoney;
double riskPct;

double potentialRewardMoney;
double netPotentialRewardMoney;
double riskReward;

double confidence;
double oppositeConfidence;
double confidenceGap;

ENUM_STRUCTURE_STATE structure;
ENUM_DIRECTION_REGIME directionRegime;
ENUM_ENVIRONMENT_REGIME environmentRegime;
ENUM_VOLUME_STATE volumeState;

ENUM_WINDOW_ID window;

bool highVolatility;

double spreadPoints;
double spreadPercentile;
double spreadToATR;
double expectedSlippage;
double expectedCost;

ConfidenceBreakdown confidenceBreakdown;

string setupName;
string signalReasons;
string gateReason;
};

This structure becomes the authoritative internal trade-plan/telemetry object.

Do not break existing state structs.

This is additive.

======================================================================
14. SIGNAL REASONS
==================

For every candidate generate clear reasons.

Examples:

LONG reasons:

HH_HL
BULLISH_BOS
EMA9>EMA20
EMA20>EMA50
ABOVE_EMA200
M5_TREND_UP
VWAP_SUPPORT
RSI_BULLISH
MACD_BULLISH
VOLUME_SPIKE_CONFIRMED
SR_BREAKOUT
LIQUIDITY_SWEEP_LOW
FVG_BULL
IFVG_BULL
PTB_BULL
MACRO_SUPPORTIVE
RR_PASS
COST_PASS.

SHORT symmetrical.

Do NOT concatenate an unbounded massive string every tick.

Build reason text only:

* when evaluating a final candidate
* when logging
* when dashboard needs it.

======================================================================
15. SETUP-SPECIFIC CONFIDENCE
=============================

Do NOT apply identical rules to every setup.

Recognize existing setups such as:

EMA PULLBACK
VWAP MEAN REVERSION
LONDON BREAKOUT
NY MOMENTUM
GENERAL COMPLEX-MODE SIGNAL
RECOVERY.

Weight evidence differently where appropriate.

Example:

EMA PULLBACK:
trend alignment more important
EMA9/20/50 useful
EMA200 contextual
MACD useful
volume moderate confirmation.

VWAP REVERSION:
VWAP deviation
RSI extreme
Bollinger recross
reversal candle
M5 ADX not too strong
support/resistance
liquidity sweep

more important than perfect EMA stacking.

London Breakout:
range break
volume spike
ATR expansion
M5 trend
VWAP
market structure
spread/liquidity

more important.

NY Momentum:
volume
breakout
trend
MACD
EMA alignment
VWAP
liquidity.

Do not make mean-reversion impossible because trend-following components disagree.

======================================================================
16. SETUP-SPECIFIC R:R
======================

DO NOT add universal:

Risk/Reward >= 3.0.

That is inappropriate for the current ultra-scalp architecture.

Create setup-specific minimum NET R:R.

Add inputs:

input double InpMinNetRR_EMAPullback=1.20;
input double InpMinNetRR_VWAPReversion=1.00;
input double InpMinNetRR_LondonBreakout=1.50;
input double InpMinNetRR_NYMomentum=1.50;
input double InpMinNetRR_ComplexMode=1.20;

Recovery:
retain existing InpRecoveryMinRR unless existing logic is stricter.

NET R:R must consider:

expected spread
commission
expected slippage

where possible.

Do not replace existing TP ladder.

The minimum R:R is a quality gate only.

Preserve:

TP1
TP2
TP3
existing ATR targets
liquidity target snapping
SR snapping
structure-aware stops.

======================================================================
17. RISK/REWARD SCORE
=====================

The Confidence Engine allocates 5 points for R:R + cost quality.

Score proportionally.

Example concept:

below setup minimum:
0 and block trade.

minimum achieved:
partial score.

excellent net R:R:
full score.

Also consider:

expected cost / gross target reward.

Do not double-count existing cost gates.

Reuse ExpectedAllInCost and current net-profit viability functions.

======================================================================
18. PRICE ACTION SCORE — 20
===========================

Suggested composition:

HH/HL or LH/LL ........... up to 5
BOS / CHOCH .............. up to 5
Liquidity sweep .......... up to 3
FVG / IFVG / PTB ......... up to 4
S/R structural support ... up to 3

TOTAL:
20.

Do not automatically award all subcomponents.

Directional alignment matters.

For LONG:

bullish structure votes increase long score.

Bearish evidence should:

* score LONG zero for that subcomponent
* and increase SHORT confidence.

Do not use negative scores unless architecture remains clean.

======================================================================
19. TREND SCORE — 15
====================

Suggested:

EMA9/20 .................. 3
EMA20/50 ................. 3
EMA200 bias .............. 3
M5 trend ................. 3
M15/H1 trend/SuperTrend .. 3

TOTAL 15.

Reuse existing HTF EMA information.

Do not create duplicate CopyBuffer calls where values already exist.

======================================================================
20. VOLUME / LIQUIDITY SCORE — 15
=================================

Suggested:

Relative volume .......... 5
Volume percentile ........ 4
Directional spike ........ 3
Liquidity quality ........ 3

TOTAL 15.

Extreme volume in disorder conditions must NOT increase trade confidence.

Environment gate takes precedence.

======================================================================
21. MOMENTUM SCORE — 10
=======================

Suggested:

RSI directional state .... 3
MACD ..................... 4
ADX/DI or displacement ... 3

TOTAL 10.

Do NOT add Rate of Change.

Avoid redundant over-weighting of momentum.

======================================================================
22. VWAP / LOCATION SCORE — 10
==============================

Use:

price vs VWAP
VWAP bands/deviation
setup context
VWAP support/resistance
Bollinger recross where appropriate.

For trend setups:
above VWAP can support long.

For reversion:
extreme deviation and valid recross can support opposite-direction entry.

Make it setup-aware.

======================================================================
23. VOLATILITY SCORE — 10
=========================

Use:

ATR percentile
ATR expansion quality
candle displacement
spread/ATR
HV conditions.

NORMAL favorable:
good score.

HIGH VOLATILITY:
reduced score but may still trade.

EXTREME:
BLOCK.

LOW liquidity:
BLOCK.

Do not reward chaos.

======================================================================
24. MACRO / INTERMARKET SCORE — 10
==================================

Reuse existing:

FMP USD basket
SPX
EURUSD
macro bias.

Do NOT add new external providers.

Directional contribution:

Gold LONG generally supported by:
USD weakness
risk-off where existing logic defines it.

Gold SHORT:
USD strength
risk-on where appropriate.

Respect existing macro architecture.

If unavailable and external data not required:
renormalize confidence.

======================================================================
25. OPTIONAL GOLD OPTIONS/OI MODULE
===================================

Implement the INTERNAL ARCHITECTURE but do NOT introduce a mandatory new live dependency unless an existing external API/provider can supply reliable data.

Add a struct:

struct GoldOptionsSnapshot
{
bool available;
datetime timestamp;

double callOI;
double putOI;
double callOIChange;
double putOIChange;

double pcr;

double impliedVolatility;
double ivPercentile;

double callVolume;
double putVolume;

double nearestCallWall;
double nearestPutWall;

double callWallOI;
double putWallOI;

double gammaWall;
bool gammaAvailable;

string source;
};

Add:

input bool InpUseOptionsContext=false;
input bool InpRequireOptionsData=false;
input int InpOptionsMaxAgeSec=900;

IMPORTANT:

Default:
false.

No new hard-coded API key.

No external dependency should break the EA.

If data is unavailable:

InpRequireOptionsData=false
→ fail open and remove 5-point weight from possible score.

InpRequireOptionsData=true
→ block entry.

Do NOT add:

Theta
Vega

as direct directional score components.

Delta/Gamma can be stored later, but Gamma is only directional/contextual when used meaningfully around major strikes.

======================================================================
26. OPTIONS SCORE — 5
=====================

When available:

PCR directional context
OI change
major call/put walls
IV regime
options volume.

Suggested maximum:
5.

Do not make options dominate the M1 strategy.

Example interpretations:

Large put wall below spot:
possible support context.

Large call wall above:
possible resistance context.

Rising IV:
environment risk / volatility context, not automatically directional.

PCR:
context only, do not use simplistic always-inverse rules.

======================================================================
27. STRIKE-WISE OI ARCHITECTURE
===============================

If implementing future-ready storage:

define a small fixed-size structure:

struct OptionStrikeLevel
{
double strike;
double callOI;
double putOI;
double callVolume;
double putVolume;
};

Keep max count bounded.

Do not dynamically allocate huge option chains every tick.

Do not fetch options chain every tick.

======================================================================
28. ENVIRONMENT RISK MODIFIERS
==============================

Integrate with the EXISTING adaptive risk system.

Do NOT create a second independent lot-sizing engine.

Create only a risk multiplier request.

Example:

double RegimeRiskMultiplier();

NORMAL:
1.00

STRONG directional trend:
1.00

SIDEWAYS:
0.50–0.75

HIGH_VOLATILITY:
reuse existing HV multiplier, do not multiply risk twice.

EXTREME_VOLATILITY:
0 / block.

LOW_LIQUIDITY:
0 / block.

DISORDER:
0 / block.

CRITICAL:

Do not double-reduce risk if the existing High Volatility system already applies:

InpHVExtraSignalRiskMult.

There must be ONE effective HV risk reduction.

Audit and integrate rather than stacking duplicate multipliers.

======================================================================
29. CANENTER / TRYARM INTEGRATION
=================================

Do not rebuild all entry functions.

Integrate the new central decision cleanly.

Recommended flow:

Existing setup detection
→
Build candidate direction
→
Build SignalDecision
→
Determine structure
→
Determine regimes
→
Compute long/short confidence
→
select BUY/SELL/NO_TRADE
→
validate adaptive threshold
→
validate setup-specific R:R
→
existing news/session/disorder/spread/slippage gates
→
existing capital/risk/margin engine
→
order preparation
→
OrderCheck
→
OrderSend.

Avoid evaluating expensive full confidence calculations multiple times per tick.

Cache candidate decision per relevant bar/event.

======================================================================
30. SIMPLE SCALP MODE
=====================

Do NOT disable the existing Simple Scalp engine.

Its existing setups:

VWAP reversion
London breakout
NY momentum
EMA pullback

must remain.

Use the new confidence/regime engine as a FINAL QUALITY / CLASSIFICATION layer.

Do not replace those setups with a generic indicator soup.

Simple mode should remain setup-driven.

======================================================================
31. COMPLEX MODE
================

The full multi-filter engine may transition more directly from:

g_score/g_scoreMax

to:

0–100 ConfidenceBreakdown.

Maintain backward compatibility.

If:

InpUseConfidenceEngine=false

preserve existing filter scoring behavior.

If true:
use new normalized confidence logic.

======================================================================
32. BUY / SELL / NO_TRADE RULES
===============================

LONG generally requires:

valid bullish/setup candidate
AND
environment allowed
AND
confidence >= threshold
AND
confidence gap adequate
AND
setup-specific net R:R met
AND
existing risk availability
AND
existing cost/spread/slippage/margin/news/session protections.

SHORT symmetrical.

NO_TRADE if:

no valid setup
OR
confidence too low
OR
direction ambiguous
OR
SIDEWAYS confidence threshold fails
OR
EXTREME_VOLATILITY
OR
LOW_LIQUIDITY
OR
DISORDER
OR
R:R fails
OR
risk unavailable
OR
broker/execution gate fails.

Do NOT create trades from confidence score alone.

A valid SETUP must still exist.

======================================================================
33. DASHBOARD
=============

Extend the current dashboard without redesigning it.

Add concise fields:

Decision:
BUY / SELL / NO TRADE

Setup:
EMA_PULLBACK
VWAP_REVERSION
LONDON_BREAKOUT
NY_MOMENTUM
COMPLEX
RECOVERY

Confidence:
82.4 / 75.0

Long Confidence:
82.4

Short Confidence:
48.2

Confidence Gap:
34.2

Structure:
HH-HL
LH-LL
RANGE
TRANSITION

Direction Regime:
STRONG BULLISH
BULLISH
SIDEWAYS
BEARISH
STRONG BEARISH

Environment:
NORMAL
HIGH VOL
EXTREME VOL
LOW LIQUIDITY
DISORDER

EMA:
9 / 20 / 50 / 200

MACD:
BULL / BEAR / FLAT

Volume:
NORMAL / ELEVATED / SPIKE / EXTREME

Volume Percentile:
xx

Net R:R:
x.xx

Signal Reasons:
compact top reasons.

Do not make dashboard too large.

Prefer one or two compact rows plus details already available elsewhere.

======================================================================
34. CSV / PERFORMANCE LOGGING
=============================

Append new columns without breaking existing historical field meaning:

SignalDecision
SetupName
Confidence
LongConfidence
ShortConfidence
ConfidenceGap

PriceActionScore
TrendScore
VolumeLiquidityScore
MomentumScore
VWAPScore
VolatilityScore
MacroScore
OptionsScore
RiskRewardScore

StructureState
DirectionRegime
EnvironmentRegime

EMA9
EMA20
EMA50
EMA200

MACDMain
MACDSignal
MACDHist

VolumeRatio
VolumePercentile
VolumeState

ATRPercentile
SpreadPercentile
SpreadToATR

NetRR

OptionsAvailable
PCR
IV
IVPercentile
NearestCallWall
NearestPutWall

SignalReasons
GateReason.

======================================================================
35. PERFORMANCE TRACKING BY CONFIDENCE
======================================

Add bounded performance buckets:

70–74
75–79
80–84
85–89
90+.

Track:

trades
wins
losses
net R
average R
profit factor if practical.

This allows later validation of whether:

75

is actually the right threshold.

Do NOT dynamically self-optimize the live threshold yet.

Telemetry only.

======================================================================
36. PERFORMANCE TRACKING BY SETUP
=================================

Track independent statistics for:

EMA_PULLBACK
VWAP_REVERSION
LONDON_BREAKOUT
NY_MOMENTUM
COMPLEX
RECOVERY.

Track:

trades
wins
losses
net R
avg R
profit factor
MAE
MFE
slippage
spread
confidence.

Do not let these statistics alter the strategy unless existing performance gating already supports it.

======================================================================
37. PERFORMANCE TRACKING BY REGIME
==================================

Track:

STRONG_BULLISH
BULLISH
SIDEWAYS
BEARISH
STRONG_BEARISH

and environment:

NORMAL
HIGH_VOLATILITY.

EXTREME/LOW_LIQ/DISORDER should mostly record rejected candidate counts.

This will permit later evidence-based refinement.

======================================================================
38. CPU / PERFORMANCE
=====================

This is an M1 ultra-scalper.

Do not add expensive calculations every tick unnecessarily.

EMA/MACD:
indicator handles and CopyBuffer.

Structure:
recalculate on new M1 bar or confirmed swing.

Volume percentile:
fixed ring buffer.

Confidence:
only on trade candidate / new relevant event.

Regime:
cached and update once per bar or when extreme conditions change.

Options:
never fetch every tick.

Dashboard:
reuse cached values.

Avoid:

large dynamic arrays
unbounded CopyRates
repeated full-history scans
duplicate S/R calculations.

======================================================================
39. PRICE NORMALIZATION / BROKER SAFETY
=======================================

Do NOT change the completed broker-native capital work.

All final entries/SL/TP/volume must still go through existing:

broker tick-size normalization
volume normalization
risk engine
OrderCalcProfit
OrderCalcMargin
adaptive spread
adaptive slippage
RiskRoom
OrderCheck
OrderSend.

The new confidence engine cannot bypass any execution safeguard.

======================================================================
40. NO OVER-FILTERING
=====================

This is extremely important.

Do NOT implement:

EMA9
EMA20
EMA50
EMA200
VWAP
RSI
MACD
ADX
volume
SMC
options
macro

as ALL-REQUIRED hard gates simultaneously.

That will kill valid M1 signals.

Use the WEIGHTED CONFIDENCE model.

Hard gates should remain limited to:

* valid setup
* environment safety
* confidence threshold
* R:R minimum
* capital/risk
* margin
* spread/slippage
* news/disorder
* broker execution
* session requirements.

Everything else contributes evidence.

======================================================================
41. AVOID DOUBLE COUNTING
=========================

Audit correlated evidence.

Examples:

EMA9/20
EMA20/50
M5 EMA20/50

all represent trend.

Do not award each so heavily that trend dominates the 100-point score.

Similarly:

ATR
ATR percentile
HV state

are related.

Volume ratio
volume percentile

are related.

SMC BOS
HH/HL

are related.

Respect category caps.

No category may exceed its allocated maximum.

======================================================================
42. WEIGHT VALIDATION
=====================

Add initialization validation.

Expected default total:

Price Action = 20
Trend = 15
Volume/Liquidity = 15
Momentum = 10
VWAP = 10
Volatility = 10
Macro = 10
Options = 5
RiskReward = 5

TOTAL:
100.

Prefer defining them as configurable inputs:

InpWeightPriceAction
InpWeightTrend
InpWeightVolumeLiquidity
InpWeightMomentum
InpWeightVWAP
InpWeightVolatility
InpWeightMacro
InpWeightOptions
InpWeightRiskReward.

At initialization:

sum weights.

If sum <= 0:
disable confidence engine safely.

If sum != 100:
NORMALIZE internally rather than fail the EA.

Log:

CONFIDENCE_WEIGHTS_NORMALIZED.

======================================================================
43. SIGNAL CONFLICT HANDLING
============================

Example:

Price Action LONG = strong
Trend LONG = strong
MACD LONG = strong

but:

major resistance immediately overhead
poor R:R
spread poor.

Result:
NO_TRADE.

Confidence cannot override R:R/execution safety.

Another example:

LONG confidence 79
SHORT confidence 78.

Result:
NO_TRADE due insufficient directional separation.

Another:

LONG=88
SHORT=40
HIGH_VOLATILITY
threshold=80
risk reduced
R:R pass.

Result:
BUY allowed subject to all existing gates.

======================================================================
44. EXTREME VOLATILITY CLASSIFICATION
=====================================

Build on existing disorder/HV logic.

Possible ingredients:

ATR percentile >= high extreme threshold
AND/OR
candle displacement extreme
AND/OR
spread percentile extreme
AND/OR
volume extreme
AND/OR
slippage abnormal.

Do not trigger EXTREME based on one mild indicator.

Expose:

input double InpExtremeATRPercentile=97.0;
input double InpExtremeVolumePercentile=97.0;
input double InpExtremeDisplacementATR=2.8;

Reuse existing disorder spread/slippage inputs.

If EXTREME:
block NEW entries.

Do not automatically flatten positions unless existing breaker logic says so.

======================================================================
45. LOW LIQUIDITY CLASSIFICATION
================================

Use combination of:

very low relative volume
very low volume percentile
poor liquidity ratio
potentially abnormally wide spread.

Do not classify an ordinary quiet minute as permanently low liquidity.

Use persistence / multi-condition confirmation.

Example:

InpLowLiquidityConfirmBars=2.

Block new entries while confirmed.

Do not disable session permanently.

======================================================================
46. SIDEWAYS CLASSIFICATION
===========================

Use evidence such as:

ADX low
EMA20/50 flat / closely compressed
lack of HH/HL or LH/LL
frequent VWAP crossing
low directional structure confidence.

SIDEWAYS is not necessarily complete NO_TRADE.

Mean-reversion setups may still be valid.

Trend-following/breakout setups require higher confidence.

Use setup-aware behavior.

======================================================================
47. STRONG BULLISH / STRONG BEARISH
===================================

Do not classify only from EMA stacking.

STRONG BULLISH should require a combination such as:

HH/HL
bullish BOS
EMA alignment
price above EMA200
M5 trend up
ADX/DI confirmation
VWAP support
volume acceptable.

STRONG BEARISH symmetrical.

Use a directional regime score internally rather than a single rule.

======================================================================
48. OPTIONS FAIL-OPEN
=====================

The options module must NEVER make the base EA nonfunctional by default.

Default:

InpUseOptionsContext=false.

When enabled but stale/unavailable:

if InpRequireOptionsData=false:
remove its 5 points from possible score.

Never fabricate options values.

Never use stale snapshot past:

InpOptionsMaxAgeSec.

======================================================================
49. DO NOT ADD NEW NETWORK DEPENDENCY UNLESS ALREADY AVAILABLE
==============================================================

Do not automatically integrate:

Polygon
Tradier
CBOE paid endpoints
IBKR
third-party DLLs

during this task.

Create the architecture/hooks only.

If an existing FMP endpoint can provide reliable Gold Futures/options data already supported by the project, it may be integrated carefully.

Otherwise:
options data stays optional placeholder interface with unavailable status.

Do not hardcode credentials.

======================================================================
50. COMPILATION / FULL AUDIT
============================

After implementing:

Re-read the complete file.

Search for:

EMA9
EMA200
MACD
StructureState
DirectionRegime
EnvironmentRegime
VolumePercentile
ConfidenceBreakdown
SignalDecision
InpMinConfidenceScore
BuildSignalDecision
NetRR.

Verify every function is actually called.

Check:

indicator handles
INVALID_HANDLE
CopyBuffer return counts
array bounds
division by zero
enum bounds
string sizes
performance loops
dashboard fields
CSV argument count
persistence implications
netting/hedging behavior
simple mode
complex mode
recovery mode.

If MetaEditor compiler is available:

COMPILE.

Fix all errors.

Target:
0 errors.

Fix warnings where reasonably possible.

If compiler is unavailable:
perform static syntax/type/call-site audit.

Do NOT falsely claim compilation.

======================================================================
51. FINAL REGRESSION CHECKLIST
==============================

Before completing verify:

[ ] Capital profile engine unchanged.
[ ] Auto risk sizing unchanged.
[ ] OrderCalcProfit logic unchanged except required integration.
[ ] OrderCalcMargin unchanged.
[ ] OrderCheck unchanged.
[ ] Adaptive spread/slippage unchanged.
[ ] Sydney works.
[ ] Tokyo works.
[ ] London works.
[ ] New York works.
[ ] Overlaps work.
[ ] HV engine works.
[ ] SMC works.
[ ] FVG works.
[ ] IFVG works.
[ ] PTB works.
[ ] SR works.
[ ] VWAP works.
[ ] Bollinger existing logic retained.
[ ] EMA20/50 retained.
[ ] EMA9 added.
[ ] EMA200 added.
[ ] MACD truly implemented.
[ ] HH/HL/LH/LL explicitly classified.
[ ] Volume percentile implemented.
[ ] Volume spike state implemented.
[ ] Direction regime implemented.
[ ] Environment regime implemented.
[ ] Confidence score 0-100 implemented.
[ ] Threshold configurable.
[ ] Missing data renormalization implemented.
[ ] BUY/SELL/NO_TRADE centralized.
[ ] Direction confidence gap implemented.
[ ] Setup-specific R:R implemented.
[ ] Universal 1:3 rule NOT introduced.
[ ] Options context optional/fail-open.
[ ] No ROC added.
[ ] No duplicate Bollinger added.
[ ] No mandatory Theta/Vega added.
[ ] No new martingale.
[ ] No averaging down.
[ ] No risk-control bypass.
[ ] Dashboard updated.
[ ] CSV updated.
[ ] Performance buckets added.
[ ] Existing strategy still trades rather than being over-filtered.

======================================================================
52. FINAL OUTPUT FROM CODEX
===========================

Modify the EXISTING Predict-A-Trade-Ultra.mq5 directly.

Do NOT return only a patch.

Do NOT return pseudo-code.

Do NOT create a replacement simplified EA.

After modification provide a concise report:

A. File modified

B. New functions added

C. New enums/structs

D. New inputs

E. HH/HL/LH/LL implementation

F. EMA9/EMA200 integration

G. MACD integration

H. Volume percentile/spike engine

I. Direction regime logic

J. Environment regime logic

K. Confidence 0-100 architecture

L. BUY/SELL/NO_TRADE decision flow

M. Setup-specific R:R values

N. Options/OI architecture status

O. Dashboard additions

P. CSV additions

Q. Compilation result

R. Regression confirmation that existing capital/risk/broker/session/SMC systems remain intact.

======================================================================
FINAL DESIGN PRINCIPLE
======================

The EA must remain SETUP-DRIVEN.

Indicators provide CONFLUENCE.

They do NOT independently manufacture trades.

The desired flow is:

MARKET DATA
↓
PRICE ACTION / SMC
↓
SETUP DETECTION
↓
DIRECTION REGIME
↓
ENVIRONMENT REGIME
↓
TREND / MOMENTUM / VOLUME / VWAP / MACRO / OPTIONAL OPTIONS
↓
LONG CONFIDENCE
↓
SHORT CONFIDENCE
↓
BUY / SELL / NO_TRADE
↓
SETUP-SPECIFIC NET R:R
↓
EXISTING SPREAD / SLIPPAGE / NEWS / DISORDER / SESSION GATES
↓
EXISTING CAPITAL / RISK / MARGIN ENGINE
↓
OrderCheck
↓
OrderSend.

CONFIDENCE >= 75 is NOT sufficient by itself.

A VALID SETUP must exist.

EXTREME VOLATILITY:
NO TRADE.

LOW LIQUIDITY:
NO TRADE.

DISORDER:
NO TRADE.

HIGH VOLATILITY:
higher confidence + reduced existing HV risk.

SIDEWAYS:
higher confidence for trend setups, but valid mean-reversion setups remain possible.

DO NOT use universal 1:3 R:R.

DO NOT duplicate existing features.

DO NOT weaken anything already implemented.

Apply all pending upgrades directly to the current production MQL5.
