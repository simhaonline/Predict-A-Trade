You are an MQL5 MetaTrader 5 EA configuration and code-audit engineer.

MISSION
Review the Predict-A-Trade EA source in this repository. Apply the following authoritative XAUUSD M1 ultra-scalp profile.

Create a loadable .set file containing every listed input.
Audit the EA source for:
- missing input names
- inputs ignored in InpSimpleScalpMode=true
- hardcoded simple-mode TP/SL values that conflict with this profile
- any invariant violations

If simple-mode TP/SL is hardcoded, modify only those TP/SL multipliers as described below.
Do not change trading logic outside the listed modifications.
Do not enable martingale, averaging down, scale-in, or loss-chasing recovery.

FINAL AUTHORITATIVE VALUES

Core mode
InpSimpleScalpMode = true
InpScalpMinMomentumATR = 0.08

Capital protection
InpDailyLossPercent = 2.5
InpMaxFloatingDDPercent = 3.0
InpWeeklyLossLimit = 6.0
InpMonthlyLossLimit = 10.0
InpRiskPercent = 0.35
InpRiskStepDownOnDD = 0.15
InpMaxConsecutiveLosses = 3
InpMaxTradesPerDay = 25
InpAllowMinLotFallback = true
InpMinLotMaxRiskPct = 1.5
InpMaxAggregateOpenRiskPct = 2.5
InpMaxDirectionalRiskPct = 1.5
InpBreakerAction = BREAKER_CLOSE_ALL
InpNoMartingale = true
InpNoAveragingDown = true

Broker / cost model
InpMaxSpreadPoints = 35
InpSpreadSpikeRatio = 2.0
InpMaxSpreadPercentile = 90.0
InpMaxSlippagePoints = 25
InpCommissionPerLotRTFallback = 7.00
InpExpectedSlipPtsFallback = 3.5
InpMaxCostToTP1Pct = 40.0
InpMinNetProfitTP1Money = 0.30
InpMinNetProfitTP2Money = 0.50
InpMinNetProfitTP3Money = 0.70
InpOrderRetry = 2
InpMaxAverageSlippagePoints = 15.0
InpExtremeSlippagePoints = 25.0

Risk-reward validation
InpMinRR_TP2 = 0.55
InpMinRR_TP3 = 1.10

Execution / anti-overtrading
InpExecutionMode = EXEC_DIRECTIONAL
InpStraddleLayers = 1
InpLayerStepATR = 0.35
InpMaxConcurrentPositions = 3
InpMaxTotalLots = 1.20
InpArmWhileInTrade = true
InpScaleIn = false
InpMinSecondsBetweenEntries = 20
InpMinBarsFreshStructure = 2
InpMaxSignalsPerWindow = 10
InpPerWindowRiskBudgetPct = 1.5
InpOncePerValidatedEvent = true
InpCancelStalePendings = true
InpPendingExpiryMinutes = 3
InpDistance = 1.00
InpUseATRForDistance = true
InpATRMultiplier = 0.22
InpLayerSpacingATR = 0.25
InpLotSize = 0.05

Filters / SMC
InpFilterMode = FILTER_SCORING
InpMinFilterScore = 5
InpUseEMA20 = true
InpUseEMA50 = true
InpUseSuperTrend = true
InpUseADX = true
InpUseVWAP = true
InpUseFVG = true
InpUseAMD = true
InpUseVolumeFilter = true
InpUseLiquidityFilter = true
InpUseRSI = true
InpUseSMC = true
InpMinDirBias = 2
InpMinSMCConfluence = 1
InpSwingLookback = 12
InpFVGLookbackBars = 12
InpFVGMinGapATR = 0.05
InpAMDLookbackBars = 20
InpAMDCoilRatio = 0.80

Indicators / volatility
InpEMA20Period = 20
InpEMA50Period = 50
InpSuperTrendPeriod = 10
InpSuperTrendMultiplier = 3.0
InpADXPeriod = 14
InpMinADX = 20.0
InpATRPeriod = 14
InpMinATRPoints = 22
InpMaxATRPoints = 550
InpATRPercentileLookback = 240
InpHVMinATRPercentile = 65.0
InpVolumeMA = 25
InpMinVolumeRatio = 1.15
InpHVMinVolumeRatio = 1.30
InpMinLiquidityLevel = 0.90
InpRSIPeriod = 9
InpRSIOverbought = 75
InpRSIOversold = 25
InpVWAPAnchor = VWAP_BROKER_DAY

Session / overlap engine
InpUseSessionFilter = true
InpTradeAllFourSessions = true
InpTradeSydney = true
InpTradeTokyo = true
InpTradeLondon = true
InpTradeNewYork = true
InpTradeSydneyTokyo = true
InpTradeTokyoLondon = true
InpTradeLondonOpen = true
InpTradeLondonNY = true
InpTradeNYOpen = true
InpTradeVerifiedExpansion = true
InpNeverDisablePrimarySessions = true
InpSydneyLocalOpenMin = 480
InpSydneyLocalCloseMin = 1020
InpTokyoLocalOpenMin = 540
InpTokyoLocalCloseMin = 1080
InpLondonLocalOpenMin = 480
InpLondonLocalCloseMin = 990
InpNewYorkLocalOpenMin = 480
InpNewYorkLocalCloseMin = 1020
InpLondonOpenWindowMin = 75
InpNYOpenWindowMin = 60
InpOverlapPadMinutes = 0
InpFridayCutoffServer = 19.0
InpAutoDetectServerOffset = true
InpManualServerOffsetHours = 3
InpServerOffsetRefreshSec = 60

High-volatility mode
InpHighVolatilityMode = HV_AUTO
InpHVMinScore = 6
InpHVMinDisplacementATR = 0.60
InpHVMaxDisorderATR = 2.50
InpHVMinVWAPDeviationATR = 0.10
InpSessionBreakoutLookback = 30
InpHVExtraSignalRiskMult = 0.70
InpVerifiedBucketMinSamples = 30
InpVerifiedBucketATRRatio = 1.15
InpVerifiedBucketVolRatio = 1.10

TP ladder / exit engine
InpUseThreeTargets = true
InpTP1Pct = 0.75
InpTP2Pct = 0.20
InpTP3Pct = 0.05
InpSL_ATR_Multiplier = 0.80
InpSLStructureBufferATR = 0.12
InpTP1_ATR_Floor = 0.25
InpTP1_ATR_Cap = 0.40
InpTP2_ATR_Floor = 0.60
InpTP2_ATR_Cap = 1.10
InpTP3_ATR_Floor = 1.00
InpTP3_ATR_Cap = 1.80
InpUseCostAdjustedBE = true
InpBEExtraLockATR = 0.02
InpUseTP3StructureTrail = true
InpTP3TrailATR = 0.50
InpTP3TrailStepATR = 0.10
InpTP3EarlyExit = true
InpMaxTradeMinutes = 10

News / disorder protection
InpUseNewsFilter = true
InpNewsBufferMinutes = 10
InpNewsLookaheadMin = 120
InpPostNewsStabilizeMinutes = 5
InpDisorderSpreadPct = 95.0
InpMaxChaseCandleATR = 2.20
InpMaxEntryVWAPDeviationATR = 2.00
InpDisorderSlipPts = 18.0
InpDisorderCooldownMinutes = 5

FMP macro / external data
InpUseFMP = true
InpFMPRefreshSec = 600
InpFMPTimeoutMs = 5000
InpFMPUSDPairMinPct = 0.020
InpFMPIncludeSPX = true
InpFMPSPXMinPct = 0.30
InpFMPNewsHardBlock = false
InpFMPNewsLimit = 25
InpAllowBrokerMacroFallback = true
InpMacroTF = PERIOD_M5
InpMacroMomentumBars = 6
InpUseEURUSD = true
InpEURUSDSymbol = ""
InpEURUSDMinMovePct = 0.020
InpMacroMinConfluence = 0
InpRequireExternalData = false

IFVG / propulsion block
InpUseIFVG = true
InpIFVGLookbackBars = 40
InpIFVGMinGapATR = 0.05
InpUsePTB = true
InpPTBLookbackBars = 40
InpPTBMinDisplacementATR = 0.55
InpMinAdvancedSMCConfluence = 0

Loss recovery / reversal engine
InpUseRecovery = true
InpRecoveryMaxLegs = 1
InpRecoveryRiskPct = 0.15
InpRecoveryMinRR = 1.50
InpRecoveryCooldownSec = 300
InpRecoveryMaxAgeSec = 600
InpRecoveryMaxSpreadPts = 30

Slippage / swap protection
InpCloseOnExtremeSlippage = false
InpSlippageCooldownMinutes = 3
InpAvoidSwap = true
InpForceFlatBeforeSwap = true
InpSwapRolloverServerHour = 0.0
InpSwapBlockMinutesBefore = 60
InpSwapBlockMinutesAfter = 10

Performance self-gating / A-B
InpEnablePerformanceGating = true
InpPerfMinTrades = 20
InpPerfRollingTrades = 40
InpDisableExpectancyMoney = -0.15
InpRiskReduceExpectancyMoney = 0.08
InpWeakWindowRiskMultiplier = 0.50
InpAB_EnableBase = true
InpAB_EnableHighVol = true
InpAB_EnableThreeTP = true

Logging / dashboard / identity
InpUseLogFile = true
InpPersistState = true
InpShowDashboard = true
InpPanelX = 430
InpPanelY = 30
InpPanelFontSize = 8
InpDashRefreshMs = 400
InpPanelTitle = "PREDICT-A-TRADE GOLD"
InpPanelDraggable = true
InpSoundPause = "alert2.wav"
InpSoundResume = "alert.wav"
InpMagicNumber = 20260911
InpComment = "Predict-A-Trade v4"

SIMPLE-MODE TP/SL CODE ALIGNMENT

Search the simple-mode branch in TryArm(), ScalpTarget1(), ScalpStopDistance(), and related functions.

Current simple-mode hardcoded profile is approximately:
- Normal TP1 = 0.55 ATR
- Normal TP2 = 0.95 ATR total
- Normal TP3 = 1.40 ATR total
- Normal SL = 0.90 ATR
- Reversion SL = 0.50 ATR beyond extreme
- London breakout SL = 1.00 ATR

Replace those effective simple-mode distances with:
- Normal TP1 = 0.40 ATR
- Normal TP2 = 0.75 ATR total
- Normal TP3 = 1.15 ATR total
- Normal SL = 0.80 ATR
- Reversion SL = 0.45 ATR beyond extreme
- London breakout SL = 0.85 ATR

Keep all existing price distance logic, normalization, spread/cost checks, direction handling, and signal-specific target behavior unchanged.

If the source already honors the listed TP1/TP2/TP3 ATR inputs and InpSL_ATR_Multiplier in simple mode, do not apply the hardcoded replacement above. Instead, only ensure the .set file uses the final values in this prompt.

DELIVERABLES

1. Create or update:
   presets/XAUUSD_M1_UltraScalp.set

2. Create or update:
   docs/XAUUSD_M1_UltraScalp_Audit.md

3. If source changes were needed, provide a minimal diff.

AUDIT REPORT MUST CONTAIN
- Every input name above and whether it exists in source.
- Whether each input is effective in InpSimpleScalpMode=true.
- Any hardcoded values that override the intended micro-scalp profile.
- The effective simple-mode TP/SL distances after code changes.
- Explicit note that recovery, RR validation, or TP/SL ATR inputs are ignored by design in simple mode unless code was changed.
- Broker-specific warnings for:
  - InpManualServerOffsetHours
  - InpSwapRolloverServerHour
  - InpMaxSpreadPoints
  - InpCommissionPerLotRTFallback
  - InpExpectedSlipPtsFallback

ACCEPTANCE CRITERIA
- The .set file loads without invalid input name errors.
- InpSimpleScalpMode=true.
- InpNoMartingale=true.
- InpNoAveragingDown=true.
- InpScaleIn=false.
- InpUseRecovery=true but simple mode must skip recovery execution.
- InpRequireExternalData=false.
- The EA can still trade if FMP or external macro data is unavailable.
- No changes are made to session open/close logic except the values listed.
- No changes are made to brokerage order-send logic except respecting the values listed.

Do not optimize any other parameters.
Do not switch the EA to complex mode.
Do not add new filters or new exit logic.

You are an MQL5 MetaTrader 5 EA architect and code-audit engineer working in this repository.

CONTEXT
The Predict-A-Trade EA currently has NO standalone Support & Resistance layer.
S/R exists only implicitly via:
- DetectSMC() swing high/low (g_swingHigh / g_swingLow, InpSwingLookback)
- NearestLiquidityTarget() TP snapping
- BOS / CHoCH / sweep detection
- FVG / IFVG / PTB zones
- VWAP + 1σ bands and manual Bollinger bands
- TP3 structure trail

Missing capabilities:
- no multi-timeframe S/R levels (M15/H1/H4/D1)
- no S/R zone thickness (levels are single prices)
- no touch counting or level strength scoring
- no round-number / psychological levels
- no prior day / prior week / prior session levels
- no S/R confluence scoring
- no S/R proximity gate on entries
- no S/R-aware SL placement in simple scalp mode

MISSION
Add a dedicated, self-contained HTF Support & Resistance module ("SR module") and integrate it into the existing engine.

HARD CONSTRAINTS (do not violate)
1. The SR module is ADDITIVE. When InpUseSRZones=false the EA must behave bit-identically to the current build, with zero added per-tick CPU cost.
2. The SR module MUST NOT generate entry signals. It may only: filter, score, snap targets, refine stops, refine trailing, and display.
3. Do NOT switch the EA out of InpSimpleScalpMode. Do NOT add new trade modes.
4. Do NOT modify session open/close logic, news logic, order-send retry logic, or breaker logic.
5. Preserve invariants: InpNoMartingale=true, InpNoAveragingDown=true, InpScaleIn=false, no loss-chasing recovery in simple mode.
6. S/R MUST NEVER increase risk. If an SR-adjusted stop is wider than the base stop, the lot size must be recomputed so risk % stays identical. If the recomputed lot is below broker minimum, apply existing InpAllowMinLotFallback / InpMinLotMaxRiskPct rules; if still invalid, reject the SR stop adjustment and keep the base stop.
7. Any SR-adjusted TP must be re-validated against InpMaxCostToTP1Pct, InpMinNetProfitTP1Money, InpMinNetProfitTP2Money, InpMinNetProfitTP3Money, broker stop level, and freeze level. If validation fails, revert to the original TP.
8. Zero compile errors, zero compile warnings, MQL5 strict mode.

FILE LAYOUT
Match the existing repository structure.
- If the EA uses .mqh includes, create Include/PredictATrade/SRZones.mqh and include it.
- If the EA is a single .mq5, insert the module as one contiguous block delimited by:
  //================ SR MODULE BEGIN ================
  //================ SR MODULE END ==================
Place all SR inputs in a new input group: "=== SUPPORT & RESISTANCE (HTF ZONES) ===".

DATA MODEL

Add:

enum ENUM_SR_MODE
{
   SR_ADVISORY = 0,    // score + display only, never blocks
   SR_SOFT_FILTER = 1, // blocks only entries into strong opposing walls
   SR_HARD_FILTER = 2  // additionally requires TP1 headroom
};

enum ENUM_SR_SRC
{
   SRSRC_PIVOT    = 1,
   SRSRC_PREVDAY  = 2,
   SRSRC_PREVWEEK = 4,
   SRSRC_SESSION  = 8,
   SRSRC_ROUND    = 16,
   SRSRC_DAILYOPEN= 32,
   SRSRC_FVG      = 64,
   SRSRC_IFVG     = 128,
   SRSRC_PTB      = 256,
   SRSRC_VWAP     = 512
};

struct SRZone
{
   double   lower;        // zone lower edge (price)
   double   upper;        // zone upper edge (price)
   double   anchor;       // originating level price
   int      side;         // +1 = above current price (resistance), -1 = below (support)
   double   strength;     // final weighted score after decay
   double   rawStrength;  // pre-decay
   int      touches;      // confirmed touches within tolerance
   int      rejections;   // touches that reversed
   int      breaks;       // confirmed closes through the zone
   bool     broken;       // currently invalidated
   datetime lastTouch;
   datetime created;
   int      tfMask;       // bitmask of contributing timeframes
   int      srcMask;      // bitmask of ENUM_SR_SRC contributors
   bool     fresh;        // never traded into since creation
};

Store zones in a fixed-size static array (no dynamic reallocation per tick), capped by InpSRMaxTotalZones.

NEW INPUTS (exact names and defaults)

Master
InpUseSRZones                 = true
InpSRMode                     = SR_SOFT_FILTER
InpSRRefreshSeconds           = 15
InpSRRebuildOnNewHTFBar       = true

Timeframes and history
InpSR_TF1                     = PERIOD_M15
InpSR_TF2                     = PERIOD_H1
InpSR_TF3                     = PERIOD_H4
InpSR_TF4                     = PERIOD_D1
InpSR_BarsTF1                 = 300
InpSR_BarsTF2                 = 300
InpSR_BarsTF3                 = 240
InpSR_BarsTF4                 = 90
InpSRFractalLeft              = 2
InpSRFractalRight             = 2

Level sources
InpSRUsePivotSwings           = true
InpSRUsePrevDayHL             = true
InpSRUsePrevWeekHL            = true
InpSRUseSessionHL             = true
InpSRUseDailyOpen             = true
InpSRUseRoundNumbers          = true
InpSRRoundStepUSD             = 10.0
InpSRRoundSubStepUSD          = 5.0
InpSRRoundMaxLevels           = 6
InpSRUseFVGConfluence         = true
InpSRUseVWAPConfluence        = false

Zone geometry
InpSRZoneATRTF                = PERIOD_M15
InpSRZoneThicknessATR         = 0.35
InpSRZoneMinPoints            = 20
InpSRZoneMaxPoints            = 150
InpSRMergeOverlapATR          = 0.25
InpSRMaxZonesPerSide          = 6
InpSRMaxTotalZones            = 24
InpSRMaxDistanceATR           = 12.0

Strength scoring
InpSRTouchToleranceATR        = 0.20
InpSRMinTouches               = 1
InpSRWeightTouch              = 1.00
InpSRWeightRejection          = 0.50
InpSRWeightTF_M15             = 1.00
InpSRWeightTF_H1              = 2.00
InpSRWeightTF_H4              = 3.00
InpSRWeightTF_D1              = 4.00
InpSRWeightPrevDay            = 2.00
InpSRWeightPrevWeek           = 2.50
InpSRWeightSession            = 1.50
InpSRWeightRound              = 1.00
InpSRWeightDailyOpen          = 1.00
InpSRWeightFVG                = 1.00
InpSRWeightVWAP               = 1.00
InpSRFreshBonus               = 0.50
InpSRBreakPenalty             = 1.50
InpSRRecencyHalfLifeBars      = 400
InpSRMinStrengthToUse         = 3.00

Entry gating
InpSRWallMinStrength          = 5.00
InpSRBlockIntoWallATR         = 0.45
InpSRRequireHeadroomTP1       = true
InpSRHeadroomFactor           = 1.10
InpSRAllowBreakoutThrough     = true
InpSRBreakoutBufferATR        = 0.15
InpSRScoreBonus               = 1
InpSRScorePenalty             = 1

Exit integration
InpSRSnapTP                   = true
InpSRSnapTPMaxShiftATR        = 0.25
InpSRTPFrontRunPoints         = 8
InpSRSLBehindZone             = true
InpSRSLBufferATR              = 0.10
InpSRSLMaxExtraATR            = 0.30
InpSRTrailUseZones            = true

Display / logging
InpSRDrawZones                = true
InpSRMaxDrawZones             = 12
InpSRColorResistance          = clrIndianRed
InpSRColorSupport             = clrMediumSeaGreen
InpSRColorBroken              = clrDimGray
InpSRZoneFill                 = true
InpSRShowLabels               = true
InpSRShowOnPanel              = true
InpSRLogLevels                = true
InpSRLogEveryNSeconds         = 300
InpSRObjPrefix                = "PAT_SR_"

FUNCTIONS TO IMPLEMENT

Lifecycle
bool   SR_Init();                        // called from OnInit after indicator handles exist
void   SR_Deinit();                      // delete all objects with InpSRObjPrefix
void   SR_Reset();                       // clear arrays and counters
bool   SR_Rebuild(bool force=false);     // throttled full rebuild

Collection
void   SR_CollectPivots(ENUM_TIMEFRAMES tf,int bars,double tfWeight);
void   SR_CollectPrevDayHL();
void   SR_CollectPrevWeekHL();
void   SR_CollectSessionHL();            // Asian range H/L, prior London H/L, prior NY H/L
void   SR_CollectDailyOpen();
void   SR_CollectRoundNumbers(double price,double atr);
void   SR_CollectStructureConfluence();  // FVG / IFVG / PTB / VWAP bands overlap tagging

Processing
void   SR_MergeZones(double atr);
void   SR_CountTouches(double atr);
void   SR_ApplyRecencyDecay();
void   SR_ScoreZones(double atr);
void   SR_ClassifySides(double price);
void   SR_PruneWeakAndDistant(double price,double atr);

Queries (must be O(n) over a capped array, no CopyRates inside)
bool   SR_NearestAbove(double price,double minStrength,double &nearEdge,double &farEdge,double &strength,int &idx);
bool   SR_NearestBelow(double price,double minStrength,double &nearEdge,double &farEdge,double &strength,int &idx);
double SR_HeadroomPrice(int dir,double entry,double minStrength);   // price of first opposing zone edge, 0 if none
double SR_HeadroomATR(int dir,double entry,double atr,double minStrength);
bool   SR_PriceInsideZone(double price,int &idx);
bool   SR_BreakoutConfirmed(int dir,double atr);                    // close beyond zone + InpSRBreakoutBufferATR

Decision helpers
bool   SR_EntryAllowed(int dir,double entry,double atr,double tp1Distance,string &reason);
int    SR_DirectionalVote(int dir,double entry,double atr);         // returns -InpSRScorePenalty .. +InpSRScoreBonus
double SR_AdjustTP(int dir,double entry,double tpIn,double atr,int legIndex);
double SR_AdjustSL(int dir,double entry,double slIn,double atr);
double SR_TrailAnchor(int dir,double atr);                          // zone-based trail reference, 0 if none

Presentation
void   SR_Draw();
void   SR_ClearObjects();
string SR_PanelLine1();   // e.g. "SR R:3412.40 s6.5 d0.8A | S:3402.10 s5.0 d1.4A"
string SR_PanelLine2();   // e.g. "SR zones 14 | mode SOFT | block NONE"
void   SR_LogSnapshot();

ALGORITHM SPECIFICATION

1) Rebuild trigger
Rebuild when any of:
- forced
- InpSRRefreshSeconds elapsed since last rebuild
- InpSRRebuildOnNewHTFBar and a new bar opened on any enabled SR timeframe
Never rebuild more than once per tick. Track and log rebuild duration with GetMicrosecondCount(); if a rebuild exceeds 20000 microseconds, print a single throttled warning.

2) Pivot collection
For each enabled TF with sufficient history:
- Copy the last N rates once into a local array.
- A pivot high at index i requires high[i] >= high of the previous InpSRFractalLeft bars and >= high of the next InpSRFractalRight bars.
- A pivot low is the mirror condition.
- Skip index 0 (forming bar).
- Create a candidate level with the TF weight and SRSRC_PIVOT.
If Bars(symbol,tf) < required, skip that TF silently (log once per session at most).

3) Zone thickness
thickness = clamp(InpSRZoneThicknessATR * ATR(InpSRZoneATRTF),
                  InpSRZoneMinPoints * _Point,
                  InpSRZoneMaxPoints * _Point)
lower = anchor - thickness/2, upper = anchor + thickness/2.
Normalize both edges with the existing price normalization helper.

4) Merging
Merge two zones when their edges overlap OR their anchors are within InpSRMergeOverlapATR * ATR.
Merged zone:
- anchor = strength-weighted average of anchors
- lower = min(lower), upper = max(upper)
- touches = sum, rejections = sum, breaks = max
- tfMask |= , srcMask |=
- rawStrength = sum of contributions, but cap timeframe contribution so the same TF is not double-counted more than twice
- created = earliest, lastTouch = latest
Re-run merging until stable or a max of 3 passes.

5) Touch counting
Using M1 history over the last max(InpSR_BarsTF1, 500) bars:
- A touch is a bar whose high enters [lower - tol, upper + tol] for resistance, or whose low enters the equivalent for support, where tol = InpSRTouchToleranceATR * ATR.
- A rejection is a touch where the bar closes back outside the zone in the opposing direction.
- A break is a bar that closes fully beyond the zone by more than InpSRBreakoutBufferATR * ATR.
- Consecutive touches within 3 bars count once.
Set broken=true when breaks >= 1 and the most recent break is more recent than the most recent rejection.

6) Scoring
rawStrength =
   InpSRWeightTouch * touches
 + InpSRWeightRejection * rejections
 + sum(timeframe weights from tfMask)
 + source weights from srcMask (prev day, prev week, session, round, daily open, FVG, VWAP)
 + (fresh ? InpSRFreshBonus : 0)
 - InpSRBreakPenalty * breaks

Recency decay:
strength = rawStrength * pow(0.5, barsSinceLastTouch / InpSRRecencyHalfLifeBars)
Clamp strength to >= 0. A broken zone keeps at most 50% of its strength and flips its intended side (broken resistance may act as support) only if it also has at least one post-break rejection.

7) Pruning
Drop zones where:
- strength < InpSRMinStrengthToUse, or
- touches < InpSRMinTouches and srcMask has only SRSRC_ROUND, or
- distance from current price > InpSRMaxDistanceATR * ATR
Then keep the strongest InpSRMaxZonesPerSide above and below, and never exceed InpSRMaxTotalZones.

8) Entry gate — SR_EntryAllowed
Inputs: trade direction, intended entry price, ATR, TP1 distance.
Behavior by InpSRMode:
- SR_ADVISORY: always returns true; still fills reason string for logging.
- SR_SOFT_FILTER: return false if an opposing zone with strength >= InpSRWallMinStrength has its near edge within InpSRBlockIntoWallATR * ATR of entry, UNLESS InpSRAllowBreakoutThrough is true and SR_BreakoutConfirmed(dir,atr) is true.
- SR_HARD_FILTER: all of the above, plus require
  SR_HeadroomPrice distance >= tp1Distance * InpSRHeadroomFactor.
Always set a short machine-parsable reason such as "SR_WALL_5.8@0.31A" or "SR_NO_HEADROOM" or "SR_OK".
Never block when no qualifying zone exists. Never block on missing data or on ATR<=0.

9) TP adjustment — SR_AdjustTP
For a buy, if a resistance zone lies between entry and tpIn or slightly beyond it:
- candidate = zone.lower - InpSRTPFrontRunPoints * _Point
For a sell, mirror using zone.upper + front-run points.
Accept the candidate only if:
- |candidate - tpIn| <= InpSRSnapTPMaxShiftATR * ATR
- candidate is still beyond the minimum stop/freeze distance
- the leg still passes its net-profit gate and, for leg 1, InpSRMaxCostToTP1Pct-equivalent check (InpMaxCostToTP1Pct)
- monotonic ordering is preserved: buys t1 < t2 < t3, sells t1 > t2 > t3
Otherwise return tpIn unchanged. Apply per leg with legIndex 1,2,3.
Run after existing NearestLiquidityTarget() snapping; if both propose a level, prefer the higher-strength SR zone when strengths are comparable, otherwise keep the closer valid target.

10) SL adjustment — SR_AdjustSL
Only when InpSRSLBehindZone=true.
For a buy: if a support zone sits between the base SL and entry, or within InpSRSLBufferATR*ATR below the base SL, move SL to zone.lower - InpSRSLBufferATR*ATR.
For a sell: mirror.
Reject the adjustment if:
- the new SL is wider than base SL by more than InpSRSLMaxExtraATR * ATR
- the new SL violates broker stop level or freeze level
- the recomputed lot for identical risk % is invalid
Never tighten the stop inside the entry candle extreme used by the existing simple-mode logic.
After any accepted widening, recompute lot size before order send.

11) Trailing
When InpSRTrailUseZones=true and the TP3 runner is active, feed SR_TrailAnchor() into the existing TP3 structure trail as an additional candidate. Choose the more conservative (closer to price in the profitable direction) of the existing swing-based anchor and the SR anchor, and continue to respect InpTP3TrailATR and InpTP3TrailStepATR. Trailing must remain monotonic; never move the stop against the position.

12) Complex-mode scoring vote
When InpSimpleScalpMode=false and InpFilterMode=FILTER_SCORING, add SR_DirectionalVote() to the filter score:
+InpSRScoreBonus when price is leaving a supportive zone in the trade direction with headroom,
-InpSRScorePenalty when price is entering an opposing wall.
This vote must never be able to satisfy InpMinFilterScore on its own; document this in the audit.

INTEGRATION POINTS (edit minimally and mark each edit with // [SR])
1. OnInit: call SR_Init() after indicator handles are created; return INIT_FAILED only if InpUseSRZones=true and a fatal allocation error occurs.
2. OnDeinit: call SR_Deinit() before existing cleanup.
3. OnTick: after existing indicator/state refresh and before signal evaluation, call SR_Rebuild().
4. Entry path (CanEnter/TryArm and the simple-mode branch): call SR_EntryAllowed() immediately before order dispatch, after all existing cost/spread/session/news gates. Log rejections through the existing rejection-reason mechanism.
5. Target construction: apply SR_AdjustTP() to t1/t2/t3 in both the simple-mode branch and BuildThreeTargets(), then re-run existing validation.
6. Stop construction: apply SR_AdjustSL() to the simple-mode stop distance result and to ComputeSL(), then recompute lot size.
7. TP3 trail: integrate SR_TrailAnchor().
8. Dashboard: add two rows using SR_PanelLine1()/SR_PanelLine2() when InpSRShowOnPanel=true. Respect InpDashRefreshMs and the existing two-column layout; do not push other rows off-panel.
9. CSV log: append columns
   sr_mode, sr_zone_count, sr_up_price, sr_up_strength, sr_up_dist_atr,
   sr_dn_price, sr_dn_strength, sr_dn_dist_atr, sr_tp_snapped, sr_sl_shifted, sr_block_reason
   Preserve existing column order; append only at the end and update the header writer.

PERFORMANCE AND SAFETY RULES
- No CopyRates or iCustom calls inside per-tick hot paths; all history reads happen inside SR_Rebuild().
- Reuse static buffers; no dynamic array resizing per tick.
- Guard every division by ATR, point, tick size, and bar count.
- Handle ATR <= 0, Bars insufficient, symbol history not synced, and CopyRates returning -1 by skipping the affected source without spamming the log.
- Chart objects: create once, update in place, all with InpSRObjPrefix, OBJPROP_BACK=true, OBJPROP_SELECTABLE=false, OBJPROP_HIDDEN=true. Throttle ChartRedraw to at most once per InpDashRefreshMs.
- Skip all drawing when MQLInfoInteger(MQL_TESTER) is true and MQL_VISUAL_MODE is false.
- SR_Deinit must remove every object it created, including on parameter change and chart close.
- Total added CPU with InpUseSRZones=true must stay under ~2 ms per rebuild on a standard M1 XAUUSD chart; log a throttled warning otherwise.

DELIVERABLES
1. Source changes implementing the SR module and the integration points.
2. presets/XAUUSD_M1_UltraScalp.set updated to include every new Inp* above with the defaults listed, while preserving all previously agreed ultra-scalp values unchanged.
3. presets/XAUUSD_M1_UltraScalp_SR_Off.set — identical, but InpUseSRZones=false, for A/B baseline testing.
4. docs/SR_Zones_Module.md containing:
   - architecture overview and data flow
   - full input reference table with ranges and tuning guidance
   - scoring formula worked example on XAUUSD
   - exact integration point list with file and function names
   - explicit statement that SR never generates entries and never increases risk
   - known limitations
5. docs/XAUUSD_M1_UltraScalp_Audit.md updated with a new "Support & Resistance" section listing which SR features are active in InpSimpleScalpMode=true.
6. A minimal unified diff summary of all source edits.
7. SR_SelfTest(): when InpSRLogLevels=true, print one formatted zone table at OnInit and every InpSRLogEveryNSeconds:
   idx | side | anchor | lower | upper | strength | touches | rej | breaks | tfMask | srcMask | fresh | broken

ACCEPTANCE CRITERIA
- Compiles clean: zero errors, zero warnings.
- With InpUseSRZones=false, a Strategy Tester run over the same period produces trade-for-trade identical results to the pre-change build.
- With InpUseSRZones=true and InpSRMode=SR_ADVISORY, entry count is unchanged versus SR off; only logging, panel output, and optional TP snapping differ.
- With InpSRMode=SR_SOFT_FILTER, entries into strong opposing zones are demonstrably rejected and logged with a parsable reason.
- No SR path can widen realized risk per trade above InpRiskPercent.
- No SR path can move a stop against an open position.
- All SR chart objects are removed on deinit; ObjectsTotal for the prefix returns 0 after removal.
- The EA still trades normally when higher timeframe history is incomplete (fresh chart, limited history) — SR degrades gracefully to fewer zones, never to a hard stop.
- InpSimpleScalpMode remains true; no new trade modes, filters, or signals were added.

Do not refactor unrelated code.
Do not change any previously configured ultra-scalp values.
Do not add external dependencies or web requests.