You are modifying my EXISTING production MQL5 Expert Advisor:

Predict-A-Trade-Ultra.mq5

DO NOT rebuild the EA from scratch.

DO NOT replace it with a new/simple EA.

DO NOT copy generic MQL4/MQL5 percentage-TP examples into this EA.

Perform an IN-PLACE, SURGICAL, PRODUCTION-GRADE upgrade of the existing file.

======================================================================
0. REFERENCE HIERARCHY — MANDATORY
==================================

Use the following hierarchy when making decisions:

REFERENCE 1 — PRIMARY / AUTHORITATIVE:
The EXISTING Predict-A-Trade-Ultra.mq5 source.

Its existing strategy logic, architecture, broker telemetry, risk controls, session engine, dashboard, logging, licensing, SMC, SR, execution protections and existing working behavior are the primary source of truth.

REFERENCE 2 — SECONDARY DESIGN REFERENCE:
"Predict-A-Trade-Ultra.mq5 — Percentage & Multi-Account Compatibility Audit"

Use it to identify fixed-value/account-scaling problems, but DO NOT blindly copy its proposed formulas/defaults.

Specifically DO NOT blindly adopt:

* increased risk simply to force small accounts to trade;
* 3% minimum-lot risk for Micro accounts;
* manual margin formula contract × price / leverage as primary calculation;
* commission as percentage of XAUUSD notional;
* balance-percentage TP price targeting;
* fixed-lot scaling tables.

REFERENCE 3 — MQL5 NATIVE API / PLATFORM BEHAVIOR:
For monetary P/L, margin and request validation, use native MQL5 APIs as authoritative:

OrderCalcProfit()
OrderCalcMargin()
OrderCheck()

Use actual SymbolInfo*/AccountInfo* broker/account specifications.

Do NOT recreate broker margin/P&L formulas manually when native MQL5 can calculate them.

======================================================================

1. CORE MISSION
   ======================================================================

Upgrade ONLY the:

CAPITAL
RISK
POSITION SIZING
BROKER NORMALIZATION
COST
MARGIN
SPREAD
SLIPPAGE
PRE-TRADE VALIDATION
PERFORMANCE NORMALIZATION

layers.

The same EA must safely adapt to:

$50-$500
$500-$5,000
$5,000+
$10,000+
$50,000+
$100,000+

and different:

brokers
account currencies
leverage levels
XAUUSD contract sizes
tick sizes
tick values
digits
points
minimum volumes
maximum volumes
volume steps
volume limits
stop levels
freeze levels
spreads
commissions
slippage profiles
hedging accounts
netting accounts.

THE DESIGN PRINCIPLE IS:

CAPITAL %
→
REAL RISK MONEY
→
REAL BROKER LOSS AT SL
→
EXECUTION COST
→
BROKER-VALID VOLUME
→
MARGIN VALIDATION
→
ORDERCHECK
→
ORDERSEND.

DO NOT use:

ACCOUNT SIZE → FIXED LOT SIZE TABLE.

======================================================================
2. ABSOLUTELY PRESERVE EXISTING EA FUNCTIONALITY
================================================

Do NOT remove, weaken, bypass or rewrite unrelated logic including:

Sydney
Tokyo
London
New York
Sydney/Tokyo overlap
Tokyo/London overlap
London open
London/New York overlap
New York open
verified expansion windows
broker-server-time synchronization
UTC/DST handling
High Volatility engine
SMC
BOS
CHOCH
liquidity sweeps
FVG
IFVG
PTB
VWAP
EMA
SuperTrend
ADX
ATR
RSI
volume filtering
liquidity filtering
support/resistance zones
macro/FMP
EURUSD
news protection
market disorder protection
swap protection
TP1/TP2/TP3
cost-adjusted break-even
trailing
recovery/reversal
no martingale
no averaging down
daily loss protection
weekly loss protection
monthly loss protection
floating drawdown protection
aggregate risk protection
directional risk protection
per-window risk protection
performance statistics
license system
mobile commands
persistence
CSV logging
dashboard
existing filling-mode handling
stop/freeze-level enforcement
existing trade-state management.

Signal generation is NOT the target of this upgrade.

======================================================================
3. FIRST PERFORM A FULL DEPENDENCY AUDIT
========================================

Before editing, search the ENTIRE source for every use of:

InpRiskPercent
0.35
InpLotSize
InpMaxTotalLots
InpMinLotMaxRiskPct
InpMinNetProfitTP1Money
InpMinNetProfitTP2Money
InpMinNetProfitTP3Money
InpDisableExpectancyMoney
InpRiskReduceExpectancyMoney
InpMaxSpreadPoints
InpMaxSlippagePoints
InpMaxAverageSlippagePoints
InpExtremeSlippagePoints
InpRecoveryMaxSpreadPts
InpCommissionPerLotRTFallback
ACCOUNT_BALANCE
ACCOUNT_EQUITY
ACCOUNT_MARGIN
ACCOUNT_MARGIN_FREE
SYMBOL_VOLUME_MIN
SYMBOL_VOLUME_MAX
SYMBOL_VOLUME_STEP
SYMBOL_VOLUME_LIMIT
SYMBOL_TRADE_TICK_SIZE
SYMBOL_TRADE_TICK_VALUE
SYMBOL_TRADE_CONTRACT_SIZE
g_ptScale
PriceMoveMoney
ExpectedAllInCost
CurrentRiskPct
CalculateLot
RiskRoom
NetProfitValid
WindowExpectancy
WindowAvgR
RefreshWindowGating
WindowRiskMultiplier
TryArm
TryRecovery
MarketOrder
PlaceStop
SendOrder
ClosePartialSafe
ProcessMobileCommands
PAT_RISK_OVERRIDE.

Classify every fixed value as:

A. CAPITAL-DEPENDENT
B. BROKER/EXECUTION-DEPENDENT
C. MARKET/VOLATILITY-DEPENDENT
D. STRATEGY CONSTANT
E. DISPLAY/TELEMETRY ONLY.

Only convert category A to capital percentage/R-based logic.

Do NOT blindly turn every number into a percentage.

======================================================================
4. CAPITAL PROFILE ENGINE
=========================

Add:

enum ENUM_CAPITAL_PROFILE
{
CAPITAL_MICRO=0,
CAPITAL_STANDARD=1,
CAPITAL_PRO=2
};

Use USD-EQUIVALENT EQUITY ONLY for determining the profile.

Profile boundaries:

MICRO:
$50 <= equityUSD < $500

STANDARD:
$500 <= equityUSD < $5,000

PRO:
equityUSD >= $5,000.

Default profile parameters:

MICRO:
Base trade risk = 0.25%
Aggregate open risk = 0.75%
Directional open risk = 0.50%
Per-window risk budget = 0.50%
Maximum strategy positions = 1
Minimum-lot exception ceiling = 1.00%

STANDARD:
Base trade risk = 0.35%
Aggregate open risk = 1.50%
Directional open risk = 1.00%
Per-window risk budget = 0.75%
Maximum strategy positions = 2
Minimum-lot exception ceiling = 0.75%

PRO:
Base trade risk = 0.35%
Aggregate open risk = 2.50%
Directional open risk = 1.50%
Per-window risk budget = 1.50%
Maximum strategy positions = 3
Minimum-lot exception ceiling = 0.50%.

IMPORTANT:

A larger account should scale through VOLUME.

Do NOT automatically increase its percentage risk.

A Micro account must NOT receive a larger normal risk percentage merely because its minimum lot is inconvenient.

Add:

input bool InpAutoCapitalProfile=true;

When false, retain existing manual risk controls.

Centralize profile access:

ENUM_CAPITAL_PROFILE GetCapitalProfile();
string CapitalProfileName(...);
double GetProfileBaseRiskPct();
double GetProfileAggregateRiskPct();
double GetProfileDirectionalRiskPct();
double GetProfileWindowRiskPct();
double GetProfileMinLotRiskCeilingPct();
int GetProfileMaxPositions();

Do not scatter tier if-statements throughout the EA.

======================================================================
5. ACCOUNT-CURRENCY AND USD PROFILE CONVERSION
==============================================

Risk money itself must remain in ACCOUNT CURRENCY because native:

OrderCalcProfit()
OrderCalcMargin()

return calculations appropriate for the current account.

USD conversion is needed only for CAPITAL PROFILE classification and display.

Implement:

double GetEquityUSD();
double GetAccountCurrencyToUSD();

If ACCOUNT_CURRENCY == "USD":
conversion = 1.

Otherwise:

discover a broker FX symbol capable of converting account currency to USD.

Support:
BASEUSD
USDBASE
broker suffix/prefix variants.

Use existing broker Market Watch symbols where practical.

Cache the conversion symbol/rate.

Do not perform full symbol scans on every tick.

Refresh periodically.

If reliable conversion cannot be obtained:

DO NOT invent a conversion rate.

Use the MOST CONSERVATIVE profile temporarily:

CAPITAL_MICRO

and set telemetry:

CAPITAL_USD_CONVERSION_UNAVAILABLE

or

CAPITAL_PROFILE_CONSERVATIVE_FALLBACK.

Trading may continue only under conservative limits if all other risk calculations are valid.

======================================================================
6. CONSERVATIVE CAPITAL BASE
============================

For NEW trade sizing use:

balance = ACCOUNT_BALANCE
equity = ACCOUNT_EQUITY

capitalBase =
MathMin(balance,equity).

Do not size new trades from balance alone.

Do not size new trades upward using floating profit.

If floating loss lowers equity, new risk money must automatically decrease.

Implement:

double GetConservativeCapitalBase();

Risk budget:

riskBudgetMoney =
capitalBase * effectiveRiskPct / 100.0.

======================================================================
7. REMOVE HARDCODED SIMPLE-SCALP 0.35%
======================================

The existing source currently has Simple Scalp risk effectively hardcoded separately from the main risk input.

Remove that divergence.

There must be ONE authoritative risk resolver:

double GetEffectiveTradeRiskPct(
ENUM_WINDOW_ID window,
bool highVolatility
);

Required order:

profile base risk
→
optional validated manual/mobile request
→
drawdown reduction
→
consecutive-loss reduction
→
window-performance multiplier
→
HV multiplier
→
profile hard ceiling
→
final effective risk.

Do NOT allow Simple Scalp Mode to bypass this resolver.

Do NOT allow Complex Mode to use a separate sizing architecture.

======================================================================
8. CONSECUTIVE LOSS / DRAWDOWN MODIFIERS
========================================

Preserve current consecutive-loss risk decay.

Preserve current drawdown risk reduction.

Preserve no-martingale and no-averaging-down behavior.

Review the current universal 0.10% risk floor.

The floor must NEVER cause risk to increase after modifiers.

Use logic equivalent to:

finalRisk =
MathMin(baseAllowedRisk,
modifiedRisk);

Any floor must be bounded by the current profile's safe base risk and must not undo drawdown/loss reductions.

A risk modifier should never turn a reduced-risk situation into a larger-risk situation.

======================================================================
9. MOBILE RISK OVERRIDE — FIX AND INTEGRATE
===========================================

The current EA accepts a mobile command of the form:

RISK_x

and writes:

PAT_RISK_OVERRIDE.

Audit whether this Global Variable is actually read by the risk engine.

If it is currently only written and not consumed, fix this.

Treat mobile risk as a REQUEST, not permission to bypass safety.

Example:

requestedRisk =
mobile override.

final permitted risk =
MIN(
requestedRisk,
profile base-risk ceiling,
drawdown-adjusted ceiling,
loss-adjusted ceiling,
remaining aggregate capacity,
remaining directional capacity,
remaining window capacity
).

Do not allow the existing possible 5% command range to create 5% live risk.

If a request is clamped, log:

RISK_OVERRIDE_CLAMPED
requested
accepted.

Provide a way for the existing mobile/control architecture to clear the override if one already exists or add a safe clear behavior without breaking compatibility.

======================================================================
10. FIX UNDERWATER-POSITION CLAMP
=================================

The existing underwater-position protection currently references the legacy base risk.

Make it reference the dynamically resolved profile base risk.

If ANY own position is underwater:

a new trade must never size above the normally permitted base risk.

No martingale.

No loss-based size increase.

No recovery size escalation.

======================================================================
11. AUTO RISK SIZING
====================

Add:

input bool InpAutoRiskSizing=true;

When true:

InpLotSize must NOT control normal position sizing.

Do not fall back to arbitrary 0.05 lots when sizing fails.

InpLotSize may remain only for:

manual/debug/legacy mode when InpAutoRiskSizing=false.

When Auto mode cannot derive safe volume:

BLOCK THE TRADE.

Do not manufacture a volume.

======================================================================
12. REMOVE FIXED 1.20 LOT BOTTLENECK
====================================

The existing:

InpMaxTotalLots

must NOT limit production auto-sizing by default.

Do not delete it if backward compatibility with .set files matters.

Add:

input bool InpUseAbsoluteLotEmergencyCap=false;
input double InpEmergencyMaxTotalLots=0.0;

When AutoRiskSizing=true and emergency cap=false:

do not apply the old fixed lot limit.

The effective lot limit must instead come from:

risk budget
aggregate risk
directional risk
window risk
margin
SYMBOL_VOLUME_MAX
SYMBOL_VOLUME_LIMIT
free margin
broker validation.

A $50,000 account must not be restricted simply because the legacy setting says 1.20 lots.

======================================================================
13. EXTEND BROKER PROFILE
=========================

Retain all existing BrokerProfile data.

Where useful add/cache:

SYMBOL_TRADE_TICK_VALUE_PROFIT
SYMBOL_TRADE_TICK_VALUE_LOSS
SYMBOL_VOLUME_LIMIT
SYMBOL_TRADE_CALC_MODE.

Do NOT assume:

SYMBOL_TRADE_TICK_VALUE

is identical under all profit/loss situations.

Use the richer values as fallback telemetry.

Native OrderCalcProfit remains primary for risk calculation.

======================================================================
14. ORDERCALCPROFIT — AUTHORITATIVE SL RISK
===========================================

Add a helper:

bool CalcBrokerPnL(
int direction,
double volume,
double openPrice,
double closePrice,
double &pnl
);

For BUY:
ORDER_TYPE_BUY.

For SELL:
ORDER_TYPE_SELL.

Use:

OrderCalcProfit()

as primary.

To estimate SL loss:

lossAtSL =
MathAbs(calculatedPnL).

This value is already in account currency.

If OrderCalcProfit fails:

fallback using the existing tick-size/tick-value/PriceMoveMoney architecture.

Prefer SYMBOL_TRADE_TICK_VALUE_LOSS for a loss calculation if valid.

Log fallback use.

Do not silently assume zero risk.

======================================================================
15. COST MODEL — KEEP ONE SOURCE OF TRUTH
=========================================

The EA already has:

LearnCommission()
CommissionRT()
ExpectedSlippagePoints()
ExpectedAllInCost().

Preserve the centralized design.

The current EA learns actual commission from:

DEAL_COMMISSION / DEAL_VOLUME

and maintains learned round-trip commission per lot.

KEEP THIS.

Do NOT replace commission fallback with percentage of XAUUSD notional.

Commission is broker/execution-dependent, not account-size-dependent.

Priority:

1. sufficiently learned actual commission
2. configured account-currency-per-lot fallback.

Keep:

InpCommissionPerLotRTFallback

or a backwards-compatible equivalent.

Document clearly:

fallback is ACCOUNT-CURRENCY round-trip commission per 1.0 lot.

Do not treat $7 as universal USD if account currency differs.

Do not double count entry/exit commission.

======================================================================
16. REAL TRADE RISK MONEY
=========================

Create ONE authoritative method such as:

double CalculateRealTradeRiskMoney(
int direction,
double volume,
double entry,
double stopLoss
);

It must combine:

broker-calculated SL loss
+
expected all-in execution costs

using a single consistent cost basis.

Audit ExpectedAllInCost carefully.

Avoid:

spread counted once in OrderCalcProfit and again incorrectly;
commission counted twice;
slippage counted twice.

Document what each component includes.

Use the exact same basis for:

CalculateLot
RiskRoom new-risk request
initialRiskMoney
R calculation
TP viability.

======================================================================
17. REBUILD CALCULATELOT AS AN ITERATIVE SAFE SOLVER
====================================================

CalculateLot must become broker-native.

Required process:

1. resolve effective risk %
2. obtain capitalBase
3. calculate allowed riskMoney
4. obtain exact planned entry
5. obtain exact planned SL
6. calculate risk per 1.0 lot
7. derive raw lots
8. FLOOR to SYMBOL_VOLUME_STEP
9. enforce SYMBOL_VOLUME_MIN
10. enforce SYMBOL_VOLUME_MAX
11. enforce SYMBOL_VOLUME_LIMIT
12. recalculate REAL risk at normalized volume
13. verify actual risk <= allowed risk
14. verify aggregate risk
15. verify directional risk
16. verify window risk
17. verify margin
18. verify broker request
19. return approved volume.

Volume normalization MUST round DOWN.

Never round upward beyond the permitted risk.

If a normalized volume is too large:

reduce by one volume step
and recalculate.

Use bounded loops.

Do not create unbounded iterations.

======================================================================
18. MINIMUM LOT FEASIBILITY
===========================

Preserve the useful concept of minimum-lot fallback, but make it fully broker-native.

If calculated lots < SYMBOL_VOLUME_MIN:

calculate actual minimum-volume risk using:

OrderCalcProfit at the proposed SL
+
expected execution costs.

Then:

minLotRiskPct =
minimumLotRiskMoney /
capitalBase *
100.

Maximum exception ceilings:

MICRO = 1.00%
STANDARD = 0.75%
PRO = 0.50%.

These are HARD exception ceilings.

They are NOT target risk percentages.

If minimum volume exceeds the ceiling:

DO NOT TRADE.

Gate:

MIN_LOT_RISK_TOO_HIGH.

Log:

profile
balance
equity
capitalBase
equityUSD
symbol
contractSize
tickSize
tickValue
volumeMin
volumeStep
SL distance
minimum lot risk money
minimum lot risk %
profile exception limit
required margin.

IMPORTANT:

Do not attempt to guarantee a $50 account can trade.

If 0.01 XAUUSD risks 4-8% of a $50 account:

BLOCK IT.

The correct solution is a broker offering:

0.001 volume
smaller contract
micro/cent gold specification.

Never weaken risk limits to force execution.

======================================================================
19. RISKROOM MUST USE PROFILE LIMITS
====================================

Preserve RiskRoom's current percentage architecture.

When InpAutoCapitalProfile=true use:

GetProfileAggregateRiskPct()
GetProfileDirectionalRiskPct()
GetProfileWindowRiskPct().

When false, use existing manual inputs.

Do not weaken:

InpDailyLossPercent
InpMaxFloatingDDPercent
InpWeeklyLossLimit
InpMonthlyLossLimit.

These remain hard protection limits unless existing behavior is more conservative.

======================================================================
20. OPEN RISK CALCULATION
=========================

Audit OpenRiskMoney().

Where possible compute each open position's SL risk using broker-native P/L estimation rather than only raw tick multiplication.

For an existing position:

use its actual open price
current SL
current volume.

If a position has no SL:

do NOT treat its risk as zero.

Use a conservative policy:

* treat it as maximum/unbounded risk for gating,
  OR
* use a configured catastrophe fallback,
  consistent with existing safety philosophy.

Do not permit missing-SL positions to create false available aggregate-risk room.

======================================================================
21. DYNAMIC MAX POSITIONS
=========================

When AutoCapitalProfile=true:

MICRO = 1
STANDARD = 2
PRO = 3.

But this is NOT permission to open that many.

All other constraints take precedence:

netting restriction
aggregate risk
directional risk
window risk
margin
spread
slippage
news
disorder
session logic.

For netting accounts preserve the existing strategy restriction.

======================================================================
22. NATIVE MARGIN CALCULATION
=============================

Add:

input bool InpUseAdaptiveMarginProtection=true;
input double InpMaxNewTradeMarginPct=20.0;
input double InpMinFreeMarginReservePct=50.0;

DO NOT use:

contract × price / leverage

as the primary margin formula.

Use:

OrderCalcMargin()

with actual:

request order type
symbol
volume
planned price.

OrderCalcMargin returns margin in account currency.

Use its value.

Important:

OrderCalcMargin estimates the proposed operation separately and does not represent total account margin after all positions.

Therefore combine it with:

ACCOUNT_MARGIN
ACCOUNT_MARGIN_FREE
ACCOUNT_EQUITY

and later OrderCheck result.

Calculate:

projectedFreeMargin =
freeMarginBefore - requiredMargin

and appropriate projected margin usage.

If volume violates margin protection:

decrease one volume step and retest.

If safe volume falls below minimum:

reject.

Gate:

MARGIN_CAP
or
MARGIN_INSUFFICIENT.

======================================================================
23. ORDERCHECK BEFORE NEW ORDERS
================================

Add a dedicated:

bool PreflightNewTrade(
MqlTradeRequest &request,
MqlTradeCheckResult &check,
string &reason
);

Call it before EVERY NEW:

market entry
pending entry
recovery entry.

Do NOT blindly place OrderCheck inside SendOrder for:

position modifications
SL/TP modifications
order deletion

unless appropriate.

Preflight NEW trade requests only.

Order:

construct final MqlTradeRequest
→
OrderCalcMargin validation
→
risk validation
→
OrderCheck
→
OrderSend.

Analyze:

check.retcode
check.comment
check.balance
check.equity
check.margin
check.margin_free
check.margin_level.

A successful OrderCheck does NOT guarantee eventual OrderSend success, so retain existing OrderSend retcode handling and retries.

For invalid price/stops:

do not blindly retry identical bad data.

======================================================================
24. TP1/TP2/TP3 — DO NOT TARGET BALANCE %
=========================================

CRITICAL:

Do NOT change TP PRICE calculation into:

"make 0.8% of account balance".

Do NOT copy the generic percentage-TP EA approach.

Existing TP prices should remain based on:

ATR
market structure
VWAP
S/R
liquidity
existing TP ladder rules
R:R validation.

Only replace the FIXED MONEY MINIMUM PROFIT GATES:

InpMinNetProfitTP1Money
InpMinNetProfitTP2Money
InpMinNetProfitTP3Money.

Add Auto-mode risk-relative thresholds:

input bool InpUseRiskRelativeNetProfitGate=true;

input double InpMinTP1NetRiskPct=10.0;
input double InpMinTP2NetRiskPct=20.0;
input double InpMinTP3NetRiskPct=30.0;

These mean percentage of INITIAL TRADE RISK MONEY.

Example:

initialRiskMoney = 10 account-currency units.

TP1 minimum net =
1.0 if threshold 10%.

Do not change the actual ATR/structure TP solely to meet arbitrary balance profit.

Use this only as a VIABILITY gate.

Create:

double MinNetProfitForLeg(
int leg,
double initialRiskMoney
);

Refactor NetProfitValid to accept/use initialRiskMoney or an equivalent trade-plan risk value.

Retain legacy money inputs for compatibility when the new gate is disabled.

======================================================================
25. R-BASED PERFORMANCE GATING
==============================

Do NOT convert performance expectancy to percentage of account balance.

Use R.

The EA already computes:

R =
net /
initialRiskMoney.

Build on this.

The existing WindowStats currently keeps recent net-money history.

Add a rolling RECENT R history, for example:

double recentR[64];
int recentRCount;
int recentRIdx;

or safely evolve the existing WindowStats structure.

Add:

void PushRecentR(...);
double WindowExpectancyR(...);

Suggested defaults:

input bool InpUseRExpectancyGating=true;
input double InpDisableExpectancyR=-0.10;
input double InpRiskReduceExpectancyR=0.05;

When R gating is enabled:

RefreshWindowGating()
and
WindowRiskMultiplier()

must use R expectancy, not fixed account-currency money.

Preserve:

InpNeverDisablePrimarySessions.

Sydney
Tokyo
London
New York

must remain eligible if that existing setting requires it.

A weak primary session may receive reduced risk.

Do not remove the session.

Retain money expectancy values only as legacy telemetry/backward-compatible manual mode.

======================================================================
26. ADAPTIVE SPREAD ENGINE
==========================

The EA already maintains:

g_spreadBuf
g_spreadCnt
g_spreadAvg
g_spreadStd
SpreadPercentile().

USE THEM.

Do not duplicate the same statistics.

Do NOT simply calculate:

Max(fixed 35 points, learned wide spread).

That can normalize a chronically poor broker into accepting dangerous costs.

Create a multi-condition relative gate.

Add parameters similar to:

input bool InpUseAdaptiveSpreadGate=true;
input double InpMaxSpreadToATRPct=20.0;
input double InpMaxSpreadPercentileAdaptive=90.0;
input double InpSpreadBaselineMultiplier=2.0;
input int InpSpreadWarmupSamples=30;

Calculate:

spreadPrice =
SpreadPoints() * broker.point.

spreadToATRPct =
spreadPrice / g_atr * 100.

Use existing rolling spread baseline/statistics.

Normal entry requires, after warmup:

spread percentile acceptable
AND
spread/ATR acceptable
AND
spread spike ratio acceptable.

During warmup:

use existing normalized fixed fallback.

Keep an emergency absolute sanity limit, but it should be a LAST-RESORT safety cap rather than the primary broker model.

Do not permit a broker's gradually worsening spread forever just because the rolling average also becomes worse.

Consider using both:

short rolling baseline
and
existing configured fallback/sanity constraints.

======================================================================
27. ADAPTIVE SLIPPAGE
=====================

The EA already stores recent slippage:

g_slipBuf
g_slipCnt
g_slipAvg
g_lastSlipPts.

Preserve this.

Extend it only where necessary to derive:

percentile
high percentile
optional standard deviation.

Create:

int AdaptiveDeviationPoints();

Requirements:

warmup → existing fallback
mature data → learned execution profile
respect broker point/digits
consider slippage/ATR
bounded minimum
bounded maximum.

Do not make deviation unlimited.

The existing:

InpExtremeSlippagePoints

can remain an emergency/pathological fallback but must be normalized consistently.

Use adaptive deviation in NEW entry requests instead of blindly:

rq.deviation = InpMaxSlippagePoints.

Apply carefully to closing operations:

do not make emergency closes impossible because an adaptive entry deviation became too restrictive.

Entry execution quality and emergency position closing may need separate logic.

======================================================================
28. RECOVERY SPREAD / RISK
==========================

Preserve the recovery architecture.

Do not add martingale.

Do not enlarge recovery risk.

Recovery risk must be:

<= existing InpRecoveryRiskPct
AND
< normal permitted trade risk.

Make recovery spread validation use a STRICTER version of the normal adaptive spread gate.

Example:

input double InpRecoverySpreadQualityMultiplier=0.80;

Recovery should require better-than-normal execution conditions.

Preserve:

RecoveryMaxLegs
RecoveryCooldown
RecoveryMaxAge
RecoveryMinRR.

======================================================================
29. ATR MIN/MAX — DO NOT CONFUSE WITH CAPITAL %
===============================================

ATR is a MARKET variable.

Do not convert ATR to account-balance percentage.

The existing absolute-point ATR boundaries may be enhanced for broker normalization, but keep market-volatility semantics.

Prefer:

ATR percentile
ATR relative to rolling ATR distribution
price distance
broker tick-size normalization

rather than capital percentage.

Do not blindly copy an AverageATR helper if it does not exist.

Reuse the EA's existing ATR ring buffer and ATR percentile architecture.

======================================================================
30. POINT / PRICE NORMALIZATION AUDIT
=====================================

The EA currently has g_ptScale for 2/3-digit gold feeds.

Keep backward compatibility but centralize conversion helpers:

double PointsToPrice(double points);
double PriceToPoints(double distance);
double NormalizePriceToTick(double price);
double NormalizePrice(double price);

Where appropriate normalize price to:

SYMBOL_TRADE_TICK_SIZE

not merely decimal Digits.

Audit every execution-related point input for consistent behavior:

spread
slippage
stop buffer
recovery spread
SR front-run points
minimum trade distance
pending distances.

Do not modify true ATR ratios.

======================================================================
31. SYMBOL VOLUME LIMIT
=======================

Use:

SYMBOL_VOLUME_LIMIT

when available.

This is distinct from:

SYMBOL_VOLUME_MAX.

Ensure own open + pending volume in the SAME direction does not violate the broker symbol's directional volume limit.

Retain existing strategy-specific aggregate and directional risk caps in addition to the broker's volume limit.

======================================================================
32. ORDER REQUEST VOLUME RECHECK
================================

Immediately before dispatching a new request:

re-read or validate:

SYMBOL_VOLUME_MIN
SYMBOL_VOLUME_MAX
SYMBOL_VOLUME_STEP
SYMBOL_VOLUME_LIMIT

if cached broker metadata could be stale.

Do not assume specifications can never change during a long terminal session.

Use a low-cost refresh strategy rather than per-tick heavy querying.

======================================================================
33. FIXED LOT / MONEY SEARCH
============================

After implementing the new engine, search the full source again for:

0.05
1.20
0.30
0.50
0.70
-0.20
0.10
0.35

Do NOT blindly remove them.

For every match determine whether it is:

legacy input
strategy constant
percentage
ATR ratio
R threshold
capital amount
display text.

Ensure no hidden FIXED CAPITAL-SCALE logic remains in live Auto mode.

======================================================================
34. DO NOT CHANGE EXISTING TP VOLUME SPLIT SEMANTICS
====================================================

Keep:

InpTP1Pct
InpTP2Pct
InpTP3Pct

as POSITION VOLUME FRACTIONS.

Example:

0.75 = 75%
0.20 = 20%
0.05 = 5%.

Do NOT confuse these with:

account risk percentages
profit percentages.

Retain existing:

3-leg → 2-leg → 1-leg

degradation when broker volume minimum makes partial TP impossible.

Never let rounding make total allocated volume exceed the original position.

======================================================================
35. POST-NORMALIZATION VERIFICATION LOOP
========================================

For every proposed volume perform final verification:

actual riskMoney
actual riskPct
aggregate projected riskPct
directional projected riskPct
window projected riskPct
required margin
free margin after
broker volume rules
symbol volume limit
stops
spread quality
slippage quality
cost viability.

If invalid because volume is too large:

decrement ONE broker volume step.

Recalculate.

Repeat with a bounded iteration count.

If volume falls below volumeMin:

run Min-Lot Feasibility.

If that fails:

reject.

Never increase volume during a safety correction.

======================================================================
36. POSITION RISK INVARIANTS
============================

These are mandatory:

A larger SL → same or smaller lot.

Higher expected commission → same or smaller lot.

Higher expected slippage → same or smaller lot.

Higher spread/cost → same or smaller lot.

Smaller conservative capital base → same or smaller risk money.

Lower free margin → same or smaller allowed lot.

Lower leverage must never create a larger accepted margin exposure.

Volume normalization never rounds risk upward.

Min lot never silently violates safety limit.

No martingale.

No averaging down.

Recovery < normal risk.

Aggregate <= profile aggregate cap.

Directional <= profile directional cap.

Window <= profile window cap.

Daily/weekly/monthly breakers still take precedence.

News/disorder/swap gates still take precedence.

======================================================================
37. DEPOSIT / WITHDRAWAL HANDLING
=================================

Preserve the existing stale-anchor logic.

Improve only if necessary.

Deposits/withdrawals should not create false:

daily drawdown
weekly drawdown
monthly drawdown.

However:

do NOT reset genuine trading losses merely because equity changed.

If practical, inspect balance operations/history to distinguish external balance adjustments from trading P/L.

Use conservative fallback when uncertain.

======================================================================
38. DASHBOARD
=============

Do not redesign the existing dashboard.

Add compact telemetry using cached/precomputed values:

Capital Profile
Equity USD
Account Currency
Capital Base
Base Risk %
Effective Risk %
Allowed Risk Money
Raw Lot
Final Lot
Volume Min/Step/Max
Volume Limit
Projected Risk Money/%
Aggregate Risk current/max
Directional Risk current/max
Window Risk current/max
Required Margin
Free Margin
Projected Free Margin
Margin %
Spread points
Spread/ATR %
Spread percentile
Adaptive deviation
Expected all-in cost
Learned commission RT/lot
Min-lot feasibility
OrderCheck state
USD conversion state.

Do not run expensive trade simulations solely because the dashboard repaints.

======================================================================
39. LOGGING
===========

Append telemetry without breaking existing log parsing where possible:

CapitalProfile
AccountCurrency
Equity
EquityUSD
CapitalBase
BaseRiskPct
EffectiveRiskPct
AllowedRiskMoney
RawLots
FinalLots
ActualRiskMoney
ActualRiskPct
AggregateRiskPct
DirectionalRiskPct
WindowRiskPct
VolumeMin
VolumeStep
VolumeMax
VolumeLimit
RequiredMargin
FreeMarginBefore
FreeMarginAfter
MarginPct
SpreadPoints
SpreadToATRPct
SpreadPercentile
ExpectedSlipPts
AdaptiveDeviation
CommissionRTPerLot
ExpectedAllInCost
MinLotRiskPct
OrderCheckRetcode
OrderCheckComment
RiskSizingReason.

Add gate reasons including:

CAPITAL_TOO_SMALL
CAPITAL_PROFILE_CONSERVATIVE_FALLBACK
MIN_LOT_RISK_TOO_HIGH
MARGIN_INSUFFICIENT
MARGIN_CAP
AGGREGATE_RISK_CAP
DIRECTIONAL_RISK_CAP
WINDOW_RISK_CAP
SYMBOL_VOLUME_LIMIT
BROKER_VOLUME_INVALID
BROKER_STOPS_INVALID
ORDER_CHECK_FAILED
SPREAD_RELATIVE_HIGH
SLIPPAGE_RELATIVE_HIGH
COST_TOO_HIGH
TP_NET_RISK_TOO_LOW
RISK_OVERRIDE_CLAMPED.

Keep existing gate reasons as well.

======================================================================
40. PERFORMANCE REPORT
======================

Preserve:

number of trades
wins
losses
win rate
profit factor
net R/trade
Sharpe
net profit
max drawdown
slippage
spread
commission.

Add:

capital profile
average effective risk %
average actual R
window expectancy R where useful
min-lot rejects
margin rejects
spread rejects
slippage rejects
OrderCheck rejects.

Do not remove existing metrics.

======================================================================
41. DO NOT USE BROKER NAME HEURISTICS
=====================================

Do not determine risk simply from strings such as:

ECN
STP
Standard
Micro
Cent.

Use real account/symbol economics:

tick value
tick size
contract size
volume min
volume step
volume max
volume limit
margin
leverage
trade mode
margin mode
spread
commission
slippage.

Broker/company/account labels may be DISPLAY telemetry only.

======================================================================
42. PERFORMANCE / CPU
=====================

This is an M1 ultra-scalper.

Avoid expensive work every tick.

Static broker values:
cache.

Capital profile:
recompute when equity/currency materially changes or on reasonable timer.

FX conversion:
cache and periodically refresh.

OrderCalcProfit:
use during trade sizing/risk validation, not every tick unnecessarily.

OrderCalcMargin:
use during trade preparation.

OrderCheck:
use before new requests.

Spread/slippage:
reuse current ring buffers.

Do not add external network dependencies.

======================================================================
43. BACKWARD COMPATIBILITY
==========================

Do not delete old inputs unnecessarily.

Old .set files may depend on them.

When old inputs are superseded by Auto mode:

retain them
mark comments as LEGACY/MANUAL
clearly define when ignored.

Examples:

InpLotSize
InpMaxTotalLots
fixed TP money gates
fixed money expectancy gates
fixed spread/slippage fallbacks.

Avoid changing input types/names unless required.

======================================================================
44. SELF-TESTS
==============

Add non-trading self-test/debug checks for:

Profile boundary:

49.99 or below
50
100
499.99
500
1,000
4,999.99
5,000
10,000
50,000
100,000.

Broker-volume scenarios:

0.01 min / 0.01 step
0.001 min / 0.001 step
different contract sizes
2-digit XAUUSD
3-digit XAUUSD
volume limit.

Risk monotonicity:

larger SL => lot never increases
larger commission => lot never increases
larger slippage => lot never increases
smaller equity => risk money never increases.

Min-lot:

unsafe min lot => blocked.

Margin:

insufficient margin => reduced or blocked.

No real orders must be sent by self-test.

======================================================================
45. COMPILE / VALIDATE
======================

After editing:

1. Re-read the complete source.

2. Run searches for all old fixed-risk paths.

3. Check function signatures and every caller.

4. Check struct changes and persistence implications.

5. Check array bounds.

6. Check enum indexing.

7. Check WIN_NONE usage in risk arrays.

8. Check division-by-zero guards.

9. Check account-currency assumptions.

10. Check price/tick normalization.

11. Check volume normalization.

12. Check OrderCalcProfit failure fallback.

13. Check OrderCalcMargin failure fallback.

14. Check OrderCheck retcodes.

15. Check netting behavior.

16. Check hedging behavior.

17. Check recovery behavior.

18. Check TP partial volume behavior.

19. Check restart persistence.

20. Check dashboard compile.

21. Check CSV FileWrite column consistency.

If MetaEditor/MetaEditor64 compiler is available in the environment:

COMPILE the resulting MQ5.

Target:

0 errors
0 warnings where reasonably achievable.

If the compiler is NOT available:

do NOT falsely claim successful compilation.

Instead perform a complete static MQL5 syntax/type/call-site audit and state clearly that native MetaEditor compilation remains required.

======================================================================
46. DO NOT RETURN A PARTIAL PATCH
=================================

Apply all required changes directly to the EXISTING file.

Do not stop after modifying only:

CalculateLot

or:

CurrentRiskPct.

Perform the entire dependency conversion.

Do not leave TODO placeholders.

Do not supply pseudo-code as the implementation.

Do not produce a fresh simplified EA.

Preserve the complete existing EA.

======================================================================
47. REQUIRED FINAL AUDIT
========================

Before completing, explicitly verify internally that:

[ ] No hardcoded Simple Scalp 0.35 risk path bypasses profile engine.

[ ] InpRiskPercent remains available for manual mode.

[ ] InpLotSize does not affect Auto mode.

[ ] Legacy 1.20 max-lot cap does not restrict Auto mode.

[ ] Volume is determined by actual risk, not account-size lot tables.

[ ] OrderCalcProfit is primary monetary SL-risk calculator.

[ ] PriceMoveMoney remains fallback.

[ ] Learned commission remains primary.

[ ] Commission fallback is not converted into notional percentage.

[ ] TP1/TP2/TP3 price targets remain ATR/structure based.

[ ] Fixed TP MONEY viability gates are superseded by risk-relative gates.

[ ] Performance gating uses rolling R in Auto mode.

[ ] Native OrderCalcMargin is used.

[ ] New trade requests go through OrderCheck.

[ ] Existing modification/delete requests are not incorrectly blocked by new-entry preflight.

[ ] Min-lot risk cannot silently exceed profile ceiling.

[ ] Spread gate uses existing rolling spread statistics.

[ ] Slippage gate uses existing slippage statistics.

[ ] g_ptScale/price-distance normalization is consistent.

[ ] SYMBOL_VOLUME_LIMIT is respected.

[ ] Aggregate/directional/window risk remain percentage based.

[ ] Mobile RISK override cannot bypass safety.

[ ] Daily/weekly/monthly DD breakers remain intact.

[ ] No martingale remains intact.

[ ] No averaging down remains intact.

[ ] Recovery risk remains smaller.

[ ] Sydney/Tokyo/London/New York all remain available according to existing configuration.

[ ] Overlap/HV engine remains intact.

[ ] News protection remains intact.

[ ] Swap protection remains intact.

[ ] License/mobile architecture remains intact.

[ ] Dashboard remains functional.

[ ] Existing logs/performance metrics remain functional.

======================================================================
48. REQUIRED FINAL REPORT FROM CODEX
====================================

After modifying the actual MQ5 file, return a concise implementation report containing:

A. FILE MODIFIED
exact path/file.

B. CAPITAL ENGINE
profile thresholds and detected current profile.

C. RISK ENGINE
old risk path vs new authoritative path.

D. BROKER ENGINE
which broker properties are now used.

E. LOT SIZING
how raw and final volume are calculated.

F. MARGIN ENGINE
OrderCalcMargin integration.

G. PREFLIGHT
OrderCheck integration and exact call sites.

H. COST ENGINE
commission/spread/slippage behavior.

I. PERFORMANCE GATING
money expectancy → R expectancy.

J. SMALL ACCOUNT BEHAVIOR
exact conditions where a $50-$500 account trades or is blocked.

K. BACKWARD COMPATIBILITY
which old inputs remain and when they are ignored.

L. COMPILATION
actual compiler result if compiler was available; otherwise state NOT COMPILED.

M. FINAL DIFF SUMMARY
functions added
functions modified
inputs added
structs modified.

======================================================================
FINAL PRINCIPLE
===============

The SAME Predict-A-Trade-Ultra.mq5 must safely work across brokers and account sizes by calculating economic risk from the broker/account environment.

It must NOT say:

"$100 uses 0.01 lot"
"$1,000 uses 0.10"
"$10,000 uses 1.00."

It must calculate:

SAFE CAPITAL BASE
×
ALLOWED RISK %
==============

RISK MONEY

then:

REAL BROKER LOSS FROM ENTRY TO SL
+
EXPECTED EXECUTION COST
=======================

RISK PER LOT

then:

# RISK MONEY / RISK PER LOT

RAW VOLUME

then validate against:

VOLUME MIN
VOLUME STEP
VOLUME MAX
VOLUME LIMIT
AGGREGATE RISK
DIRECTIONAL RISK
WINDOW RISK
MARGIN
SPREAD
SLIPPAGE
COST
ORDERCHECK.

Only after all checks pass:

ORDERSEND.

A $50 account may correctly produce NO TRADE if the broker's minimum XAUUSD contract is economically unsafe.

A $50,000+ account must be allowed to scale its broker-valid volume without being constrained by an obsolete fixed 1.20-lot ceiling.

PRESERVE THE ENTIRE EXISTING TRADING STRATEGY.

CHANGE ONLY WHAT IS NECESSARY TO MAKE CAPITAL, RISK, COST, MARGIN AND EXECUTION BROKER-NATIVE AND ACCOUNT-SIZE-INDEPENDENT.
