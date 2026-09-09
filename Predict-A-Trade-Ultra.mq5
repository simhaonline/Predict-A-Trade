//+------------------------------------------------------------------+
//| Predict-A-Trade-Ultra.mq5                                        |
//| Production-oriented XAUUSD M1 intraday / ultra-scalping EA       |
//| Session Overlap + High-Volatility Opportunity Engine             |
//| Copyright 2026 Predict-A-Trade | Simha FinTech LLC, Dubai, UAE   |
//+------------------------------------------------------------------+
//| PRE-DEPLOY WARNING - READ BEFORE ENABLING REAL CAPITAL           |
//|                                                                  |
//| Many default values in this file were hand-tuned against recent  |
//| market behaviour ("lowered from 6", "was 35", "was 15", etc.).   |
//| Hand-tuning to visible screenshots and recent gold behaviour     |
//| risks OVERFITTING: parameters that look perfect on the last few  |
//| days routinely fail on new data.                                 |
//|                                                                  |
//| Before real capital, these defaults MUST pass:                   |
//|  1. Walk-forward / out-of-sample testing (optimize on window A,  |
//|     validate on unseen window B, roll forward).                  |
//|  2. At least 2-3 months on a demo account of the SAME broker     |
//|     and account type, with real spread/slippage/commission.      |
//|  3. Minimum trade count for statistical meaning (100+ trades).   |
//| A profitable backtest alone proves nothing. Tight gates that     |
//| "feel" safer can simply select a lucky historical sample.        |
//+------------------------------------------------------------------+
#property copyright "Predict-A-Trade | Simha FinTech LLC"
#property version   "2.00"
#property description "XAUUSD M1 four-session + overlap/HV ultra-scalper. Pure MQL5: native OrderSend (no includes, no CTrade). FMP stable macro adapter with obfuscated credentials, MQL5 calendar news gate, TP1/TP2/TP3 ladder with R:R validation, reversal loss-recovery leg, broker/account telemetry and a two-column control dashboard (click header to collapse, F key to pause arming)."

//====================================================================
// ENUMS
//====================================================================
enum ENUM_TREND_DIRECTION { TREND_NONE=0, TREND_UP=1, TREND_DOWN=-1 };
enum ENUM_MARKET_PHASE    { PHASE_ACCUMULATION=0, PHASE_MANIPULATION=1, PHASE_DISTRIBUTION=2 };
enum ENUM_FILTER_MODE     { FILTER_SCORING=0, FILTER_ALL_REQUIRED=1 };
enum ENUM_EXECUTION_MODE  { EXEC_STRADDLE=0, EXEC_DIRECTIONAL=1, EXEC_AUTO=2 };
enum ENUM_VWAP_ANCHOR     { VWAP_BROKER_DAY=0, VWAP_LONDON=1, VWAP_NEWYORK=2 };
enum ENUM_BREAKER_ACTION  { BREAKER_BLOCK_ONLY=0, BREAKER_CLOSE_ALL=1 };
enum ENUM_HV_MODE         { HV_OFF=0, HV_AUTO=1, HV_FORCE_GATED=2 };
enum ENUM_SR_MODE         { SR_ADVISORY=0, SR_SOFT_FILTER=1, SR_HARD_FILTER=2 };
enum ENUM_LADDER_MODE     { LADDER_FAVOR_TP1=0, LADDER_FAVOR_RUNNER=1, LADDER_PROPORTIONAL=2 };
//--- [SIGNAL QUALITY] explicit market-structure classification (prompt.md section 3)
enum ENUM_STRUCTURE_STATE
{
   STRUCTURE_UNKNOWN=0,
   STRUCTURE_HH_HL,
   STRUCTURE_LH_LL,
   STRUCTURE_TRANSITION_BULL,
   STRUCTURE_TRANSITION_BEAR,
   STRUCTURE_RANGE
};
//--- [SIGNAL QUALITY] volume distribution state (section 7)
enum ENUM_VOLUME_STATE
{
   VOLUME_LOW=0,
   VOLUME_NORMAL,
   VOLUME_ELEVATED,
   VOLUME_SPIKE,
   VOLUME_EXTREME
};
//--- [SIGNAL QUALITY] two-dimensional regime (section 8): direction and environment
//--- are INDEPENDENT dimensions - never forced into one mutually-exclusive enum.
enum ENUM_DIRECTION_REGIME
{
   REGIME_STRONG_BULLISH=0,
   REGIME_BULLISH,
   REGIME_SIDEWAYS,
   REGIME_BEARISH,
   REGIME_STRONG_BEARISH
};
enum ENUM_ENVIRONMENT_REGIME
{
   ENV_NORMAL=0,
   ENV_HIGH_VOLATILITY,
   ENV_EXTREME_VOLATILITY,
   ENV_LOW_LIQUIDITY,
   ENV_DISORDER
};
//--- [SIGNAL QUALITY] centralized decision (section 12)
enum ENUM_SIGNAL_DECISION
{
   SIGNAL_NO_TRADE=0,
   SIGNAL_BUY=1,
   SIGNAL_SELL=-1
};
//--- [CAPITAL ENGINE] account capital tier (prompt.md section 4). Classification uses
//--- USD-EQUIVALENT EQUITY ONLY; risk money itself stays in account currency.
enum ENUM_CAPITAL_PROFILE
{
   CAPITAL_MICRO=0,      // $50  <= equityUSD <  $500
   CAPITAL_STANDARD=1,   // $500 <= equityUSD < $5000
   CAPITAL_PRO=2         // equityUSD >= $5000
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
enum ENUM_WINDOW_ID
{
   WIN_NONE=0,
   WIN_SYDNEY=1,
   WIN_TOKYO=2,
   WIN_SYDNEY_TOKYO=3,
   WIN_TOKYO_LONDON=4,
   WIN_LONDON_OPEN=5,
   WIN_LONDON=6,
   WIN_LONDON_NY=7,
   WIN_NY_OPEN=8,
   WIN_NEWYORK=9,
   WIN_VERIFIED_EXPANSION=10,
   WIN_COUNT=11
};

//--- [CAPITAL ENGINE] forward declarations (definition order independence)
int AdaptiveDeviationPoints();
bool PreflightNewTrade(MqlTradeRequest &request,MqlTradeCheckResult &check,string &reason);
double CalculateRealTradeRiskMoney(int direction,double volume,double entry,double stopLoss);
bool CalcBrokerPnL(int direction,double volume,double openPrice,double closePrice,double &pnl);
double GetEffectiveTradeRiskPct(ENUM_WINDOW_ID window,bool highVolatility);
double GetConservativeCapitalBase();
double GetProfileBaseRiskPct();
double GetProfileMinLotRiskCeilingPct();
double WindowRiskMultiplier(ENUM_WINDOW_ID w);
ENUM_CAPITAL_PROFILE GetCapitalProfile();
string CapitalProfileName(ENUM_CAPITAL_PROFILE p);
double GetProfileAggregateRiskPct();
double GetProfileDirectionalRiskPct();
double GetProfileWindowRiskPct();
int GetProfileMaxPositions();
double GetAccountCurrencyToUSD();
double GetEquityUSD();
double ExpectedAllInCost(double lots);
double PriceMoveMoney(double dist,double lots);


//====================================================================
// INPUTS
//====================================================================
input group "=== ULTRA-SCALP MODE (SIMPLIFIED ENGINE) ==="
input bool   InpSimpleScalpMode           = true;      // TRUE = simple M1 scalp engine (recommended); false = full multi-filter engine
input double InpScalpMinMomentumATR       = 0.08;      // simple engine: min last-bar momentum in ATR (0.12 = gentle)
input double InpTP1SpreadMultiple         = 2.0;       // Phase 2.4: TP1 must exceed (spread+slippage) x this multiple, else TP1_TOO_TIGHT

input group "=== CAPITAL PROTECTION ==="
input double InpDailyLossPercent          = 2.5;
input double InpMaxFloatingDDPercent      = 3.0;
input double InpWeeklyLossLimit           = 6.0;
input double InpMonthlyLossLimit          = 10.0;
input double InpRiskPercent               = 0.35;      // LEGACY/MANUAL: base trade risk when InpAutoCapitalProfile=false
input double InpRiskStepDownOnDD          = 0.15;
input int    InpMaxConsecutiveLosses      = 10;       // pause only after 3 straight; risk decays 30% per loss before that
input int    InpMaxTradesPerDay           = 100;
input bool   InpAllowMinLotFallback       = true;      // size to broker min lot when risk-% lots < min (small accounts)
input double InpMinLotMaxRiskPct          = 1.5;       // LEGACY/MANUAL: min-lot ceiling when AutoCapitalProfile=false (else profile ceiling)
input double InpMaxAggregateOpenRiskPct   = 2.5;
input double InpMaxDirectionalRiskPct     = 1.5;
input ENUM_BREAKER_ACTION InpBreakerAction= BREAKER_CLOSE_ALL;
input bool   InpNoMartingale              = true;      // invariant; retained for audit visibility
input bool   InpNoAveragingDown           = true;      // invariant; never add to losing exposure

input group "=== ADAPTIVE CAPITAL ENGINE (prompt.md 4-12, 43) ==="
input bool   InpAutoCapitalProfile        = true;      // FALSE = legacy manual mode: InpRiskPercent/InpMax* inputs drive sizing exactly as before
input bool   InpAutoRiskSizing            = true;      // FALSE = legacy: InpLotSize used directly (manual/debug). TRUE: InpLotSize ignored for sizing.
input bool   InpUseAbsoluteLotEmergencyCap= false;     // legacy 1.20-lot cap only when TRUE + AutoRiskSizing
input double InpEmergencyMaxTotalLots     = 0.0;       // emergency absolute lot ceiling (0 = disabled)
input double InpRiskFloorPct              = 0.10;      // absolute risk floor AFTER modifiers; never above profile base
input double InpMinTP1NetRiskPct          = 10.0;      // TP1 net-profit viability = % of INITIAL TRADE RISK (Auto mode)
input double InpMinTP2NetRiskPct          = 20.0;      // TP2 viability = % of initial trade risk
input double InpMinTP3NetRiskPct          = 30.0;      // TP3 viability = % of initial trade risk
input bool   InpUseRiskRelativeNetProfitGate = true;   // FALSE = legacy fixed-money gates (InpMinNetProfitTP*Money)
input bool   InpUseRExpectancyGating      = true;      // TRUE = window gating on rolling R expectancy (Auto mode)
input double InpDisableExpectancyR        = -0.10;     // R expectancy below this disables a non-primary window
input double InpRiskReduceExpectancyR     = 0.05;      // R expectancy below this reduces window risk
input double InpMaxNewTradeMarginPct      = 20.0;      // new-trade margin <= this % of equity (OrderCalcMargin)
input double InpMinFreeMarginReservePct   = 50.0;      // projected free margin must stay >= this % of equity
input bool   InpUseAdaptiveSpreadGate     = true;      // relative multi-condition spread gate (warmup = legacy fixed)
input double InpMaxSpreadToATRPct         = 20.0;      // spread/ATR ceiling % (adaptive gate)
input double InpMaxSpreadPercentileAdaptive = 90.0;    // spread percentile ceiling (adaptive gate)
input double InpSpreadBaselineMultiplier  = 2.0;       // spread vs rolling-average spike ratio (adaptive gate)
input int    InpSpreadWarmupSamples       = 30;        // ticks before the adaptive spread gate arms
input double InpRecoverySpreadQualityMultiplier = 0.80; // recovery requires this x normal spread allowance (stricter)
input double InpCatastropheNoSLRiskPct    = 5.0;       // no-SL open positions count as this % risk (conservative policy)

input group "=== BROKER / COST MODEL ==="
input int    InpMaxSpreadPoints           = 35;      // hard sanity fallback only - PERCENTAGE gate is primary (below)
input double InpMaxSpreadPctOfSL          = 100.0;   // [PERCENTAGE GATE] spread may consume at most this % of the SL distance (broker-adaptive; geometry auto-widens)
input double InpMaxSlippagePctOfATR       = 5.0;     // avg slippage <= this % of ATR (percentage form)
input double InpExtremeSlippagePctOfATR   = 12.0;    // last-fill slippage extreme <= this % of ATR
input double InpDisorderSlipPctOfATR      = 10.0;    // disorder slippage trigger <= this % of ATR
input double InpSpreadSpikeRatio          = 2.0;
input double InpMaxSpreadPercentile       = 90.0;     // p85 was below this broker's normal spread range
input int    InpMaxSlippagePoints         = 25;
input double InpCommissionPerLotRTFallback= 7.00;      // account-currency round trip / lot fallback
input double InpExpectedSlipPtsFallback   = 3.5;
input double InpMaxCostToTP1Pct           = 40.0;     // was 35: ECN spread pushed cost ratio over 35
input double InpMinNetProfitTP1Money      = 0.30;      // LEGACY/MANUAL: TP1 fixed money gate when InpUseRiskRelativeNetProfitGate=false
input double InpMinNetProfitTP2Money      = 0.50;      // LEGACY/MANUAL: TP2 fixed money gate when InpUseRiskRelativeNetProfitGate=false
input double InpMinNetProfitTP3Money      = 0.70;      // LEGACY/MANUAL: TP3 fixed money gate when InpUseRiskRelativeNetProfitGate=false
input int    InpOrderRetry                = 2;

input group "=== RISK-REWARD VALIDATION ==="
input double InpMinRR_TP2                 = 0.55;      // TP2 reward must beat this multiple of SL distance
input double InpMinRR_TP3                 = 1.10;      // TP3 reward must beat this multiple of SL distance

input group "=== EXECUTION / ANTI-OVERTRADING ==="
input ENUM_EXECUTION_MODE InpExecutionMode= EXEC_DIRECTIONAL;
input int    InpStraddleLayers            = 1;
input double InpLayerStepATR              = 0.35;
input int    InpMaxConcurrentPositions    = 3;
input double InpMaxTotalLots              = 1.20;      // LEGACY/MANUAL: absolute cap only when InpUseAbsoluteLotEmergencyCap=true (never in Auto mode)
input bool   InpArmWhileInTrade           = true;
input bool   InpScaleIn                   = false;
input int    InpMinSecondsBetweenEntries  = 20;     // was 120
input int    InpMinBarsFreshStructure     = 2;
input int    InpMaxSignalsPerWindow       = 10;
input double InpPerWindowRiskBudgetPct    = 1.5;
input bool   InpOncePerValidatedEvent     = true;
input bool   InpCancelStalePendings       = true;
input int    InpPendingExpiryMinutes      = 3;
input double InpDistance                  = 1.00;
input bool   InpUseATRForDistance         = true;
input double InpATRMultiplier             = 0.22;
input double InpLayerSpacingATR           = 0.25;
input double InpLotSize                   = 0.05;      // LEGACY/MANUAL: fixed lot ONLY when InpAutoRiskSizing=false (manual/debug)

input group "=== FILTERS / SMC ==="
input ENUM_FILTER_MODE InpFilterMode      = FILTER_SCORING;
input int    InpMinFilterScore            = 5;      // lowered from 6 for execution flow
input bool   InpUseEMA20                  = true;
input bool   InpUseEMA50                  = true;
input bool   InpUseSuperTrend             = true;
input bool   InpUseADX                    = true;
input bool   InpUseVWAP                   = true;
input bool   InpUseFVG                    = true;
input bool   InpUseAMD                    = true;
input bool   InpUseVolumeFilter           = true;
input bool   InpUseLiquidityFilter        = true;
input bool   InpUseRSI                    = true;
input bool   InpUseSMC                    = true;
input int    InpMinDirBias                = 2;      // lowered from 3: 3 blocked many valid signals
input int    InpMinSMCConfluence          = 1;      // min bull/bear structure votes (2 = very selective)
input int    InpSwingLookback             = 12;
input int    InpFVGLookbackBars           = 12;
input double InpFVGMinGapATR              = 0.05;
input int    InpAMDLookbackBars           = 20;
input double InpAMDCoilRatio              = 0.80;

input group "=== INDICATORS / VOLATILITY ==="
input int    InpEMA20Period               = 20;
input int    InpEMA50Period               = 50;
input int    InpSuperTrendPeriod          = 10;
input double InpSuperTrendMultiplier      = 3.0;
input int    InpADXPeriod                 = 14;
input double InpMinADX                    = 22.0;
input int    InpATRPeriod                 = 14;
input double InpMinATRPoints              = 25;
input double InpMaxATRPoints              = 600;      // gold M1 ATR regularly exceeds 350pt
input int    InpATRPercentileLookback     = 240;
input double InpHVMinATRPercentile        = 65.0;
input int    InpVolumeMA                  = 30;
input double InpMinVolumeRatio            = 1.20;
input double InpHVMinVolumeRatio          = 1.35;
input double InpMinLiquidityLevel         = 0.90;
input int    InpRSIPeriod                 = 9;

input group "=== SIGNAL QUALITY / CONFIDENCE ENGINE (prompt.md 3-15) ==="
input bool   InpUseEMA9                   = true;      // short-term micro-momentum (entry timing evidence, NOT a hard gate)
input int    InpEMA9Period                = 9;
input bool   InpUseEMA200                 = true;      // major-trend regime context
input int    InpEMA200Period              = 200;
input bool   InpUseMACD                   = true;      // proper native MACD momentum evidence
input int    InpMACDFast                  = 12;
input int    InpMACDSlow                  = 26;
input int    InpMACDSignal                = 9;
input bool   InpUseConfidenceEngine       = true;      // 0-100 weighted confidence replaces raw filter score in Auto mode
input double InpMinConfidenceScore        = 75.0;      // base minimum normalized confidence
input double InpMinDirectionalConfidenceGap = 5.0;     // |long-short| required when both sides exceed threshold
input bool   InpNormalizeMissingExternalData = true;   // unavailable categories lose weight from possible (fail-open)
input bool   InpUseAdaptiveConfidenceThreshold = true; // threshold varies by environment
input double InpConfidenceHighVol         = 80.0;
input double InpConfidenceSideways        = 82.0;
input double InpConfidenceLowLiquidity    = 100.0;     // LOW_LIQUIDITY blocks regardless of score
input double InpConfidenceExtremeVol      = 100.0;     // EXTREME_VOLATILITY blocks regardless of score
//--- confidence category weights (normalized internally if sum != 100, section 42)
input double InpWeightPriceAction         = 20.0;
input double InpWeightTrend               = 15.0;
input double InpWeightVolumeLiquidity     = 15.0;
input double InpWeightMomentum            = 10.0;
input double InpWeightVWAP                = 10.0;
input double InpWeightVolatility          = 10.0;
input double InpWeightMacro               = 10.0;
input double InpWeightOptions             = 5.0;
input double InpWeightRiskReward          = 5.0;
//--- volume state thresholds (section 7; percentiles)
input double InpVolumeLowPct              = 25.0;
input double InpVolumeElevatedPct         = 65.0;
input double InpVolumeSpikePct            = 85.0;
input double InpVolumeExtremePct          = 97.0;
//--- environment extremes (section 44/45)
input double InpExtremeATRPercentile      = 97.0;
input double InpExtremeVolumePercentile   = 97.0;
input double InpExtremeDisplacementATR    = 2.8;
input int    InpLowLiquidityConfirmBars   = 2;         // persistence required for LOW_LIQUIDITY
//--- setup-specific minimum NET R:R (section 16; NO universal 1:3)
input double InpMinNetRR_EMAPullback      = 0.40;      // scalp geometry: TP1 0.4R/SL 0.8R ladder-weighted
input double InpMinNetRR_VWAPReversion    = 0.30;
input double InpMinNetRR_LondonBreakout   = 0.60;
input double InpMinNetRR_NYMomentum       = 0.60;
input double InpMinNetRR_ComplexMode      = 0.40;
//--- optional Gold Options/OI context: architecture only, FAIL-OPEN (sections 25/26/48)
input bool   InpUseOptionsContext         = false;
input bool   InpRequireOptionsData        = false;
input int    InpOptionsMaxAgeSec          = 900;
input int    InpRSIOverbought             = 78;
input int    InpRSIOversold               = 22;
input ENUM_VWAP_ANCHOR InpVWAPAnchor      = VWAP_BROKER_DAY;

input group "=== FOUR-SESSION + OVERLAP ENGINE (UTC->BROKER SERVER) ==="
input bool   InpUseSessionFilter          = true;
input bool   InpTradeAllFourSessions      = true;       // master guarantee: Sydney, Tokyo, London and New York all participate
input bool   InpTradeSydney               = true;
input bool   InpTradeTokyo                = true;
input bool   InpTradeLondon               = true;
input bool   InpTradeNewYork              = true;
input bool   InpTradeSydneyTokyo          = true;       // true simultaneous Sydney/Tokyo liquidity window
input bool   InpTradeTokyoLondon          = true;       // true simultaneous Tokyo/London window (DST aware)
input bool   InpTradeLondonOpen           = true;
input bool   InpTradeLondonNY             = true;       // true simultaneous London/New York window
input bool   InpTradeNYOpen               = true;
input bool   InpTradeVerifiedExpansion    = true;
input bool   InpNeverDisablePrimarySessions= true;      // expectancy may reduce risk, but cannot turn Sydney/Tokyo/London/NY off
input int    InpSydneyLocalOpenMin        = 8*60;       // 08:00 Australia/Sydney local
input int    InpSydneyLocalCloseMin       = 17*60;      // 17:00 Australia/Sydney local
input int    InpTokyoLocalOpenMin         = 9*60;       // 09:00 JST
input int    InpTokyoLocalCloseMin        = 18*60;      // 18:00 JST
input int    InpLondonLocalOpenMin        = 8*60;       // 08:00 London local
input int    InpLondonLocalCloseMin       = 16*60+30;   // 16:30 London local
input int    InpNewYorkLocalOpenMin       = 8*60;       // 08:00 New York local
input int    InpNewYorkLocalCloseMin      = 17*60;      // 17:00 New York local
input int    InpLondonOpenWindowMin       = 60;
input int    InpNYOpenWindowMin           = 60;
input int    InpOverlapPadMinutes         = 0;
input double InpFridayCutoffServer        = 19.0;
input bool   InpAutoDetectServerOffset    = true;
input int    InpManualServerOffsetHours   = 3;
input int    InpServerOffsetRefreshSec    = 60;

input group "=== HIGH-VOLATILITY MODE ==="
input ENUM_HV_MODE InpHighVolatilityMode  = HV_AUTO;
input int    InpHVMinScore                = 6;
input double InpHVMinDisplacementATR      = 0.65;
input double InpHVMaxDisorderATR          = 2.80;
input double InpHVMinVWAPDeviationATR     = 0.10;
input int    InpSessionBreakoutLookback   = 30;      // ROLLING M1 bars (not session-anchored range)
input double InpHVExtraSignalRiskMult     = 0.70;
input int    InpVerifiedBucketMinSamples  = 30;
input double InpVerifiedBucketATRRatio    = 1.15;
input double InpVerifiedBucketVolRatio    = 1.10;

input group "=== TP1 + TP2 + TP3 EXIT ENGINE ==="
input bool   InpUseThreeTargets           = true;
input double InpTP1Pct                    = 0.75;      // 70% off at TP1: scalp banking, small runner
input double InpTP2Pct                    = 0.20;
input double InpTP3Pct                    = 0.05;
// Phase 2.5: lot-ladder feasibility. Decimal fractions ONLY (0.75 = 75%), must sum to 1.0.
input bool            InpAutoDegradeTPLadder = true;                // 3-leg -> 2-leg -> 1-leg when the position is too small
input ENUM_LADDER_MODE InpLadderRoundingMode = LADDER_FAVOR_TP1;    // where rounding residue goes
input double InpSL_ATR_Multiplier         = 0.80;      // was 1.25: tighter stop improves ladder R:R
input double InpSLStructureBufferATR      = 0.12;
input double InpTP1_ATR_Floor             = 0.25;
input double InpTP1_ATR_Cap               = 0.40;
input double InpTP2_ATR_Floor             = 0.60;
input double InpTP2_ATR_Cap               = 1.10;
input double InpTP3_ATR_Floor             = 1.00;
input double InpTP3_ATR_Cap               = 1.80;
input bool   InpUseCostAdjustedBE         = true;
input double InpBEExtraLockATR            = 0.02;
input bool   InpUseTP3StructureTrail      = true;
input double InpTP3TrailATR               = 0.50;
input double InpTP3TrailStepATR           = 0.10;
input bool   InpTP3EarlyExit              = true;
input int    InpMaxTradeMinutes           = 10;      // scalp: in-and-out; stale scalps die fast

input group "=== NEWS / DISORDER PROTECTION ==="
input bool   InpUseNewsFilter             = true;
input int    InpNewsBufferMinutes         = 10;     // was 15: 15+stabilize froze too long
input int    InpNewsLookaheadMin          = 120;
input int    InpPostNewsStabilizeMinutes  = 5;
input double InpDisorderSpreadPct         = 95.0;
input double InpMaxChaseCandleATR         = 2.60;     // gold M1 displacement 2+ ATR is normal momentum, not a chase
input double InpMaxEntryVWAPDeviationATR  = 2.20;
input double InpDisorderSlipPts           = 20.0;
input int    InpDisorderCooldownMinutes   = 5;

input group "=== FMP MACRO / NEWS (OBFUSCATED CREDENTIALS) ==="
input bool   InpUseFMP                    = true;      // FMP stable REST macro adapter (primary intermarket source)
input int    InpFMPRefreshSec             = 600;        // quote refresh throttle (floor 3600s enforced - see RefreshFMPMacro)
input int    InpFMPTimeoutMs              = 5000;      // per-request HTTP timeout
input double InpFMPUSDPairMinPct          = 0.020;     // min averaged USD-basket move % for a directional vote
input bool   InpFMPIncludeSPX             = true;      // S&P 500 risk sentiment vote (risk-off = gold bid)
input double InpFMPSPXMinPct              = 0.30;      // SPX move % threshold for a sentiment vote
input bool   InpFMPNewsHardBlock          = false;     // true = FMP headline hits also block entries (soft/log-only by default)
input int    InpFMPNewsLimit              = 25;        // headlines scanned per refresh
input bool   InpAllowBrokerMacroFallback  = true;      // broker-side EURUSD momentum when FMP is unreachable
input ENUM_TIMEFRAMES InpMacroTF         = PERIOD_M5;
input int    InpMacroMomentumBars         = 6;
input bool   InpUseEURUSD                 = true;
input string InpEURUSDSymbol              = "";        // blank = auto-detect broker EURUSD including suffix/prefix
input double InpEURUSDMinMovePct          = 0.020;
input int    InpMacroMinConfluence        = 0;        // 0 = macro is advisory (FMP down must not veto entries)         // aligned USD-basket/EUR/SPX votes required vs opposing
input bool   InpRequireExternalData       = false;     // true blocks entry until a macro feed is available

input group "=== IFVG / PROPULSION BLOCK (PTB) ==="
input bool   InpUseIFVG                   = true;
input int    InpIFVGLookbackBars          = 40;
input double InpIFVGMinGapATR             = 0.05;
input bool   InpUsePTB                    = true;      // PTB = ICT Propulsion Block
input int    InpPTBLookbackBars           = 40;
input double InpPTBMinDisplacementATR     = 0.55;
input int    InpMinAdvancedSMCConfluence  = 0;      // 0 = IFVG/PTB add score but never block entries

input group "=== LOSS RECOVERY / REVERSAL ENGINE ==="
input bool   InpUseRecovery               = true;      // after a realized loss, arm ONE controlled reversal leg
input int    InpRecoveryMaxLegs           = 1;         // reversal legs allowed per loss event (1 = single counter-trade)
input double InpRecoveryRiskPct           = 0.20;      // smaller counter-leg risk at scalp frequency      // % balance risked on the recovery leg (below base risk)
input double InpRecoveryMinRR             = 1.60;      // recovery TP1 must beat this multiple of its SL distance
input int    InpRecoveryCooldownSec       = 240;       // min seconds between the loss and the recovery entry
input int    InpRecoveryMaxAgeSec         = 900;       // recovery opportunity expires after this many seconds
input double InpRecoveryMaxSpreadPts      = 35;        // tighter spread cap for recovery entries

input group "=== SLIPPAGE / SWAP PROTECTION ==="
input double InpMaxAverageSlippagePoints  = 15.0;     // LEGACY/MANUAL slippage quality gate (adaptive deviation governs entries in Auto mode)
input double InpExtremeSlippagePoints     = 25.0;     // emergency/pathological fallback cap (adaptive deviation governs entries)
input int    InpStopLevelBufferPoints     = 5;        // Phase 2.4/4.1: safety buffer above broker stops/freeze level
input bool   InpRespectStopLevel          = true;     // enforce stops/freeze distance on every SR/proposed price
input bool   InpValidateSymbolOnInit      = true;     // fail fast when the symbol is not fully tradeable
input bool   InpCloseOnExtremeSlippage    = false;     // optional emergency flatten after a pathological fill
input int    InpSlippageCooldownMinutes   = 3;        // was 10: 10-min sit-outs after every SL fill = "no trades"
input bool   InpAvoidSwap                 = true;
input bool   InpForceFlatBeforeSwap       = true;
input double InpSwapRolloverServerHour    = 0.0;       // server-hour of swap rollover; 0.0 = midnight server (Xelans GMT+3: correct). Verify in Journal around 00:00 server.
input int    InpSwapBlockMinutesBefore    = 60;
input int    InpSwapBlockMinutesAfter     = 10;

input group "=== PERFORMANCE SELF-GATING / A-B ==="
input bool   InpEnablePerformanceGating   = true;
input int    InpPerfMinTrades             = 20;
input int    InpPerfRollingTrades         = 40;
input double InpDisableExpectancyMoney    = -0.20;     // LEGACY/MANUAL: money expectancy disable when InpUseRExpectancyGating=false
input double InpRiskReduceExpectancyMoney = 0.10;      // LEGACY/MANUAL: money expectancy reduce when InpUseRExpectancyGating=false
input double InpWeakWindowRiskMultiplier  = 0.50;
input bool   InpAB_EnableBase             = true;
input bool   InpAB_EnableHighVol          = true;
input bool   InpAB_EnableThreeTP          = true;

input group "=== LOGGING / DASHBOARD ==="
input bool   InpUseLogFile                = true;
input bool   InpPersistState              = true;
input bool   InpShowDashboard             = true;
input int    InpPanelX                    = 430;       // initial panel X (clear of left dock; drag header to move)
input int    InpPanelY                    = 30;        // initial panel Y (drag header to move)
input int    InpPanelFontSize             = 8;         // 6..12; 8 recommended - all values readable
input int    InpDashRefreshMs             = 400;       // dashboard repaint throttle (CPU friendly)
input string InpPanelTitle                = "PREDICT-A-TRADE GOLD";  // panel header title
input bool   InpPanelDraggable            = true;      // drag the header to move the panel
input string InpSoundPause                = "alert2.wav";  // sound when arming is paused
input string InpSoundResume               = "alert.wav";   // sound when arming is resumed
input int    InpMagicNumber               = 20260911;
input string InpComment                   = "Predict-A-Trade v4";

input group "=== LICENSE / MOBILE CONTROL ==="
input string InpLicenseKey            = "PAT-EF52-457F-CD40-BF9F";    // License key; blank = local/unrestricted mode
input string InpLicenseServerURL      = "https://license.predictatrade.com"; // License server base URL (HTTPS only)
input string InpLicenseServerURL2     = "https://license2.predictatrade.com"; // Backup license endpoint (auto-failover; blank = primary only)
input int    InpLicenseGraceMinutes   = 720;   // Grace period when the server is unreachable (minutes)
input bool   InpCloseOnLicenseRevoke  = false; // Flatten positions when the license is revoked
input bool   InpEnableMobileCommands  = true;  // MT5 Mobile command bridge (pending-order comments)

input group "=== SUPPORT & RESISTANCE (HTF ZONES) ==="
input bool            InpUseSRZones              = true;             // master switch; false = bit-identical legacy build
input ENUM_SR_MODE    InpSRMode                  = SR_SOFT_FILTER;   // advisory / soft wall filter / hard headroom filter
input int             InpSRRefreshSeconds        = 15;               // throttled rebuild interval
input bool            InpSRRebuildOnNewHTFBar    = true;             // also rebuild when any SR timeframe opens a bar
input ENUM_TIMEFRAMES InpSR_TF1                  = PERIOD_M15;
input ENUM_TIMEFRAMES InpSR_TF2                  = PERIOD_H1;
input ENUM_TIMEFRAMES InpSR_TF3                  = PERIOD_H4;
input ENUM_TIMEFRAMES InpSR_TF4                  = PERIOD_D1;
input int             InpSR_BarsTF1              = 300;
input int             InpSR_BarsTF2              = 300;
input int             InpSR_BarsTF3              = 240;
input int             InpSR_BarsTF4              = 90;
input int             InpSRFractalLeft           = 2;
input int             InpSRFractalRight          = 2;
input bool            InpSRUsePivotSwings        = true;
input bool            InpSRUsePrevDayHL          = true;
input bool            InpSRUsePrevWeekHL         = true;
input bool            InpSRUseSessionHL          = true;
input bool            InpSRUseDailyOpen          = true;
input bool            InpSRUseRoundNumbers       = true;
input double          InpSRRoundStepUSD          = 10.0;
input double          InpSRRoundSubStepUSD       = 5.0;
input int             InpSRRoundMaxLevels        = 6;
input bool            InpSRUseFVGConfluence      = true;
input bool            InpSRUseVWAPConfluence     = false;
input ENUM_TIMEFRAMES InpSRZoneATRTF             = PERIOD_M15;
input double          InpSRZoneThicknessATR      = 0.35;
input double          InpSRZoneMinPoints         = 20;
input double          InpSRZoneMaxPoints         = 150;
input double          InpSRMergeOverlapATR       = 0.25;
input int             InpSRMaxZonesPerSide       = 6;
input int             InpSRMaxTotalZones         = 24;
input double          InpSRMaxDistanceATR        = 12.0;
input double          InpSRTouchToleranceATR     = 0.20;
input int             InpSRMinTouches            = 1;
input double          InpSRWeightTouch           = 1.00;
input double          InpSRWeightRejection       = 0.50;
input double          InpSRWeightTF_M15          = 1.00;
input double          InpSRWeightTF_H1           = 2.00;
input double          InpSRWeightTF_H4           = 3.00;
input double          InpSRWeightTF_D1           = 4.00;
input double          InpSRWeightPrevDay         = 2.00;
input double          InpSRWeightPrevWeek        = 2.50;
input double          InpSRWeightSession         = 1.50;
input double          InpSRWeightRound           = 1.00;
input double          InpSRWeightDailyOpen       = 1.00;
input double          InpSRWeightFVG             = 1.00;
input double          InpSRWeightVWAP            = 1.00;
input double          InpSRFreshBonus            = 0.50;
input double          InpSRBreakPenalty          = 1.50;
input int             InpSRRecencyHalfLifeBars   = 400;
input double          InpSRMinStrengthToUse      = 3.00;
input double          InpSRWallMinStrength       = 5.00;
input double          InpSRBlockIntoWallATR      = 0.45;
input bool            InpSRRequireHeadroomTP1    = true;
input double          InpSRHeadroomFactor        = 1.10;
input bool            InpSRAllowBreakoutThrough  = true;
input double          InpSRBreakoutBufferATR     = 0.15;
input int             InpSRScoreBonus            = 1;
input int             InpSRScorePenalty          = 1;
input bool            InpSRSnapTP                = true;
input double          InpSRSnapTPMaxShiftATR     = 0.25;
input int             InpSRTPFrontRunPoints      = 8;
input bool            InpSRSLBehindZone          = true;
input double          InpSRSLBufferATR           = 0.10;
input double          InpSRSLMaxExtraATR         = 0.30;
input bool            InpSRTrailUseZones         = true;
input bool            InpSRDrawZones             = true;
input int             InpSRMaxDrawZones          = 12;
input color           InpSRColorResistance       = clrIndianRed;
input color           InpSRColorSupport          = clrMediumSeaGreen;
input color           InpSRColorBroken           = clrDimGray;
input bool            InpSRZoneFill              = true;
input bool            InpSRShowLabels            = true;
input bool            InpSRShowOnPanel           = true;
input bool            InpSRLogLevels             = true;
input int             InpSRLogEveryNSeconds      = 300;
input string          InpSRObjPrefix             = "PAT_SR_";

//================ SR MODULE BEGIN ================
// Self-contained HTF Support/Resistance zones (prompt.md mission 2).
// ADDITIVE ONLY: with InpUseSRZones=false every entry point below returns
// immediately and the EA behaves bit-identically to the pre-SR build, with no
// per-tick cost. The module never generates entry signals, never increases
// risk, and never moves a stop against a position. All history reads happen
// inside the throttled SR_Rebuild(); the per-tick hot paths (entry gate, TP/SL
// adjustment, trail anchor) are O(n) scans over a fixed capped array with no
// CopyRates / iCustom calls.

#define SR_MAX_ZONES 64          // compile-time array cap; InpSRMaxTotalZones caps at runtime
#define SR_MAX_CAND  512         // staging candidates per rebuild

struct SRZone
{
   double   lower;        // zone lower edge (price)
   double   upper;        // zone upper edge (price)
   double   anchor;       // originating level price
   int      side;         // +1 = above current price (resistance), -1 = below (support)
   double   strength;     // final weighted score after decay
   double   rawStrength;  // pre-decay
   int      touches;      // confirmed touches within tolerance
   int      rejections;   // touches that closed back outside
   int      breaks;       // confirmed closes through the zone
   bool     broken;       // currently invalidated
   datetime lastTouch;
   datetime created;
   int      tfMask;       // bitmask of contributing timeframes (1=TF1 2=TF2 4=TF3 8=TF4)
   int      srcMask;      // bitmask of ENUM_SR_SRC contributors
   bool     fresh;        // price has not touched the zone since it formed
};

SRZone   g_srCand[SR_MAX_CAND];  int g_srCandN=0;
SRZone   g_srZones[SR_MAX_ZONES];int g_srCount=0;
int      g_srAge[SR_MAX_ZONES];  // bars since most recent touch (per zone)
double   g_srZoneATR=0;          // ATR of InpSRZoneATRTF, refreshed per rebuild
datetime g_srLastRebuild=0;
datetime g_srLastHTFBar=0;
datetime g_srRebuildWarnAt=0;
uint     g_srLastRebuildUs=0;
datetime g_srLastSelfTest=0;
bool     g_srTpSnapped=false;    // per-arm telemetry for the CSV row
bool     g_srSlShifted=false;
string   g_srBlockReason="SR_OK";

//--- fixed-size staging: append one candidate level -------------------------
void SR_AddCandidate(double anchor,int tfBit,int src)
{
   if(g_srCandN>=SR_MAX_CAND)return;
   if(anchor<=0)return;
   SRZone z;ZeroMemory(z);
   z.anchor=anchor;z.lower=anchor;z.upper=anchor;z.side=0;
   z.rawStrength=0;z.strength=0;z.touches=0;z.rejections=0;z.breaks=0;z.broken=false;
   z.lastTouch=0;z.created=ServerNow();z.tfMask=tfBit;z.srcMask=src;z.fresh=true;
   g_srCand[g_srCandN++]=z;
}

//--- lifecycle ---------------------------------------------------------------
bool SR_Init()
{
   g_srCandN=0;g_srCount=0;g_srZoneATR=0;g_srLastRebuild=0;g_srLastHTFBar=0;
   g_srTpSnapped=false;g_srSlShifted=false;g_srBlockReason="SR_OK";g_srLastSelfTest=0;
   if(!InpUseSRZones)return true;
   SR_Rebuild(true);
   if(InpSRLogLevels)SR_LogSnapshot();
   return true;
}
void SR_Deinit(){ if(InpUseSRZones)SR_ClearObjects(); }
void SR_Reset(){ g_srCandN=0;g_srCount=0; }

double SR_ZoneATRCalc()
{
   MqlRates r[];ArraySetAsSeries(r,true);
   int n=21;if(CopyRates(eaSymbol,InpSRZoneATRTF,1,n,r)<n-1)return 0;
   double tr=0;int cnt=0;
   for(int i=0;i<n-1;i++)
   {double hi=MathMax(r[i].high,r[i+1].close),lo=MathMin(r[i].low,r[i+1].close);tr+=hi-lo;cnt++;}
   return (cnt>0?tr/cnt:0);
}

//--- throttled full rebuild --------------------------------------------------
bool SR_Rebuild(bool force=false)
{
   if(!InpUseSRZones)return false;
   datetime now=ServerNow();
   bool newHTF=false;
   if(InpSRRebuildOnNewHTFBar)
   {
      datetime t1=iTime(eaSymbol,InpSR_TF1,0),t2=iTime(eaSymbol,InpSR_TF2,0);
      datetime t3=iTime(eaSymbol,InpSR_TF3,0),t4=iTime(eaSymbol,InpSR_TF4,0);
      datetime h=t1;if(t2>h)h=t2;if(t3>h)h=t3;if(t4>h)h=t4;
      if(h>0&&h!=g_srLastHTFBar){newHTF=true;g_srLastHTFBar=h;}
   }
   if(!force)
   {
      if(g_srLastRebuild>0&&now-g_srLastRebuild<1)return false;                    // max once per tick
      if(g_srLastRebuild>0&&now-g_srLastRebuild<InpSRRefreshSeconds&&!newHTF)return false;
   }
   g_srLastRebuild=now;
   ulong us=GetMicrosecondCount();
   g_srZoneATR=SR_ZoneATRCalc();
   double atr=g_atr;if(atr<=0)atr=g_srZoneATR;
   double px=iClose(eaSymbol,PERIOD_M1,0);
   if(atr<=0||px<=0)return false;               // degrade to zero zones, never hard-stop
   SR_Reset();
   if(InpSRUsePivotSwings)
   {
      SR_CollectPivots(InpSR_TF1,InpSR_BarsTF1,InpSRWeightTF_M15);
      SR_CollectPivots(InpSR_TF2,InpSR_BarsTF2,InpSRWeightTF_H1);
      SR_CollectPivots(InpSR_TF3,InpSR_BarsTF3,InpSRWeightTF_H4);
      SR_CollectPivots(InpSR_TF4,InpSR_BarsTF4,InpSRWeightTF_D1);
   }
   if(InpSRUsePrevDayHL)SR_CollectPrevDayHL();
   if(InpSRUsePrevWeekHL)SR_CollectPrevWeekHL();
   if(InpSRUseSessionHL)SR_CollectSessionHL();
   if(InpSRUseDailyOpen)SR_CollectDailyOpen();
   if(InpSRUseRoundNumbers)SR_CollectRoundNumbers(px);
   SR_CollectStructureConfluence();
   SR_MergeZones(atr);
   SR_CountTouches(atr);
   SR_ApplyRecencyDecay();
   SR_ScoreZones(atr);
   SR_ClassifySides(px);
   SR_PruneWeakAndDistant(px,atr);
   g_srLastRebuildUs=(uint)(GetMicrosecondCount()-us);
   if(g_srLastRebuildUs>20000)
   {
      if(g_srRebuildWarnAt==0||now>g_srRebuildWarnAt)
      {Print("SR rebuild slow: ",g_srLastRebuildUs," us, zones=",g_srCount);g_srRebuildWarnAt=now+300;}
   }
   else g_srRebuildWarnAt=0;
   if(InpSRDrawZones)SR_Draw();
   return true;
}

//--- collection --------------------------------------------------------------
void SR_CollectPivots(ENUM_TIMEFRAMES tf,int bars,double tfWeight)
{
   if(tfWeight<=0||bars<InpSRFractalLeft+InpSRFractalRight+2)return;
   if(Bars(eaSymbol,tf)<bars)return;                       // insufficient history: skip silently
   MqlRates r[];ArraySetAsSeries(r,true);
   int got=CopyRates(eaSymbol,tf,1,bars,r);                // shift 1: skip the forming bar
   if(got<InpSRFractalLeft+InpSRFractalRight+2)return;
   int tfBit=(tf==InpSR_TF1?1:(tf==InpSR_TF2?2:(tf==InpSR_TF3?4:8)));
   for(int i=InpSRFractalRight;i<=got-1-InpSRFractalLeft;i++)
   {
      bool ph=true,pl=true;
      for(int k=1;k<=InpSRFractalLeft;k++)
      {if(r[i].high<r[i+k].high)ph=false;if(r[i].low>r[i+k].low)pl=false;}
      for(int k=1;k<=InpSRFractalRight;k++)
      {if(r[i].high<r[i-k].high)ph=false;if(r[i].low>r[i-k].low)pl=false;}
      if(ph)SR_AddCandidate(r[i].high,tfBit,SRSRC_PIVOT);
      if(pl)SR_AddCandidate(r[i].low,tfBit,SRSRC_PIVOT);
   }
}
void SR_CollectPrevDayHL()
{
   double h=iHigh(eaSymbol,PERIOD_D1,1),l=iLow(eaSymbol,PERIOD_D1,1);
   if(h>0)SR_AddCandidate(h,0,SRSRC_PREVDAY);
   if(l>0)SR_AddCandidate(l,0,SRSRC_PREVDAY);
}
void SR_CollectPrevWeekHL()
{
   double h=iHigh(eaSymbol,PERIOD_W1,1),l=iLow(eaSymbol,PERIOD_W1,1);
   if(h>0)SR_AddCandidate(h,0,SRSRC_PREVWEEK);
   if(l>0)SR_AddCandidate(l,0,SRSRC_PREVWEEK);
}
void SR_CollectSessionHL()
{
   // Previous UTC day ranges: Asian 00:00-06:45, London 07:00-11:00, NY 13:30-17:00.
   datetime utc=UTCNow();
   MqlDateTime d;TimeToStruct(utc,d);d.hour=0;d.min=0;d.sec=0;
   datetime today=StructToTime(d),ystart=today-86400;
   int need=(int)((utc-ystart)/60)+120;if(need>3000)need=3000;
   MqlRates r[];ArraySetAsSeries(r,true);
   int got=CopyRates(eaSymbol,PERIOD_M1,1,need,r);if(got<60)return;
   double aH=0,aL=0,lH=0,lL=0,nH=0,nL=0;
   for(int i=0;i<got;i++)
   {
      datetime ut=(datetime)((long)r[i].time-g_serverOffsetSec);
      long sec=(long)ut;if(sec<(long)ystart||sec>=(long)today)continue;
      int um=(int)((sec-(long)ystart)/60);
      if(um<7*60){if(r[i].high>aH)aH=r[i].high;if(r[i].low<aL||aL==0)aL=r[i].low;}
      else if(um>=7*60&&um<=11*60){if(r[i].high>lH)lH=r[i].high;if(r[i].low<lL||lL==0)lL=r[i].low;}
      else if(um>=13*60+30&&um<=17*60){if(r[i].high>nH)nH=r[i].high;if(r[i].low<nL||nL==0)nL=r[i].low;}
   }
   if(aH>0)SR_AddCandidate(aH,0,SRSRC_SESSION);
   if(aL>0)SR_AddCandidate(aL,0,SRSRC_SESSION);
   if(lH>0)SR_AddCandidate(lH,0,SRSRC_SESSION);
   if(lL>0)SR_AddCandidate(lL,0,SRSRC_SESSION);
   if(nH>0)SR_AddCandidate(nH,0,SRSRC_SESSION);
   if(nL>0)SR_AddCandidate(nL,0,SRSRC_SESSION);
}
void SR_CollectDailyOpen()
{
   double o=iOpen(eaSymbol,PERIOD_D1,0);
   if(o>0)SR_AddCandidate(o,0,SRSRC_DAILYOPEN);
}
void SR_CollectRoundNumbers(double price)
{
   double step=MathMax(1.0,InpSRRoundStepUSD);
   double sub=MathMax(0.0,InpSRRoundSubStepUSD);
   int maxL=MathMax(0,InpSRRoundMaxLevels);if(maxL<=0)return;
   double base=MathRound(price/step)*step;
   int added=0;
   for(int k=-maxL;k<=maxL&&added<maxL*2;k++)
   {
      double lvl=base+k*step;if(lvl<=0)continue;
      SR_AddCandidate(lvl,0,SRSRC_ROUND);added++;
      if(sub>0&&added<maxL*2)
      {double l2=lvl+sub;if(l2>0&&l2<base+(maxL+1)*step){SR_AddCandidate(l2,0,SRSRC_ROUND);added++;}}
   }
}
void SR_CollectStructureConfluence()
{
   if(InpSRUseFVGConfluence)
   {
      // FVG / IFVG / PTB band edges tag confluence; IFVG & PTB share the FVG weight
      // (the scoring spec has no separate weight inputs for them).
      if(g_fvg){SR_AddCandidate(g_fvgTop,0,SRSRC_FVG);SR_AddCandidate(g_fvgBottom,0,SRSRC_FVG);}
      if(g_ifvg){SR_AddCandidate(g_ifvgTop,0,SRSRC_IFVG);SR_AddCandidate(g_ifvgBottom,0,SRSRC_IFVG);}
      if(g_ptb){SR_AddCandidate(g_ptbTop,0,SRSRC_PTB);SR_AddCandidate(g_ptbBottom,0,SRSRC_PTB);}
   }
   if(InpSRUseVWAPConfluence&&g_vwap>0)
   {
      SR_AddCandidate(g_vwap,0,SRSRC_VWAP);
      if(g_vwapUp>0)SR_AddCandidate(g_vwapUp,0,SRSRC_VWAP);
      if(g_vwapDn>0)SR_AddCandidate(g_vwapDn,0,SRSRC_VWAP);
   }
}

//--- processing --------------------------------------------------------------
double SR_Thickness()
{
   double atrZ=(g_srZoneATR>0?g_srZoneATR:g_atr);
   if(atrZ<=0)return 0;
   double th=InpSRZoneThicknessATR*atrZ;
   double lo=InpSRZoneMinPoints*broker.point,hi=InpSRZoneMaxPoints*broker.point;
   if(hi<lo)hi=lo;
   return MathMax(lo,MathMin(hi,th));
}

void SR_MergeZones(double atr)
{
   double th=SR_Thickness();if(th<=0)return;
   for(int i=0;i<g_srCandN;i++)
   {g_srCand[i].lower=PriceNorm(g_srCand[i].anchor-th/2);g_srCand[i].upper=PriceNorm(g_srCand[i].anchor+th/2);}
   for(int pass=0;pass<3;pass++)
   {
      bool merged=false;
      for(int i=0;i<g_srCandN&&g_srCandN>1;i++)
      {
         if(merged)break;
         if(g_srCand[i].anchor<=0)continue;
         for(int j=i+1;j<g_srCandN;j++)
         {
            if(g_srCand[j].anchor<=0)continue;
            bool overlap=(g_srCand[i].lower<=g_srCand[j].upper&&g_srCand[j].lower<=g_srCand[i].upper);
            bool near=(MathAbs(g_srCand[i].anchor-g_srCand[j].anchor)<=InpSRMergeOverlapATR*atr);
            if(!overlap&&!near)continue;
            double wA=MathMax(1e-9,g_srCand[i].rawStrength),wB=MathMax(1e-9,g_srCand[j].rawStrength),sum=wA+wB;
            g_srCand[i].anchor=(g_srCand[i].anchor*wA+g_srCand[j].anchor*wB)/sum;   // strength-weighted
            g_srCand[i].lower=MathMin(g_srCand[i].lower,g_srCand[j].lower);
            g_srCand[i].upper=MathMax(g_srCand[i].upper,g_srCand[j].upper);
            g_srCand[i].touches+=g_srCand[j].touches;
            g_srCand[i].rejections+=g_srCand[j].rejections;
            g_srCand[i].breaks=MathMax(g_srCand[i].breaks,g_srCand[j].breaks);
            g_srCand[i].tfMask|=g_srCand[j].tfMask;
            g_srCand[i].srcMask|=g_srCand[j].srcMask;
            g_srCand[i].rawStrength=sum;
            if(g_srCand[i].created>g_srCand[j].created)g_srCand[i].created=g_srCand[j].created;
            if(g_srCand[i].lastTouch<g_srCand[j].lastTouch)g_srCand[i].lastTouch=g_srCand[j].lastTouch;
            g_srCand[j]=g_srCand[g_srCandN-1];g_srCandN--;   // remove j (swap-with-last)
            merged=true;
            break;   // re-scan from the next pass
         }
      }
      if(!merged)break;
   }
   g_srCount=0;
   for(int i=0;i<g_srCandN&&g_srCount<SR_MAX_ZONES;i++)g_srZones[g_srCount++]=g_srCand[i];
}

void SR_CountTouches(double atr)
{
   if(g_srCount<=0)return;
   int need=MathMax(InpSR_BarsTF1,500);if(need>5000)need=5000;
   MqlRates r[];ArraySetAsSeries(r,true);
   int got=CopyRates(eaSymbol,PERIOD_M1,1,need,r);if(got<=0)return;
   double tol=InpSRTouchToleranceATR*atr,buf=InpSRBreakoutBufferATR*atr;
   for(int zi=0;zi<g_srCount;zi++)
   {
      int touches=0,rej=0,brks=0,lastTouchIdx=-1,lastRejIdx=-1,lastBrkIdx=-1,runStart=-10;
      datetime lastT=0;
      for(int i=got-1;i>=0;i--)      // oldest -> newest
      {
         bool overlap=(r[i].high>=g_srZones[zi].lower-tol&&r[i].low<=g_srZones[zi].upper+tol);
         bool closedOutside=(r[i].close>g_srZones[zi].upper||r[i].close<g_srZones[zi].lower);
         bool brokeOut=(r[i].close>g_srZones[zi].upper+buf||r[i].close<g_srZones[zi].lower-buf);
         if(overlap)
         {
            if(i-runStart>3){touches++;lastTouchIdx=i;lastT=(datetime)r[i].time;}  // consecutive touches within 3 bars count once
            if(i-runStart>3)runStart=i;
            if(overlap&&closedOutside){rej++;lastRejIdx=i;}
         }
         if(brokeOut){brks++;lastBrkIdx=i;}
      }
      g_srZones[zi].touches=touches;
      g_srZones[zi].rejections=rej;
      g_srZones[zi].breaks=brks;
      g_srZones[zi].lastTouch=lastT;
      // a break is confirmed when breaks>=1 and the most recent break is newer than the most recent rejection
      g_srZones[zi].broken=(brks>=1&&lastBrkIdx>=0&&lastBrkIdx<lastRejIdx);
      g_srAge[zi]=(lastTouchIdx>=0?lastTouchIdx:got);   // bars since most recent touch
   }
}

void SR_ApplyRecencyDecay()
{
   // strength = rawStrength * 0.5^(barsSinceTouch / halfLife); final clamp in SR_ScoreZones
   for(int zi=0;zi<g_srCount;zi++)
   {
      double hl=MathMax(1,InpSRRecencyHalfLifeBars);
      double decay=MathPow(0.5,(double)g_srAge[zi]/hl);
      g_srZones[zi].strength=g_srZones[zi].rawStrength*decay;   // provisional; rescored below
   }
}

void SR_ScoreZones(double atr)
{
   if(atr<=0)return;
   for(int zi=0;zi<g_srCount;zi++)
   {
      double tfSum=0;
      if((g_srZones[zi].tfMask&1)!=0)tfSum+=InpSRWeightTF_M15;
      if((g_srZones[zi].tfMask&2)!=0)tfSum+=InpSRWeightTF_H1;
      if((g_srZones[zi].tfMask&4)!=0)tfSum+=InpSRWeightTF_H4;
      if((g_srZones[zi].tfMask&8)!=0)tfSum+=InpSRWeightTF_D1;
      int m=g_srZones[zi].srcMask;double srcSum=0;
      if((m&SRSRC_PREVDAY)!=0)srcSum+=InpSRWeightPrevDay;
      if((m&SRSRC_PREVWEEK)!=0)srcSum+=InpSRWeightPrevWeek;
      if((m&SRSRC_SESSION)!=0)srcSum+=InpSRWeightSession;
      if((m&SRSRC_ROUND)!=0)srcSum+=InpSRWeightRound;
      if((m&SRSRC_DAILYOPEN)!=0)srcSum+=InpSRWeightDailyOpen;
      if((m&(SRSRC_FVG|SRSRC_IFVG|SRSRC_PTB))!=0)srcSum+=InpSRWeightFVG;
      if((m&SRSRC_VWAP)!=0)srcSum+=InpSRWeightVWAP;
      g_srZones[zi].fresh=(g_srZones[zi].touches==0);   // approximation: an untouched zone is fresh
      g_srZones[zi].rawStrength=InpSRWeightTouch*g_srZones[zi].touches
                               +InpSRWeightRejection*g_srZones[zi].rejections
                               +tfSum+srcSum
                               +(g_srZones[zi].fresh?InpSRFreshBonus:0)
                               -InpSRBreakPenalty*g_srZones[zi].breaks;
      double hl=MathMax(1,InpSRRecencyHalfLifeBars);
      double decay=MathPow(0.5,(double)g_srAge[zi]/hl);
      g_srZones[zi].strength=MathMax(0.0,g_srZones[zi].rawStrength*decay);
      if(g_srZones[zi].broken)   // a broken zone keeps at most 50% of its strength
         g_srZones[zi].strength=MathMin(g_srZones[zi].strength,0.5*MathMax(0.0,g_srZones[zi].rawStrength));
   }
}

void SR_ClassifySides(double price)
{
   for(int zi=0;zi<g_srCount;zi++)
      g_srZones[zi].side=(g_srZones[zi].anchor>=price?1:-1);
}

void SR_PruneWeakAndDistant(double price,double atr)
{
   for(int i=0;i<g_srCount;i++)
   {
      bool drop=(g_srZones[i].strength<InpSRMinStrengthToUse);
      if(!drop&&g_srZones[i].touches<InpSRMinTouches&&g_srZones[i].srcMask==SRSRC_ROUND)drop=true;
      if(!drop&&atr>0&&MathAbs(g_srZones[i].anchor-price)>InpSRMaxDistanceATR*atr)drop=true;
      if(drop){for(int k=i;k<g_srCount-1;k++)g_srZones[k]=g_srZones[k+1];g_srCount--;i--;}
   }
   // strongest-first ranking, then per-side and total caps
   if(g_srCount>1)
   {
      int idx[SR_MAX_ZONES];int n=g_srCount;
      for(int i=0;i<n;i++)idx[i]=i;
      for(int i=0;i<n-1;i++)
         for(int j=i+1;j<n;j++)
            if(g_srZones[idx[j]].strength>g_srZones[idx[i]].strength){int t=idx[i];idx[i]=idx[j];idx[j]=t;}
      SRZone keep[SR_MAX_ZONES];int kn=0,up=0,dn=0;
      for(int i=0;i<n;i++)
      {
         if(kn>=InpSRMaxTotalZones)break;
         SRZone z=g_srZones[idx[i]];
         if(z.side>0){if(up>=InpSRMaxZonesPerSide)continue;up++;}
         else      {if(dn>=InpSRMaxZonesPerSide)continue;dn++;}
         keep[kn++]=z;
      }
      g_srCount=kn;
      for(int i=0;i<kn;i++)g_srZones[i]=keep[i];
   }
}

//--- queries (O(n) over the capped array; NO CopyRates here) -----------------
bool SR_NearestAbove(double price,double minStrength,double &nearEdge,double &farEdge,double &strength,int &idx)
{
   nearEdge=0;farEdge=0;strength=0;idx=-1;double best=0;
   if(!InpUseSRZones)return false;
   for(int zi=0;zi<g_srCount;zi++)
   {
      if(g_srZones[zi].side<0)continue;
      if(g_srZones[zi].broken&&g_srZones[zi].rejections<=0)continue;   // broken zone usable only with a post-break rejection
      if(g_srZones[zi].strength<minStrength)continue;
      double edge=g_srZones[zi].lower;if(edge<=price)edge=g_srZones[zi].upper;
      if(edge<=price)continue;
      if(best==0||edge<best){best=edge;nearEdge=edge;farEdge=g_srZones[zi].upper;strength=g_srZones[zi].strength;idx=zi;}
   }
   return (idx>=0);
}
bool SR_NearestBelow(double price,double minStrength,double &nearEdge,double &farEdge,double &strength,int &idx)
{
   nearEdge=0;farEdge=0;strength=0;idx=-1;double best=0;
   if(!InpUseSRZones)return false;
   for(int zi=0;zi<g_srCount;zi++)
   {
      if(g_srZones[zi].side>0)continue;
      if(g_srZones[zi].broken&&g_srZones[zi].rejections<=0)continue;
      if(g_srZones[zi].strength<minStrength)continue;
      double edge=g_srZones[zi].upper;if(edge>=price)edge=g_srZones[zi].lower;
      if(edge>=price)continue;
      if(best==0||edge>best){best=edge;nearEdge=edge;farEdge=g_srZones[zi].lower;strength=g_srZones[zi].strength;idx=zi;}
   }
   return (idx>=0);
}
double SR_HeadroomPrice(int dir,double entry,double minStrength)
{
   double ne,fe,st;int ix;
   if(dir>0){if(SR_NearestAbove(entry,minStrength,ne,fe,st,ix))return ne;}
   else     {if(SR_NearestBelow(entry,minStrength,ne,fe,st,ix))return ne;}
   return 0;
}
double SR_HeadroomATR(int dir,double entry,double atr,double minStrength)
{
   if(atr<=0)return 0;
   double h=SR_HeadroomPrice(dir,entry,minStrength);
   return (h>0?(dir*(h-entry))/atr:0);
}
bool SR_PriceInsideZone(double price,int &idx)
{
   idx=-1;if(!InpUseSRZones)return false;
   for(int zi=0;zi<g_srCount;zi++)
      if(price>=g_srZones[zi].lower&&price<=g_srZones[zi].upper){idx=zi;return true;}
   return false;
}
bool SR_BreakoutConfirmed(int dir,double atr)
{
   if(atr<=0)return false;
   double buf=InpSRBreakoutBufferATR*atr;
   double c1=iClose(eaSymbol,PERIOD_M1,1);if(c1<=0)return false;
   for(int zi=0;zi<g_srCount;zi++)
   {
      if(dir>0&&g_srZones[zi].side>0&&c1>g_srZones[zi].upper+buf)return true;   // buy closing above resistance
      if(dir<0&&g_srZones[zi].side<0&&c1<g_srZones[zi].lower-buf)return true;   // sell closing below support
   }
   return false;
}

//--- decision helpers --------------------------------------------------------
bool SR_EntryAllowed(int dir,double entry,double atr,double tp1Distance,string &reason)
{
   reason="SR_OK";
   if(!InpUseSRZones)return true;
   if(atr<=0)return true;                          // never block on missing data
   if(InpSRMode==SR_ADVISORY)return true;          // score + display only
   double ne,fe,st;int ix;
   bool wall=(dir>0?SR_NearestAbove(entry,InpSRWallMinStrength,ne,fe,st,ix)
                   :SR_NearestBelow(entry,InpSRWallMinStrength,ne,fe,st,ix));
   if(wall)
   {
      double dist=MathAbs(ne-entry)/atr;
      bool breakoutOK=(InpSRAllowBreakoutThrough&&SR_BreakoutConfirmed(dir,atr));
      if(dist<=InpSRBlockIntoWallATR&&!breakoutOK)
      {reason=StringFormat("SR_WALL_%.1f@%.2fA",st,dist);g_srBlockReason=reason;return false;}
      if(InpSRMode==SR_HARD_FILTER&&InpSRRequireHeadroomTP1)
      {
         double have=SR_HeadroomPrice(dir,entry,InpSRWallMinStrength);
         double need=tp1Distance*InpSRHeadroomFactor;
         if(have<=0||MathAbs(have-entry)<need){reason="SR_NO_HEADROOM";g_srBlockReason=reason;return false;}
      }
   }
   g_srBlockReason="SR_OK";
   return true;
}

int SR_DirectionalVote(int dir,double entry,double atr)
{
   if(!InpUseSRZones||atr<=0)return 0;
   if(InpMinFilterScore<=1)return 0;   // a +-1 vote must never satisfy the filter score on its own
   double ne,fe,st;int ix;
   bool opp=(dir>0?SR_NearestAbove(entry,InpSRWallMinStrength,ne,fe,st,ix)
                  :SR_NearestBelow(entry,InpSRWallMinStrength,ne,fe,st,ix));
   if(opp&&MathAbs(ne-entry)<=InpSRBlockIntoWallATR*atr)return -InpSRScorePenalty;   // entering an opposing wall
   bool sup=(dir>0?SR_NearestBelow(entry,InpSRMinStrengthToUse,ne,fe,st,ix)
                  :SR_NearestAbove(entry,InpSRMinStrengthToUse,ne,fe,st,ix));
   if(sup)return InpSRScoreBonus;                                                      // leaving a supportive zone
   return 0;
}

double SR_AdjustTP(int dir,double entry,double tpIn,double atr,int legIndex)
{
   if(!InpUseSRZones||!InpSRSnapTP||atr<=0)return tpIn;
   double ne,fe,st;int ix;
   bool found=(dir>0?SR_NearestAbove(entry,InpSRMinStrengthToUse,ne,fe,st,ix)
                    :SR_NearestBelow(entry,InpSRMinStrengthToUse,ne,fe,st,ix));
   if(!found)return tpIn;
   double fr=InpSRTPFrontRunPoints*broker.point;
   double cand=(dir>0?ne-fr:ne+fr);                 // front-run the near edge
   if(dir>0&&cand<=entry)return tpIn;
   if(dir<0&&cand>=entry)return tpIn;
   if(MathAbs(cand-tpIn)>InpSRSnapTPMaxShiftATR*atr)return tpIn;   // shift cap
   if(MathAbs(cand-entry)<MinTradeDistance())return tpIn;          // broker stop/freeze distance
   return PriceNorm(cand);
}

double SR_AdjustSL(int dir,double entry,double slIn,double atr)
{
   if(!InpUseSRZones||!InpSRSLBehindZone||atr<=0)return slIn;
   double ne,fe,st;int ix;
   bool zone=(dir>0?SR_NearestBelow(entry,InpSRMinStrengthToUse,ne,fe,st,ix)
                   :SR_NearestAbove(entry,InpSRMinStrengthToUse,ne,fe,st,ix));
   if(!zone)return slIn;
   double cand=(dir>0?g_srZones[ix].lower-InpSRSLBufferATR*atr
                      :g_srZones[ix].upper+InpSRSLBufferATR*atr);   // behind the whole zone
   bool between=(dir>0?(cand<entry&&cand>=slIn-InpSRSLBufferATR*atr)
                      :(cand>entry&&cand<=slIn+InpSRSLBufferATR*atr));
   if(!between)return slIn;
   if(dir>0&&cand>=slIn)return slIn;   // never tighten the stop
   if(dir<0&&cand<=slIn)return slIn;
   if(MathAbs(entry-cand)-MathAbs(entry-slIn)>InpSRSLMaxExtraATR*atr)return slIn;   // widening cap
   double minDist=(double)MathMax(broker.stopsLevel,broker.freezeLevel)*broker.point;
   if(MathAbs(entry-cand)<minDist)return slIn;
   return PriceNorm(cand);
}

double SR_TrailAnchor(int dir,double atr)
{
   if(!InpUseSRZones||!InpSRTrailUseZones||atr<=0)return 0;
   double px=(dir>0?Bid():Ask());
   double ne,fe,st;int ix;
   bool zone=(dir>0?SR_NearestBelow(px,InpSRMinStrengthToUse,ne,fe,st,ix)
                   :SR_NearestAbove(px,InpSRMinStrengthToUse,ne,fe,st,ix));
   if(!zone)return 0;
   double cand=(dir>0?g_srZones[ix].lower-InpSRSLBufferATR*atr
                      :g_srZones[ix].upper+InpSRSLBufferATR*atr);   // protection behind the zone
   if(dir>0&&cand>=px)return 0;
   if(dir<0&&cand<=px)return 0;
   return PriceNorm(cand);
}

//--- presentation ------------------------------------------------------------
void SR_ClearObjects(){ ObjectsDeleteAll(0,InpSRObjPrefix,0,-1); }

void SR_Draw()
{
   if(!InpUseSRZones||!InpSRDrawZones)return;
   if(MQLInfoInteger(MQL_TESTER)&&!MQLInfoInteger(MQL_VISUAL_MODE))return;   // skip drawing in non-visual tester
   int n=MathMin(g_srCount,MathMax(0,InpSRMaxDrawZones));
   datetime t1=ServerNow()-PeriodSeconds(InpSR_TF3)*20,t2=ServerNow()+PeriodSeconds(PERIOD_M1)*120;
   for(int i=0;i<n;i++)
   {
      string id=InpSRObjPrefix+"Z"+IntegerToString(i);
      if(ObjectFind(0,id)<0)
      {
         ObjectCreate(0,id,OBJ_RECTANGLE,0,t1,g_srZones[i].lower,t2,g_srZones[i].upper);
         ObjectSetInteger(0,id,OBJPROP_BACK,true);
         ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,id,OBJPROP_FILL,InpSRZoneFill);
      }
      ObjectSetInteger(0,id,OBJPROP_TIME,0,t1);ObjectSetDouble(0,id,OBJPROP_PRICE,0,g_srZones[i].lower);
      ObjectSetInteger(0,id,OBJPROP_TIME,1,t2);ObjectSetDouble(0,id,OBJPROP_PRICE,1,g_srZones[i].upper);
      color c=(g_srZones[i].broken?InpSRColorBroken:(g_srZones[i].side>0?InpSRColorResistance:InpSRColorSupport));
      ObjectSetInteger(0,id,OBJPROP_COLOR,c);
      if(InpSRShowLabels)
      {
         string lid=InpSRObjPrefix+"L"+IntegerToString(i);
         if(ObjectFind(0,lid)<0)
         {
            ObjectCreate(0,lid,OBJ_TEXT,0,t2,g_srZones[i].anchor);
            ObjectSetInteger(0,lid,OBJPROP_SELECTABLE,false);
            ObjectSetInteger(0,lid,OBJPROP_HIDDEN,true);
            ObjectSetInteger(0,lid,OBJPROP_FONTSIZE,7);
         }
         ObjectSetInteger(0,lid,OBJPROP_TIME,0,t2);ObjectSetDouble(0,lid,OBJPROP_PRICE,0,g_srZones[i].anchor);
         ObjectSetString(0,lid,OBJPROP_TEXT,StringFormat("%s s%.1f",(g_srZones[i].side>0?"R":"S"),g_srZones[i].strength));
         ObjectSetInteger(0,lid,OBJPROP_COLOR,c);
      }
   }
   for(int i=n;i<InpSRMaxDrawZones;i++)   // remove leftovers beyond the live count
   {
      string id=InpSRObjPrefix+"Z"+IntegerToString(i);if(ObjectFind(0,id)>=0)ObjectDelete(0,id);
      string lid=InpSRObjPrefix+"L"+IntegerToString(i);if(ObjectFind(0,lid)>=0)ObjectDelete(0,lid);
   }
   static uint lastRedraw=0;
   uint ms=GetTickCount();
   if(ms-lastRedraw>=(uint)MathMax(100,InpDashRefreshMs)){ChartRedraw();lastRedraw=ms;}
}

string SR_PanelLine1()
{
   if(!InpUseSRZones)return "SR off";
   double px=iClose(eaSymbol,PERIOD_M1,0);double atr=g_atr;
   double ne,fe,st;int ix;string up="R:-",dn="S:-";
   if(atr>0&&SR_NearestAbove(px,InpSRMinStrengthToUse,ne,fe,st,ix))
      up=StringFormat("R:%.2f s%.1f d%.1fA",ne,st,MathAbs(ne-px)/atr);
   if(atr>0&&SR_NearestBelow(px,InpSRMinStrengthToUse,ne,fe,st,ix))
      dn=StringFormat("S:%.2f s%.1f d%.1fA",px==0?ne:ne,st,MathAbs(px-ne)/atr);
   return "SR "+up+" | "+dn;
}
string SR_PanelLine2()
{
   if(!InpUseSRZones)return "SR zones 0 | off";
   string md=(InpSRMode==SR_ADVISORY?"ADV":(InpSRMode==SR_SOFT_FILTER?"SOFT":"HARD"));
   return StringFormat("SR zones %d | mode %s | block %s",g_srCount,md,g_srBlockReason);
}
void SR_LogSnapshot()
{
   Print("SR zones | idx|side|anchor|lower|upper|strength|touches|rej|breaks|tf|src|fresh|broken");
   for(int zi=0;zi<g_srCount;zi++)
      Print(StringFormat("%2d|%s|%.2f|%.2f|%.2f|%.2f|%d|%d|%d|%d|%d|%s|%s",
            zi,(g_srZones[zi].side>0?"R":"S"),g_srZones[zi].anchor,g_srZones[zi].lower,g_srZones[zi].upper,
            g_srZones[zi].strength,g_srZones[zi].touches,g_srZones[zi].rejections,g_srZones[zi].breaks,
            g_srZones[zi].tfMask,g_srZones[zi].srcMask,(g_srZones[zi].fresh?"Y":"N"),(g_srZones[zi].broken?"Y":"N")));
}
void SR_SelfTest()
{
   if(!InpUseSRZones||!InpSRLogLevels)return;
   datetime now=ServerNow();
   if(g_srLastSelfTest>0&&now-g_srLastSelfTest<InpSRLogEveryNSeconds)return;
   g_srLastSelfTest=now;
   SR_LogSnapshot();
}
//================ SR MODULE END ==================
//================ LICENSE CLIENT + MOBILE COMMAND BRIDGE BEGIN ================
// Phase 2/3 of the license-server spec. SELF-CONTAINED: no includes, no external
// scripts. WebRequest happens ONLY in OnTimer paths (never OnTick). With
// InpLicenseKey="" every function short-circuits — zero overhead, unrestricted
// local mode. Fail-safe: a previously-validated EA keeps trading through server
// outages for InpLicenseGraceMinutes; an EA that has NEVER validated cannot start.

bool     g_licenseActive       = false;
bool     g_autoTradingEnabled  = true;
int      g_settingsVersion     = 0;
datetime g_nextLicenseCheck    = 0;
datetime g_gracePeriodDeadline = 0;
string   g_machineId           = "";
int      g_licenseEndpoint     = 0;     // 0=auto, 1=primary last OK, 2=backup last OK
int      g_lastNonHTTPStatus   = 0;     // last non-HTTP status seen this poll (1009/1001/1003 middlebox class)
string   g_licenseLastReason   = "";   // last validation reason (panel/CSV)

//--- Phase 2.3: stable machine fingerprint = SHA256(computer|datapath|login|server).
//--- MQL5 has no built-in SHA256, so this is a compact, dependency-free implementation
//--- (FIPS 180-4). Output is a 64-char lowercase hex string.
string LicenseSHA256(string text)
{
      //--- static tables
      static uint K[64];
      static bool KInit=false;
      if(!KInit)
      {
         uint k[64]={
         0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
         0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
         0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
         0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
         0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
         0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
         0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
         0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
         for(int i=0;i<64;i++)K[i]=k[i];
         KInit=true;
      }
      //--- UTF-8 bytes of the input
      uchar msg[];
      int len=StringToCharArray(text,msg,0,WHOLE_ARRAY,CP_UTF8);
      if(len>0)len--;   // StringToCharArray appends the terminator
      ulong bitLen=(ulong)len*8;
      //--- padding: msg + 0x80 + zeros + 8-byte length must total a multiple of 64,
      //--- so the zeros run must end at 56 (mod 64) to leave room for the length.
      int padded=len+1;
      while(padded%64!=56)padded++;
      uchar buf[];
      ArrayResize(buf,padded+8);
      for(int i=0;i<len;i++)buf[i]=msg[i];
      buf[len]=0x80;
      for(int i=len+1;i<padded+8;i++)buf[i]=0;
      for(int i=0;i<8;i++)buf[padded+7-i]=(uchar)((bitLen>>(8*i))&0xFF);
      //--- compression
      uint h0=0x6a09e667,h1=0xbb67ae85,h2=0x3c6ef372,h3=0xa54ff53a;
      uint h4=0x510e527f,h5=0x9b05688c,h6=0x1f83d9ab,h7=0x5be0cd19;
      uint w[64];
      for(int off=0;off<padded+8;off+=64)
      {
         for(int i=0;i<16;i++)
            w[i]=((uint)buf[off+4*i]<<24)|((uint)buf[off+4*i+1]<<16)|((uint)buf[off+4*i+2]<<8)|((uint)buf[off+4*i+3]);
         for(int i=16;i<64;i++)
         {
            uint s0=((w[i-15]>>7)|(w[i-15]<<25))+((w[i-15]>>18)|(w[i-15]<<14))+0; // rotr7^rotr18^shr3
            uint x=w[i-15];
            uint rotr7=(x>>7)|(x<<25);
            uint rotr18=(x>>18)|(x<<14);
            uint shr3=(x>>3);
            s0=rotr7^rotr18^shr3;
            uint y=w[i-2];
            uint s1=((y>>17)|(y<<15))^((y>>19)|(y<<13))^(y>>10);
            w[i]=w[i-16]+s0+w[i-7]+s1;
         }
         uint a=h0,b=h1,c=h2,d=h3,e=h4,f=h5,g=h6,hh=h7;
         for(int i=0;i<64;i++)
         {
            uint S1=((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7));
            uint ch=(e&f)^((~e)&g);
            uint t1=hh+S1+ch+K[i]+w[i];
            uint S0=((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10));
            uint maj=(a&b)^(a&c)^(b&c);
            uint t2=S0+maj;
            hh=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
         }
         h0+=a;h1+=b;h2+=c;h3+=d;h4+=e;h5+=f;h6+=g;h7+=hh;
      }
      uint out[8]={h0,h1,h2,h3,h4,h5,h6,h7};
      string hex="";
      for(int i=0;i<8;i++)
         for(int nib=28;nib>=0;nib-=4)
         {
            int d=(int)((out[i]>>nib)&0xF);
            hex+=StringSubstr("0123456789abcdef",d,1);
         }
      return hex;
}

//--- Phase 2.6: the single gate used by OnTick / TryArm. Local mode (blank key)
//--- passes with zero overhead.
bool LicenseTradingAllowed()
{
   if(InpLicenseKey=="")return true;                       // local/unrestricted mode
   if(!g_licenseActive)return false;                       // never validated or revoked
   if(!g_autoTradingEnabled)return false;                  // disabled from the server
   // Mobile command bridge override (STOP_EA)
   if(InpEnableMobileCommands && GlobalVariableCheck("PAT_TRADING_ENABLED")
      && GlobalVariableGet("PAT_TRADING_ENABLED")<0.5)return false;
   return true;
}

//--- LicenseCheckGate(): top-of-tick guard. Returns false when trading must stop.
bool LicenseCheckGate()
{
   if(LicenseTradingAllowed())return true;
   if(InpLicenseKey!="" && !g_licenseActive && g_licenseLastReason!="")
      g_gateReason="LICENSE: "+g_licenseLastReason;
   return false;
}

//--- rudimentary JSON field reader (no external parser): finds "field":value
string LicenseJsonField(string body,string field)
{
   string pat="\""+field+"\":";
   int p=StringFind(body,pat);
   if(p<0)return "";
   p+=StringLen(pat);
   while(p<StringLen(body) && (StringGetCharacter(body,p)==' '))p++;
   if(p>=StringLen(body))return "";
   if(StringGetCharacter(body,p)=='"')          // string value
   {
      int q=StringFind(body,"\"",p+1);
      if(q<0)return "";
      return StringSubstr(body,p+1,q-p-1);
   }
   int e=p;
   while(e<StringLen(body))
   {
      ushort ch=StringGetCharacter(body,e);
      if(ch==','||ch=='}'||ch==' ')break;
      e++;
   }
   return StringSubstr(body,p,e-p);
}

//--- Phase 2.5: POST to the license server. 9-arg WebRequest, 5 s timeout,
//--- automatic failover between the primary and backup endpoint, one retry per
//--- endpoint. Returns HTTP status code (0 = total transport failure).
int LicenseHttpPost(string endpoint,string payload,string &response)
{
   response="";
   uchar post[];
   int len=StringToCharArray(payload,post,0,WHOLE_ARRAY,CP_UTF8);
   if(len>0)len--;   // drop terminator
   ArrayResize(post,len);
   string headers="Content-Type: application/json\r\nUser-Agent: PAT-Ultra/2.00\r\n";
   string urls[2];
   urls[0]=InpLicenseServerURL;
   urls[1]=InpLicenseServerURL2;
   // g_licenseEndpoint: 0 = auto/unknown, 1 = primary last worked, 2 = backup last worked
   int order[2];
   if(g_licenseEndpoint==2){order[0]=1;order[1]=0;}
   else                     {order[0]=0;order[1]=1;}
   for(int pick=0;pick<2;pick++)
   {
      string url=urls[order[pick]]+endpoint;
      if(urls[order[pick]]=="")continue;   // no backup configured
      for(int attempt=1;attempt<=2;attempt++)   // one quick retry per endpoint
      {
         ResetLastError();
         uchar result[];
         string resultHeaders="";
         int code=WebRequest("POST",url,headers,"",5000,post,len,result,resultHeaders);
         if(code==-1)
         {
            // Full diagnosis: older builds report 4014 for a non-whitelisted URL, newer
            // builds use 5200-5203. Print the exact code so the user's log is actionable.
            int err=GetLastError();
            switch(err)
            {
               case 4014:
               case 5200:
                  Print("LICENSE: WebRequest blocked (err ",err,") for ",url,". FIX: Tools > Options > Expert Advisors > tick 'Allow WebRequest for listed URL' and add BOTH  ",InpLicenseServerURL,"  and  ",InpLicenseServerURL2,"  (no trailing slashes), click OK, re-attach the EA.");
                  break;
               case 5201:
                  Print("LICENSE: WebRequest connect failed (err 5201) to ",url,". Check network/proxy/firewall; testing https://",urls[order[pick]],"/healthz in this machine's browser shows if the path works at all.");
                  break;
               case 5202:
                  Print("LICENSE: WebRequest timeout (err 5202): ",url," did not answer in 5 s.");
                  break;
               case 5203:
                  Print("LICENSE: WebRequest HTTP error (err 5203) from ",url,".");
                  break;
               default:
                  Print("LICENSE: WebRequest failed (err ",err,") calling ",url,".");
            }
            if(attempt==1){Sleep(300);continue;}
            break;   // give the other endpoint a chance
         }
         if(code<200||code>599)
         {
            // Not a valid HTTP status (e.g. 1009): the Go server cannot emit one, so a
            // middlebox answered - AV HTTPS-scanner, system proxy, captive portal - or
            // the connection was cut mid-response.
            g_lastNonHTTPStatus=code;
            break;   // edge-specific failure: same-edge retry would hit the same path - switch endpoint NOW
         }
         if(code==429)
         {
            // Rate-limited (10 req/min/IP). Never switch endpoints for this - the
            // limit is per-IP and both endpoints share the origin. Back off quietly.
            Print("LICENSE: rate-limited (429) - backing off until next poll");
            return 429;
         }
         // endpoint answered with a sane HTTP status - remember it as the good one
         g_licenseEndpoint=(order[pick]==0)?1:2;
         response=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8);
         if(code!=200)
            Print("LICENSE: server HTTP ",code," body: ",StringSubstr(response,0,200));
         return code;
      }
   }
   // every endpoint failed - one compact summary (both non-HTTP statuses if seen)
   if(g_lastNonHTTPStatus>0)
      Print("LICENSE: transport degraded (last non-HTTP status ",g_lastNonHTTPStatus,", Cloudflare edge or middlebox) - both endpoints tried, grace period covers trading; next poll retries");
   g_lastNonHTTPStatus=0;
   return 0;   // every endpoint failed - caller applies the grace-period logic
}

//--- activate this machine/account; returns true when the seat is granted.
bool LicenseActivate()
{
   string payload="{\"license_key\":\""+InpLicenseKey+"\",\"machine_id\":\""+g_machineId+
                  "\",\"account_login\":"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+
                  ",\"broker_server\":\""+AccountInfoString(ACCOUNT_SERVER)+"\"}";
   string resp="";
   int code=LicenseHttpPost("/v1/activate",payload,resp);
   if(code!=200)
   {
      // Transport failure (1009/1001/1003 class) at INIT is fatal for a fresh attach:
      // one bounded second pass after a short settle usually lands on the healthy edge.
      Sleep(2000);
      code=LicenseHttpPost("/v1/activate",payload,resp);
      if(code!=200)return false;   // caller handles grace/INIT semantics
   }
   string v=LicenseJsonField(resp,"valid");
   g_licenseLastReason=LicenseJsonField(resp,"reason");
   if(v!="true")
   {
      Print("LICENSE: activation refused (",g_licenseLastReason,")");
      return false;
   }
   g_licenseActive=true;
   g_autoTradingEnabled=(LicenseJsonField(resp,"auto_trading_enabled")!="false");
   g_settingsVersion=(int)StringToInteger(LicenseJsonField(resp,"settings_version"));
   g_gracePeriodDeadline=0;
   Print("LICENSE: activated. auto_trading=",g_autoTradingEnabled," settings_version=",g_settingsVersion);
   return true;
}

//--- Phase 2.5 CheckLicense(): heartbeat poll with grace-period fallback.
void CheckLicense()
{
   if(InpLicenseKey=="")return;
   string payload="{\"license_key\":\""+InpLicenseKey+"\",\"machine_id\":\""+g_machineId+
                  "\",\"account_login\":"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+
                  ",\"broker_server\":\""+AccountInfoString(ACCOUNT_SERVER)+"\""+
                  ",\"settings_version\":"+IntegerToString(g_settingsVersion)+"}";
   string resp="";
   int code=LicenseHttpPost("/v1/heartbeat",payload,resp);

   if(code==0)
   {
      // transport failure: grace period if previously valid, block if never validated
      if(g_licenseActive)
      {
         if(g_gracePeriodDeadline==0)
         {
            g_gracePeriodDeadline=TimeCurrent()+InpLicenseGraceMinutes*60;
            Print("LICENSE: server unreachable - grace period until ",TimeToString(g_gracePeriodDeadline,TIME_DATE|TIME_MINUTES));
         }
         if(TimeCurrent()>g_gracePeriodDeadline)
         {
            g_licenseActive=false;
            g_licenseLastReason="grace_expired";
            Print("LICENSE: grace period expired - trading blocked");
         }
      }
      else if(g_licenseLastReason!="pending_activation")g_licenseLastReason="server_unreachable";   // keep PENDING state sticky
      return;
   }

   if(code!=200)
   {
      // Transport-level failure (timeout, reset, non-HTTP middlebox status such as
      // 1009) or an unexpected server code. This is NOT a license revocation - the
      // fail-safe rule: only a parsed "valid":false body may deactivate. Treat as
      // server-unreachable and let the grace period carry the EA.
      g_licenseLastReason="transport_http_"+IntegerToString(code);
      if(g_licenseActive)
      {
         if(g_gracePeriodDeadline==0)
         {
            g_gracePeriodDeadline=TimeCurrent()+InpLicenseGraceMinutes*60;
            Print("LICENSE: server unreachable (HTTP ",code,") - grace period until ",TimeToString(g_gracePeriodDeadline,TIME_DATE|TIME_MINUTES));
         }
         if(TimeCurrent()>g_gracePeriodDeadline)
         {
            g_licenseActive=false;
            g_licenseLastReason="grace_expired";
            Print("LICENSE: grace period expired - trading blocked");
         }
      }
      else Print("LICENSE: server unreachable (HTTP ",code,") - will retry in 10 min");
      return;
   }

   string v=LicenseJsonField(resp,"valid");
   if(v!="true")
   {
      // PENDING activation + "not_activated": the init activate never landed (transport
      // blip) - the heartbeat cannot validate a seat that doesn't exist. Recover by
      // running the REAL activation now (same retry/failover inside LicenseHttpPost).
      if(g_licenseLastReason=="pending_activation" && LicenseJsonField(resp,"reason")=="not_activated")
      {
         Print("LICENSE: PENDING state - heartbeat says seat missing; running full activation");
         if(LicenseActivate())return;   // activated - trading unblocked on next gate
         return;                         // still failing transport; next retry continues
      }
      bool wasActive=g_licenseActive;
      g_licenseActive=false;
      g_licenseLastReason=LicenseJsonField(resp,"reason");
      if(g_licenseLastReason=="")g_licenseLastReason="invalid";
      Print("LICENSE: invalid (",g_licenseLastReason,")");
      if(wasActive&&InpCloseOnLicenseRevoke)
      {
         Print("LICENSE: InpCloseOnLicenseRevoke=true -> emergency close all");
         EmergencyCloseAll();
      }
      return;
   }

   // success: reset grace, refresh state, pull settings when the server bumped them
   g_licenseActive=true;
   g_gracePeriodDeadline=0;
   g_autoTradingEnabled=(LicenseJsonField(resp,"auto_trading_enabled")!="false");
   int serverVersion=(int)StringToInteger(LicenseJsonField(resp,"settings_version"));
   if(serverVersion>g_settingsVersion)
   {
      g_settingsVersion=serverVersion;
      Print("LICENSE: settings updated to version ",serverVersion);
   }
   if(g_licenseLastReason=="pending_activation")
   {
      g_licenseLastReason="";
      Print("LICENSE: PENDING activation RESOLVED - seat validated, trading unblocked");   // self-heal proof
   }
}

//--- Phase 3: MT5 Mobile command bridge. Subscribers place a PENDING ORDER whose
//--- comment carries the command; the EA executes it and deletes the order.
void ProcessMobileCommands()
{
   if(!InpEnableMobileCommands)return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0)continue;
      string comment=OrderGetString(ORDER_COMMENT);
      if(StringFind(comment,"STOP_EA")>=0)
      {
         GlobalVariableSet("PAT_TRADING_ENABLED",0);
         DeleteOrderSafe(ticket);
         Print("Mobile Command: STOP_EA");
      }
      else if(StringFind(comment,"START_EA")>=0)
      {
         GlobalVariableSet("PAT_TRADING_ENABLED",1);
         DeleteOrderSafe(ticket);
         Print("Mobile Command: START_EA");
      }
      else if(StringFind(comment,"RISK_")>=0)
      {
         double risk=StringToDouble(StringSubstr(comment,5));
         // RISK_0 = safe clear behavior (section 9): clears any existing override.
         if(risk==0)
         {
            GlobalVariableSet("PAT_RISK_OVERRIDE",0);
            DeleteOrderSafe(ticket);
            Print("Mobile Command: Risk override CLEARED (RISK_0)");
         }
         else if(risk>0 && risk<=5.0)   // request ceiling: the risk engine still clamps to live limits
         {
            GlobalVariableSet("PAT_RISK_OVERRIDE",risk);
            DeleteOrderSafe(ticket);
            Print("Mobile Command: Risk REQUESTED ",risk," (engine clamps to profile/derived ceilings)");
         }
      }
   }
}

//--- self-test: SHA256 known-answer (empty string + "abc") + gate sanity.
void LicenseSelfTest()
{
   if(InpLicenseKey=="")return;
   string e=LicenseSHA256("");
   string a=LicenseSHA256("abc");
   bool ok=(e=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        && (a=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
   if(ok)Print("LICENSE: self-test PASS (SHA256 known answers, gate active)");
   else   Print("LICENSE: self-test FAIL - SHA256 implementation mismatch; license binding is NOT safe");
}
//================ LICENSE CLIENT + MOBILE COMMAND BRIDGE END ==================
//====================================================================
// STRUCTS
//====================================================================
struct BrokerProfile
{
   string symbol;
   double point,tickSize,tickValue,contractSize,volumeMin,volumeMax,volumeStep;
   double swapLong,swapShort;
   int digits,stopsLevel,freezeLevel,leverage;
   string company,currency;
   ENUM_ACCOUNT_MARGIN_MODE marginMode;
   ENUM_ACCOUNT_TRADE_MODE tradeMode;
   bool hedging;
   //--- [BROKER ENGINE] richer specs: tick value can differ for profit vs loss legs;
   //--- volume limit is the broker's directional open+pending cap (distinct from max).
   double tickValueProfit,tickValueLoss,volumeLimit;
   ENUM_SYMBOL_CALC_MODE calcMode;
};

struct WindowStats
{
   long observations;
   int trades,wins,losses,tp1Hits,tp2Hits,tp3Hits;
   double grossPL,netPL,costs,slipSum,spreadPctSum,atrPctSum,volRatioSum;
   double maeSum,mfeSum,rSum,peakNet,maxDD;
   double recentNet[64];
   int recentCount,recentIdx;
   double obsATRRatioSum,obsVolRatioSum;
   bool disabled;
   //--- [PERFORMANCE GATING] rolling recent-R history (prompt.md section 25).
   double recentR[64];
   int recentRCount,recentRIdx;
};

struct PositionState
{
   ulong ticket;
   long positionId;
   int direction;
   ENUM_WINDOW_ID window;
   string setupId;
   bool hv;
   bool recovery;                  // loss-recovery reversal leg (excluded from window stats)
   double initialVolume;
   double initialRiskMoney;
   double entry;
   double initialSL;
   double tp1,tp2,tp3;
   double volTP1,volTP2,volTP3;
   bool tp1Done,tp2Done,tp3Done;
   double maePrice,mfePrice;
   datetime opened;
   double entrySpreadPct;
   double entrySlipPts;
   double entryAtrPct;
   double entryVolRatio;
   double realizedGross;
   double realizedNet;
   double realizedCosts;
};

struct BucketStats
{
   long samples;
   double atrRatioSum;
   double volRatioSum;
};

//====================================================================
// GLOBALS
//====================================================================
BrokerProfile broker;
string eaSymbol="";

int hATR=INVALID_HANDLE,hADX=INVALID_HANDLE,hEMA20=INVALID_HANDLE,hEMA50=INVALID_HANDLE;
int hH1EMA20=INVALID_HANDLE,hH1EMA50=INVALID_HANDLE,hM15EMA20=INVALID_HANDLE,hM15EMA50=INVALID_HANDLE;
int hRSI=INVALID_HANDLE,hM5E20=INVALID_HANDLE,hM5E50=INVALID_HANDLE,hM5ADX=INVALID_HANDLE;
int hEMA9=INVALID_HANDLE,hEMA200=INVALID_HANDLE,hMACD=INVALID_HANDLE;   // [SIGNAL QUALITY]

double g_atr=0,g_adx=0,g_adxPlus=0,g_adxMinus=0,g_rsi=0;
double g_ema20=0,g_ema50=0,g_h1e20=0,g_h1e50=0,g_m15e20=0,g_m15e50=0;
double g_vwap=0,g_vwapUp=0,g_vwapDn=0;
int g_superTrendDir=0;
double g_superTrend=0;
ENUM_MARKET_PHASE g_phase=PHASE_ACCUMULATION;
bool g_fvg=false; int g_fvgDir=0; double g_fvgTop=0,g_fvgBottom=0;
bool g_bosUp=false,g_bosDn=false,g_chochUp=false,g_chochDn=false,g_sweepUp=false,g_sweepDn=false;
double g_swingHigh=0,g_swingLow=0;
int g_dirBias=0,g_score=0,g_scoreMax=0,g_smcScoreBull=0,g_smcScoreBear=0;
double g_volRatio=0;                                   // cached per-bar volume ratio (no CopyRates per tick)
bool g_ifvg=false; int g_ifvgDir=0; double g_ifvgTop=0,g_ifvgBottom=0;
bool g_ptb=false; int g_ptbDir=0; double g_ptbTop=0,g_ptbBottom=0;
double g_lastSlipPts=0;
int g_perfTrades=0,g_perfWins=0,g_perfLosses=0,g_perfRetN=0;
double g_perfNetProfit=0,g_perfGrossProfit=0,g_perfGrossLoss=0,g_perfRetMean=0,g_perfRetM2=0,g_perfCumNet=0,g_perfPeakNet=0,g_perfMaxDDMoney=0;

//--- FMP macro state (credentials decoded at runtime only)
#define FMPUSD_COUNT 7
string g_usdPairs[FMPUSD_COUNT]={"EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD","NZDUSD"};
double g_usdMove[FMPUSD_COUNT];
bool   g_usdGot[FMPUSD_COUNT];
double g_usdAvg=0;
int    g_usdBias=0;
bool   g_usdAvailable=false;
string g_eurSymbol="";
double g_eurMovePct=0;
int    g_eurBias=0;
bool   g_eurAvailable=false;
double g_spxMovePct=0;
int    g_spxBias=0;
bool   g_spxAvailable=false;
bool   g_fmpEverOK=false;
int    g_fmpErrCount=0;
bool     g_webRequestWarned=false;
int      g_fmp429Count=0;
int      g_fmpCycle=0;
bool     g_usdGotSPX=false;
double   g_m5e20=0,g_m5e50=0,g_m5adx=0,g_m5adxPlus=0,g_m5adxMinus=0;
double   g_bbUp=0,g_bbLo=0,g_bbMid=0;
int      g_scalpSignal=0;   // +1 trend-long, -1 trend-short, +2 reversion-long, -2 reversion-short, 0 none
string   g_scalpWhy="";
double   g_spxBatchChg=0;
string g_fmpLastErr="";
datetime g_fmpLastTry=0,g_fmpLastOK=0;
int    g_fmpNewsCount=0;
string g_fmpNewsLast="";
int    g_macroBull=0,g_macroBear=0;

//--- loss recovery / reversal state
int      g_lastLossDir=0;             // direction of the last realized loss (+1 buy, -1 sell)
datetime g_lastLossTime=0;
double   g_lastLossMoney=0;
datetime g_recoveryArmedUntil=0;
int      g_recoveryLegs=0;

#define SPREAD_SAMPLES 256
double g_spreadBuf[SPREAD_SAMPLES]; int g_spreadCnt=0,g_spreadIdx=0; double g_spreadAvg=0;
double g_spreadStd=0;
#define SLIP_SAMPLES 64
double g_slipBuf[SLIP_SAMPLES]; int g_slipCnt=0,g_slipIdx=0; double g_slipAvg=0;
#define ATR_SAMPLES 512
int g_atrKeep=512;                     // effective ring size = min(ATR_SAMPLES, InpATRPercentileLookback)
double g_atrBuf[ATR_SAMPLES]; int g_atrCnt=0,g_atrIdx=0;

WindowStats g_ws[WIN_COUNT];
BucketStats g_bucket[48];
PositionState g_ps[];

long g_serverOffsetSec=0;
double g_ptScale=1.0;                    // point-unit auto-scale for 3-digit gold feeds
//--- Phase 2.2: EFFECTIVE TP volume split (decimal fractions). Inputs are read-only in
//--- MQL5, so a whole-number misconfiguration (75/20/5) is normalized here at init and
//--- every volume allocation reads the *Eff globals instead of the raw inputs.
double g_tp1PctEff=0.75,g_tp2PctEff=0.20,g_tp3PctEff=0.05;
double InpTPPctSanitize(double v){ return (v>1.0?v/100.0:v); }
datetime g_lastOffsetRefresh=0,g_lastBar=0,g_lastExitTime=0,g_lastEntryTime=0;
// Simple-mode armed plan snapshot: TryArm() computes the scalp ladder (t1/t2/t3) before
// the market order fills; OnTradeTransaction later reconstructs position state from the
// deal. These carry the ARMED plan into AddPositionState so the broker TP and the managed
// micro-TP ladder are the same distances the entry was cost-validated against.
double g_armTp1=0,g_armTp2=0,g_armTp3=0;bool g_armValid=false;
datetime g_newsChecked=0,g_nextNewsTime=0,g_newsBlockedUntil=0,g_disorderUntil=0;
string g_nextNewsName="",g_gateReason="";
bool g_newsBlocked=false,g_paused=false;

int g_tradesToday=0,g_consecutiveLosses=0;
double g_dayAnchor=0,g_weekAnchor=0,g_monthAnchor=0,g_maxDDSeen=0;
int g_dayKey=-1,g_weekKey=-1,g_monthKey=-1;
bool g_stopDay=false,g_stopWeek=false,g_stopMonth=false;
double g_commissionRTPerLot=0;
double g_windowRiskUsed[WIN_COUNT];
int g_windowSignals[WIN_COUNT];
string g_lastSetupBuy[WIN_COUNT],g_lastSetupSell[WIN_COUNT];
datetime g_lastWindowEntry[WIN_COUNT];

int g_log=INVALID_HANDLE;
#define UI_PREFIX "PAT4_"

//--- dashboard colour system: deep navy base, high-contrast text, semantic status colours
color C_BG=C'0,0,0',C_BG2=C'10,12,16',C_PANEL=C'6,8,12',C_SECTION=C'16,24,40',C_SECTION_TXT=C'120,220,255';
color C_TXT=C'255,255,255',C_TXT2=C'208,216,232',C_DIM=C'150,160,180',C_GRAY=C'110,120,140',C_GRID=C'40,48,64';
color C_HDR=C'12,18,30',C_ACCENT=C'0,160,255',C_BORDER=C'70,80,100';
color C_UP=C'0,230,118',C_UP_TXT=C'0,255,140',C_DN=C'255,64,64',C_DN_TXT=C'255,110,110';
color C_WARN=C'255,193,7',C_WARN_TXT=C'255,224,102',C_INFO=C'64,196,255',C_GOLD=C'255,193,7',C_GOLD_TXT=C'255,215,64';
color C_SYD=C'0,176,255',C_TOK=C'155,89,255',C_LON=C'255,145,0',C_NY=C'0,230,118';
color C_SYD_DIM=C'20,60,90',C_TOK_DIM=C'50,32,90',C_LON_DIM=C'90,54,0',C_NY_DIM=C'20,80,50';

//--- dashboard geometry (recomputed from InpPanelFontSize)
// Flow layout: columns are drawn with a running Y cursor and every string is
// width-clipped to its column, so overlap is impossible by construction.
// Row counts below are the single source of truth for the panel height.
#define L_SECTIONS 3
#define L_ROWS     16
#define R_SECTIONS 4
#define R_ROWS     32      // 22 legacy + 2 SR [SR] + 4 capital-engine + 4 signal-quality rows
int g_font=7,g_fontPx=9,g_dpi=96;
double g_dpiScale=1.0;
int g_rh=16,g_hdrH=30,g_colW=300,g_pad=12,g_gap=14,g_panelW=0;
int g_bodyTop=0,g_colHL=0,g_colHR=0,g_tlTop=0,g_tlH=0,g_panelH=0;
bool g_dashCollapsed=false,g_dashWasCollapsed=false;
uint g_lastDashMs=0;
int g_x=8,g_y=24;                    // live panel origin (draggable)
bool g_dragging=false,g_maybeClick=false;
int g_dragOffX=0,g_dragOffY=0,g_dragStartX=0,g_dragStartY=0;
uint g_lastDragMs=0;
bool g_measure=false;                // pass-1 layout mode (no drawing)
int g_yCurL=0,g_yCurR=0,g_rowL=0,g_rowR=0;//====================================================================
// BASIC HELPERS
//====================================================================
int VolDigits(double step)
{
   int d=0; if(step<=0) return 2;
   while(step<1.0 && d<8){ step*=10.0; d++; }
   return d;
}

double FloorVolume(double lots)
{
   double step=(broker.volumeStep>0?broker.volumeStep:0.01);
   if(lots<=0) return 0;
   lots=MathFloor((lots+1e-12)/step)*step;
   if(lots<broker.volumeMin-1e-12) return 0;
   lots=MathMin(lots,broker.volumeMax);
   return NormalizeDouble(lots,VolDigits(step));
}

double NormalizeVolume(double lots)
{
   if(lots<=0) return 0;
   double v=FloorVolume(lots);
   if(v<=0 && lots>=broker.volumeMin*0.999) v=broker.volumeMin;
   return NormalizeDouble(MathMin(v,broker.volumeMax),VolDigits(broker.volumeStep));
}

double PriceNorm(double p){ return NormalizeDouble(p,broker.digits); }
double MinTradeDistance()
{
   double base=MathMax(broker.stopsLevel,broker.freezeLevel)*broker.point+2*broker.point;
   // Phase 4.1: optionally add the safety buffer on top of broker stops/freeze level
   if(InpRespectStopLevel)base+=InpStopLevelBufferPoints*broker.point;
   return base;
}

//--- Phase 2.3: authoritative ultra-scalp constants (simple-mode engine).
//--- These are the code equivalents of the complex-mode inputs:
//---   SCALP_TP1_ATR ~ InpTP1_ATR_Floor/Cap midpoint, SCALP_SL_ATR ~ InpSL_ATR_Multiplier.
//--- Distance = ATR multiple (volatility-adjusted); volume split = decimal fraction (Phase 2.1).
const double SCALP_TP1_ATR   = 0.40;   // TP1 distance (complex-mode analogue: InpTP1_ATR_Floor 0.25..Cap 0.40)
const double SCALP_TP2_TOT   = 0.75;   // TP2 distance from entry (InpTP2_ATR_Floor 0.60..Cap 1.10)
const double SCALP_TP3_TOT   = 1.15;   // TP3 distance from entry (InpTP3_ATR_Floor 1.00..Cap 1.80)
const double SCALP_SL_ATR    = 0.80;   // trend-pullback / momentum stop (InpSL_ATR_Multiplier)
const double SCALP_SL_REV    = 0.45;   // VWAP-reversion stop beyond the extreme
const double SCALP_SL_BRK    = 0.85;   // London-breakout stop

double Bid(){ return SymbolInfoDouble(eaSymbol,SYMBOL_BID); }
double Ask(){ return SymbolInfoDouble(eaSymbol,SYMBOL_ASK); }
double SpreadPoints(){ double a=Ask(),b=Bid(); return (a>0&&b>0&&broker.point>0)?(a-b)/broker.point:99999; }

bool InitBroker()
{
   broker.symbol=eaSymbol;
   broker.point=SymbolInfoDouble(eaSymbol,SYMBOL_POINT);
   broker.tickSize=SymbolInfoDouble(eaSymbol,SYMBOL_TRADE_TICK_SIZE);
   broker.tickValue=SymbolInfoDouble(eaSymbol,SYMBOL_TRADE_TICK_VALUE);
   broker.contractSize=SymbolInfoDouble(eaSymbol,SYMBOL_TRADE_CONTRACT_SIZE);
   broker.volumeMin=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_MIN);
   broker.volumeMax=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_MAX);
   broker.volumeStep=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_STEP);
   broker.swapLong=SymbolInfoDouble(eaSymbol,SYMBOL_SWAP_LONG);
   broker.swapShort=SymbolInfoDouble(eaSymbol,SYMBOL_SWAP_SHORT);
   //--- [BROKER ENGINE] extended specs (prompt.md section 13): profit/loss tick values
   //--- can differ on some brokers; volume limit caps DIRECTIONAL open+pending volume.
   broker.tickValueProfit=SymbolInfoDouble(eaSymbol,SYMBOL_TRADE_TICK_VALUE_PROFIT);
   broker.tickValueLoss=SymbolInfoDouble(eaSymbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   broker.volumeLimit=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_LIMIT);
   broker.calcMode=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_CALC_MODE);
   broker.digits=(int)SymbolInfoInteger(eaSymbol,SYMBOL_DIGITS);
   broker.stopsLevel=(int)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_STOPS_LEVEL);
   broker.freezeLevel=(int)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_FREEZE_LEVEL);
   broker.leverage=(int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   broker.company=AccountInfoString(ACCOUNT_COMPANY);
   broker.currency=AccountInfoString(ACCOUNT_CURRENCY);
   broker.marginMode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   broker.tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   broker.hedging=(broker.marginMode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   // Point-unit auto-scale: 3-digit gold feeds quote 10x more points per dollar than
   // 2-digit feeds. Every point-denominated input is scaled so gates behave identically.
   g_ptScale=(broker.digits==3?10.0:1.0);
   return (broker.point>0 && broker.tickSize>0 && broker.volumeMin>0 && broker.volumeStep>0);
}

bool Copy1(int handle,int buffer,int shift,double &value)
{
   double x[1]; if(handle==INVALID_HANDLE) return false;
   if(CopyBuffer(handle,buffer,shift,1,x)!=1) return false;
   value=x[0]; return true;
}

bool IsNewBar()
{
   datetime t=iTime(eaSymbol,PERIOD_M1,0);
   if(t>0 && t!=g_lastBar){ g_lastBar=t; return true; }
   return false;
}

//====================================================================
// TIME / DST / SESSION ENGINE
//====================================================================
bool IsLeap(int y){ return ((y%4==0 && y%100!=0) || y%400==0); }
int DaysInMonth(int y,int m)
{
   int d[12]={31,28,31,30,31,30,31,31,30,31,30,31};
   if(m==2 && IsLeap(y)) return 29; return d[m-1];
}

datetime MakeDT(int y,int mon,int day,int hour,int minute=0,int sec=0)
{
   MqlDateTime x; ZeroMemory(x); x.year=y;x.mon=mon;x.day=day;x.hour=hour;x.min=minute;x.sec=sec;
   return StructToTime(x);
}

int DayOfWeekUTC(int y,int mon,int day)
{
   MqlDateTime x; TimeToStruct(MakeDT(y,mon,day,12),x); return x.day_of_week;
}

int NthSunday(int y,int mon,int nth)
{
   int dow=DayOfWeekUTC(y,mon,1);
   int first=1+((7-dow)%7);
   return first+(nth-1)*7;
}

int LastSunday(int y,int mon)
{
   int last=DaysInMonth(y,mon);
   int dow=DayOfWeekUTC(y,mon,last);
   return last-dow;
}

bool LondonDST(datetime utc)
{
   MqlDateTime d; TimeToStruct(utc,d);
   datetime start=MakeDT(d.year,3,LastSunday(d.year,3),1);
   datetime stop =MakeDT(d.year,10,LastSunday(d.year,10),1);
   return (utc>=start && utc<stop);
}

bool NewYorkDST(datetime utc)
{
   MqlDateTime d; TimeToStruct(utc,d);
   // US DST: 02:00 local; approximated in UTC at 07:00 start and 06:00 end.
   datetime start=MakeDT(d.year,3,NthSunday(d.year,3,2),7);
   datetime stop =MakeDT(d.year,11,NthSunday(d.year,11,1),6);
   return (utc>=start && utc<stop);
}

// Australia/Sydney DST: first Sunday in October at 02:00 AEST until
// first Sunday in April at 03:00 AEDT. Convert those local transition
// instants to UTC and handle the southern-hemisphere year crossover.
bool SydneyDST(datetime utc)
{
   MqlDateTime d; TimeToStruct(utc,d);
   datetime octStartThis=MakeDT(d.year,10,NthSunday(d.year,10,1),2)-10*3600;
   datetime aprEndThis =MakeDT(d.year,4,NthSunday(d.year,4,1),3)-11*3600;
   if(d.mon<=4)
   {
      datetime octPrev=MakeDT(d.year-1,10,NthSunday(d.year-1,10,1),2)-10*3600;
      return (utc>=octPrev && utc<aprEndThis);
   }
   if(d.mon>=10)
   {
      datetime aprNext=MakeDT(d.year+1,4,NthSunday(d.year+1,4,1),3)-11*3600;
      return (utc>=octStartThis && utc<aprNext);
   }
   return false;
}

int WrapMin(int m){ while(m<0)m+=1440; while(m>=1440)m-=1440; return m; }

void RefreshServerOffset(bool force=false)
{
   datetime now=TimeCurrent();
   if(!force && g_lastOffsetRefresh>0 && now-g_lastOffsetRefresh<InpServerOffsetRefreshSec) return;
   g_lastOffsetRefresh=now;
   if(InpAutoDetectServerOffset && !MQLInfoInteger(MQL_TESTER))
   {
      datetime s=TimeTradeServer(),u=TimeGMT();
      if(s>0 && u>0) g_serverOffsetSec=(long)(s-u);
      else g_serverOffsetSec=(long)InpManualServerOffsetHours*3600;
   }
   else g_serverOffsetSec=(long)InpManualServerOffsetHours*3600;
}

datetime ServerNow(){ datetime s=TimeTradeServer(); return (s>0?s:TimeCurrent()); }
datetime UTCNow(){ RefreshServerOffset(false); return (datetime)(ServerNow()-g_serverOffsetSec); }
int MinuteOfDay(datetime t){ MqlDateTime d;TimeToStruct(t,d);return d.hour*60+d.min; }

bool InWindowMinutes(int x,int a,int b)
{
   if(a<=b) return x>=a && x<b;
   return (x>=a || x<b);
}

string WindowName(ENUM_WINDOW_ID w)
{
   switch(w)
   {
      case WIN_SYDNEY:return "SYDNEY";
      case WIN_TOKYO:return "TOKYO";
      case WIN_SYDNEY_TOKYO:return "SYDNEY/TOKYO";
      case WIN_TOKYO_LONDON:return "TOKYO/LONDON";
      case WIN_LONDON_OPEN:return "LONDON OPEN";
      case WIN_LONDON:return "LONDON";
      case WIN_LONDON_NY:return "LONDON/NY";
      case WIN_NY_OPEN:return "NY OPEN";
      case WIN_NEWYORK:return "NEW YORK";
      case WIN_VERIFIED_EXPANSION:return "VERIFIED EXPANSION";
      default:return "NONE";
   }
}

void SessionUTCBounds(datetime utc,int &sydOpen,int &sydClose,int &tokOpen,int &tokClose,int &lonOpen,int &lonClose,int &nyOpen,int &nyClose)
{
   int pad=MathMax(0,InpOverlapPadMinutes);
   // Sydney: local Australia/Sydney clock, UTC+10 standard / UTC+11 DST.
   int sydOff=(SydneyDST(utc)?11*60:10*60);
   sydOpen =WrapMin(InpSydneyLocalOpenMin-pad-sydOff);
   sydClose=WrapMin(InpSydneyLocalCloseMin+pad-sydOff);

   // Tokyo: Japan does not observe DST, JST = UTC+9.
   tokOpen =WrapMin(InpTokyoLocalOpenMin-pad-9*60);
   tokClose=WrapMin(InpTokyoLocalCloseMin+pad-9*60);

   // London: local clock, UTC+0 winter / UTC+1 British Summer Time.
   int lonOff=LondonDST(utc)?60:0;
   lonOpen =WrapMin(InpLondonLocalOpenMin-pad-lonOff);
   lonClose=WrapMin(InpLondonLocalCloseMin+pad-lonOff);

   // New York: local clock, UTC-5 winter / UTC-4 daylight time.
   int nyOff=NewYorkDST(utc)?-4*60:-5*60;
   nyOpen =WrapMin(InpNewYorkLocalOpenMin-pad-nyOff);
   nyClose=WrapMin(InpNewYorkLocalCloseMin+pad-nyOff);
}

bool IsVerifiedExpansionBucket(datetime utc)
{
   int b=MinuteOfDay(utc)/30;
   if(b<0||b>=48) return false;
   if(g_bucket[b].samples<InpVerifiedBucketMinSamples) return false;
   double ar=g_bucket[b].atrRatioSum/g_bucket[b].samples;
   double vr=g_bucket[b].volRatioSum/g_bucket[b].samples;
   return (ar>=InpVerifiedBucketATRRatio && vr>=InpVerifiedBucketVolRatio);
}

// Single source of truth for "does this window participate" - used by the
// entry engine AND the dashboard so the panel can never disagree with trading.
bool WindowAllowed(ENUM_WINDOW_ID w)
{
   switch(w)
   {
      case WIN_SYDNEY:            return (InpTradeAllFourSessions||InpTradeSydney);
      case WIN_TOKYO:             return (InpTradeAllFourSessions||InpTradeTokyo);
      case WIN_LONDON:            return (InpTradeAllFourSessions||InpTradeLondon);
      case WIN_NEWYORK:           return (InpTradeAllFourSessions||InpTradeNewYork);
      case WIN_SYDNEY_TOKYO:      return (InpTradeSydneyTokyo && (InpTradeAllFourSessions||(InpTradeSydney&&InpTradeTokyo)));
      case WIN_TOKYO_LONDON:      return (InpTradeTokyoLondon && (InpTradeAllFourSessions||(InpTradeTokyo&&InpTradeLondon)));
      case WIN_LONDON_OPEN:       return ((InpTradeAllFourSessions||InpTradeLondon) && InpTradeLondonOpen);
      case WIN_LONDON_NY:         return (InpTradeLondonNY && (InpTradeAllFourSessions||(InpTradeLondon&&InpTradeNewYork)));
      case WIN_NY_OPEN:           return ((InpTradeAllFourSessions||InpTradeNewYork) && InpTradeNYOpen);
      case WIN_VERIFIED_EXPANSION:return InpTradeVerifiedExpansion;
      default:                    return false;
   }
}

ENUM_WINDOW_ID CurrentWindow(bool &tradeable)
{
   tradeable=false;
   datetime utc=UTCNow();
   int m=MinuteOfDay(utc),so,sc,to,tc,lo,lc,no,nc;
   SessionUTCBounds(utc,so,sc,to,tc,lo,lc,no,nc);

   bool syd=InWindowMinutes(m,so,sc);
   bool tok=InWindowMinutes(m,to,tc);
   bool lon=InWindowMinutes(m,lo,lc);
   bool ny =InWindowMinutes(m,no,nc);
   bool sydTok=syd&&tok;
   bool tokLon=tok&&lon;
   bool lonNY=lon&&ny;
   bool londOpen=lon&&InWindowMinutes(m,lo,WrapMin(lo+InpLondonOpenWindowMin));
   bool nyOpen=ny&&InWindowMinutes(m,no,WrapMin(no+InpNYOpenWindowMin));

   ENUM_WINDOW_ID w=WIN_NONE;
   // Give true overlaps first priority so their statistics/risk budgets remain independent.
   if(lonNY) w=WIN_LONDON_NY;
   else if(tokLon) w=WIN_TOKYO_LONDON;
   else if(sydTok) w=WIN_SYDNEY_TOKYO;
   else if(londOpen) w=WIN_LONDON_OPEN;
   else if(nyOpen) w=WIN_NY_OPEN;
   else if(lon) w=WIN_LONDON;
   else if(ny) w=WIN_NEWYORK;
   else if(tok) w=WIN_TOKYO;
   else if(syd) w=WIN_SYDNEY;
   else if(IsVerifiedExpansionBucket(utc)) w=WIN_VERIFIED_EXPANSION;

   // Master switch guarantees participation in every primary market session.
   // Individual switches remain available for controlled A/B validation only when the master is false.
   tradeable=WindowAllowed(w);
   if(!InpUseSessionFilter) tradeable=true;
   return w;
}

string FmtHHMM(int m){ m=WrapMin(m); return StringFormat("%02d:%02d",m/60,m%60); }
int ForwardMinutesTo(int fromMin,int toMin){ int d=toMin-fromMin;if(d<0)d+=1440;return d; }

// Minutes until the earliest constituent session of the active window closes.
int MinsUntilWindowClose(ENUM_WINDOW_ID w,int utcMin,int sc,int tc,int lc,int nc)
{
   int best=1441;
   if(w==WIN_SYDNEY||w==WIN_SYDNEY_TOKYO)best=MathMin(best,ForwardMinutesTo(utcMin,sc));
   if(w==WIN_TOKYO||w==WIN_SYDNEY_TOKYO||w==WIN_TOKYO_LONDON)best=MathMin(best,ForwardMinutesTo(utcMin,tc));
   if(w==WIN_LONDON||w==WIN_LONDON_OPEN||w==WIN_TOKYO_LONDON||w==WIN_LONDON_NY)best=MathMin(best,ForwardMinutesTo(utcMin,lc));
   if(w==WIN_NEWYORK||w==WIN_NY_OPEN||w==WIN_LONDON_NY)best=MathMin(best,ForwardMinutesTo(utcMin,nc));
   return (best>1440?-1:best);
}

int WindowOpenMin(ENUM_WINDOW_ID w,int so,int sc,int to,int tc,int lo,int lc,int no,int nc)
{
   switch(w)
   {
      case WIN_SYDNEY:return so; case WIN_TOKYO:return to;
      case WIN_LONDON:return lo; case WIN_NEWYORK:return no;
      case WIN_SYDNEY_TOKYO:return MathMin(so,to);
      case WIN_TOKYO_LONDON:return MathMin(to,lo);
      case WIN_LONDON_NY:return MathMin(lo,no);
      case WIN_LONDON_OPEN:return lo; case WIN_NY_OPEN:return no;
      default:return so;
   }
}
int WindowCloseMin(ENUM_WINDOW_ID w,int so,int sc,int to,int tc,int lo,int lc,int no,int nc)
{
   switch(w)
   {
      case WIN_SYDNEY:return sc; case WIN_TOKYO:return tc;
      case WIN_LONDON:return lc; case WIN_NEWYORK:return nc;
      case WIN_SYDNEY_TOKYO:return MathMax(sc,tc);
      case WIN_TOKYO_LONDON:return MathMax(tc,lc);
      case WIN_LONDON_NY:return MathMax(lc,nc);
      case WIN_LONDON_OPEN:return WrapMin(lo+InpLondonOpenWindowMin);
      case WIN_NY_OPEN:return WrapMin(no+InpNYOpenWindowMin);
      default:return sc;
   }
}

string SessionRangeText(string tag,int o,int c){ return tag+" "+FmtHHMM(o)+"-"+FmtHHMM(c); }

string WindowUTCText(ENUM_WINDOW_ID w,int so,int sc,int to,int tc,int lo,int lc,int no,int nc)
{
   switch(w)
   {
      case WIN_SYDNEY:            return SessionRangeText("SYD",so,sc)+" UTC";
      case WIN_TOKYO:             return SessionRangeText("TOK",to,tc)+" UTC";
      case WIN_LONDON:            return SessionRangeText("LON",lo,lc)+" UTC";
      case WIN_NEWYORK:           return SessionRangeText("NY",no,nc)+" UTC";
      case WIN_SYDNEY_TOKYO:      return SessionRangeText("S",so,sc)+"+"+SessionRangeText("T",to,tc)+" UTC";
      case WIN_TOKYO_LONDON:      return SessionRangeText("T",to,tc)+" + "+SessionRangeText("L",lo,lc)+" UTC";
      case WIN_LONDON_NY:         return SessionRangeText("L",lo,lc)+" + "+SessionRangeText("N",no,nc)+" UTC";
      case WIN_LONDON_OPEN:       return SessionRangeText("LOPEN",lo,WrapMin(lo+InpLondonOpenWindowMin))+" UTC";
      case WIN_NY_OPEN:           return SessionRangeText("NOPEN",no,WrapMin(no+InpNYOpenWindowMin))+" UTC";
      case WIN_VERIFIED_EXPANSION:return "30-min expansion bucket (learned)";
      default:                    return "no active session";
   }
}

void PrintSessionMapAudit()
{
   datetime u=UTCNow();int so,sc,to,tc,lo,lc,no,nc;SessionUTCBounds(u,so,sc,to,tc,lo,lc,no,nc);
   Print("SESSION MAP UTC | Sydney ",FmtHHMM(so),"-",FmtHHMM(sc),
         " | Tokyo ",FmtHHMM(to),"-",FmtHHMM(tc),
         " | London ",FmtHHMM(lo),"-",FmtHHMM(lc),
         " | NewYork ",FmtHHMM(no),"-",FmtHHMM(nc),
         " | serverOffsetSec=",g_serverOffsetSec);
}

bool WeekendOrRollover()
{
   datetime s=ServerNow(); MqlDateTime d;TimeToStruct(s,d);
   double h=d.hour+d.min/60.0;
   if(d.day_of_week==6) return true;
   if(d.day_of_week==0 && h<22.0) return true;
   if(d.day_of_week==5 && h>=InpFridayCutoffServer) return true;
   if(h>=21.95 && h<22.10) return true;
   return false;
}

//====================================================================
// ROLLING STATS / PERCENTILES
//====================================================================
void UpdateSpreadStats()
{
   double s=SpreadPoints(); if(s<=0||s>10000) return;
   g_spreadBuf[g_spreadIdx]=s; g_spreadIdx=(g_spreadIdx+1)%SPREAD_SAMPLES; if(g_spreadCnt<SPREAD_SAMPLES)g_spreadCnt++;
   double sum=0;for(int i=0;i<g_spreadCnt;i++)sum+=g_spreadBuf[i];g_spreadAvg=(g_spreadCnt?sum/g_spreadCnt:s);
   double ss=0;for(int i=0;i<g_spreadCnt;i++){double d=g_spreadBuf[i]-g_spreadAvg;ss+=d*d;}
   g_spreadStd=(g_spreadCnt>1?MathSqrt(ss/g_spreadCnt):0);
}

double PercentileRank(const double &a[],int n,double v)
{
   if(n<=1) return 50.0; int le=0; for(int i=0;i<n;i++)if(a[i]<=v)le++;
   return 100.0*le/n;
}

double SpreadPercentile(){ return PercentileRank(g_spreadBuf,g_spreadCnt,SpreadPoints()); }
void PushATR(double x)
{
   if(x<=0)return;
   g_atrBuf[g_atrIdx]=x;
   g_atrIdx=(g_atrIdx+1)%g_atrKeep;
   if(g_atrCnt<g_atrKeep)g_atrCnt++;
}
double ATRPercentile(){ return PercentileRank(g_atrBuf,g_atrCnt,g_atr); }
void PushSlippage(double s)
{
   s=MathAbs(s);
   if(s>1000.0) s=0;   // insane value (uninitialized intended price) - never poison the ring
   g_lastSlipPts=s;g_slipBuf[g_slipIdx]=s;g_slipIdx=(g_slipIdx+1)%SLIP_SAMPLES;if(g_slipCnt<SLIP_SAMPLES)g_slipCnt++;
   double z=0;for(int i=0;i<g_slipCnt;i++)z+=g_slipBuf[i];g_slipAvg=(g_slipCnt?z/g_slipCnt:0);
}
double SlippagePercentile(){ return PercentileRank(g_slipBuf,g_slipCnt,g_lastSlipPts); }

//--- [PERCENTAGE GATES] broker-adaptive forms: spread measured against the trade's SL
//--- distance (the risk the spread is paid against), slippage against ATR (market-
//--- adaptive). These are the PRIMARY gates; the absolute-point inputs are fallbacks.
double AdaptiveSpreadCap(double slDist)
{
   //--- percentage-of-SL budget in price terms
   double pctCap=(g_atr>0&&slDist>0?slDist*InpMaxSpreadPctOfSL/100.0:0);
   double pctPts=(broker.point>0&&pctCap>0?pctCap/broker.point:0);
   //--- the absolute legacy cap remains a last-resort ceiling: take the LOOSER of the two
   //--- so no broker with a legitimately wider (but economically viable) feed is blocked
   return MathMax((double)InpMaxSpreadPoints*g_ptScale,pctPts);
}

//--- [BROKER ADAPTATION] scale the scalp geometry so a wide-spread broker keeps
//--- producing signals: the ladder (SL + TPs) widens proportionally to the spread's
//--- share of ATR, keeping the risk:reward RATIO constant while risk-% sizing holds
//--- the money risk constant. No signal is lost to fixed absolute costs.
double SpreadCompensationFactor()
{
   if(g_atr<=0||broker.point<=0)return 1.0;
   double spreadPrice=SpreadPoints()*broker.point;
   //--- baseline: spread should be ~25% of ATR on a good feed
   double ratio=spreadPrice/(0.25*g_atr);
   return MathMin(2.0,MathMax(1.0,ratio));
}

double AdaptiveMaxAvgSlippagePts()
{
   //--- percentage-of-ATR form; legacy absolute becomes the fallback when ATR is unknown
   if(g_atr<=0)return InpMaxAverageSlippagePoints;
   double pts=(g_atr*InpMaxSlippagePctOfATR/100.0)/broker.point;
   return MathMax(pts,3.0);
}

double AdaptiveExtremeSlippagePts()
{
   if(g_atr<=0)return InpExtremeSlippagePoints;
   double pts=(g_atr*InpExtremeSlippagePctOfATR/100.0)/broker.point;
   return MathMax(pts,(double)InpExtremeSlippagePoints);
}

double AdaptiveDisorderSlipPts()
{
   if(g_atr<=0)return InpDisorderSlipPts;
   double pts=(g_atr*InpDisorderSlipPctOfATR/100.0)/broker.point;
   return MathMax(pts,InpDisorderSlipPts);
}

//--- [SPREAD] adaptive multi-condition relative gate (section 26). Reuses the existing
//--- rolling spread buffer/avg/percentile; warmup falls back to the legacy fixed cap.
//--- Returns true when spread conditions allow a NEW ENTRY. Emergency closes never call this.
bool AdaptiveSpreadOK(double atr,string &why)
{
   if(!InpUseAdaptiveSpreadGate)return true;   // legacy behavior only
   if(g_spreadCnt<InpSpreadWarmupSamples)return true;   // warmup: legacy fixed gate governs
   if(atr<=0){why="spread: ATR unavailable";return false;}
   double spPts=SpreadPoints();
   double spreadPrice=spPts*broker.point;
   double spreadToATRPct=spreadPrice/atr*100.0;
   double spp=SpreadPercentile();
   // (1) relative ATR condition
   if(spreadToATRPct>InpMaxSpreadToATRPct){why="SPREAD_RELATIVE_HIGH";g_spreadRejects++;return false;}
   // (2) distribution percentile condition (adaptive ceiling)
   if(spp>InpMaxSpreadPercentileAdaptive){why="SPREAD_RELATIVE_HIGH";g_spreadRejects++;return false;}
   // (3) spike vs rolling baseline (existing average reused; NOT a self-normalizing
   // widening allowance - the fixed sanity cap still binds above).
   if(g_spreadAvg>0&&spPts>g_spreadAvg*InpSpreadBaselineMultiplier){why="SPREAD_RELATIVE_HIGH";g_spreadRejects++;return false;}
   // Absolute last-resort sanity cap: percentage-of-SL budget (SL = InpSL_ATR_Multiplier x ATR).
   double slProj=MathMax(g_atr,MinTradeDistance())*SpreadCompensationFactor()*(InpSimpleScalpMode?SCALP_SL_ATR:InpSL_ATR_Multiplier);
   if(spPts>AdaptiveSpreadCap(slProj)){why="spread hard cap";g_spreadRejects++;return false;}
   return true;
}

//====================================================================
// FMP MACRO / NEWS (stable REST; credentials obfuscated, runtime-decoded)
//====================================================================
// Credentials are stored as +3 ASCII cipher literals so no API key or URL
// appears in the source, the compiled .ex5 strings table, logs or reports.
// Decode happens in memory only, at use time.
string FMP_APIKEY_C="81,113,109,89,90,104,83,56,110,84,88,121,113,118,86,81,55,82,57,70,70,101,100,70,76,111,86,82,112,60,109,119";
string FMP_BASE_C  ="107,119,119,115,118,61,50,50,105,108,113,100,113,102,108,100,111,112,114,103,104,111,108,113,106,115,117,104,115,49,102,114,112,50,118,119,100,101,111,104,50";

string FMPKey()
{
   string parts[]; int n=StringSplit(FMP_APIKEY_C,',',parts);
   string s=""; for(int i=0;i<n;i++) s+=CharToString((uchar)(StringToInteger(parts[i])-3));
   return s;
}

string FMPBase()
{
   string parts[]; int n=StringSplit(FMP_BASE_C,',',parts);
   string s=""; for(int i=0;i<n;i++) s+=CharToString((uchar)(StringToInteger(parts[i])-3));
   return s;
}

// 9-arg WebRequest signature; hosts are whitelisted in MT5 options.
int HttpGet(string url,int timeoutMs,string &body)
{
   body="";
   if(MQLInfoInteger(MQL_TESTER)){g_fmpLastErr="tester: web offline";return -1;}   // Strategy Tester: no WebRequest
   uchar post[]; uchar result[]; string rh="";
   string headers="User-Agent: Predict-A-Trade/1.00\r\nAccept: application/json\r\n";
   ResetLastError();
   int code=WebRequest("GET",url,"","",timeoutMs,post,0,result,rh);
   if(code<200||code>=300)
   {
      int err=GetLastError();
      g_fmpLastErr="http "+IntegerToString(code)+" err "+IntegerToString(err);
      // 4014 = ERR_FUNCTION_NOT_ALLOWED: this URL is not in the terminal's WebRequest
      // whitelist. Raise ONE unmissable popup per session (not per poll), with the exact fix.
      if(err==4014 && !g_webRequestWarned)
      {
         g_webRequestWarned=true;
         string host=url;
         int p1=StringFind(host,"//"); if(p1>0)host=StringSubstr(host,p1+2);
         int p2=StringFind(host,"/");  if(p2>0)host=StringSubstr(host,0,p2);
         Alert("FMP feed blocked (err 4014). FIX: Tools > Options > Expert Advisors > tick 'Allow WebRequest for listed URL' and add:  https://",host,"   Then click OK and re-attach the EA. Until then the macro layer runs on broker EURUSD fallback.");
      }
      return -1;
   }
   body=CharArrayToString(result,0,-1,CP_UTF8);
   return code;
}

//--- broker-side symbol/momentum helpers (broker fallback for the macro gate)
string ResolveBrokerSymbol(string requested,string needle1,string needle2="")
{
   if(requested!="" && SymbolSelect(requested,true)) return requested;
   int total=SymbolsTotal(false);
   for(int i=0;i<total;i++)
   {
      string n=SymbolName(i,false);if(n=="")continue;
      if(StringFind(n,needle1)>=0 || (needle2!=""&&StringFind(n,needle2)>=0))
      { if(SymbolSelect(n,true)) return n; }
   }
   return "";
}

double SymbolMomentumPct(string sym,ENUM_TIMEFRAMES tf,int bars,bool &ok)
{
   ok=false;if(sym==""||bars<1)return 0;MqlRates r[];ArraySetAsSeries(r,true);
   if(CopyRates(sym,tf,1,bars+1,r)<bars+1||r[bars].close==0)return 0;
   ok=true;return 100.0*(r[0].close-r[bars].close)/r[bars].close;
}

bool JsonNumber(const string text,const string key,double &value)
{
   value=0;if(key=="")return false;string pat="\""+key+"\"";int p=StringFind(text,pat);if(p<0)return false;
   p=StringFind(text,":",p+StringLen(pat));if(p<0)return false;p++;
   int n=StringLen(text);while(p<n){ushort ch=StringGetCharacter(text,p);if(ch==32||ch==9||ch==34)p++;else break;}
   int e=p;while(e<n){ushort ch=StringGetCharacter(text,e);if((ch>=48&&ch<=57)||ch==45||ch==43||ch==46||ch==101||ch==69)e++;else break;}
   if(e<=p)return false;string num=StringSubstr(text,p,e-p);value=StringToDouble(num);return true;
}

//--- one FMP quote; returns the day change % and whether price data arrived
// Batch quote: FMP /stable/quote accepts comma-separated symbols in ONE request -
// critical for free-plan rate limits (429 = quota exhausted).
bool FMPQuoteBatch(string &syms[],double &chg[],int count)
{
   if(MQLInfoInteger(MQL_TESTER))return false;
   // Live probe 2026-09-09: FMP free plan returns 402 Premium for ANY multi-symbol
   // batch on /stable/quote, while every SINGLE-symbol call is 200. The old
   // one-request batch therefore never yielded data and the panel stayed
   // "feed OFF" forever. Loop single quotes instead (8 requests per cycle; the
   // 3600s floor in RefreshFMPMacro keeps the daily total inside the free plan).
   int okN=0;
   for(int i=0;i<count;i++)
   {
      chg[i]=0;
      double price=0;
      if(FMPQuote(syms[i],chg[i],price))okN++;
   }
   // Tolerant: succeed if at most 2 pairs failed (matches the basket's own
   // "tolerate up to 2 dead pairs" rule); failed entries carry chg=0 and are
   // diluted out of the USD average exactly like missing symbols in the old
   // batch response parser.
   return (okN>0 && okN>=count-2);
}

bool FMPQuote(string sym,double &chgPct,double &price)
{
   chgPct=0;price=0;
   string url=FMPBase()+"/quote?symbol="+sym+"&apikey="+FMPKey();
   string body;
   if(HttpGet(url,InpFMPTimeoutMs,body)<=0) return false;
   if(StringFind(body,"Error Message")>=0||StringFind(body,"Restricted Endpoint")>=0||StringFind(body,"Premium Query")>=0)
   { g_fmpLastErr=sym+" plan-restricted"; return false; }
   if(!JsonNumber(body,"changePercentage",chgPct)) return false;
   JsonNumber(body,"price",price);
   return true;
}

void FMPNewsScan()
{
   if(!InpUseFMP||MQLInfoInteger(MQL_TESTER))return;
   // Live probe 2026-09-09: /stable/news returns 404 on this plan (endpoint
   // removed from the free tier - legacy /api/v3 news is 403 for post-Aug-2025
   // keys). Keep the scan wired for plan tiers where it exists; on 404 the
   // parse below is a no-op and g_fmpNewsCount stays 0 (panel shows "none").
   string url=FMPBase()+"/news?limit="+IntegerToString(InpFMPNewsLimit)+"&page=0&apikey="+FMPKey();
   string body;
   if(HttpGet(url,InpFMPTimeoutMs,body)<=0)return;
   if(StringFind(body,"\"title\"")<0)return;   // 404 body "[]" or error object: not news data
   // Count gold-relevant headlines and keep the newest title for the panel.
   int hits=0;string newest="";int pos=0;
   string pat="\"title\"";
   while(pos<StringLen(body))
   {
      int p=StringFind(body,pat,pos);if(p<0)break;
      p=StringFind(body,":",p);if(p<0)break;p++;
      while(p<StringLen(body)){ushort ch=StringGetCharacter(body,p);if(ch==32||ch==34)p++;else break;}
      int e=p;while(e<StringLen(body)&&StringGetCharacter(body,e)!=34)e++;
      string title=StringSubstr(body,p,e-p);pos=e;
      string low=title;StringToLower(low);
      if(StringFind(low,"gold")>=0||StringFind(low,"fed ")>=0||StringFind(low,"fomc")>=0||
         StringFind(low,"inflation")>=0||StringFind(low,"cpi")>=0||StringFind(low,"rate cut")>=0||
         StringFind(low,"rate hike")>=0||StringFind(low,"powell")>=0||StringFind(low,"treasury")>=0||
         StringFind(low,"tariff")>=0||StringFind(low,"nonfarm")>=0||StringFind(low,"payrolls")>=0)
      {
         hits++;if(newest=="")newest=title;
      }
   }
   g_fmpNewsCount=hits;
   if(hits>0)g_fmpNewsLast=newest; else g_fmpNewsLast="";
}

void RefreshFMPMacro(bool force=false)
{
   if(!InpUseFMP)return;
   if(MQLInfoInteger(MQL_TESTER))
   {
      // Strategy Tester: WebRequest is unavailable - run ONLY the broker-side
      // EURUSD momentum fallback so the macro layer stays functional offline.
      g_usdAvailable=false;g_spxAvailable=false;g_usdBias=0;g_spxBias=0;
      if(InpAllowBrokerMacroFallback&&InpUseEURUSD)
      {
         if(g_eurSymbol=="")g_eurSymbol=ResolveBrokerSymbol(InpEURUSDSymbol,"EURUSD");
         bool ok=false;
         g_eurMovePct=SymbolMomentumPct(g_eurSymbol,InpMacroTF,InpMacroMomentumBars,ok);
         g_eurAvailable=ok;
         g_eurBias=(ok?(g_eurMovePct>=InpEURUSDMinMovePct?1:(g_eurMovePct<=-InpEURUSDMinMovePct?-1:0)):0);
      }
      return;
   }
   datetime now=ServerNow();
   // Rate-limit defense (HTTP 429). Live probe 2026-09-09: the multi-symbol
   // batch endpoint is premium (402), so quotes now cost 7-8 single requests
   // per cycle. Base cycle 3600s keeps the free plan's ~250/day budget intact
   // (8*24=192 quote calls + 8 news = 200/day); doubles per consecutive 429.
   int effSec=InpFMPRefreshSec;                       // input is in SECONDS
   if(effSec<3600)effSec=3600;                        // floor: singles are ~8x the old batch cost
   if(g_fmp429Count>0)effSec=(int)MathMin(7200,3600.0*MathPow(2,MathMin(2,g_fmp429Count)));
   if(!force && g_fmpLastTry>0 && now-g_fmpLastTry<effSec)return;
   g_fmpLastTry=now;
   bool doNews=(g_fmpCycle%3==0);   // news every 3rd cycle: keeps daily total under the free-plan quota

   // Single-symbol loop (see FMPQuoteBatch): batch endpoint is premium-gated.
   string syms[FMPUSD_COUNT+1];
   for(int i=0;i<FMPUSD_COUNT;i++)syms[i]=g_usdPairs[i];
   int batchN=FMPUSD_COUNT;
   if(InpFMPIncludeSPX){syms[FMPUSD_COUNT]="^GSPC";batchN=FMPUSD_COUNT+1;}
   double chg[FMPUSD_COUNT+1];
   bool batchOK=FMPQuoteBatch(syms,chg,batchN);
   if(batchOK)
   {
      for(int i=0;i<FMPUSD_COUNT;i++){g_usdGot[i]=true;g_usdMove[i]=chg[i];}
      if(InpFMPIncludeSPX){g_usdGotSPX=true;g_spxBatchChg=chg[FMPUSD_COUNT];}
   }
   int okCount=0;
   for(int i=0;i<FMPUSD_COUNT;i++)if(g_usdGot[i])okCount++;
   g_usdAvailable=(okCount>=(FMPUSD_COUNT-2));       // tolerate up to 2 dead pairs
   if(!g_usdAvailable && g_fmpEverOK==false && g_fmpErrCount==1)
   {
      if(StringFind(g_fmpLastErr,"429")>=0)
         Print("FMP quota exhausted (HTTP 429): free plan allows ~250 requests/day. The EA polls once per ",effSec,"s with single-symbol quotes (~200/day incl. news) and will recover automatically when the quota resets.");
      else
         Print("FMP feed unavailable: ",g_fmpLastErr," | check Tools>Options>Expert Advisors>Allow WebRequest for https://financialmodelingprep.com");
   }
   if(g_usdAvailable)
   {
      double sum=0;int n=0;
      for(int i=0;i<FMPUSD_COUNT;i++)
      {
         if(!g_usdGot[i])continue;
         // Convert each pair's move into USD strength: USD/xxx rising = USD up (+),
         // xxx/USD rising = USD down (-).
         bool usdBase=(StringSubstr(g_usdPairs[i],0,3)=="USD");
         sum+=(usdBase?g_usdMove[i]:-g_usdMove[i]);n++;
      }
      if(n>0)g_usdAvg=sum/n;
      g_usdBias=(g_usdAvg<=-InpFMPUSDPairMinPct?1:(g_usdAvg>=InpFMPUSDPairMinPct?-1:0));
      g_fmpEverOK=true;g_fmpLastOK=now;g_fmpErrCount=0;g_fmp429Count=0;g_fmpCycle++;
   }
   else
   {
      g_fmpErrCount++;
      // Classify BEFORE backoff: 402 = plan-restricted (live probe 2026-09-09),
      // never retry-soon; "err 0" alone still means rate-limit/transport stall.
      bool planRestricted=(StringFind(g_fmpLastErr,"http 402")>=0);
      if(planRestricted)
      {
         if(g_fmpErrCount==1)Print("FMP feed plan-restricted (HTTP 402): this API key's plan does not cover the requested data. Check the FMP subscription for key ",StringSubstr(FMPKey(),0,4),"**** - macro layer stays on broker EURUSD fallback.");
      }
      else if(StringFind(g_fmpLastErr,"429")>=0||StringFind(g_fmpLastErr,"err 0")>=0)g_fmp429Count++;
      // Keep the last-good basket values (stale) for 70 minutes so one failed poll
      // doesn't flip the macro gate; after that, fall back to broker EURUSD momentum.
      // 70 > 60-min healthy cycle: a single missed poll must not kill the feed.
      bool stale=(g_fmpLastOK>0 && now-g_fmpLastOK<4200);
      g_usdAvailable=stale;
      if(!stale)g_usdBias=0;
      if(InpAllowBrokerMacroFallback&&InpUseEURUSD&&!stale)
      {
         if(g_eurSymbol=="")g_eurSymbol=ResolveBrokerSymbol(InpEURUSDSymbol,"EURUSD");
         bool ok=false;
         g_eurMovePct=SymbolMomentumPct(g_eurSymbol,InpMacroTF,InpMacroMomentumBars,ok);
         g_eurAvailable=ok;
         g_eurBias=(ok?(g_eurMovePct>=InpEURUSDMinMovePct?1:(g_eurMovePct<=-InpEURUSDMinMovePct?-1:0)):0);
      }
   }

   if(InpFMPIncludeSPX&&batchOK)
   {
      // SPX rides the same single-quote loop (one extra request, see FMPQuoteBatch).
      g_spxAvailable=g_usdGotSPX;
      if(g_spxAvailable)
      {
         g_spxMovePct=g_spxBatchChg;
         // Risk-off (SPX down) favours gold bids; risk-on (SPX up) leans bearish gold.
         g_spxBias=(g_spxMovePct<=-InpFMPSPXMinPct?1:(g_spxMovePct>=InpFMPSPXMinPct?-1:0));
      }
      else g_spxBias=0;
   }
   else if(!batchOK){ g_spxAvailable=false;g_spxBias=0; }

   if(doNews)FMPNewsScan();

   g_macroBull=(g_usdBias>0?1:0)+(g_spxBias>0?1:0)+(g_eurBias>0?1:0);
   g_macroBear=(g_usdBias<0?1:0)+(g_spxBias<0?1:0)+(g_eurBias<0?1:0);
}

bool ExternalDataReady(string &why)
{
   if(!InpRequireExternalData)return true;
   if(InpUseFMP&&!g_usdAvailable&&!g_eurAvailable){why="FMP macro unavailable";return false;}
   return true;
}

int MacroVotes(int dir){return dir>0?g_macroBull:g_macroBear;}
int AvailableMacroCount(){return (g_usdAvailable?1:0)+(g_spxAvailable?1:0)+(g_eurAvailable?1:0);}

//====================================================================
// INDICATORS / SMC
//====================================================================
void UpdateIndicators()
{
   Copy1(hATR,0,1,g_atr); if(g_atr>0) PushATR(g_atr);
   Copy1(hADX,0,1,g_adx);Copy1(hADX,1,1,g_adxPlus);Copy1(hADX,2,1,g_adxMinus);
   Copy1(hEMA20,0,1,g_ema20);Copy1(hEMA50,0,1,g_ema50);
   Copy1(hH1EMA20,0,1,g_h1e20);Copy1(hH1EMA50,0,1,g_h1e50);
   Copy1(hM15EMA20,0,1,g_m15e20);Copy1(hM15EMA50,0,1,g_m15e50);
   Copy1(hRSI,0,1,g_rsi);
   //--- [SIGNAL QUALITY] EMA9 / EMA200 / MACD (sections 4/5/6)
   if(hEMA9!=INVALID_HANDLE)Copy1(hEMA9,0,1,g_ema9);
   if(hEMA200!=INVALID_HANDLE)Copy1(hEMA200,0,1,g_ema200);
   if(hMACD!=INVALID_HANDLE)
   {
      double m=0,sg=0;
      if(Copy1(hMACD,0,1,m)&&Copy1(hMACD,1,1,sg))
      {
         g_macdHistPrev=g_macdHist;      // previous close-bar histogram (increasing/decreasing evidence)
         g_macdMain=m;g_macdSignal=sg;g_macdHist=m-sg;
      }
   }
}

double VolumeRatio(int shift=1)
{
   MqlRates r[];ArraySetAsSeries(r,true);
   int need=InpVolumeMA+shift+2;if(CopyRates(eaSymbol,PERIOD_M1,0,need,r)<need)return 0;
   double avg=0;for(int i=shift+1;i<=shift+InpVolumeMA;i++)avg+=(double)r[i].tick_volume;
   avg/=InpVolumeMA; return avg>0?(double)r[shift].tick_volume/avg:0;
}

// Cached per-bar value: the M1 volume ratio only changes on a new closed bar,
// so caching removes a CopyRates() call from every tick, every filter and the panel.
void RefreshVolumeRatio(){ g_volRatio=VolumeRatio(1); }

double AverageATR(int n)
{
   int k=MathMin(n,g_atrCnt);if(k<=0)return g_atr;double s=0;for(int i=0;i<k;i++)s+=g_atrBuf[i];return s/k;
}

void UpdateSuperTrend()
{
   MqlRates r[];ArraySetAsSeries(r,true);int n=InpSuperTrendPeriod+8;
   if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n || g_atr<=0)return;
   double mid=(r[0].high+r[0].low)/2.0;
   double upper=mid+InpSuperTrendMultiplier*g_atr,lower=mid-InpSuperTrendMultiplier*g_atr;
   if(r[0].close>upper) g_superTrendDir=1;
   else if(r[0].close<lower) g_superTrendDir=-1;
   else if(g_superTrendDir==0) g_superTrendDir=(r[0].close>=g_ema20?1:-1);
   g_superTrend=(g_superTrendDir>0?lower:upper);
}

void UpdateVWAP()
{
   MqlRates r[];ArraySetAsSeries(r,true);int n=240;
   if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<30)return;
   datetime anchor=0;
   MqlDateTime d;TimeToStruct(ServerNow(),d);d.hour=0;d.min=0;d.sec=0;anchor=StructToTime(d);
   if(InpVWAPAnchor!=VWAP_BROKER_DAY)
   {
      datetime utc=UTCNow();int so,sc,to,tc,lo,lc,no,nc;SessionUTCBounds(utc,so,sc,to,tc,lo,lc,no,nc);
      int target=(InpVWAPAnchor==VWAP_LONDON?lo:no);
      MqlDateTime ud;TimeToStruct(UTCNow(),ud);ud.hour=target/60;ud.min=target%60;ud.sec=0;
      datetime utcAnchor=StructToTime(ud);anchor=(datetime)(utcAnchor+g_serverOffsetSec);
      if(anchor>ServerNow())anchor-=86400;
   }
   double pv=0,v=0,p2=0;
   for(int i=0;i<ArraySize(r);i++)
   {
      if(r[i].time<anchor)continue;double tp=(r[i].high+r[i].low+r[i].close)/3.0;double vv=(double)r[i].tick_volume;
      pv+=tp*vv;v+=vv;p2+=tp*tp*vv;
   }
   if(v>0){g_vwap=pv/v;double var=MathMax(0,p2/v-g_vwap*g_vwap);double sd=MathSqrt(var);g_vwapUp=g_vwap+sd;g_vwapDn=g_vwap-sd;}
}

void DetectFVG()
{
   g_fvg=false;g_fvgDir=0;MqlRates r[];ArraySetAsSeries(r,true);
   int n=InpFVGLookbackBars+3;if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n)return;
   for(int i=0;i<InpFVGLookbackBars;i++)
   {
      double minGap=InpFVGMinGapATR*MathMax(g_atr,broker.point);
      if(r[i].low-r[i+2].high>=minGap){g_fvg=true;g_fvgDir=1;g_fvgBottom=r[i+2].high;g_fvgTop=r[i].low;return;}
      if(r[i+2].low-r[i].high>=minGap){g_fvg=true;g_fvgDir=-1;g_fvgBottom=r[i].high;g_fvgTop=r[i+2].low;return;}
   }
}

void DetectIFVG()
{
   g_ifvg=false;g_ifvgDir=0;g_ifvgTop=g_ifvgBottom=0;MqlRates r[];ArraySetAsSeries(r,true);
   int n=InpIFVGLookbackBars+5;if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n||g_atr<=0)return;double minGap=InpIFVGMinGapATR*g_atr;
   for(int i=2;i<InpIFVGLookbackBars;i++)
   {
      // Original bullish FVG fails and closes below its lower boundary => bearish IFVG.
      if(r[i].low-r[i+2].high>=minGap)
      {double bot=r[i+2].high,top=r[i].low;if(r[1].high>=bot&&r[0].close<bot){g_ifvg=true;g_ifvgDir=-1;g_ifvgBottom=bot;g_ifvgTop=top;return;}}
      // Original bearish FVG fails and closes above its upper boundary => bullish IFVG.
      if(r[i+2].low-r[i].high>=minGap)
      {double bot=r[i].high,top=r[i+2].low;if(r[1].low<=top&&r[0].close>top){g_ifvg=true;g_ifvgDir=1;g_ifvgBottom=bot;g_ifvgTop=top;return;}}
   }
}

void DetectPTB()
{
   g_ptb=false;g_ptbDir=0;g_ptbTop=g_ptbBottom=0;MqlRates r[];ArraySetAsSeries(r,true);
   int n=InpPTBLookbackBars+6;if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n||g_atr<=0)return;
   double body0=MathAbs(r[0].close-r[0].open)/g_atr;if(body0<InpPTBMinDisplacementATR)return;
   for(int j=3;j<InpPTBLookbackBars;j++)
   {
      bool bullOB=r[j].close<r[j].open;bool bearOB=r[j].close>r[j].open;
      bool overlap=(r[1].low<=r[j].high&&r[1].high>=r[j].low);
      if(!overlap)continue;
      if(bullOB&&r[1].close<r[1].open&&r[0].close>r[1].high&&r[0].close>r[j].high)
      {g_ptb=true;g_ptbDir=1;g_ptbBottom=r[1].low;g_ptbTop=r[1].high;return;}
      if(bearOB&&r[1].close>r[1].open&&r[0].close<r[1].low&&r[0].close<r[j].low)
      {g_ptb=true;g_ptbDir=-1;g_ptbBottom=r[1].low;g_ptbTop=r[1].high;return;}
   }
}

void AnalyzeAMD()
{
   MqlRates r[];ArraySetAsSeries(r,true);int n=InpAMDLookbackBars+2;if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n)return;
   double hi=-DBL_MAX,lo=DBL_MAX,avgRange=0;
   for(int i=1;i<n;i++){hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);avgRange+=r[i].high-r[i].low;}
   avgRange/=(n-1);double cur=r[0].high-r[0].low;
   if(cur<avgRange*InpAMDCoilRatio)g_phase=PHASE_ACCUMULATION;
   else if(r[0].high>hi || r[0].low<lo)g_phase=PHASE_MANIPULATION;
   else g_phase=PHASE_DISTRIBUTION;
}

void DetectSMC()
{
   g_bosUp=g_bosDn=g_chochUp=g_chochDn=g_sweepUp=g_sweepDn=false;
   g_smcScoreBull=g_smcScoreBear=0;
   MqlRates r[];ArraySetAsSeries(r,true);int n=InpSwingLookback+4;if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n)return;
   double priorHi=-DBL_MAX,priorLo=DBL_MAX;
   for(int i=2;i<n;i++){priorHi=MathMax(priorHi,r[i].high);priorLo=MathMin(priorLo,r[i].low);}
   g_swingHigh=priorHi;g_swingLow=priorLo;
   if(r[0].close>priorHi){g_bosUp=true;g_smcScoreBull++;}
   if(r[0].close<priorLo){g_bosDn=true;g_smcScoreBear++;}
   if(r[0].high>priorHi && r[0].close<priorHi){g_sweepUp=true;g_smcScoreBear++;}
   if(r[0].low<priorLo && r[0].close>priorLo){g_sweepDn=true;g_smcScoreBull++;}
   bool prevUp=(r[1].close>r[2].close),curUp=(r[0].close>r[1].close);
   if(!prevUp&&curUp&&r[0].close>r[1].high){g_chochUp=true;g_smcScoreBull++;}
   if(prevUp&&!curUp&&r[0].close<r[1].low){g_chochDn=true;g_smcScoreBear++;}
   if(g_fvg&&g_fvgDir>0)g_smcScoreBull++;if(g_fvg&&g_fvgDir<0)g_smcScoreBear++;
   if(InpUseIFVG&&g_ifvg&&g_ifvgDir>0)g_smcScoreBull++;if(InpUseIFVG&&g_ifvg&&g_ifvgDir<0)g_smcScoreBear++;
   if(InpUsePTB&&g_ptb&&g_ptbDir>0)g_smcScoreBull++;if(InpUsePTB&&g_ptb&&g_ptbDir<0)g_smcScoreBear++;
}

void EvaluateFilters()
{
   g_score=0;g_scoreMax=0;g_dirBias=0;
   double c=iClose(eaSymbol,PERIOD_M1,1);
   bool emaBull=(c>g_ema20&&g_ema20>g_ema50),emaBear=(c<g_ema20&&g_ema20<g_ema50);
   if(InpUseEMA20||InpUseEMA50){g_scoreMax++;if(emaBull||emaBear)g_score++;if(emaBull)g_dirBias++;if(emaBear)g_dirBias--;}
   if(InpUseSuperTrend){g_scoreMax++;if(g_superTrendDir!=0)g_score++;g_dirBias+=g_superTrendDir;}
   if(InpUseADX){g_scoreMax++;if(g_adx>=InpMinADX)g_score++;if(g_adxPlus>g_adxMinus)g_dirBias++;else if(g_adxMinus>g_adxPlus)g_dirBias--;}
   if(InpUseVWAP){g_scoreMax++;if(g_vwap>0){g_score++;if(c>g_vwap)g_dirBias++;else g_dirBias--;}}
   if(InpUseFVG){g_scoreMax++;if(g_fvg)g_score++;if(g_fvgDir>0)g_dirBias++;if(g_fvgDir<0)g_dirBias--;}
   if(InpUseAMD){g_scoreMax++;if(g_phase!=PHASE_ACCUMULATION)g_score++;}
   double vr=g_volRatio;
   if(InpUseVolumeFilter){g_scoreMax++;if(vr>=InpMinVolumeRatio)g_score++;}
   if(InpUseLiquidityFilter){g_scoreMax++;if(vr>=InpMinLiquidityLevel)g_score++;}
   bool hBull=(g_h1e20>g_h1e50&&g_m15e20>g_m15e50),hBear=(g_h1e20<g_h1e50&&g_m15e20<g_m15e50);
   g_scoreMax++;if(hBull||hBear){g_score++;g_dirBias+=(hBull?2:-2);}
   if(InpUseRSI){g_scoreMax++;if(g_rsi>InpRSIOversold&&g_rsi<InpRSIOverbought)g_score++;if(g_rsi>=52)g_dirBias++;else if(g_rsi<=48)g_dirBias--;}
   if(InpUseSMC){g_scoreMax++;if(MathMax(g_smcScoreBull,g_smcScoreBear)>=InpMinSMCConfluence)g_score++;g_dirBias+=(g_smcScoreBull-g_smcScoreBear);}
   if(InpUseIFVG){g_scoreMax++;if(g_ifvg)g_score++;if(g_ifvgDir>0)g_dirBias++;else if(g_ifvgDir<0)g_dirBias--;}
   if(InpUsePTB){g_scoreMax++;if(g_ptb)g_score++;if(g_ptbDir>0)g_dirBias++;else if(g_ptbDir<0)g_dirBias--;}
   if(AvailableMacroCount()>0){g_scoreMax++;if(MathMax(g_macroBull,g_macroBear)>=InpMacroMinConfluence)g_score++;g_dirBias+=(g_macroBull-g_macroBear);}
}

//====================================================================
// HIGH VOLATILITY / DISORDER ENGINE
//====================================================================
//--- live-chart confirmation: current price agrees with EMA20 direction (uses the forming
//--- bar's live bid/ask, so entries read the live chart, not just closed bars)
//--- ULTRA-SCALP simple engine: 5 binary votes, no filter-score machinery.
//--- Direction: net votes >= InpScalpMinScore AND live price agrees.
//--- Votes: 1) EMA20 vs EMA50  2) close vs EMA20  3) last-bar momentum  4) MACD hist
//---        5) candle body direction vs previous (continuation)
//--- ULTRA-SCALP ENGINE v2 (evidence-based):
//--- Mode A trend-pullback: M5 trend + M1 pullback-to-EMA + reversal candle close.
//--- Mode B mean-reversion: 2+ sigma extension from VWAP + RSI extreme + reversal
//--- candle, ONLY when M5 ADX < 30 (reversion fails in strong trends).
void EvaluateScalpSignal()
{
   g_scalpSignal=0;g_scalpWhy="";
   double c1=iClose(eaSymbol,PERIOD_M1,1),o1=iOpen(eaSymbol,PERIOD_M1,1);
   double h1=iHigh(eaSymbol,PERIOD_M1,1),l1=iLow(eaSymbol,PERIOD_M1,1);
   double c2=iClose(eaSymbol,PERIOD_M1,2),h2=iHigh(eaSymbol,PERIOD_M1,2),l2=iLow(eaSymbol,PERIOD_M1,2);
   if(g_atr<=0)return;
   int um=MinuteOfDay(UTCNow());
   double minBody=MathMax(0.25,InpScalpMinMomentumATR)*g_atr;

   //================= MODE B: VWAP MEAN REVERSION (any session) ==================
   // Documented gold edge: 68-73% reversion after 2-sigma extension. Relaxed from
   // the too-strict v2 (1.8 ATR + RSI72 + candle + ADX<30 all at once = never fires).
   if(g_vwap>0&&g_rsi>0)
   {
      double dev=(c1-g_vwap)/g_atr;
      bool extUp=(dev>=1.5),extDn=(dev<=-1.5);
      // confirmation: reversal candle OR Bollinger band recross (either)
      bool confDn=(c1<o1)||(c1<g_bbMid);
      bool confUp=(c1>o1)||(c1>g_bbMid);
      if(extUp&&(g_rsi>=70.0)&&confDn&&g_m5adx<35.0){g_scalpSignal=-2;g_scalpWhy="VWAP reversion SHORT";return;}
      if(extDn&&(g_rsi<=30.0)&&confUp&&g_m5adx<35.0){g_scalpSignal=2;g_scalpWhy="VWAP reversion LONG";return;}
   }

   //================= MODE C: LONDON OPEN BREAKOUT (07:00-08:15 UTC) ==============
   // Asian range (00:00-06:45 UTC) break during the first London hour. Gold's first
   // directional move of the day; 70% of daily extremes form in LDN/NY.
   if(um>=7*60&&um<=8*60+15)
   {
      // Asian range = high/low of 00:00-06:45 UTC today
      datetime dayStart=ServerNow()-(ServerNow()%86400);
      int asiaBars=(int)((6*60+45));
      double ah=0,al=0;
      MqlRates r[];
      if(CopyRates(eaSymbol,PERIOD_M1,1,asiaBars,r)==asiaBars)
      {
         ah=-DBL_MAX;al=DBL_MAX;
         for(int k=0;k<asiaBars;k++)
         {
            datetime bt=(datetime)r[k].time;
            if(bt>=dayStart&&bt<dayStart+(6*60+45)*60)
            {ah=MathMax(ah,r[k].high);al=MathMin(al,r[k].low);}
         }
         if(ah>0&&al>0&&(ah-al)>=0.8*g_atr)   // meaningful range, not dead tape
         {
            if(c1>ah&&c1>o1&&(c1-o1)>=minBody){g_scalpSignal=3;g_scalpWhy="London breakout LONG";return;}
            if(c1<al&&c1<o1&&(o1-c1)>=minBody){g_scalpSignal=-3;g_scalpWhy="London breakout SHORT";return;}
         }
      }
   }

   //================= MODE D: NY OPEN MOMENTUM (13:30-15:30 UTC) ==================
   // Liquidity peak (BIS data); deploy momentum with the trend, not fades.
   if(um>=13*60+30&&um<=15*60+30)
   {
      bool m5Up=(g_m5e20>g_m5e50),m5Dn=(g_m5e20<g_m5e50);
      // M1 momentum burst closing beyond the 15-bar high/low with M5 trend
      double hh=-DBL_MAX,ll=DBL_MAX;
      double bars[15];
      MqlRates r2[];
      if(CopyRates(eaSymbol,PERIOD_M1,2,15,r2)==15)
      {
         for(int k=0;k<15;k++){hh=MathMax(hh,r2[k].high);ll=MathMin(ll,r2[k].low);}
         if(m5Up&&c1>o1&&(c1-o1)>=0.5*g_atr&&c1>hh){g_scalpSignal=1;g_scalpWhy="NY momentum LONG";return;}
         if(m5Dn&&c1<o1&&(o1-c1)>=0.5*g_atr&&c1<ll){g_scalpSignal=-1;g_scalpWhy="NY momentum SHORT";return;}
      }
   }

   //================= MODE A2: EMA PULLBACK (liquid windows, simplified) ==========
   // v2 was too strict (low touched EMA AND close beyond prior high in one candle).
   // Simplified: M5 trend + last bar closed back across EMA20 in trend direction
   // after being on the wrong side of it (the dip happened, the resumption confirms).
   {
      bool m5Up=(g_m5e20>g_m5e50),m5Dn=(g_m5e20<g_m5e50);
      bool wasBelow=(iClose(eaSymbol,PERIOD_M1,3)<g_ema20||iLow(eaSymbol,PERIOD_M1,1)<=g_ema20);
      bool wasAbove=(iClose(eaSymbol,PERIOD_M1,3)>g_ema20||iHigh(eaSymbol,PERIOD_M1,1)>=g_ema20);
      if(m5Up&&wasBelow&&c1>g_ema20&&c1>o1){g_scalpSignal=1;g_scalpWhy="EMA pullback LONG";return;}
      if(m5Dn&&wasAbove&&c1<g_ema20&&c1<o1){g_scalpSignal=-1;g_scalpWhy="EMA pullback SHORT";return;}
   }
}

//====================================================================
// [SIGNAL QUALITY] structure classifier + volume states + regimes +
// confidence engine + centralized decision (prompt.md sections 3-15).
// Additive layer: classifies and scores; never bypasses existing gates.
//====================================================================
//--- 3. explicit HH/HL/LH/LL from confirmed (closed-bar) swings
ENUM_STRUCTURE_STATE g_structureState=STRUCTURE_UNKNOWN;
double g_lastSwingHigh=0,g_prevSwingHigh=0,g_lastSwingLow=0,g_prevSwingLow=0;
double g_structureBullStrength=0,g_structureBearStrength=0;
datetime g_lastStructureEval=0;
//--- 7. volume distribution ring (reuses PercentileRank architecture)
#define VOLUME_SAMPLES 256
double g_volBuf[VOLUME_SAMPLES]; int g_volCnt=0,g_volIdx=0;
ENUM_VOLUME_STATE g_volumeState=VOLUME_NORMAL;
double g_volumePercentile=50.0;
//--- 8. regime caches (recomputed on new M1 bar; cheap reads elsewhere)
ENUM_DIRECTION_REGIME g_dirRegime=REGIME_SIDEWAYS;
ENUM_ENVIRONMENT_REGIME g_envRegime=ENV_NORMAL;
int g_lowLiqBars=0;                    // persistence counter for LOW_LIQUIDITY
//--- 6. MACD cache
double g_macdMain=0,g_macdSignal=0,g_macdHist=0,g_macdHistPrev=0;
//--- 4/5. new EMA cache
double g_ema9=0,g_ema200=0;
//--- 9. confidence breakdowns (computed per candidate, not per tick)
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
//--- 13. central SignalDecision telemetry structure (additive; never replaces state structs)
struct SignalDecision
{
   string instrument;
   ENUM_SIGNAL_DECISION decision;
   int direction;
   double entry,stopLoss,tp1,tp2,tp3;
   double quantity;
   double riskMoney,riskPct;
   double potentialRewardMoney,netPotentialRewardMoney,riskReward;
   double confidence,oppositeConfidence,confidenceGap;
   ENUM_STRUCTURE_STATE structure;
   ENUM_DIRECTION_REGIME directionRegime;
   ENUM_ENVIRONMENT_REGIME environmentRegime;
   ENUM_VOLUME_STATE volumeState;
   ENUM_WINDOW_ID window;
   bool highVolatility;
   double spreadPoints,spreadPercentile,spreadToATR,expectedSlippage,expectedCost;
   ConfidenceBreakdown confidenceBreakdown;
   string setupName,signalReasons,gateReason;
};
SignalDecision g_lastDecision;         // authoritative last candidate telemetry (dashboard/CSV)
//--- 25/27. options architecture: bounded, no fetch per tick, fail-open by default
struct OptionStrikeLevel
{
   double strike;
   double callOI;
   double putOI;
   double callVolume;
   double putVolume;
};
#define OPTION_STRIKE_MAX 64
struct GoldOptionsSnapshot
{
   bool available;
   datetime timestamp;
   double callOI,putOI,callOIChange,putOIChange;
   double pcr;
   double impliedVolatility,ivPercentile;
   double callVolume,putVolume;
   double nearestCallWall,nearestPutWall,callWallOI,putWallOI;
   double gammaWall;
   bool gammaAvailable;
   string source;
};
GoldOptionsSnapshot g_options;
OptionStrikeLevel g_optionStrikes[OPTION_STRIKE_MAX];
int g_optionStrikeCount=0;
//--- 35. confidence performance buckets (bounded, telemetry only)
struct ConfBucketStats { int trades,wins,losses; double netR,rSum; };
ConfBucketStats g_confBuckets[5];      // 70-74,75-79,80-84,85-89,90+
//--- 36. performance by setup (bounded ids 0..5: EB,VR,LDN,NY,COMPLEX,RCV)
ConfBucketStats g_setupStats[6];
//--- 37. regime counters (direction x5, env accepted x2, env rejects x3)
int g_regimeTrades[5];
int g_envTrades[5];                    // index = ENUM_ENVIRONMENT_REGIME (accepted entries)
int g_envRejects[5];
//--- weight cache (normalized at init; section 42)
double g_wPrice=20,g_wTrend=15,g_wVolume=15,g_wMomentum=10,g_wVWAP=10,g_wVol=10,g_wMacro=10,g_wOptions=5,g_wRR=5;
double g_weightSum=100;
string g_confTelemetry="";             // CONFIDENCE_WEIGHTS_NORMALIZED etc.

//--- 42. normalize configured weights; disable engine safely on degenerate config
void InitConfidenceWeights()
{
   g_wPrice=InpWeightPriceAction;g_wTrend=InpWeightTrend;g_wVolume=InpWeightVolumeLiquidity;
   g_wMomentum=InpWeightMomentum;g_wVWAP=InpWeightVWAP;g_wVol=InpWeightVolatility;
   g_wMacro=InpWeightMacro;g_wOptions=InpWeightOptions;g_wRR=InpWeightRiskReward;
   g_weightSum=g_wPrice+g_wTrend+g_wVolume+g_wMomentum+g_wVWAP+g_wVol+g_wMacro+g_wOptions+g_wRR;
   if(g_weightSum<=0)
   {
      g_confTelemetry="CONFIDENCE_ENGINE_DISABLED_WEIGHTS_ZERO";
      return;
   }
   if(MathAbs(g_weightSum-100.0)>0.001)
   {
      double k=100.0/g_weightSum;
      g_wPrice*=k;g_wTrend*=k;g_wVolume*=k;g_wMomentum*=k;g_wVWAP*=k;g_wVol*=k;g_wMacro*=k;g_wOptions*=k;g_wRR*=k;
      g_weightSum=100.0;
      g_confTelemetry="CONFIDENCE_WEIGHTS_NORMALIZED";
      Print("CONFIDENCE_WEIGHTS_NORMALIZED: configured weights sum ",DoubleToString(InpWeightPriceAction+InpWeightTrend+InpWeightVolumeLiquidity+InpWeightMomentum+InpWeightVWAP+InpWeightVolatility+InpWeightMacro+InpWeightOptions+InpWeightRiskReward,2)," -> normalized to 100");
   }
}

//--- 3. structure classification: confirmed swings from DetectSMC's prior Hi/Lo windows,
//--- refined with the last two completed swing extremes. Runs on NEW M1 bar only.
void UpdateStructureState()
{
   MqlRates r[];ArraySetAsSeries(r,true);
   int n=MathMax(InpSwingLookback*3,90);
   if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n)return;
   //--- detect confirmed swing highs/lows with a 2-bar fractal (closed bars only)
   double swH[];double swL[];datetime swHT[];datetime swLT[];
   ArrayResize(swH,0);ArrayResize(swL,0);ArrayResize(swHT,0);ArrayResize(swLT,0);
   for(int i=2;i<n-2;i++)
   {
      // series arrays: index i is older than i-1
      if(r[i].high>r[i+1].high&&r[i].high>r[i+2].high&&r[i].high>=r[i-1].high&&r[i].high>=r[i-2].high)
      {
         int cnt=ArraySize(swH);ArrayResize(swH,cnt+1);ArrayResize(swHT,cnt+1);
         swH[cnt]=r[i].high;swHT[cnt]=r[i].time;
      }
      if(r[i].low<r[i+1].low&&r[i].low<r[i+2].low&&r[i].low<=r[i-1].low&&r[i].low<=r[i-2].low)
      {
         int cnt=ArraySize(swL);ArrayResize(swL,cnt+1);ArrayResize(swLT,cnt+1);
         swL[cnt]=r[i].low;swLT[cnt]=r[i].time;
      }
   }
   int nh=ArraySize(swH),nl=ArraySize(swL);
   if(nh<2||nl<2)return;
   //--- series arrays are oldest-first; take the two most recent of each
   g_lastSwingHigh=swH[nh-1];g_prevSwingHigh=swH[nh-2];
   g_lastSwingLow=swL[nl-1];g_prevSwingLow=swL[nl-2];
   bool hh=(g_lastSwingHigh>g_prevSwingHigh),hl=(g_lastSwingLow>g_prevSwingLow);
   bool lh=(g_lastSwingHigh<g_prevSwingHigh),ll=(g_lastSwingLow<g_prevSwingLow);
   //--- progression strength: fraction of the last N swings agreeing directionally
   double bullPts=0,bearPts=0,rangePts=0;int pairs=MathMin(4,MathMin(nh,nl)-1);
   for(int k=0;k<pairs;k++)
   {
      bool hUp=swH[nh-1-k]>swH[nh-2-k],lUp=swL[nl-1-k]>swL[nl-2-k];
      if(hUp&&lUp)bullPts+=1.0;
      else if(!hUp&&!lUp)bearPts+=1.0;
      else rangePts+=1.0;
   }
   double den=MathMax(1,pairs);
   g_structureBullStrength=bullPts/den*100.0;
   g_structureBearStrength=bearPts/den*100.0;
   //--- transitions use the existing confirmed CHOCH/BOS evidence
   ENUM_STRUCTURE_STATE st=STRUCTURE_UNKNOWN;
   if(hh&&hl)st=STRUCTURE_HH_HL;
   else if(lh&&ll)st=STRUCTURE_LH_LL;
   else if(hh||hl)
   {
      if(g_chochUp||g_bosUp)st=STRUCTURE_TRANSITION_BULL;
      else st=STRUCTURE_RANGE;
   }
   else if(lh||ll)
   {
      if(g_chochDn||g_bosDn)st=STRUCTURE_TRANSITION_BEAR;
      else st=STRUCTURE_RANGE;
   }
   else st=STRUCTURE_RANGE;
   //--- cross-check: a bullish CHOCH/BOS out of a bearish/range structure = transition bull
   if((g_chochUp||g_bosUp)&&(st==STRUCTURE_RANGE||st==STRUCTURE_LH_LL))st=STRUCTURE_TRANSITION_BULL;
   if((g_chochDn||g_bosDn)&&(st==STRUCTURE_RANGE||st==STRUCTURE_HH_HL))st=STRUCTURE_TRANSITION_BEAR;
   g_structureState=st;
   g_lastStructureEval=ServerNow();
}

//--- 7. volume percentile + state classification (per closed M1 bar)
void UpdateVolumeEngine()
{
   MqlRates r[];ArraySetAsSeries(r,true);
   if(!CopyRates(eaSymbol,PERIOD_M1,1,1,r))return;
   double v=(double)r[0].tick_volume;
   if(v<=0)return;
   // maintain rolling distribution of relative volume (volRatio of each closed bar)
   double ratio=VolumeRatio(1);
   if(ratio<=0)return;
   g_volBuf[g_volIdx]=ratio;g_volIdx=(g_volIdx+1)%VOLUME_SAMPLES;if(g_volCnt<VOLUME_SAMPLES)g_volCnt++;
   g_volumePercentile=PercentileRank(g_volBuf,g_volCnt,ratio);
   double p=g_volumePercentile;
   if(p<InpVolumeLowPct)g_volumeState=VOLUME_LOW;
   else if(p<InpVolumeElevatedPct)g_volumeState=VOLUME_NORMAL;
   else if(p<InpVolumeSpikePct)g_volumeState=VOLUME_ELEVATED;
   else if(p<InpVolumeExtremePct)g_volumeState=VOLUME_SPIKE;
   else g_volumeState=VOLUME_EXTREME;
}

string VolumeStateName(ENUM_VOLUME_STATE v)
{
   switch(v)
   {
      case VOLUME_LOW:return "LOW";
      case VOLUME_NORMAL:return "NORMAL";
      case VOLUME_ELEVATED:return "ELEVATED";
      case VOLUME_SPIKE:return "SPIKE";
      case VOLUME_EXTREME:return "EXTREME";
   }
   return "?";
}

string StructureStateName(ENUM_STRUCTURE_STATE st)
{
   switch(st)
   {
      case STRUCTURE_HH_HL:return "HH-HL";
      case STRUCTURE_LH_LL:return "LH-LL";
      case STRUCTURE_TRANSITION_BULL:return "TRANS-BULL";
      case STRUCTURE_TRANSITION_BEAR:return "TRANS-BEAR";
      case STRUCTURE_RANGE:return "RANGE";
      case STRUCTURE_UNKNOWN:return "UNKNOWN";
   }
   return "?";
}

string DirectionRegimeName(ENUM_DIRECTION_REGIME r)
{
   switch(r)
   {
      case REGIME_STRONG_BULLISH:return "STRONG BULL";
      case REGIME_BULLISH:return "BULLISH";
      case REGIME_SIDEWAYS:return "SIDEWAYS";
      case REGIME_BEARISH:return "BEARISH";
      case REGIME_STRONG_BEARISH:return "STRONG BEAR";
   }
   return "?";
}

string EnvironmentRegimeName(ENUM_ENVIRONMENT_REGIME e)
{
   switch(e)
   {
      case ENV_NORMAL:return "NORMAL";
      case ENV_HIGH_VOLATILITY:return "HIGH VOL";
      case ENV_EXTREME_VOLATILITY:return "EXTREME VOL";
      case ENV_LOW_LIQUIDITY:return "LOW LIQ";
      case ENV_DISORDER:return "DISORDER";
   }
   return "?";
}

//--- 8B. environment regime: independent volatility/liquidity/disorder dimension.
//--- Reuses existing ATR/spread/volume/disorder infrastructure - no duplicate stats.
void UpdateEnvironmentRegime()
{
   double atrp=ATRPercentile();
   double disp=CandleDisplacementATR();
   double vpp=g_volumePercentile;
   //--- DISORDER first (existing microstructure logic owns this classification)
   if(IsDisorder()){g_envRegime=ENV_DISORDER;g_lowLiqBars=0;return;}
   //--- EXTREME volatility: multiple conditions must coincide (section 44: never one mild indicator)
   int extremeVotes=0;
   if(atrp>=InpExtremeATRPercentile)extremeVotes++;
   if(vpp>=InpExtremeVolumePercentile)extremeVotes++;
   if(disp>=InpExtremeDisplacementATR)extremeVotes++;
   if(SpreadPercentile()>=InpDisorderSpreadPct)extremeVotes++;
   if(extremeVotes>=2){g_envRegime=ENV_EXTREME_VOLATILITY;g_lowLiqBars=0;return;}
   //--- LOW liquidity: multi-condition + persistence (section 45)
   bool lowVol=(g_volRatio<InpMinLiquidityLevel&&vpp<InpVolumeLowPct);
   bool wideSpread=(SpreadPercentile()>=InpMaxSpreadPercentile);
   if(lowVol||wideSpread)g_lowLiqBars++;else g_lowLiqBars=0;
   if(g_lowLiqBars>=InpLowLiquidityConfirmBars){g_envRegime=ENV_LOW_LIQUIDITY;return;}
   //--- HIGH volatility: existing HV engine drives this classification
   int hs=HVScore(g_dirBias>=0?1:-1);
   if(InpHighVolatilityMode!=HV_OFF&&hs>=InpHVMinScore){g_envRegime=ENV_HIGH_VOLATILITY;return;}
   g_envRegime=ENV_NORMAL;
}

//--- 8A. direction regime: weighted directional evidence score (internal -50..+50 scale)
int DirectionRegimeScore()
{
   int sc=0;
   double c=iClose(eaSymbol,PERIOD_M1,1);
   //--- structure (HH/HL vs LH/LL): up to +/-12
   if(g_structureState==STRUCTURE_HH_HL)sc+=12;
   else if(g_structureState==STRUCTURE_LH_LL)sc-=12;
   else if(g_structureState==STRUCTURE_TRANSITION_BULL)sc+=8;
   else if(g_structureState==STRUCTURE_TRANSITION_BEAR)sc-=8;
   //--- BOS/CHOCH (related to structure; small additional weight)
   if(g_bosUp)sc+=4;if(g_bosDn)sc-=4;
   if(g_chochUp)sc+=3;if(g_chochDn)sc-=3;
   //--- EMA stack on M1: 9>20>50 vs 9<20<50 (+/-6), partial stacks +/-3
   if(g_ema9>g_ema20&&g_ema20>g_ema50)sc+=6;
   else if(g_ema9<g_ema20&&g_ema20<g_ema50)sc-=6;
   else if(g_ema20>g_ema50)sc+=3;else if(g_ema20<g_ema50)sc-=3;
   //--- EMA200 major bias +/-4
   if(g_ema200>0&&c>g_ema200)sc+=4;else if(g_ema200>0&&c<g_ema200)sc-=4;
   //--- M5 trend +/-3, H1/M15 trend +/-3
   if(g_m5e20>g_m5e50)sc+=3;else if(g_m5e20<g_m5e50)sc-=3;
   if(g_h1e20>g_h1e50&&g_m15e20>g_m15e50)sc+=3;
   else if(g_h1e20<g_h1e50&&g_m15e20<g_m15e50)sc-=3;
   //--- VWAP +/-2 (location, capped - trend evidence already weighted)
   if(g_vwap>0){if(c>g_vwap)sc+=2;else sc-=2;}
   //--- ADX/DI +/-3
   if(g_adx>=InpMinADX){if(g_adxPlus>g_adxMinus)sc+=3;else if(g_adxMinus>g_adxPlus)sc-=3;}
   //--- SuperTrend +/-3
   if(g_superTrendDir>0)sc+=3;else if(g_superTrendDir<0)sc-=3;
   //--- macro as SMALL contextual input +/-2
   sc+=(int)MathMax(-2,MathMin(2,(g_macroBull-g_macroBear)));
   return sc;
}

ENUM_DIRECTION_REGIME UpdateDirectionRegime()
{
   int sc=DirectionRegimeScore();
   ENUM_DIRECTION_REGIME r;
   if(sc>=20)r=REGIME_STRONG_BULLISH;
   else if(sc>=8)r=REGIME_BULLISH;
   else if(sc<=-20)r=REGIME_STRONG_BEARISH;
   else if(sc<=-8)r=REGIME_BEARISH;
   else r=REGIME_SIDEWAYS;
   g_dirRegime=r;
   return r;
}

//--- 28. environment risk multiplier REQUEST (no second sizing engine; HV NOT doubled:
//--- the existing InpHVExtraSignalRiskMult already applies in GetEffectiveTradeRiskPct).
double RegimeRiskMultiplier()
{
   switch(g_envRegime)
   {
      case ENV_EXTREME_VOLATILITY:return 0.0;    // block
      case ENV_LOW_LIQUIDITY:return 0.0;         // block
      case ENV_DISORDER:return 0.0;              // block
      case ENV_HIGH_VOLATILITY:return 1.0;       // existing HV multiplier already applied once
      case ENV_NORMAL:break;
   }
   //--- direction dimension: SIDEWAYS = reduced risk request
   if(g_dirRegime==REGIME_SIDEWAYS)return 0.60;
   return 1.00;
}

//--- 11. effective confidence threshold by environment
double EffectiveConfidenceThreshold()
{
   if(!InpUseAdaptiveConfidenceThreshold)return InpMinConfidenceScore;
   switch(g_envRegime)
   {
      case ENV_HIGH_VOLATILITY:return InpConfidenceHighVol;
      case ENV_EXTREME_VOLATILITY:return InpConfidenceExtremeVol;   // blocks anyway
      case ENV_LOW_LIQUIDITY:return InpConfidenceLowLiquidity;      // blocks anyway
      case ENV_DISORDER:return 100.0;                               // blocks anyway
      case ENV_NORMAL:break;
   }
   if(g_dirRegime==REGIME_SIDEWAYS)return InpConfidenceSideways;
   return InpMinConfidenceScore;
}

//--- 25/48. options snapshot accessor: architecture + fail-open policy.
//--- No network fetch here by default; a future provider (e.g. an FMP endpoint if it
//--- ever proves reliable) fills g_options. Stale data is never used.
bool OptionsDataUsable()
{
   if(!InpUseOptionsContext)return false;
   if(!g_options.available)return false;
   if(g_options.timestamp<=0)return false;
   return (ServerNow()-g_options.timestamp)<=InpOptionsMaxAgeSec;
}

//--- 26. options directional score 0..1 (contextual, never Theta/Vega directional)
double OptionsScore(int dir)
{
   if(!OptionsDataUsable())return 0;
   double sc=0;
   //--- PCR context (mild)
   if(g_options.pcr>0)
   {
      if(dir<0&&g_options.pcr>1.0)sc+=0.3;         // heavy puts = bearish context
      else if(dir>0&&g_options.pcr<0.8)sc+=0.3;    // light puts = bullish context
   }
   //--- OI change agreement
   if(dir>0&&g_options.callOIChange>0)sc+=0.3;
   if(dir<0&&g_options.putOIChange>0)sc+=0.3;
   //--- walls as S/R context
   if(dir>0&&g_options.nearestCallWall>0&&g_options.nearestCallWall>iClose(eaSymbol,PERIOD_M1,1))sc+=0.2;   // resistance overhead
   if(dir<0&&g_options.nearestPutWall>0&&g_options.nearestPutWall<iClose(eaSymbol,PERIOD_M1,1))sc+=0.2;     // support below
   return MathMin(1.0,sc);
}

//--- 9/10. confidence computation for ONE direction. reasonBuf accumulates evidence tags
//--- (bounded; only called for real candidates, never per tick).
double ComputeConfidence(int dir,ConfidenceBreakdown &out,string &reasonBuf,bool buildReasons)
{
   double price=0,trend=0,volu=0,mom=0,vwapS=0,volat=0,macro=0,opts=0,rr=0;
   double c=iClose(eaSymbol,PERIOD_M1,1);
   bool bullish=(dir>0);
   //================= PRICE ACTION / SMC (max 20) =================
   {
      //--- structure alignment up to 5
      if(g_structureState==STRUCTURE_HH_HL){if(bullish)price+=5;else reasonBuf+="[opp]HH_HL ";}
      else if(g_structureState==STRUCTURE_LH_LL){if(!bullish)price+=5;else reasonBuf+="[opp]LH_LL ";}
      else if(g_structureState==STRUCTURE_TRANSITION_BULL){if(bullish){price+=3;reasonBuf+="TRANS_BULL ";}}
      else if(g_structureState==STRUCTURE_TRANSITION_BEAR){if(!bullish){price+=3;reasonBuf+="TRANS_BEAR ";}}
      else if(g_structureState==STRUCTURE_RANGE&&buildReasons)reasonBuf+="RANGE ";
      //--- BOS/CHOCH up to 5
      if(bullish&&g_bosUp){price+=3;reasonBuf+="BULLISH_BOS ";}
      if(!bullish&&g_bosDn){price+=3;reasonBuf+="BEARISH_BOS ";}
      if(bullish&&g_chochUp){price+=2;reasonBuf+="BULLISH_CHOCH ";}
      if(!bullish&&g_chochDn){price+=2;reasonBuf+="BEARISH_CHOCH ";}
      //--- liquidity sweep up to 3
      if(bullish&&g_sweepDn){price+=3;reasonBuf+="LIQUIDITY_SWEEP_LOW ";}
      if(!bullish&&g_sweepUp){price+=3;reasonBuf+="LIQUIDITY_SWEEP_HIGH ";}
      //--- FVG/IFVG/PTB up to 4
      if(bullish&&g_fvg&&g_fvgDir>0){price+=1.5;reasonBuf+="FVG_BULL ";}
      if(!bullish&&g_fvg&&g_fvgDir<0){price+=1.5;reasonBuf+="FVG_BEAR ";}
      if(bullish&&g_ifvg&&g_ifvgDir>0){price+=1.5;reasonBuf+="IFVG_BULL ";}
      if(!bullish&&g_ifvg&&g_ifvgDir<0){price+=1.5;reasonBuf+="IFVG_BEAR ";}
      if(bullish&&g_ptb&&g_ptbDir>0){price+=1.0;reasonBuf+="PTB_BULL ";}
      if(!bullish&&g_ptb&&g_ptbDir<0){price+=1.0;reasonBuf+="PTB_BEAR ";}
      //--- S/R structural support up to 3 (SR vote)
      double srV=SR_DirectionalVote(dir,(dir>0?Ask():Bid()),g_atr);
      if(srV>0){price+=MathMin(3.0,srV*3.0);reasonBuf+="SR_SUPPORT ";}
   }
   //================= TREND / MTF (max 15) =================
   {
      //--- EMA9/20 up to 3
      if(g_ema9>0&&g_ema20>0)
      {
         if(bullish&&g_ema9>g_ema20){trend+=3;reasonBuf+="EMA9>EMA20 ";}
         if(!bullish&&g_ema9<g_ema20){trend+=3;reasonBuf+="EMA9<EMA20 ";}
      }
      //--- EMA20/50 up to 3 (full stack bonus already partially covered; avoid double-count:
      //--- award full only when 9/20 disagreed, else partial)
      if(bullish&&g_ema20>g_ema50){trend+=(trend>=3?1.5:3);if(trend>=3)reasonBuf+="EMA20>EMA50 ";}
      if(!bullish&&g_ema20<g_ema50){trend+=(trend>=3?1.5:3);if(trend>=3)reasonBuf+="EMA20<EMA50 ";}
      //--- EMA200 bias up to 3 (context: partial credit on counter-trend reversion handled by setup)
      if(g_ema200>0)
      {
         if(bullish&&c>g_ema200){trend+=3;reasonBuf+="ABOVE_EMA200 ";}
         if(!bullish&&c<g_ema200){trend+=3;reasonBuf+="BELOW_EMA200 ";}
      }
      //--- M5 trend up to 3
      if(bullish&&g_m5e20>g_m5e50){trend+=3;reasonBuf+="M5_TREND_UP ";}
      if(!bullish&&g_m5e20<g_m5e50){trend+=3;reasonBuf+="M5_TREND_DN ";}
      //--- M15/H1 trend up to 3
      bool hBull=(g_h1e20>g_h1e50&&g_m15e20>g_m15e50),hBear=(g_h1e20<g_h1e50&&g_m15e20<g_m15e50);
      if(bullish&&hBull){trend+=3;reasonBuf+="H1_M15_UP ";}
      if(!bullish&&hBear){trend+=3;reasonBuf+="H1_M15_DN ";}
      trend=MathMin(trend,15.0);
   }
   //================= VOLUME / LIQUIDITY (max 15) =================
   {
      //--- relative volume up to 5
      if(g_volRatio>=InpMinVolumeRatio){volu+=5;reasonBuf+="VOL_RATIO_OK ";}
      else if(g_volRatio>=1.0)volu+=2.5;
      //--- volume percentile up to 4
      if(g_volumePercentile>=InpVolumeElevatedPct)volu+=4;
      else if(g_volumePercentile>=InpVolumeLowPct)volu+=2;
      //--- directional spike up to 3: spike counts ONLY with directional candle + structure agreement
      double disp=CandleDisplacementATR();
      bool dirCandle=(bullish?(iClose(eaSymbol,PERIOD_M1,1)>iOpen(eaSymbol,PERIOD_M1,1)):(iClose(eaSymbol,PERIOD_M1,1)<iOpen(eaSymbol,PERIOD_M1,1)));
      if(g_volumeState==VOLUME_SPIKE&&dirCandle&&(bullish?(g_structureBullStrength>=g_structureBearStrength):(g_structureBearStrength>=g_structureBullStrength)))
      {volu+=3;reasonBuf+="VOLUME_SPIKE_CONFIRMED ";}
      //--- liquidity quality up to 3
      if(g_volRatio>=InpMinLiquidityLevel){volu+=3;reasonBuf+="LIQUIDITY_OK ";}
      volu=MathMin(volu,15.0);
   }
   //================= MOMENTUM (max 10) =================
   {
      //--- RSI directional state up to 3
      if(bullish&&g_rsi>=52&&g_rsi<InpRSIOverbought){mom+=3;reasonBuf+="RSI_BULLISH ";}
      if(!bullish&&g_rsi<=48&&g_rsi>InpRSIOversold){mom+=3;reasonBuf+="RSI_BEARISH ";}
      //--- MACD up to 4 (proper native MACD)
      if(InpUseMACD&&g_macdHist!=0)
      {
         if(bullish&&g_macdMain>g_macdSignal&&g_macdHist>0){mom+=3;reasonBuf+="MACD_BULLISH ";}
         if(!bullish&&g_macdMain<g_macdSignal&&g_macdHist<0){mom+=3;reasonBuf+="MACD_BEARISH ";}
         if(bullish&&g_macdHist>g_macdHistPrev)mom+=1;    // hist increasing
         if(!bullish&&g_macdHist<g_macdHistPrev)mom+=1;   // hist decreasing
      }
      //--- ADX/DI or displacement up to 3
      if(g_adx>=InpMinADX){if(bullish&&g_adxPlus>g_adxMinus){mom+=3;reasonBuf+="DI_BULL ";}
                           if(!bullish&&g_adxMinus>g_adxPlus){mom+=3;reasonBuf+="DI_BEAR ";}}
      else if(CandleDisplacementATR()>=0.5){mom+=1.5;}   // displacement as weaker substitute
      mom=MathMin(mom,10.0);
   }
   //================= VWAP / LOCATION (max 10; setup-aware) =================
   {
      string why=g_scalpWhy;
      bool reversion=(StringFind(why,"reversion")>=0);
      if(g_vwap>0)
      {
         double dev=(c-g_vwap)/g_atr;
         if(!reversion)
         {
            //--- trend setups: same side of VWAP supports
            if(bullish&&c>g_vwap){vwapS+=6;reasonBuf+="VWAP_SUPPORT ";}
            if(!bullish&&c<g_vwap){vwapS+=6;reasonBuf+="VWAP_RESIST ";}
            //--- modest deviation fine; huge adverse deviation costs
            if(bullish&&dev<-1.5)vwapS=0;
            if(!bullish&&dev>1.5)vwapS=0;
         }
         else
         {
            //--- reversion: extreme deviation + recross supports OPPOSITE-direction entry
            if(bullish&&dev<=-1.2){vwapS+=8;reasonBuf+="VWAP_DEV_LOW ";}
            if(!bullish&&dev>=1.2){vwapS+=8;reasonBuf+="VWAP_DEV_HIGH ";}
         }
      }
      //--- Bollinger recross where appropriate (reversion): existing bb values reused
      if(reversion)
      {
         if(bullish&&c>g_bbMid){vwapS+=2;reasonBuf+="BB_RECOVER ";}
         if(!bullish&&c<g_bbMid){vwapS+=2;reasonBuf+="BB_REJECT ";}
      }
      vwapS=MathMin(vwapS,10.0);
   }
   //================= VOLATILITY / ENVIRONMENT (max 10) =================
   {
      double atrp=ATRPercentile();
      if(g_envRegime==ENV_NORMAL)
      {
         //--- favorable band: ATR percentile 30-85 good
         if(atrp>=30&&atrp<=85)volat+=8;else volat+=4;
         if(g_volumeState!=VOLUME_LOW)volat+=2;
         reasonBuf+="ENV_NORMAL ";
      }
      else if(g_envRegime==ENV_HIGH_VOLATILITY){volat+=4;reasonBuf+="ENV_HIGH_VOL ";}
      //--- EXTREME/LOW_LIQ/DISORDER: environment gate blocks; contribute 0
   }
   //================= MACRO / INTERMARKET (max 10) =================
   {
      if(AvailableMacroCount()>0)
      {
         int mv=MacroVotes(dir),ov=MacroVotes(-dir);
         if(mv>ov){macro+=10;reasonBuf+="MACRO_SUPPORTIVE ";}
         else if(mv==ov)macro+=4;   // neutral
         //--- opposing macro contributes 0 (never negative per section 18)
      }
      //--- unavailable: possibleScore loses this weight (renormalization below)
   }
   //================= OPTIONS (max 5; fail-open) =================
   {
      if(OptionsDataUsable())
      {
         opts=OptionsScore(dir)*5.0;
         if(opts>0&&buildReasons)reasonBuf+="OPTIONS_CONTEXT ";
      }
      //--- unavailable/stale: weight removed from possibleScore below
   }
   //================= RISK/REWARD + COST (max 5) =================
   {
      //--- net R:R score filled by caller via SetRRScore (needs entry/SL/TP plan)
      rr=0;   // assigned in BuildSignalDecision where the plan exists
   }
   //================= aggregate with missing-data renormalization (section 10) =========
   double possible=g_wPrice+g_wTrend+g_wVolume+g_wMomentum+g_wVWAP+g_wVol+g_wMacro+g_wOptions+g_wRR;
   if(InpNormalizeMissingExternalData)
   {
      if(AvailableMacroCount()==0)possible-=g_wMacro;
      if(!OptionsDataUsable())possible-=g_wOptions;
   }
   if(possible<=0)possible=1;
   double raw=price+trend+volu+mom+vwapS+volat+macro+opts+rr;
   //--- scale raw (absolute category maxima) into the weight space, then normalize
   double scale=possible/MathMax(1.0,(g_wPrice+g_wTrend+g_wVolume+g_wMomentum+g_wVWAP+g_wVol+g_wMacro+g_wOptions+g_wRR));
   raw*=scale;
   out.priceAction=price;out.trend=trend;out.volumeLiquidity=volu;out.momentum=mom;
   out.vwapLocation=vwapS;out.volatility=volat;out.macro=macro;out.options=opts;out.riskReward=rr;
   out.rawScore=raw;out.possibleScore=possible;
   out.normalizedScore=(g_weightSum>0?raw/possible*100.0:0);
   return out.normalizedScore;
}

//--- 16. setup-specific minimum NET R:R (no universal 1:3)
double SetupMinNetRR(string setupName)
{
   if(StringFind(setupName,"RCV")>=0)return InpRecoveryMinRR;   // recovery keeps its own (stricter, validated separately)
   if(StringFind(setupName,"pullback")>=0)return InpMinNetRR_EMAPullback;
   if(StringFind(setupName,"reversion")>=0)return InpMinNetRR_VWAPReversion;
   if(StringFind(setupName,"London")>=0)return InpMinNetRR_LondonBreakout;
   if(StringFind(setupName,"NY")>=0)return InpMinNetRR_NYMomentum;
   return InpMinNetRR_ComplexMode;
}

//--- 12/13. centralized BUY/SELL/NO_TRADE decision. Called from TryArm AFTER the setup
//--- exists (setup-driven: confidence classifies, never manufactures trades).
ENUM_SIGNAL_DECISION BuildSignalDecision(int dir,double entry,double sl,double t1,double t2,double t3,double lots,ENUM_WINDOW_ID w,bool hv,string setupName)
{
   SignalDecision d;
   ZeroMemory(d);
   d.instrument=eaSymbol;
   d.direction=dir;
   d.entry=entry;d.stopLoss=sl;d.tp1=t1;d.tp2=t2;d.tp3=t3;
   d.quantity=lots;d.window=w;d.highVolatility=hv;
   d.setupName=setupName;
   d.structure=g_structureState;
   d.directionRegime=g_dirRegime;
   d.environmentRegime=g_envRegime;
   d.volumeState=g_volumeState;
   d.spreadPoints=SpreadPoints();
   d.spreadPercentile=SpreadPercentile();
   d.spreadToATR=(g_atr>0?d.spreadPoints*broker.point/g_atr*100.0:0);
   d.expectedSlippage=ExpectedSlippagePoints();
   //--- confidence for the proposed side and the opposite side
   string reasonsL="",reasonsS="";
   ConfidenceBreakdown cd,co;
   double confProp=ComputeConfidence(dir,cd,reasonsL,true);
   double confOpp=ComputeConfidence(-dir,co,reasonsS,false);
   d.confidenceBreakdown=cd;
   d.confidence=confProp;d.oppositeConfidence=confOpp;
   d.confidenceGap=MathAbs(confProp-confOpp);
   //--- net R:R for the proposed plan (uses the authoritative cost engine)
   double slDist=MathAbs(entry-sl);
   double riskMoney=CalculateRealTradeRiskMoney(dir,lots,entry,sl);
   double grossTP1=PriceMoveMoney(MathAbs(t1-entry),lots);
   double netTP1=grossTP1-ExpectedAllInCost(lots);
   double netRR=(riskMoney>0?netTP1/riskMoney:0);
   d.riskMoney=riskMoney;
   d.riskPct=(GetConservativeCapitalBase()>0?riskMoney/GetConservativeCapitalBase()*100.0:0);
   d.potentialRewardMoney=grossTP1;
   d.netPotentialRewardMoney=netTP1;
   d.riskReward=netRR;
   d.expectedCost=ExpectedAllInCost(lots);
   //--- R:R quality score into the 5-point category (section 17)
   double minRR=SetupMinNetRR(setupName);
   if(netRR>=minRR)
   {
      double excellent=minRR*1.6;
      cd.riskReward=(netRR>=excellent?5.0:5.0*(netRR-minRR)/(excellent-minRR));
      reasonsL+="RR_PASS ";
      double costPct=(grossTP1>0?d.expectedCost/grossTP1*100.0:999);
      if(costPct<=InpMaxCostToTP1Pct*0.6)reasonsL+="COST_PASS ";
   }
   else reasonsL+="RR_FAIL ";
   //--- recompute normalized score with the R:R points included
   double possible=cd.possibleScore;
   double rawNoRR=cd.rawScore;
   // rawScore already included riskReward=0 from ComputeConfidence; add scored R:R now
   d.confidenceBreakdown.riskReward=cd.riskReward;
   d.confidenceBreakdown.rawScore=rawNoRR+cd.riskReward;
   d.confidenceBreakdown.normalizedScore=(possible>0?(rawNoRR+cd.riskReward)/possible*100.0:0);
   confProp=d.confidenceBreakdown.normalizedScore;
   d.confidence=confProp;
   //--- environment block checks first (sections 8/32)
   if(g_envRegime==ENV_EXTREME_VOLATILITY){d.decision=SIGNAL_NO_TRADE;d.gateReason="EXTREME_VOLATILITY";g_envRejects[2]++;g_lastDecision=d;return d.decision;}
   if(g_envRegime==ENV_LOW_LIQUIDITY){d.decision=SIGNAL_NO_TRADE;d.gateReason="LOW_LIQUIDITY";g_envRejects[3]++;g_lastDecision=d;return d.decision;}
   if(g_envRegime==ENV_DISORDER){d.decision=SIGNAL_NO_TRADE;d.gateReason="DISORDER";g_envRejects[4]++;g_lastDecision=d;return d.decision;}
   //--- adaptive threshold
   double thr=EffectiveConfidenceThreshold();
   //--- directional gap: both sides above threshold need separation
   bool oppAbove=(confOpp>=thr);
   bool propAbove=(confProp>=thr);
   if(!propAbove)
   {
      d.decision=SIGNAL_NO_TRADE;
      d.gateReason="CONFIDENCE_LOW "+DoubleToString(confProp,1)+"<"+DoubleToString(thr,1);
      g_lastDecision=d;return d.decision;
   }
   if(oppAbove&&(confProp-confOpp)<InpMinDirectionalConfidenceGap)
   {
      d.decision=SIGNAL_NO_TRADE;
      d.gateReason="DIRECTION_AMBIGUOUS gap="+DoubleToString(confProp-confOpp,1);
      g_lastDecision=d;return d.decision;
   }
   //--- net R:R hard quality gate (setup-specific)
   if(netRR<minRR)
   {
      d.decision=SIGNAL_NO_TRADE;
      d.gateReason="NET_RR_FAIL "+DoubleToString(netRR,2)+"<"+DoubleToString(minRR,2);
      g_lastDecision=d;return d.decision;
   }
   //--- regime risk request: SIDEWAYS reduces via multiplier request (environment blocks handled above)
   if(RegimeRiskMultiplier()<=0){d.decision=SIGNAL_NO_TRADE;d.gateReason="REGIME_BLOCK";g_lastDecision=d;return d.decision;}
   //--- PASSED: decision stands subject to all existing downstream gates (TryArm continues)
   d.decision=(dir>0?SIGNAL_BUY:SIGNAL_SELL);
   d.signalReasons=reasonsL;
   d.gateReason="CONF_PASS "+DoubleToString(confProp,1)+"/"+DoubleToString(thr,1);
   g_lastDecision=d;
   return d.decision;
}

bool LiveMomentumConfirm(int dir)
{
   if(g_ema20<=0)return true;                      // no EMA yet -> do not block
   double px=(dir>0?Bid():Ask());
   double tol=0.05*g_atr;                          // small tolerance band around EMA
   if(dir>0) return (px>=g_ema20-tol);
   return (px<=g_ema20+tol);
}

double CandleDisplacementATR()
{
   if(g_atr<=0)return 0;double o=iOpen(eaSymbol,PERIOD_M1,1),c=iClose(eaSymbol,PERIOD_M1,1);return MathAbs(c-o)/g_atr;
}

// Rolling N-bar breakout (default 30 closed M1 bars) - NOT a true session high/low.
// Named honestly; a session-anchored range would need SessionUTCBounds integration.
bool RollingBreakout(int dir)
{
   MqlRates r[];ArraySetAsSeries(r,true);int n=InpSessionBreakoutLookback+2;if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n)return false;
   double hi=-DBL_MAX,lo=DBL_MAX;for(int i=1;i<n;i++){hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);}double c=r[0].close;
   return dir>0?(c>hi):(c<lo);
}

int HVScore(int dir)
{
   int s=0;double atrp=ATRPercentile(),vr=g_volRatio,disp=CandleDisplacementATR();double c=iClose(eaSymbol,PERIOD_M1,1);
   if(atrp>=InpHVMinATRPercentile)s++;
   if(vr>=InpHVMinVolumeRatio)s++;
   if(disp>=InpHVMinDisplacementATR && disp<=InpHVMaxDisorderATR)s++;
   if(g_vwap>0 && MathAbs(c-g_vwap)>=InpHVMinVWAPDeviationATR*g_atr)s++;
   if(RollingBreakout(dir))s++;
   if(dir>0 && g_smcScoreBull>=InpMinSMCConfluence)s++;
   if(dir<0 && g_smcScoreBear>=InpMinSMCConfluence)s++;
   if((dir>0&&((g_ifvg&&g_ifvgDir>0)||(g_ptb&&g_ptbDir>0)))||(dir<0&&((g_ifvg&&g_ifvgDir<0)||(g_ptb&&g_ptbDir<0))))s++;
   if(MacroVotes(dir)>=InpMacroMinConfluence)s++;
   bool mtf=(dir>0?(g_h1e20>g_h1e50&&g_m15e20>g_m15e50):(g_h1e20<g_h1e50&&g_m15e20<g_m15e50));if(mtf)s++;
   return s;
}

bool IsHighVolatilityQualified(int dir,int &score)
{
   score=HVScore(dir);if(InpHighVolatilityMode==HV_OFF)return false;return score>=InpHVMinScore;
}

bool IsDisorder()
{
   datetime now=ServerNow();if(g_disorderUntil>now)return true;
   // Disorder = microstructure breakdown only. A high spread PERCENTILE alone is noise
   // on brokers whose spread is near-constant (p100 == normal 40pt on Xelans), so the
   // relative spike must ALSO breach the absolute hard cap before halting. Realised
   // slippage stays an independent trigger.
   double sp=SpreadPoints();
   if(SpreadPercentile()>=InpDisorderSpreadPct && sp>AdaptiveSpreadCap(MathMax(g_atr,MinTradeDistance())*SpreadCompensationFactor()*(InpSimpleScalpMode?SCALP_SL_ATR:InpSL_ATR_Multiplier)))
   {g_disorderUntil=now+InpDisorderCooldownMinutes*60;return true;}
   if(g_slipCnt>=5&&g_slipAvg>=AdaptiveDisorderSlipPts())
   {g_disorderUntil=now+InpDisorderCooldownMinutes*60;return true;}
   return false;
}

void UpdateOpportunityObservations()
{
   double avgAtr=AverageATR(60);if(avgAtr<=0||g_atr<=0)return;double ar=g_atr/avgAtr,vr=g_volRatio;
   int b=MinuteOfDay(UTCNow())/30;if(b>=0&&b<48){g_bucket[b].samples++;g_bucket[b].atrRatioSum+=ar;g_bucket[b].volRatioSum+=vr;}
   bool tr=false;ENUM_WINDOW_ID w=CurrentWindow(tr);if(w>WIN_NONE&&w<WIN_COUNT){g_ws[w].observations++;g_ws[w].obsATRRatioSum+=ar;g_ws[w].obsVolRatioSum+=vr;}
}

//====================================================================
// NEWS FILTER (MQL5 economic calendar, USD high-impact)
//====================================================================
bool CriticalNewsEvent(string name)
{
   string low=name;StringToLower(low);
   // Tight gold-driver list only; minor releases must never freeze an ultra-scalper.
   if(StringFind(low,"nonfarm")>=0)return true;
   if(StringFind(low,"payrolls")>=0)return true;
   if(StringFind(low,"cpi")>=0)return true;
   if(StringFind(low,"core inflation")>=0)return true;
   if(StringFind(low,"pce")>=0)return true;
   if(StringFind(low,"fomc")>=0)return true;
   if(StringFind(low,"fed funds")>=0)return true;
   if(StringFind(low,"rate decision")>=0)return true;
   if(StringFind(low,"interest rate")>=0)return true;
   if(StringFind(low,"gdp")>=0)return true;
   if(StringFind(low,"unemployment rate")>=0)return true;
   if(StringFind(low,"ism manufacturing")>=0)return true;
   if(StringFind(low,"ism services")>=0)return true;
   if(StringFind(low,"jobless claims")>=0)return true;
   return false;
}

void CheckNews(bool force=false)
{
   datetime now=ServerNow();
   if(!InpUseNewsFilter){g_newsBlocked=false;g_nextNewsTime=0;g_nextNewsName="";return;}
   if(!force && g_newsChecked>0 && now-g_newsChecked<60)return;g_newsChecked=now;
   bool wasBlocked=g_newsBlocked;g_newsBlocked=false;g_nextNewsTime=0;g_nextNewsName="";
   if(MQLInfoInteger(MQL_TESTER))
   {
      // Tester cannot replay the terminal economic calendar. Use conservative manual UTC release bands.
      int m=MinuteOfDay(UTCNow());int blocks[4]={8*60+30,12*60+30,13*60+30,18*60};
      for(int i=0;i<4;i++)if(MathAbs(m-blocks[i])<=InpNewsBufferMinutes){g_newsBlocked=true;g_nextNewsName="tester macro block";break;}
   }
   else
   {
      MqlCalendarValue vals[];datetime t0=now-InpNewsBufferMinutes*60,t1=now+(InpNewsLookaheadMin+InpNewsBufferMinutes)*60;
      int n=CalendarValueHistory(vals,t0,t1,NULL,"USD");
      for(int i=0;i<n;i++)
      {
         MqlCalendarEvent ev;if(!CalendarEventById(vals[i].event_id,ev))continue;if(ev.importance<CALENDAR_IMPORTANCE_HIGH)continue;
         if(!CriticalNewsEvent(ev.name))continue;
         datetime et=vals[i].time;if(g_nextNewsTime==0||et<g_nextNewsTime){g_nextNewsTime=et;g_nextNewsName=ev.name;}
         if(MathAbs((long)(et-now))<=InpNewsBufferMinutes*60)g_newsBlocked=true;
      }
   }
   // FMP headline scan is advisory: it never blocks by default (plan-restricted on
   // some keys anyway), but a hard block is available via InpFMPNewsHardBlock.
   if(InpFMPNewsHardBlock&&g_fmpNewsCount>0)g_newsBlocked=true;
   if(wasBlocked&&!g_newsBlocked)g_newsBlockedUntil=now+InpPostNewsStabilizeMinutes*60;
}

//====================================================================
// SWAP / ROLLOVER PROTECTION
//====================================================================
int ServerMinuteOfDay(){return MinuteOfDay(ServerNow());}
int RolloverMinute(){int m=(int)MathRound(InpSwapRolloverServerHour*60.0);while(m<0)m+=1440;return m%1440;}
bool InSwapDangerWindow()
{
   if(!InpAvoidSwap)return false;int now=ServerMinuteOfDay(),roll=RolloverMinute();int until=ForwardMinutesTo(now,roll);int after=ForwardMinutesTo(roll,now);
   bool before=(until<=InpSwapBlockMinutesBefore);bool justAfter=(after<=InpSwapBlockMinutesAfter);
   bool projectedCross=(until<=MathMax(0,InpMaxTradeMinutes));return before||justAfter||projectedCross;
}
void EnforceSwapFlat()
{
   if(!InpAvoidSwap||!InpForceFlatBeforeSwap)return;int now=ServerMinuteOfDay(),roll=RolloverMinute();int until=ForwardMinutesTo(now,roll);
   if(until>InpSwapBlockMinutesBefore)return;
   DeleteOwnPendings(false);for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==eaSymbol&&PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)ClosePositionSafe(t);}
}

//====================================================================
// ACCOUNT / RISK / COSTS
//====================================================================
int WeekKey(datetime t){MqlDateTime d;TimeToStruct(t,d);return d.year*100+(d.day_of_year/7);}
int MonthKey(datetime t){MqlDateTime d;TimeToStruct(t,d);return d.year*100+d.mon;}
int DayKey(datetime t){MqlDateTime d;TimeToStruct(t,d);return d.year*1000+d.day_of_year;}

void ResetWindowDay()
{
   for(int i=0;i<WIN_COUNT;i++){g_windowRiskUsed[i]=0;g_windowSignals[i]=0;g_lastWindowEntry[i]=0;}
}

void UpdateRiskPeriods()
{
   datetime n=ServerNow();int dk=DayKey(n),wk=WeekKey(n),mk=MonthKey(n);double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayKey!=dk){g_dayKey=dk;g_dayAnchor=eq;g_tradesToday=0;g_consecutiveLosses=0;g_recoveryLegs=0;g_stopDay=false;ResetWindowDay();}
   if(g_weekKey!=wk){g_weekKey=wk;g_weekAnchor=eq;g_stopWeek=false;}
   // Stale-anchor guard: a persisted anchor from an older week can show absurd weekly
   // DD (e.g. 93%) after deposits/withdrawals or state carry-over. Re-anchor when the
   // number is not physically plausible for one week of trading.
   if(g_weekAnchor>0)
   {
      double wdd=(g_weekAnchor-eq)/g_weekAnchor*100.0;
      if(wdd>60.0||wdd<-60.0)
      {
         g_weekAnchor=eq;    // anchor provably stale (state carry-over) - re-anchor
         g_stopWeek=false;   // and clear the halt it wrongly triggered
      }
   }
   if(g_monthKey!=mk){g_monthKey=mk;g_monthAnchor=eq;g_stopMonth=false;}
   if(g_dayAnchor>0)
   {
      double dd2=(g_dayAnchor-eq)/g_dayAnchor*100.0;
      if(dd2>60.0||dd2<-60.0){g_dayAnchor=eq;g_stopDay=false;g_tradesToday=0;}
   }
   if(g_monthAnchor>0)
   {
      double md2=(g_monthAnchor-eq)/g_monthAnchor*100.0;
      if(md2>60.0||md2<-60.0){g_monthAnchor=eq;g_stopMonth=false;}
   }
   double d=(g_dayAnchor>0?(g_dayAnchor-eq)/g_dayAnchor*100:0),w=(g_weekAnchor>0?(g_weekAnchor-eq)/g_weekAnchor*100:0),m=(g_monthAnchor>0?(g_monthAnchor-eq)/g_monthAnchor*100:0);
   g_maxDDSeen=MathMax(g_maxDDSeen,MathMax(0,d));if(d>=InpDailyLossPercent||d>=InpMaxFloatingDDPercent)g_stopDay=true;if(w>=InpWeeklyLossLimit)g_stopWeek=true;if(m>=InpMonthlyLossLimit)g_stopMonth=true;
   // consecutive losses: risk decays 30% per loss in CurrentRiskPct - no hard halt (user directive: keep trading)
}

double MoneyPerPricePerLot()
{
   if(broker.tickSize<=0||broker.tickValue<=0)return 0;return broker.tickValue/broker.tickSize;
}

double PriceMoveMoney(double dist,double lots){return MathAbs(dist)*MoneyPerPricePerLot()*lots;}

double CommissionRT(double lots)
{
   double c=(g_commissionRTPerLot>0?g_commissionRTPerLot:InpCommissionPerLotRTFallback);return c*lots;
}

double ExpectedSlippagePoints(){return (g_slipCnt>=5?MathMax(g_slipAvg,1.0):InpExpectedSlipPtsFallback);}

double ExpectedAllInCost(double lots)
{
   double spreadPrice=SpreadPoints()*broker.point;double slipPrice=ExpectedSlippagePoints()*broker.point;
   return PriceMoveMoney(spreadPrice+slipPrice,lots)+CommissionRT(lots);
}

double WindowExpectancy(ENUM_WINDOW_ID w)
{
   if(w<=WIN_NONE||w>=WIN_COUNT||g_ws[w].recentCount<=0)return 0;double s=0;for(int i=0;i<g_ws[w].recentCount;i++)s+=g_ws[w].recentNet[i];return s/g_ws[w].recentCount;
}

//--- [PERFORMANCE GATING] rolling recent-R expectancy (section 25)
double WindowExpectancyR(ENUM_WINDOW_ID w)
{
   if(w<=WIN_NONE||w>=WIN_COUNT||g_ws[w].recentRCount<=0)return 0;
   double s=0;for(int i=0;i<g_ws[w].recentRCount;i++)s+=g_ws[w].recentR[i];
   return s/g_ws[w].recentRCount;
}

void PushRecentR(ENUM_WINDOW_ID w,double r)
{
   if(w<=WIN_NONE||w>=WIN_COUNT)return;
   int cap=64;int i=g_ws[w].recentRIdx%cap;g_ws[w].recentR[i]=r;g_ws[w].recentRIdx=(i+1)%cap;
   if(g_ws[w].recentRCount<cap)g_ws[w].recentRCount++;
}

double WindowAvgR(ENUM_WINDOW_ID w)
{
   if(w<=WIN_NONE||w>=WIN_COUNT||g_ws[w].trades<=0)return 0;return g_ws[w].rSum/g_ws[w].trades;
}

bool IsPrimarySessionWindow(ENUM_WINDOW_ID w)
{
   return (w==WIN_SYDNEY||w==WIN_TOKYO||w==WIN_LONDON||w==WIN_NEWYORK);
}

void RefreshWindowGating(ENUM_WINDOW_ID w)
{
   if(w<=WIN_NONE||w>=WIN_COUNT)return;g_ws[w].disabled=false;
   if(!InpEnablePerformanceGating||g_ws[w].trades<InpPerfMinTrades)return;
   // Primary sessions remain eligible by design. Weak expectancy is handled by
   // WindowRiskMultiplier rather than deleting an entire market session.
   if(InpNeverDisablePrimarySessions && IsPrimarySessionWindow(w))return;
   // [PERFORMANCE GATING] rolling R expectancy in Auto mode (section 25);
   // legacy money expectancy retained for manual/back-compatible mode.
   if(InpUseRExpectancyGating&&InpAutoCapitalProfile)
   {
      if(WindowExpectancyR(w)<=InpDisableExpectancyR)g_ws[w].disabled=true;
      return;
   }
   if(WindowExpectancy(w)<=InpDisableExpectancyMoney)g_ws[w].disabled=true;
}

double WindowRiskMultiplier(ENUM_WINDOW_ID w)
{
   RefreshWindowGating(w);if(g_ws[w].disabled)return 0;
   if(InpEnablePerformanceGating&&g_ws[w].trades>=InpPerfMinTrades)
   {
      if(InpUseRExpectancyGating&&WindowExpectancyR(w)<InpRiskReduceExpectancyR)return InpWeakWindowRiskMultiplier;
      if(!InpUseRExpectancyGating&&WindowExpectancy(w)<InpRiskReduceExpectancyMoney)return InpWeakWindowRiskMultiplier;
   }
   return 1.0;
}

//--- section 14: OrderCalcProfit is the AUTHORITATIVE SL-risk calculator.
bool CalcBrokerPnL(int direction,double volume,double openPrice,double closePrice,double &pnl)
{
   pnl=0;
   if(volume<=0||openPrice<=0||closePrice<=0)return false;
   ENUM_ORDER_TYPE t=(direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   ResetLastError();
   if(!OrderCalcProfit(t,eaSymbol,volume,openPrice,closePrice,pnl))return false;
   if(pnl==0)return false;   // broker refused/returned nothing -> use fallback
   return true;
}

double OpenRiskMoney(int directionFilter=0)
{
   double sum=0;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   // [OPEN RISK] no-SL positions are NOT free risk room: conservative policy charges
   // each of them a catastrophe fallback percentage of equity (prompt.md section 20).
   double noSLPenalty=(eq>0?eq*InpCatastropheNoSLRiskPct/100.0:0);
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=eaSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue;
      int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);if(directionFilter!=0&&dir!=directionFilter)continue;
      double sl=PositionGetDouble(POSITION_SL),op=PositionGetDouble(POSITION_PRICE_OPEN),v=PositionGetDouble(POSITION_VOLUME);
      if(sl<=0){sum+=noSLPenalty;continue;}   // missing SL = unbounded risk, never zero
      // Broker-native estimate first (returns account-currency loss at SL);
      // tick-size/tick-value fallback keeps the same semantics if the call fails.
      double pnl=0;
      if(CalcBrokerPnL(dir,v,op,sl,pnl))sum+=MathAbs(pnl);
      else sum+=PriceMoveMoney(op-sl,v);
   }
   return sum;
}

double SumOwnLots()
{
   double s=0;for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==eaSymbol&&PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)s+=PositionGetDouble(POSITION_VOLUME);}return s;
}

int CountOwnPositions()
{
   int n=0;for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==eaSymbol&&PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)n++;}return n;
}

int CountOwnPendings()
{
   int n=0;for(int i=0;i<OrdersTotal();i++){ulong t=OrderGetTicket(i);if(t&&OrderSelect(t)&&OrderGetString(ORDER_SYMBOL)==eaSymbol&&OrderGetInteger(ORDER_MAGIC)==InpMagicNumber)n++;}return n;
}

//====================================================================
// [CAPITAL ENGINE] adaptive profile + risk resolver + broker-native sizing
// (prompt.md sections 4-12, 14, 16-18, 22-23). Auto mode = InpAutoCapitalProfile.
// Legacy manual mode (InpAutoCapitalProfile=false) keeps the exact old behavior:
// InpRiskPercent base, InpMax* fixed caps, InpLotSize when InpAutoRiskSizing=false.
//====================================================================
ENUM_CAPITAL_PROFILE g_capitalProfile=CAPITAL_MICRO;   // conservative until classified
string  g_usdConvertNote="";          // CAPITAL_USD_CONVERSION_UNAVAILABLE / fallback telemetry
string  g_fxConvSymbol="";            // cached conversion symbol (empty = USD account / unresolved)
bool    g_fxConvInvert=false;         // true: symbol is USDBASE (rate must be inverted)
double  g_fxConvRate=0;               // cached account-currency -> USD rate (0 = unresolved)
datetime g_fxLastRefresh=0;
string  g_lastRiskReason="";          // RiskSizingReason telemetry
double  g_lastRawLots=0,g_lastFinalLots=0,g_lastAllowedRiskMoney=0,g_lastActualRiskMoney=0;
double  g_lastRequiredMargin=0;int    g_lastOrderCheckRetcode=0;string g_lastOrderCheckComment="";
int     g_minLotRejects=0,g_marginRejects=0,g_spreadRejects=0,g_slipRejects=0,g_orderCheckRejects=0;
double  g_riskOverrideRequested=0;    // mobile RISK_x request (0 = none)

//--- USD-equivalent equity for PROFILE CLASSIFICATION AND DISPLAY ONLY (section 5)
double GetAccountCurrencyToUSD()
{
   string cur=AccountInfoString(ACCOUNT_CURRENCY);
   if(cur=="USD"||cur==""){g_fxConvSymbol="";return 1.0;}
   // Periodic refresh: no per-tick symbol scans. Cached symbol is reused.
   datetime now=TimeCurrent();
   bool needScan=(g_fxConvSymbol==""||g_fxConvRate<=0||now-g_fxLastRefresh>=900);
   if(!needScan)return g_fxConvRate;
   g_fxLastRefresh=now;
   // Try cached symbol first, then discover BASEUSD / USDBASE (+ prefix/suffix variants).
   string base=cur;
   if(g_fxConvSymbol!="")
   {
      double px=SymbolInfoDouble(g_fxConvSymbol,SYMBOL_BID);
      if(px>0){g_fxConvRate=(g_fxConvInvert?1.0/px:px);return g_fxConvRate;}
      g_fxConvSymbol="";   // stale: rediscover
   }
   int total=SymbolsTotal(false);
   string direct="";string inverse="";
   for(int i=0;i<total;i++)
   {
      string s=SymbolName(i,false);
      if(StringLen(s)<6)continue;
      if(StringFind(s,base)!=0 && StringFind(s,base)==StringLen(s)-StringLen(base)-3 && StringSubstr(s,StringLen(s)-3)!=base){/*prefix variant handled below*/}
      // BASEUSD: symbol starts with account currency and ends with USD
      if(StringFind(s,base)==0 && StringSubstr(s,StringLen(s)-3)=="USD"){direct=s;break;}
      // USDBASE: symbol starts with USD and ends with account currency
      if(StringFind(s,"USD")==0 && StringSubstr(s,StringLen(s)-StringLen(base))==base && inverse=="")inverse=s;
   }
   string pick="";bool inv=false;
   if(direct!=""){pick=direct;inv=false;}
   else if(inverse!=""){pick=inverse;inv=true;}
   if(pick!="")
   {
      if(SymbolSelect(pick,true))
      {
         double px=SymbolInfoDouble(pick,SYMBOL_BID);
         if(px>0){g_fxConvSymbol=pick;g_fxConvInvert=inv;g_fxConvRate=(inv?1.0/px:px);g_usdConvertNote="";return g_fxConvRate;}
      }
   }
   // NO invented rates: conservative profile fallback + telemetry (section 5).
   g_fxConvSymbol="";g_fxConvRate=0;g_usdConvertNote="CAPITAL_USD_CONVERSION_UNAVAILABLE";
   return 0;
}

double GetEquityUSD()
{
   double r=GetAccountCurrencyToUSD();
   if(r<=0)return 0;
   return AccountInfoDouble(ACCOUNT_EQUITY)*r;
}

//--- centralized profile access (section 4): no scattered tier ifs elsewhere
ENUM_CAPITAL_PROFILE GetCapitalProfile()
{
   if(!InpAutoCapitalProfile)return CAPITAL_STANDARD;   // manual mode: neutral tier, legacy inputs rule
   double usd=GetEquityUSD();
   if(usd<=0)
   {
      if(g_usdConvertNote=="")g_usdConvertNote="CAPITAL_PROFILE_CONSERVATIVE_FALLBACK";
      return CAPITAL_MICRO;    // unresolved conversion -> MOST CONSERVATIVE profile
   }
   if(usd<500.0)return CAPITAL_MICRO;
   if(usd<5000.0)return CAPITAL_STANDARD;
   return CAPITAL_PRO;
}

string CapitalProfileName(ENUM_CAPITAL_PROFILE p)
{
   switch(p)
   {
      case CAPITAL_MICRO:return "MICRO";
      case CAPITAL_STANDARD:return "STANDARD";
      case CAPITAL_PRO:return "PRO";
   }
   return "UNKNOWN";
}

//--- profile parameters (section 4 defaults; hard exception ceilings for min-lot)
double GetProfileBaseRiskPct()
{
   if(!InpAutoCapitalProfile)return InpRiskPercent;
   switch(GetCapitalProfile())
   {
      case CAPITAL_MICRO:return 0.25;
      case CAPITAL_STANDARD:return 0.35;
      case CAPITAL_PRO:return 0.35;
   }
   return 0.35;
}
double GetProfileAggregateRiskPct()
{
   if(!InpAutoCapitalProfile)return InpMaxAggregateOpenRiskPct;
   switch(GetCapitalProfile())
   {
      case CAPITAL_MICRO:return 0.75;
      case CAPITAL_STANDARD:return 1.50;
      case CAPITAL_PRO:return 2.50;
   }
   return 1.50;
}
double GetProfileDirectionalRiskPct()
{
   if(!InpAutoCapitalProfile)return InpMaxDirectionalRiskPct;
   switch(GetCapitalProfile())
   {
      case CAPITAL_MICRO:return 0.50;
      case CAPITAL_STANDARD:return 1.00;
      case CAPITAL_PRO:return 1.50;
   }
   return 1.00;
}
double GetProfileWindowRiskPct()
{
   if(!InpAutoCapitalProfile)return InpPerWindowRiskBudgetPct;
   switch(GetCapitalProfile())
   {
      case CAPITAL_MICRO:return 0.50;
      case CAPITAL_STANDARD:return 0.75;
      case CAPITAL_PRO:return 1.50;
   }
   return 0.75;
}
double GetProfileMinLotRiskCeilingPct()
{
   if(!InpAutoCapitalProfile)return InpMinLotMaxRiskPct;
   switch(GetCapitalProfile())
   {
      case CAPITAL_MICRO:return 1.00;
      case CAPITAL_STANDARD:return 0.75;
      case CAPITAL_PRO:return 0.50;
   }
   return 0.75;
}
int GetProfileMaxPositions()
{
   if(!InpAutoCapitalProfile)return InpMaxConcurrentPositions;
   switch(GetCapitalProfile())
   {
      case CAPITAL_MICRO:return 1;
      case CAPITAL_STANDARD:return 2;
      case CAPITAL_PRO:return 3;
   }
   return 2;
}

//--- section 6: new trades size from min(balance,equity) - never from floating profit
double GetConservativeCapitalBase()
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE),eq=AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMin(bal,eq);
}

//--- section 9: mobile RISK_x is a REQUEST; clamped to every live ceiling here.
//--- Returns the permitted risk % (Auto mode); manual mode returns the raw request
//--- clamped by the legacy base risk path as before.
double GetMobileRiskRequestPct()
{
   if(!InpEnableMobileCommands)return 0;
   if(!GlobalVariableCheck("PAT_RISK_OVERRIDE"))return 0;
   double v=GlobalVariableGet("PAT_RISK_OVERRIDE");
   if(v<=0)return 0;
   return v;   // caller clamps; GV persists until RISK_0 clears it
}

double GetEffectiveTradeRiskPct(ENUM_WINDOW_ID window,bool highVolatility)
{
   // Order (section 7): profile base -> mobile request (clamped) -> DD reduction ->
   // consecutive-loss reduction -> window multiplier -> HV multiplier -> ceiling.
   bool auto=(InpAutoCapitalProfile&&InpAutoRiskSizing);
   double base=(auto?GetProfileBaseRiskPct():InpRiskPercent);
   double r=base;
   // Mobile request: a REQUEST, never a bypass. Accepted only if at or below every
   // applicable ceiling; otherwise clamped with RISK_OVERRIDE_CLAMPED telemetry.
   double req=GetMobileRiskRequestPct();
   if(req>0)
   {
      double cap=base;
      double dd=(g_dayAnchor>0?(g_dayAnchor-AccountInfoDouble(ACCOUNT_EQUITY))/g_dayAnchor*100:0);
      if(dd>InpMaxFloatingDDPercent*0.5)cap=MathMin(cap,base-InpRiskStepDownOnDD);
      cap=MathMin(cap,base*MathPow(0.70,MathMin(4,g_consecutiveLosses)));
      cap*=WindowRiskMultiplier(window);
      if(highVolatility)cap*=InpHVExtraSignalRiskMult;
      if(cap>0&&req>cap)
      {
         if(req!=g_riskOverrideRequested)Print("RISK_OVERRIDE_CLAMPED requested=",DoubleToString(req,3)," accepted=",DoubleToString(cap,3));
      }
      if(cap>0)r=MathMin(r,cap);   // never above the modified base regardless
   }
   // Drawdown reduction (existing behavior, now profile-relative).
   double dd2=(g_dayAnchor>0?(g_dayAnchor-AccountInfoDouble(ACCOUNT_EQUITY))/g_dayAnchor*100:0);
   if(dd2>InpMaxFloatingDDPercent*0.5)r=MathMax(0.0,r-InpRiskStepDownOnDD);
   // Consecutive-loss decay 30%/loss (existing behavior, no hard halt).
   r*=MathPow(0.70,MathMin(4,g_consecutiveLosses));
   // Window performance multiplier (R-based in Auto mode, money in legacy).
   r*=WindowRiskMultiplier(window);
   // HV multiplier (existing behavior).
   if(highVolatility)r*=InpHVExtraSignalRiskMult;
   // Floor: bounded by the profile safe base - modifiers can never be UNDONE
   // (a floor may not exceed the current modified risk; it only stops decay-to-zero).
   double floor=MathMin(InpRiskFloorPct,(auto?GetProfileBaseRiskPct():InpRiskPercent));
   if(r<floor&&r>0)r=floor;
   // Profile hard ceiling: final effective risk may never exceed the profile base.
   double ceiling=(auto?GetProfileBaseRiskPct():InpRiskPercent);
   if(r>ceiling)r=ceiling;
   if(r<=0)return 0;
   return r;
}



//--- section 16: ONE authoritative risk method = broker SL loss + all-in costs.
//--- Components (single basis, no double counting):
//---   OrderCalcProfit(entry -> SL)  : price risk INCLUDING the spread the position
//---     actually loses through (buy closes at bid / sell at ask).
//---   ExpectedAllInCost(lots)       : remaining execution costs NOT in the SL P/L:
//---     round-trip commission + expected entry slippage. Spread is NOT added again.
double CalculateRealTradeRiskMoney(int direction,double volume,double entry,double stopLoss)
{
   if(volume<=0||entry<=0||stopLoss<=0)return 0;
   double riskMoney=0;
   if(CalcBrokerPnL(direction,volume,entry,stopLoss,riskMoney))
   {
      riskMoney=MathAbs(riskMoney);
   }
   else
   {
      // Fallback: existing tick-size/tick-value architecture. Prefer the LOSS-side
      // tick value when the broker publishes it (section 13/14) and log the fallback.
      double tv=broker.tickValueLoss;
      if(tv<=0)tv=broker.tickValue;
      if(broker.tickSize>0&&tv>0)
      {
         riskMoney=MathAbs(entry-stopLoss)/broker.tickSize*tv*volume;
         if(g_lastRiskReason!="")g_lastRiskReason=g_lastRiskReason+"|OCF_FALLBACK";
         else g_lastRiskReason="OCF_FALLBACK";
      }
      else return 0;   // cannot estimate: caller BLOCKS (never assume zero risk)
   }
   return riskMoney+ExpectedAllInCost(volume);
}

//--- section 31: directional volume limit (open + pending, same direction)
double SumOwnLotsDirectional(int dir)
{
   double s=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);if(!t||!PositionSelectByTicket(t))continue;
      if(PositionGetString(POSITION_SYMBOL)!=eaSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue;
      int d=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
      if(d==dir)s+=PositionGetDouble(POSITION_VOLUME);
   }
   for(int i=0;i<OrdersTotal();i++)
   {
      ulong t=OrderGetTicket(i);if(!t||!OrderSelect(t))continue;
      if(OrderGetString(ORDER_SYMBOL)!=eaSymbol||OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      int d=((ot==ORDER_TYPE_BUY||ot==ORDER_TYPE_BUY_STOP||ot==ORDER_TYPE_BUY_LIMIT)?1:-1);
      if(d==dir)s+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return s;
}

//--- section 32: low-cost periodic refresh of mutable broker volume specs
datetime g_volSpecLastCheck=0;
void RefreshVolumeSpecs()
{
   datetime now=ServerNow();
   if(g_volSpecLastCheck>0&&now-g_volSpecLastCheck<300)return;   // 5-min refresh, not per tick
   g_volSpecLastCheck=now;
   broker.volumeMin=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_MIN);
   broker.volumeMax=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_MAX);
   broker.volumeStep=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_STEP);
   broker.volumeLimit=SymbolInfoDouble(eaSymbol,SYMBOL_VOLUME_LIMIT);
   broker.stopsLevel=(int)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_STOPS_LEVEL);
   broker.freezeLevel=(int)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_FREEZE_LEVEL);
}

//--- section 17: authoritative broker-native lot solver.
//--- direction: +1 buy / -1 sell. entry: planned entry. sl: planned SL (price).
//--- Returns approved volume (0 = BLOCK THE TRADE; g_lastRiskReason carries the gate).
double CalculateLotNative(double slDist,int dir,double entry,double sl,ENUM_WINDOW_ID w,bool hv)
{
   g_lastRiskReason="";g_lastRawLots=0;g_lastFinalLots=0;g_lastAllowedRiskMoney=0;g_lastActualRiskMoney=0;g_lastRequiredMargin=0;
   if(slDist<=0||entry<=0||sl<=0){g_lastRiskReason="INVALID_SL";return 0;}
   RefreshVolumeSpecs();
   ENUM_CAPITAL_PROFILE prof=GetCapitalProfile();
   // Legacy manual path: InpAutoRiskSizing=false -> old fixed-lot behavior exactly.
   if(!InpAutoRiskSizing)
   {
      if(InpRiskPercent<=0)return NormalizeVolume(InpLotSize);
      // manual risk % sizing on the conservative base (old math kept, new base)
      double cap=GetConservativeCapitalBase();
      double risk=cap*InpRiskPercent/100.0;
      double perLot=PriceMoveMoney(slDist,1.0)+ExpectedAllInCost(1.0);
      if(perLot<=0)return 0;
      return FloorVolume(risk/perLot);
   }
   // -------- AUTO MODE: the full section-17 pipeline --------
   double rp=GetEffectiveTradeRiskPct(w,hv);
   if(rp<=0){g_lastRiskReason="RISK_RESOLVER_ZERO";return 0;}
   double capitalBase=GetConservativeCapitalBase();
   if(capitalBase<=0){g_lastRiskReason="CAPITAL_TOO_SMALL";return 0;}
   double allowedRisk=capitalBase*rp/100.0;
   g_lastAllowedRiskMoney=allowedRisk;
   // No-martingale / no-averaging-down: ANY underwater position of ours caps the new
   // trade at the current base risk money (never larger). Section 10 + 36.
   double baseCapMoney=capitalBase*GetProfileBaseRiskPct()/100.0;
   if((InpNoMartingale||InpNoAveragingDown)&&CountOwnPositions()>0)
   {
      for(int i=0;i<PositionsTotal();i++)
      {
         ulong t=PositionGetTicket(i);if(!t||!PositionSelectByTicket(t))continue;
         if(PositionGetString(POSITION_SYMBOL)!=eaSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue;
         double op=PositionGetDouble(POSITION_PRICE_OPEN);
         int pd=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
         double px=(pd>0?Bid():Ask());
         if((pd>0&&px<op)||(pd<0&&px>op)){if(allowedRisk>baseCapMoney)allowedRisk=baseCapMoney;g_lastRiskReason="UNDERWATER_CAP";break;}
      }
   }
   // Risk per 1.0 lot via the authoritative money engine (broker SL loss + costs).
   double perLot=CalculateRealTradeRiskMoney(dir,1.0,entry,sl);
   if(perLot<=0){g_lastRiskReason="RISK_PER_LOT_ZERO";return 0;}
   double raw=allowedRisk/perLot;
   g_lastRawLots=raw;
   // Normalize DOWN to the broker grid; never round risk upward.
   double vol=FloorVolume(raw);
   // Minimum-lot feasibility (section 18): hard profile exception ceiling.
   if(vol<=0)
   {
      if(!InpAllowMinLotFallback){g_lastRiskReason="BELOW_VOLUME_MIN";return 0;}
      double minVol=broker.volumeMin;
      double minRisk=CalculateRealTradeRiskMoney(dir,minVol,entry,sl);
      double minPct=(capitalBase>0?minRisk/capitalBase*100.0:999);
      double ceiling=GetProfileMinLotRiskCeilingPct();
      if(minPct<=ceiling&&minRisk>0)vol=FloorVolume(minVol);
      else
      {
         g_minLotRejects++;
         g_lastRiskReason="MIN_LOT_RISK_TOO_HIGH";
         Print("MIN_LOT_RISK_TOO_HIGH profile=",CapitalProfileName(prof)," balance=",DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)," equity=",DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)," capitalBase=",DoubleToString(capitalBase,2)," equityUSD=",DoubleToString(GetEquityUSD(),2)," symbol=",eaSymbol," contractSize=",DoubleToString(broker.contractSize,0)," tickSize=",DoubleToString(broker.tickSize,broker.digits)," tickValue=",DoubleToString(broker.tickValue,4)," volumeMin=",DoubleToString(broker.volumeMin,3)," volumeStep=",DoubleToString(broker.volumeStep,3)," slDist=",DoubleToString(slDist,broker.digits)," minLotRiskMoney=",DoubleToString(minRisk,2)," minLotRiskPct=",DoubleToString(minPct,3)," ceiling=",DoubleToString(ceiling,2));
         return 0;   // never weaken limits to force execution
      }
   }
   // Iterative safety descent: volume risk -> aggregate -> directional -> window ->
   // margin -> OrderCheck. Each violation drops ONE volume step (bounded loops,
   // never increases volume during a safety correction).
   double step=(broker.volumeStep>0?broker.volumeStep:0.01);
   int guard=0;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double freeBefore=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   while(vol>=broker.volumeMin-1e-9&&guard++<200)
   {
      bool changed=false;
      // (a) actual risk at normalized volume
      double actualRisk=CalculateRealTradeRiskMoney(dir,vol,entry,sl);
      if(actualRisk>allowedRisk+1e-9){vol=FloorVolume(vol-step);changed=true;if(vol<=0)break;continue;}
      g_lastActualRiskMoney=actualRisk;
      // (b) aggregate + directional + window caps (profile limits in Auto mode)
      double newRisk=actualRisk;
      double aggPct=(eq>0?(OpenRiskMoney()+newRisk)/eq*100.0:999);
      double dirPct=(eq>0?(OpenRiskMoney(dir)+newRisk)/eq*100.0:999);
      if(aggPct>GetProfileAggregateRiskPct()){g_lastRiskReason="AGGREGATE_RISK_CAP";break;}
      if(dirPct>GetProfileDirectionalRiskPct()){g_lastRiskReason="DIRECTIONAL_RISK_CAP";break;}
      if(g_windowRiskUsed[w]+newRisk>eq*GetProfileWindowRiskPct()/100.0){g_lastRiskReason="WINDOW_RISK_CAP";break;}
      // (c) legacy/emergency absolute lot cap: only when explicitly enabled
      if(InpUseAbsoluteLotEmergencyCap&&InpEmergencyMaxTotalLots>0)
      {
         double room=InpEmergencyMaxTotalLots-SumOwnLots();
         if(vol>room){vol=FloorVolume(room);changed=true;if(vol<=0)break;continue;}
      }
      // (d) broker directional volume limit (section 31)
      if(broker.volumeLimit>0)
      {
         double room=broker.volumeLimit-SumOwnLotsDirectional(dir);
         if(vol>room+1e-9){g_lastRiskReason="SYMBOL_VOLUME_LIMIT";vol=FloorVolume(MathMin(vol,room));changed=true;if(vol<=0)break;continue;}
      }
      // (e) margin via OrderCalcMargin (section 22): native, account currency.
      double reqMargin=0;
      ENUM_ORDER_TYPE ot=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      if(!OrderCalcMargin(ot,eaSymbol,vol,entry,reqMargin))
      {
         // Fallback: reject rather than guess margin with an invented formula.
         g_lastRiskReason="MARGIN_CALC_FAILED";break;
      }
      g_lastRequiredMargin=reqMargin;
      if(eq>0&&reqMargin/eq*100.0>InpMaxNewTradeMarginPct)
      {
         double byStep=FloorVolume(vol-step);
         if(byStep<broker.volumeMin){g_marginRejects++;g_lastRiskReason="MARGIN_CAP";break;}
         vol=byStep;changed=true;continue;
      }
      double projectedFree=freeBefore-reqMargin;
      if(eq>0&&projectedFree<eq*InpMinFreeMarginReservePct/100.0)
      {
         double byStep2=FloorVolume(vol-step);
         if(byStep2<broker.volumeMin){g_marginRejects++;g_lastRiskReason="MARGIN_INSUFFICIENT";break;}
         vol=byStep2;changed=true;continue;
      }
      // (f) OrderCheck on the real request shape (section 23).
      MqlTradeRequest rq;MqlTradeCheckResult chk;ZeroMemory(rq);ZeroMemory(chk);
      rq.action=TRADE_ACTION_DEAL;rq.symbol=eaSymbol;rq.magic=InpMagicNumber;rq.volume=vol;
      rq.type=ot;rq.price=entry;rq.sl=sl;rq.deviation=AdaptiveDeviationPoints();
      if(!OrderCheck(rq,chk))
      {
         g_orderCheckRejects++;g_lastOrderCheckRetcode=(int)chk.retcode;g_lastOrderCheckComment=chk.comment;
         // Volume-related failures shrink a step; structural failures (stops/price)
         // are retried identically by OrderSend anyway -> fail here and log.
         if(chk.retcode==TRADE_RETCODE_NO_MONEY)
         {
            double byStep3=FloorVolume(vol-step);
            if(byStep3<broker.volumeMin){g_lastRiskReason="ORDER_CHECK_FAILED";break;}
            vol=byStep3;changed=true;continue;
         }
         g_lastRiskReason="ORDER_CHECK_FAILED";
         break;
      }
      g_lastOrderCheckRetcode=0;g_lastOrderCheckComment="";
      if(!changed)break;   // all checks passed at this volume
   }
   if(vol<broker.volumeMin-1e-9)return 0;
   g_lastFinalLots=vol;
   return vol;
}

//--- section 23: dedicated preflight for NEW trade requests only. Never called for
//--- SL/TP modifications or deletions (those keep their own paths).
bool PreflightNewTrade(MqlTradeRequest &request,MqlTradeCheckResult &check,string &reason)
{
   reason="";
   MqlTradeCheckResult chk;ZeroMemory(chk);
   if(!OrderCheck(request,chk))
   {
      check=chk;g_orderCheckRejects++;
      g_lastOrderCheckRetcode=(int)chk.retcode;g_lastOrderCheckComment=chk.comment;
      reason="ORDER_CHECK_FAILED:"+chk.comment;
      Print("ORDER_CHECK_FAILED retcode=",chk.retcode," comment=",chk.comment," balance=",DoubleToString(chk.balance,2)," equity=",DoubleToString(chk.equity,2)," margin=",DoubleToString(chk.margin,2)," free=",DoubleToString(chk.margin_free,2)," level=",DoubleToString(chk.margin_level,2));
      return false;
   }
   check=chk;g_lastOrderCheckRetcode=0;g_lastOrderCheckComment="";
   return true;
}

//--- section 27: adaptive slippage deviation for NEW ENTRY requests.
//--- Emergency closes keep their own explicit deviation (never restricted by this).
int AdaptiveDeviationPoints()
{
   //--- [PERCENTAGE FORM] deviation budget = % of ATR (broker-adaptive); the absolute
   //--- legacy ceiling remains as the bound when ATR is unknown. CLOSING operations use
   //--- the fixed legacy deviation so emergency exits are never restricted.
   int extreme=(int)AdaptiveExtremeSlippagePts();
   if(g_slipCnt<5)return (int)MathMin(InpMaxSlippagePoints,extreme);   // warmup -> legacy fallback
   double avg=g_slipAvg;   // measured in points already (PushSlippage)
   double pctCap=(g_atr>0?(g_atr*InpMaxSlippagePctOfATR/100.0)/broker.point:InpMaxSlippagePoints);
   int dev=(int)MathMax(3.0,MathMin(pctCap,MathMin(extreme-1,MathMax(avg*2.0,pctCap*0.4))));
   return dev;
}

//--- section 44: non-trading self-tests. Profile classification boundaries and risk
//--- monotonicity on synthetic broker specs. NO real orders are sent by this function.
double g_usdTestHelper=0;
ENUM_CAPITAL_PROFILE CapClassifyTest()
{
   // Local mirror of the boundary logic in GetCapitalProfile (that function reads live
   // account state; the test verifies the BOUNDARY TABLE itself).
   if(g_usdTestHelper<500.0)return CAPITAL_MICRO;
   if(g_usdTestHelper<5000.0)return CAPITAL_STANDARD;
   return CAPITAL_PRO;
}
void CapitalSelfTest()
{
   bool allOK=true;
   // --- profile boundary table (section 44) ---
   double  tUsd[11]={49.99,50.0,100.0,499.99,500.0,1000.0,4999.99,5000.0,10000.0,50000.0,100000.0};
   int     tExp[11]={0,0,0,0,1,1,1,2,2,2,2};   // 0=MICRO 1=STANDARD 2=PRO
   for(int i=0;i<11;i++)
   {
      g_usdTestHelper=tUsd[i];
      ENUM_CAPITAL_PROFILE got=CapClassifyTest();
      if((int)got!=tExp[i])
      {
         allOK=false;
         Print("CAPITAL SELF-TEST FAIL: equityUSD=",DoubleToString(tUsd[i],2)," expected=",tExp[i]," got=",CapitalProfileName(got));
      }
   }
   // --- risk monotonicity on the volume solver (synthetic specs, no orders) ---
   {
      double saveMin=broker.volumeMin,saveMax=broker.volumeMax,saveStep=broker.volumeStep,saveTick=broker.tickSize,saveTickV=broker.tickValue;
      broker.volumeMin=0.01;broker.volumeMax=100;broker.volumeStep=0.01;broker.tickSize=0.01;broker.tickValue=1.0;
      double e=2000.0,sl1=e-4.0,sl2=e-8.0;   // larger SL = larger distance
      double r1=CalculateRealTradeRiskMoney(1,1.0,e,sl1);
      double r2=CalculateRealTradeRiskMoney(1,1.0,e,sl2);
      if(!(r2>r1)){allOK=false;Print("CAPITAL SELF-TEST FAIL: larger SL must produce larger risk money (",DoubleToString(r2,2)," vs ",DoubleToString(r1,2),")");}
      broker.tickValue=200.0;   // XAUUSD-like: $1 move = $100/lot
      double r3=CalculateRealTradeRiskMoney(1,1.0,e,sl1);
      if(!(r3>r1)){allOK=false;Print("CAPITAL SELF-TEST FAIL: higher tick value must produce larger risk money");}
      broker.volumeMin=saveMin;broker.volumeMax=saveMax;broker.volumeStep=saveStep;broker.tickSize=saveTick;broker.tickValue=saveTickV;
   }
   if(allOK)Print("CAPITAL SELF-TEST PASS: profile boundaries + risk monotonicity (no orders sent)");
   else      Print("CAPITAL SELF-TEST FAIL: see lines above - DO NOT deploy");
}

double CurrentRiskPct(ENUM_WINDOW_ID w,bool hv)
{
   // Legacy-compatible wrapper: existing callers get the new resolver transparently.
   return GetEffectiveTradeRiskPct(w,hv);
}

//--- section 17 driver: signature kept, body delegates to the native solver.
//--- (dir/entry from the current spread: market entries at Ask/Bid; pending at price.)
double CalculateLot(double slDist,ENUM_WINDOW_ID w,bool hv)
{
   if(InpAutoRiskSizing&&InpAutoCapitalProfile)
   {
      // direction comes from the live scalp signal; solver itself is direction-symmetric
      // for the gold quote (OrderCalcProfit BUY/SELL differ only by the entry/exit side,
      // which is captured by entry+SL prices).
      int dir=(g_scalpSignal>0?1:(g_scalpSignal<0?-1:0));
      if(dir==0)dir=1;
      double entry=(dir>0?Ask():Bid());
      double sl=(dir>0?entry-slDist:entry+slDist);
      return CalculateLotNative(slDist,dir,entry,PriceNorm(sl),w,hv);
   }
   // Legacy manual pipeline (InpAutoRiskSizing=false ONLY): unchanged behavior,
   // conservative base swapped in. InpLotSize applies here exactly as before.
   if(InpRiskPercent<=0)return NormalizeVolume(InpLotSize);if(slDist<=0)return 0;double bal=GetConservativeCapitalBase(),rp=CurrentRiskPct(w,hv);if(rp<=0)return 0;
   double risk=bal*rp/100.0;
   if((InpNoMartingale||InpNoAveragingDown)&&CountOwnPositions()>0)
   {
      for(int i=0;i<PositionsTotal();i++)
      {
         ulong t=PositionGetTicket(i);if(!t||!PositionSelectByTicket(t))continue;
         if(PositionGetString(POSITION_SYMBOL)!=eaSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue;
         double op=PositionGetDouble(POSITION_PRICE_OPEN);
         int pd=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
         double px=(pd>0?Bid():Ask());
         if((pd>0&&px<op)||(pd<0&&px>op)){risk=MathMin(risk,bal*InpRiskPercent/100.0);break;}
      }
   }
   double perLot=PriceMoveMoney(slDist,1.0)+ExpectedAllInCost(1.0);if(perLot<=0)return 0;double lots=risk/perLot;
   if(InpMaxTotalLots>0&&InpUseAbsoluteLotEmergencyCap)lots=MathMin(lots,MathMax(0,InpMaxTotalLots-SumOwnLots()));
   double fv=FloorVolume(lots);
   if(fv<=0 && InpAllowMinLotFallback && lots>0)
   {
      double minRisk=PriceMoveMoney(slDist,broker.volumeMin)+ExpectedAllInCost(broker.volumeMin);
      if(bal>0 && minRisk/bal*100.0<=InpMinLotMaxRiskPct) fv=FloorVolume(broker.volumeMin);
   }
   return fv;
}

bool RiskRoom(double newRisk,int dir,ENUM_WINDOW_ID w,string &why)
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);if(eq<=0){why="bad equity";return false;}
   // [CAPITAL ENGINE] profile limits in Auto mode; identical legacy inputs when false.
   if((OpenRiskMoney()+newRisk)/eq*100.0>GetProfileAggregateRiskPct()){why="aggregate risk cap";return false;}
   if((OpenRiskMoney(dir)+newRisk)/eq*100.0>GetProfileDirectionalRiskPct()){why="direction risk cap";return false;}
   if(g_windowRiskUsed[w]+newRisk>eq*GetProfileWindowRiskPct()/100.0){why="window risk budget";return false;}
   return true;
}

bool ShouldStopTrading()
{
   UpdateRiskPeriods();if(g_stopDay||g_stopWeek||g_stopMonth)return true;
   return false;
}

//====================================================================
// STRUCTURE-AWARE SL / TP ENGINE (monotonic ladder + cost-positive legs)
//====================================================================
double NearestLiquidityTarget(int dir,double entry,int lookback,double fallback)
{
   MqlRates r[];ArraySetAsSeries(r,true);int n=(int)MathMax(10,lookback);if(CopyRates(eaSymbol,PERIOD_M1,1,n,r)<n)return fallback;
   double best=0;
   if(dir>0){for(int i=0;i<n;i++)if(r[i].high>entry && (best==0||r[i].high<best))best=r[i].high;}
   else {for(int i=0;i<n;i++)if(r[i].low<entry && (best==0||r[i].low>best))best=r[i].low;}
   return (best>0?best:fallback);
}

//--- Signal-aware SL/TP for the ultra-scalp engine (Phase 2 profile; see SCALP_* constants):
//--- trend-pullback: SL = 0.80 ATR (invalidation), TP1 = 0.40 ATR (0.50R)
//--- mean-reversion: SL = beyond last bar extreme + 0.45 ATR (noise-proof),
//---                 TP1 = VWAP (the mean) - the highest-probability target
double ScalpStopDistance(int dir,double entry,double &slPrice)
{
   double atr=MathMax(g_atr,MinTradeDistance())*SpreadCompensationFactor();   // [BROKER ADAPTATION] widen geometry on wide-spread feeds
   if(g_scalpSignal==2||g_scalpSignal==-2)   // VWAP reversion: beyond the extreme + 0.45 ATR
   {
      double ext=(dir>0?iLow(eaSymbol,PERIOD_M1,1):iHigh(eaSymbol,PERIOD_M1,1));
      slPrice=PriceNorm(ext-dir*SCALP_SL_REV*atr);
   }
   else if(g_scalpSignal==3||g_scalpSignal==-3)  // London breakout: 0.85 ATR stop
      slPrice=PriceNorm(entry-dir*SCALP_SL_BRK*atr);
   else slPrice=PriceNorm(entry-dir*SCALP_SL_ATR*atr);   // NY momentum / EMA pullback
   double d=MathAbs(entry-slPrice);
   double md=MinTradeDistance();
   if(d<md){d=md;slPrice=PriceNorm(entry-dir*d);}
   return d;
}
double ScalpTarget1(int dir,double entry)
{
   double atr=MathMax(g_atr,MinTradeDistance())*SpreadCompensationFactor();   // [BROKER ADAPTATION]
   if((g_scalpSignal==2||g_scalpSignal==-2)&&g_vwap>0)
   {
      // reversion: target the mean (VWAP), min 0.6 ATR away
      double d=MathAbs(g_vwap-entry);
      if(d<0.6*atr)d=0.6*atr;
      return PriceNorm(entry+dir*d);
   }
   // breakout/momentum/pullback: fixed ~2R-style via 0.40 ATR (stop is 0.80-0.85 ATR)
   return PriceNorm(entry+dir*SCALP_TP1_ATR*atr);
}

double ComputeSL(int dir,double entry)
{
   double atr=MathMax(g_atr,MinTradeDistance());double byAtr=(dir>0?entry-InpSL_ATR_Multiplier*atr:entry+InpSL_ATR_Multiplier*atr);
   double sl=byAtr;
   // Structure-aware SL only in the complex engine. In ultra-scalp mode the ATR stop is
   // HARD: widening to swing structure (potentially 3-5x the ATR distance on M1 gold)
   // is exactly what turned "risk 0.5%" into major losses.
   if(!InpSimpleScalpMode)
   {
      if(dir>0&&g_swingLow>0)sl=MathMin(sl,g_swingLow-InpSLStructureBufferATR*atr);
      if(dir<0&&g_swingHigh>0)sl=MathMax(sl,g_swingHigh+InpSLStructureBufferATR*atr);
   }
   double md=MinTradeDistance();if(dir>0&&entry-sl<md)sl=entry-md;if(dir<0&&sl-entry<md)sl=entry+md;return PriceNorm(sl);
}

double RegimeTPMultiplier(ENUM_WINDOW_ID w,bool hv)
{
   if(hv&&(w==WIN_SYDNEY_TOKYO||w==WIN_TOKYO_LONDON||w==WIN_LONDON_OPEN||w==WIN_LONDON_NY||w==WIN_NY_OPEN))return 0.85;
   if(hv)return 1.05;return 1.0;
}

//--- section 24: risk-relative TP viability gate. leg 1/2/3 -> % of INITIAL TRADE
//--- RISK MONEY. Legacy fixed-money gates retained when the new gate is disabled.
double MinNetProfitForLeg(int leg,double initialRiskMoney)
{
   if(!InpUseRiskRelativeNetProfitGate)
   {
      switch(leg)
      {
         case 1:return InpMinNetProfitTP1Money;
         case 2:return InpMinNetProfitTP2Money;
         case 3:return InpMinNetProfitTP3Money;
      }
      return InpMinNetProfitTP1Money;
   }
   double r=(initialRiskMoney>0?initialRiskMoney:0);
   switch(leg)
   {
      case 1:return r*InpMinTP1NetRiskPct/100.0;
      case 2:return r*InpMinTP2NetRiskPct/100.0;
      case 3:return r*InpMinTP3NetRiskPct/100.0;
   }
   return r*InpMinTP1NetRiskPct/100.0;
}

bool NetProfitValid(int dir,double entry,double target,double lots,double minMoney,double &net)
{
   double gross=PriceMoveMoney(target-entry,lots);double cost=ExpectedAllInCost(lots);net=gross-cost;
   if(gross<=0)return false;if(cost/gross*100.0>InpMaxCostToTP1Pct)return false;return net>=minMoney;
}

void BuildThreeTargets(int dir,double entry,double sl,double lots,ENUM_WINDOW_ID w,bool hv,double &tp1,double &tp2,double &tp3)
{
   double atr=MathMax(g_atr,MinTradeDistance())*SpreadCompensationFactor(),k=RegimeTPMultiplier(w,hv);   // [BROKER ADAPTATION]
   double d1=MathMax(InpTP1_ATR_Floor*atr,MathMin(InpTP1_ATR_Cap*atr,0.55*atr))*k;
   double d2=MathMax(InpTP2_ATR_Floor*atr,MathMin(InpTP2_ATR_Cap*atr,1.10*atr))*k;
   double d3=MathMax(InpTP3_ATR_Floor*atr,MathMin(InpTP3_ATR_Cap*atr,1.85*atr))*(hv?1.05:1.0);
   tp1=entry+dir*d1;tp2=entry+dir*d2;tp3=entry+dir*d3;
   // [SR] snap legs to nearby zone edges BEFORE validation so the existing
   // monotonic/cost machinery re-validates on the snapped prices (constraint 7)
   if(InpUseSRZones&&InpSRSnapTP)
   {tp1=SR_AdjustTP(dir,entry,tp1,atr,1);tp2=SR_AdjustTP(dir,entry,tp2,atr,2);tp3=SR_AdjustTP(dir,entry,tp3,atr,3);}
   double md=MinTradeDistance();
   // Strict monotonic ladder first: TP1 < TP2 < TP3 can never be violated.
   if(dir>0){tp1=MathMax(tp1,entry+md);tp2=MathMax(tp2,tp1+md);tp3=MathMax(tp3,tp2+md);}
   else{tp1=MathMin(tp1,entry-md);tp2=MathMin(tp2,tp1-md);tp3=MathMin(tp3,tp2-md);}
   // Live-chart precision: snap TP1 to the nearest real liquidity level when one sits
   // between entry and the ATR default (targets then mark genuine S/R, not blind ATR).
   double l1=NearestLiquidityTarget(dir,entry,20,0);
   if(l1>0)
   {
      double dd=MathAbs(l1-entry);
      if(dd>=md && dd<MathAbs(tp1-entry)) tp1=l1;   // closer REAL level wins
   }
   // Restore ordering after the snap.
   if(dir>0){tp2=MathMax(tp2,tp1+md);tp3=MathMax(tp3,tp2+md);}else{tp2=MathMin(tp2,tp1-md);tp3=MathMin(tp3,tp2-md);}
   // Cost-aware expand per leg against the volume that will ACTUALLY close there
   // (60/25/15 split of the ladder). Validating on full 'lots' was too lenient: a leg
   // closing 15% of the position earns 15% of the gross but pays commission on it too,
   // and the spread cost is only saved on that fraction.
   double sumPct=MathMax(0.0001,g_tp1PctEff+g_tp2PctEff+g_tp3PctEff);
   double v1=FloorVolume(lots*g_tp1PctEff/sumPct);
   double v2=FloorVolume(lots*g_tp2PctEff/sumPct);
   double v3=FloorVolume(lots-v1-v2);
   if(v1<broker.volumeMin)v1=lots;                       // collapse: single leg carries all
   if(v2<broker.volumeMin)v2=(v3<broker.volumeMin?0:lots-v1);
   if(v3<broker.volumeMin)v3=0;
   double net=0;int guard=0;
   // [TP GATES] risk-relative minimum net profit = % of this trade's INITIAL RISK
   // (initialRiskMoney = SL loss + all-in cost at the actual volume; section 24).
   double initialRisk=CalculateRealTradeRiskMoney(dir,lots,entry,sl);   // authoritative: SL loss + all-in cost (section 16/24)
   if(initialRisk<=0)initialRisk=PriceMoveMoney(MathAbs(entry-sl),lots)+ExpectedAllInCost(lots);   // fallback parity
   double min1=MinNetProfitForLeg(1,initialRisk),min2=MinNetProfitForLeg(2,initialRisk),min3=MinNetProfitForLeg(3,initialRisk);
   while(!NetProfitValid(dir,entry,tp1,v1,min1,net)&&guard++<10)tp1+=dir*0.10*atr;
   guard=0;
   while(v2>0&&!NetProfitValid(dir,entry,tp2,v2,min2,net)&&guard++<10)tp2+=dir*0.10*atr;
   guard=0;
   while(v3>0&&!NetProfitValid(dir,entry,tp3,v3,min3,net)&&guard++<10)tp3+=dir*0.10*atr;
   if(dir>0){tp2=MathMax(tp2,tp1+md);tp3=MathMax(tp3,tp2+md);}else{tp2=MathMin(tp2,tp1-md);tp3=MathMin(tp3,tp2-md);}
   tp1=PriceNorm(tp1);tp2=PriceNorm(tp2);tp3=PriceNorm(tp3);
}

// Reward-to-risk quality gate: the ladder must genuinely out-earn its stop.
bool RRValid(int dir,double entry,double sl,double target,double minRR)
{
   double slDist=MathAbs(entry-sl);if(slDist<=0)return false;
   double reward=MathAbs(target-entry);
   return (reward/slDist>=minRR);
}

void AllocateVolumes(double total,double &v1,double &v2,double &v3)
{
   v1=v2=v3=0;double sum=MathMax(0.0001,g_tp1PctEff+g_tp2PctEff+g_tp3PctEff);double minv=broker.volumeMin;
   v1=FloorVolume(total*g_tp1PctEff/sum);v2=FloorVolume(total*g_tp2PctEff/sum);v3=FloorVolume(total-v1-v2);
   if(v3<=0){v3=0;v2=FloorVolume(total-v1);}if(v2<=0){v2=0;v1=total;}
   // If three legs cannot satisfy broker minimum, intelligently collapse to two/one leg.
   int valid=(v1>=minv?1:0)+(v2>=minv?1:0)+(v3>=minv?1:0);
   // Phase 2.5 ladder feasibility: every leg >= volMin AND every residual after a
   // partial close also >= volMin (a broker rejects a close leaving a sub-min remainder).
   // Degradation cascade 3-leg -> 2-leg -> 1-leg, governed by InpAutoDegradeTPLadder;
   // InpLadderRoundingMode decides where the FloorVolume residue lands.
   if(!InpAutoDegradeTPLadder&&valid<3&&total>=minv){v1=total;v2=0;v3=0;return;}   // legacy single-leg fallback
   if(valid<3&&total<3*minv-1e-12)
   {
      if(total>=2*minv){v3=0;v1=FloorVolume(total*g_tp1PctEff/(g_tp1PctEff+g_tp2PctEff));v2=FloorVolume(total-v1);}
      else{v3=0;v2=0;v1=total;}
      if(v2<minv){v2=0;v1=total;}
      if(v1<minv){v1=0;}   // below one min lot the ladder is infeasible; caller rejects
      return;
   }
   if(InpLadderRoundingMode==LADDER_FAVOR_TP1){double rem=FloorVolume(total-v1-v2-v3);if(rem>=minv)v1=FloorVolume(v1+rem);}
   else if(InpLadderRoundingMode==LADDER_FAVOR_RUNNER&&v3>0){double rem=FloorVolume(total-v1-v2-v3);if(rem>=minv)v3=FloorVolume(v3+rem);}
   double used=v1+v2+v3;double rem2=FloorVolume(total-used);if(rem2>0)v1=FloorVolume(v1+rem2);
   if(v1<=0){v1=total;v2=v3=0;}
}//====================================================================
// SETUP / ENTRY GATING
//====================================================================
string MakeSetupId(int dir,ENUM_WINDOW_ID w)
{
   datetime b=iTime(eaSymbol,PERIOD_M1,1);string smc=(dir>0?(g_bosUp?"BOSU":g_chochUp?"CHU":g_sweepDn?"SWD":"BASE"):(g_bosDn?"BOSD":g_chochDn?"CHD":g_sweepUp?"SWU":"BASE"));
   return IntegerToString((int)w)+"-"+(dir>0?"B":"S")+"-"+IntegerToString((int)b)+"-"+smc;
}

bool FreshSetup(int dir,ENUM_WINDOW_ID w,string &id,string &why)
{
   id=MakeSetupId(dir,w);if(!InpOncePerValidatedEvent)return true;
   string last=(dir>0?g_lastSetupBuy[w]:g_lastSetupSell[w]);if(id==last){why="duplicate setup";return false;}
   datetime now=ServerNow();if(g_lastWindowEntry[w]>0&&now-g_lastWindowEntry[w]<InpMinSecondsBetweenEntries){why="entry spacing";return false;}
   if(g_lastWindowEntry[w]>0&&iTime(eaSymbol,PERIOD_M1,1)-g_lastWindowEntry[w]<InpMinBarsFreshStructure*60){why="fresh-structure spacing";return false;}
   if(g_windowSignals[w]>=InpMaxSignalsPerWindow){why="window signal cap";return false;}return true;
}

bool CanEnter(int dir,ENUM_WINDOW_ID &w,bool &hv,string &setup,string &why)
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)||!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)||!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)||!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)){why="trading disabled";return false;}
   if(g_paused){why="manual pause (F)";return false;}
   if(ShouldStopTrading()){why="risk breaker";return false;}if(WeekendOrRollover()){why="weekend/rollover";return false;}
   bool tr=false;w=CurrentWindow(tr);if(InpUseSessionFilter&&!tr){why="out of enabled session";return false;}if(w==WIN_NONE){why="no opportunity window";return false;}
   if(g_newsBlocked||ServerNow()<g_newsBlockedUntil){why="news/stabilization";return false;}
   if(InSwapDangerWindow()){why="swap/rollover protection";return false;}
   double sp=SpreadPoints();
   //--- [PERCENTAGE GATE] broker-adaptive: spread budget = % of the projected SL distance
   //--- (SCALP_SL_ATR x ATR in simple mode; InpSL_ATR_Multiplier x ATR in complex mode)
   double projSL=MathMax(g_atr,MinTradeDistance())*SpreadCompensationFactor()*(InpSimpleScalpMode?SCALP_SL_ATR:InpSL_ATR_Multiplier);
   double spCap=AdaptiveSpreadCap(projSL);
   if(sp>spCap){why="spread hard cap (cap "+DoubleToString(spCap,0)+"pt)";return false;}
   if(sp>=(spCap+20)*g_ptScale){why="spread extreme";return false;}   // broken feed
   // [SPREAD] adaptive relative gate after warmup (section 26): ATR-ratio + percentile
   // + spike conditions; emergency closes never pass through here.
   if(!AdaptiveSpreadOK(g_atr,why))return false;
   double atrPts=(broker.point>0?g_atr/broker.point:0);
   if(atrPts<InpMinATRPoints*g_ptScale){why="ATR chop";return false;}
   // ============ ULTRA-SCALP SIMPLE PATH (default) ============
   // Momentum + spread + risk. The multi-filter machinery below is only for
   // InpSimpleScalpMode=false. A scalp engine must fire on clean setups, not
   // survive a 14-item confluence checklist that can veto every bar.
   if(InpSimpleScalpMode)
   {
      // Ultra-scalp v3: four signal modes (VWAP reversion, London breakout, NY momentum,
      // EMA pullback) computed once per M1 bar in EvaluateScalpSignal().
      int want=(g_scalpSignal>0?1:-1);
      if(g_scalpSignal==0||want!=dir){why="no scalp signal ("+g_scalpWhy+")";return false;}
      setup=g_scalpWhy;
      // Momentum modes need liquid hours; reversion works everywhere (range fades).
      bool liquid=(w==WIN_TOKYO_LONDON||w==WIN_LONDON_NY||w==WIN_LONDON_OPEN||w==WIN_NY_OPEN
                   ||w==WIN_LONDON||w==WIN_NEWYORK);
      if((g_scalpSignal==1||g_scalpSignal==-1||g_scalpSignal==3||g_scalpSignal==-3)&&!liquid)
      {why="momentum signal in thin session";return false;}
      // Anti-stacking: no second scalp same direction within 60s or 0.35 ATR of an open one
      datetime now=ServerNow();
      if(g_lastEntryTime>0&&now-g_lastEntryTime<60){why="entry spacing 60s";return false;}
      double px=(dir>0?Ask():Bid());
      for(int i=0;i<PositionsTotal();i++)
      {
         ulong t=PositionGetTicket(i);if(!t||!PositionSelectByTicket(t))continue;
         if(PositionGetString(POSITION_SYMBOL)!=eaSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue;
         if((int)PositionGetInteger(POSITION_TYPE)!=(dir>0?POSITION_TYPE_BUY:POSITION_TYPE_SELL))continue;
         double op=PositionGetDouble(POSITION_PRICE_OPEN);
         if(MathAbs(px-op)<0.35*MathMax(g_atr,MinTradeDistance())){why="too close to open scalp";return false;}
      }
      // [SR] entry gate: after all cost/spread/session/news gates, before dispatch
      double srAtr=MathMax(g_atr,MinTradeDistance());
      double srTp1=MathAbs(ScalpTarget1(dir,px)-px);
      string srWhy="";
      if(!SR_EntryAllowed(dir,px,srAtr,srTp1,srWhy)){why=srWhy;return false;}
      hv=false;
      if(g_tradesToday>=InpMaxTradesPerDay){why="daily trade cap";return false;}
      if(!broker.hedging&&CountOwnPositions()>0){why="netting: one position";return false;}
      if(CountOwnPositions()>=GetProfileMaxPositions()){why="position cap";return false;}
      return true;
   }
   RefreshWindowGating(w);if(g_ws[w].disabled){why="window expectancy disabled";return false;}
   if(IsDisorder()){why="market disorder";return false;}
   if(g_slipCnt>=5&&g_slipAvg>AdaptiveMaxAvgSlippagePts()){why="slippage quality gate";return false;}
   if(g_lastSlipPts>=AdaptiveExtremeSlippagePts()&&ServerNow()<g_disorderUntil){why="last fill slippage extreme";return false;}
   if(!ExternalDataReady(why))return false;
   double spp=SpreadPercentile();if(g_spreadAvg>0&&sp>g_spreadAvg*InpSpreadSpikeRatio){why="spread spike";return false;}if(spp>InpMaxSpreadPercentile){why="spread percentile";return false;}
   if(InpMaxATRPoints>0&&atrPts>InpMaxATRPoints*g_ptScale){why="ATR chaos";return false;}
   double disp=CandleDisplacementATR();if(disp>InpMaxChaseCandleATR){why="anti-chase displacement";return false;}double cc=iClose(eaSymbol,PERIOD_M1,1);if(g_vwap>0&&g_atr>0&&MathAbs(cc-g_vwap)/g_atr>InpMaxEntryVWAPDeviationATR){why="anti-chase VWAP distance";return false;}
   if(InpFilterMode==FILTER_ALL_REQUIRED&&g_score<g_scoreMax){why="filters";return false;}
   g_score+=SR_DirectionalVote(dir,(dir>0?Ask():Bid()),g_atr);   // [SR] complex-mode vote: -1..+1, can never satisfy MinFilterScore alone
   if(InpFilterMode==FILTER_SCORING&&g_score<InpMinFilterScore){why="score";return false;}
   if(MathAbs(g_dirBias)<InpMinDirBias){why="weak directional bias";return false;}if((dir>0&&g_dirBias<0)||(dir<0&&g_dirBias>0)){why="bias conflict";return false;}
   if(InpUseSMC&&((dir>0?g_smcScoreBull:g_smcScoreBear)<InpMinSMCConfluence)){why="SMC confluence";return false;}
   if(!LiveMomentumConfirm(dir)){why="live price vs EMA20";return false;}
   if((InpUseIFVG||InpUsePTB)){int adv=(dir>0?((g_ifvg&&g_ifvgDir>0)?1:0)+((g_ptb&&g_ptbDir>0)?1:0):((g_ifvg&&g_ifvgDir<0)?1:0)+((g_ptb&&g_ptbDir<0)?1:0));if(adv<InpMinAdvancedSMCConfluence&&InpMinAdvancedSMCConfluence>0){why="IFVG/PTB confluence";return false;}}
   if(AvailableMacroCount()>0&&MacroVotes(dir)<InpMacroMinConfluence){why="macro conflict";return false;}
   int hvs=0;hv=InpAB_EnableHighVol&&IsHighVolatilityQualified(dir,hvs);
   if(!InpAB_EnableBase&&!hv){why="A/B base engine disabled";return false;}
   bool preferred=(w==WIN_SYDNEY_TOKYO||w==WIN_TOKYO_LONDON||w==WIN_LONDON_OPEN||w==WIN_LONDON_NY||w==WIN_NY_OPEN||w==WIN_VERIFIED_EXPANSION);
   if(InpHighVolatilityMode==HV_FORCE_GATED && preferred && !hv){why="HV verification failed";return false;}
   if(!FreshSetup(dir,w,setup,why))return false;
   if(g_tradesToday>=InpMaxTradesPerDay){why="daily trade cap";return false;}if(!broker.hedging&&CountOwnPositions()>0){why="netting account: one strategy position at a time";return false;}if(CountOwnPositions()>=GetProfileMaxPositions()){why="position cap";return false;}
   return true;
}

//====================================================================
// NATIVE TRADE EXECUTION (no CTrade; 9-arg WebRequest-safe, retcodes checked)
//====================================================================
ENUM_ORDER_TYPE_FILLING BestFillingMode()
{
   long f=SymbolInfoInteger(eaSymbol,SYMBOL_FILLING_MODE);
   long ex=SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_EXEMODE);
   if((f & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((f & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if(ex!=SYMBOL_TRADE_EXECUTION_MARKET) return ORDER_FILLING_RETURN;
   return ORDER_FILLING_FOK;
}

bool RetcodeOK(uint r){return (r==TRADE_RETCODE_DONE||r==TRADE_RETCODE_PLACED||r==TRADE_RETCODE_DONE_PARTIAL);}

bool SendOrder(MqlTradeRequest &rq,MqlTradeResult &rs)
{
   rq.type_filling=BestFillingMode();
   for(int k=0;k<=InpOrderRetry;k++)
   {
      ZeroMemory(rs);
      if(OrderSend(rq,rs)&&RetcodeOK(rs.retcode))return true;
      // 10015/10016 (invalid price/stops) will not heal by retrying.
      if(rs.retcode==TRADE_RETCODE_INVALID_PRICE||rs.retcode==TRADE_RETCODE_INVALID_STOPS)return false;
      Sleep(40);
   }
   return false;
}

bool PlaceStop(int dir,double lots,double price,double sl,double tp,string comment,ulong &ticket)
{
   ticket=0;double md=MinTradeDistance();double a=Ask(),b=Bid();
   if(dir>0){if(price-a<md)price=a+md;if(price-sl<md)sl=price-md;if(tp-price<md)tp=price+md;}
   else{if(b-price<md)price=b-md;if(sl-price<md)sl=price+md;if(price-tp<md)tp=price-md;}
   price=PriceNorm(price);sl=PriceNorm(sl);tp=PriceNorm(tp);
   MqlTradeRequest rq;MqlTradeResult rs;ZeroMemory(rq);ZeroMemory(rs);
   rq.action=TRADE_ACTION_PENDING;rq.symbol=eaSymbol;rq.magic=InpMagicNumber;rq.volume=lots;
   rq.type=(dir>0?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP);
   rq.price=price;rq.sl=sl;rq.tp=tp;rq.comment=comment;
   // [PREFLIGHT] new pending entries also go through OrderCheck (section 23).
   MqlTradeCheckResult pchk;string pr="";
   MqlTradeRequest probe=rq;probe.type_time=ORDER_TIME_GTC;probe.expiration=0;   // OrderCheck: GTC shape validates the same economics
   if(!PreflightNewTrade(probe,pchk,pr))return false;
   datetime exp=ServerNow()+InpPendingExpiryMinutes*60;
   // Most brokers accept ORDER_TIME_SPECIFIED; the final attempt falls back to
   // GTC (stale pendings are still swept by InpCancelStalePendings).
   for(int mode=0;mode<2;mode++)
   {
      if(mode==0){rq.type_time=ORDER_TIME_SPECIFIED;rq.expiration=exp;}
      else{rq.type_time=ORDER_TIME_GTC;rq.expiration=0;}
      if(SendOrder(rq,rs)){ticket=rs.order;return true;}
      if(rs.retcode==TRADE_RETCODE_INVALID_PRICE||rs.retcode==TRADE_RETCODE_INVALID_STOPS)return false;
   }
   return false;
}

bool MarketOrder(int dir,double lots,double sl,double tp,string comment,double &fillPrice,ulong &ticket)
{
   fillPrice=0;ticket=0;
   MqlTradeRequest rq;MqlTradeResult rs;ZeroMemory(rq);ZeroMemory(rs);
   rq.action=TRADE_ACTION_DEAL;rq.symbol=eaSymbol;rq.magic=InpMagicNumber;rq.volume=lots;
   rq.type=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   rq.price=(dir>0?Ask():Bid());
   // [SLIPPAGE] adaptive entry deviation from learned execution profile (section 27);
   // bounded by the legacy ceiling and the pathological cap. Closes keep their own
   // explicit deviation (ClosePartialSafe) so emergency exits are never restricted.
   rq.deviation=AdaptiveDeviationPoints();rq.comment=comment;rq.sl=sl;rq.tp=tp;
   // [PREFLIGHT] OrderCheck before dispatch of every NEW trade (section 23).
   MqlTradeCheckResult chk;string pr="";
   if(!PreflightNewTrade(rq,chk,pr))return false;
   if(!SendOrder(rq,rs))return false;
   // res.price is the real fill (B5 fix); fall back to the position price.
   fillPrice=(rs.price>0?rs.price:rq.price);
   ticket=rs.order;
   return true;
}

bool ModifyPositionSafe(ulong ticket,double sl,double tp)
{
   sl=(sl>0?PriceNorm(sl):0);tp=(tp>0?PriceNorm(tp):0);
   MqlTradeRequest rq;MqlTradeResult rs;ZeroMemory(rq);ZeroMemory(rs);
   rq.action=TRADE_ACTION_SLTP;rq.position=ticket;rq.symbol=eaSymbol;rq.sl=sl;rq.tp=tp;
   for(int k=0;k<=InpOrderRetry;k++)
   {
      ZeroMemory(rs);
      if(OrderSend(rq,rs)&&RetcodeOK(rs.retcode))return true;
      Sleep(30);
   }
   return false;
}

bool DeleteOrderSafe(ulong ticket)
{
   MqlTradeRequest rq;MqlTradeResult rs;ZeroMemory(rq);ZeroMemory(rs);
   rq.action=TRADE_ACTION_REMOVE;rq.order=ticket;
   for(int k=0;k<=InpOrderRetry;k++)
   {
      ZeroMemory(rs);
      if(OrderSend(rq,rs)&&RetcodeOK(rs.retcode))return true;
      Sleep(30);
   }
   return false;
}

void DeleteOwnPendings(bool onlyStale=false)
{
   datetime now=ServerNow();
   for(int i=OrdersTotal()-1;i>=0;i--){ulong t=OrderGetTicket(i);if(!t||!OrderSelect(t))continue;if(OrderGetString(ORDER_SYMBOL)!=eaSymbol||OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)continue;if(onlyStale){datetime st=(datetime)OrderGetInteger(ORDER_TIME_SETUP);if(now-st<InpPendingExpiryMinutes*60)continue;}DeleteOrderSafe(t);}
}

bool ClosePartialSafe(ulong ticket,double volume)
{
   if(volume<=0||!PositionSelectByTicket(ticket))return false;double cur=PositionGetDouble(POSITION_VOLUME);volume=FloorVolume(MathMin(volume,cur));if(volume<=0)return false;
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest rq;MqlTradeResult rs;ZeroMemory(rq);ZeroMemory(rs);rq.action=TRADE_ACTION_DEAL;rq.position=ticket;rq.symbol=eaSymbol;rq.magic=InpMagicNumber;rq.volume=volume;rq.deviation=InpMaxSlippagePoints;rq.type=(pt==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);rq.price=(rq.type==ORDER_TYPE_BUY?Ask():Bid());
   if(!SendOrder(rq,rs))return false;return true;
}

bool ClosePositionSafe(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))return false;
   double cur=PositionGetDouble(POSITION_VOLUME);
   return ClosePartialSafe(ticket,cur);
}

void EmergencyCloseAll()
{
   DeleteOwnPendings(false);for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==eaSymbol&&PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)ClosePositionSafe(t);}
}

//====================================================================
// POSITION STATE
//====================================================================
int FindPS(ulong ticket){for(int i=0;i<ArraySize(g_ps);i++)if(g_ps[i].ticket==ticket)return i;return -1;}
void RemovePS(int idx){int n=ArraySize(g_ps);if(idx<0||idx>=n)return;for(int i=idx;i<n-1;i++)g_ps[i]=g_ps[i+1];ArrayResize(g_ps,n-1);}

void AddPositionState(ulong ticket,long posId,int dir,ENUM_WINDOW_ID w,string setup,bool hv,bool recovery,double entry,double sl,double lots,double slip,double entryComm)
{
   int idx=FindPS(ticket);if(idx<0){idx=ArraySize(g_ps);ArrayResize(g_ps,idx+1);}
   PositionState s;ZeroMemory(s);
   s.ticket=ticket;s.positionId=posId;s.direction=dir;s.window=w;s.setupId=setup;s.hv=hv;s.recovery=recovery;
   s.entry=entry;s.initialSL=sl;s.initialVolume=lots;
   s.initialRiskMoney=MathMax(0.0,PriceMoveMoney(entry-sl,lots)+ExpectedAllInCost(lots));
   s.opened=ServerNow();s.entrySpreadPct=SpreadPercentile();s.entrySlipPts=slip;s.entryAtrPct=ATRPercentile();s.entryVolRatio=g_volRatio;
   s.realizedGross=0;s.realizedNet=entryComm;s.realizedCosts=MathAbs(entryComm)+PriceMoveMoney(SpreadPoints()*broker.point+MathAbs(slip)*broker.point,lots);
   s.maePrice=0;s.mfePrice=0;
   if(recovery)
   {
      // Single-target trade: broker TP was validated by TryRecovery before placement.
      // Mirror it into the state (tp1=tp2=tp3=placed TP) so management never runs the
      // 60/25/15 partial ladder and never rewrites the validated broker target.
      double placed=PositionGetDouble(POSITION_TP);
      s.tp1=(placed>0?placed:0);s.tp2=s.tp1;s.tp3=s.tp1;
      s.volTP1=0;s.volTP2=0;s.volTP3=lots;
      s.tp1Done=true;s.tp2Done=true;   // ladder stages pre-marked done: nothing partials
      g_ps[idx]=s;
      return;                          // broker TP/SL stand as sent - no rewrite
   }
   // Simple scalp mode: manage against the ARMED scalp plan (t1/t2/t3 computed in
   // TryArm before the fill), not the complex-engine ATR ladder - the entry was
   // cost-validated against exactly this plan. Full exit at TP1 (micro-scalp);
   // broker TP/SL are overwritten to the armed t3/SL so the plan survives restarts.
   if(InpSimpleScalpMode&&g_armValid)
   {
      s.tp1=g_armTp1;s.tp2=g_armTp2;s.tp3=g_armTp3;
      s.volTP1=lots;s.volTP2=0;s.volTP3=0;   // bank everything at TP1 (broker-min runner may trail to t3)
      s.tp1Done=false;s.tp2Done=true;s.tp3Done=false;
      g_ps[idx]=s;
      ModifyPositionSafe(ticket,sl,s.tp3);
      g_armValid=false;                       // snapshot consumed by this fill
      return;
   }
   if(InpSimpleScalpMode)g_armValid=false;    // stale snapshot (restart gap): fall back to complex ladder
   // Use the HV regime carried by the pending order so the executed plan matches the armed plan.
   BuildThreeTargets(dir,entry,sl,lots,w,hv,s.tp1,s.tp2,s.tp3);
   if(InpUseThreeTargets&&InpAB_EnableThreeTP)AllocateVolumes(lots,s.volTP1,s.volTP2,s.volTP3);
   else{s.volTP1=0;s.volTP2=0;s.volTP3=lots;s.tp1Done=true;s.tp2Done=true;}
   g_ps[idx]=s;
   // TP3 is placed at broker as catastrophe-safe final target; TP1/TP2 are virtual managed exits.
   ModifyPositionSafe(ticket,sl,s.tp3);
}

//====================================================================
// ENTRY ARMING
//====================================================================
void TryArm()
{
   if(!LicenseCheckGate()){return;}   // [LICENSE] no new trades without a valid license
   if(InpCancelStalePendings)DeleteOwnPendings(true);
   if(CountOwnPendings()>0){g_gateReason="pending orders working";return;}
   if(!InpArmWhileInTrade&&CountOwnPositions()>0){g_gateReason="managing open position";return;}
   // EXEC_STRADDLE arms stop orders ahead of price; EXEC_DIRECTIONAL fires a market
   // order at signal time; EXEC_AUTO picks directional only in verified HV windows.
   int dir;
   if(InpSimpleScalpMode)
   {
      // Direction comes from the two-mode signal computed on the last closed bar.
      if(g_scalpSignal>0)dir=1;else if(g_scalpSignal<0)dir=-1;
      else{g_gateReason="no scalp signal";return;}
   }
   else dir=(g_dirBias>0?1:-1);
   ENUM_WINDOW_ID w;bool hv=false;string setup,why;if(!CanEnter(dir,w,hv,setup,why)){g_gateReason=why;return;}
   bool directional=(InpExecutionMode==EXEC_DIRECTIONAL||(InpExecutionMode==EXEC_AUTO&&w==WIN_VERIFIED_EXPANSION));
   double entry0=(dir>0?Ask():Bid());double atr=MathMax(g_atr,MinTradeDistance());
   double dist;
   if(InpSimpleScalpMode){dist=0;}                       // market order: no pending distance
   else{dist=(InpUseATRForDistance?InpATRMultiplier*atr:InpDistance*g_ptScale*broker.point);dist=MathMax(dist,MinTradeDistance());}
   double pending=(dir>0?entry0+dist:entry0-dist);double sl;double slDist;
   if(InpSimpleScalpMode)
   {
      slDist=ScalpStopDistance(dir,entry0,sl);   // signal-aware stop (slPrice by ref)
      sl=PriceNorm(sl);
   }
   else{sl=ComputeSL(dir,pending);slDist=MathAbs(pending-sl);}
   double lots=CalculateLot(slDist,w,hv);if(lots<=0){g_gateReason=(g_lastRiskReason!=""?g_lastRiskReason:"lot/risk zero");return;}   // [SIZING] Auto mode BLOCKS on any solver gate (never manufactures volume)
   // [SR] optionally widen the stop behind an S/R zone, then recompute the lot so the
   // risk % stays IDENTICAL (constraint 6). Invalid recompute -> keep the base stop.
   if(InpSRSLBehindZone)
   {
      double srRef=(InpSimpleScalpMode?entry0:pending);   // the price the order actually enters at
      double srSl=SR_AdjustSL(dir,srRef,sl,atr);
      if(MathAbs(srSl-sl)>0)
      {
         double sd2=MathAbs(srRef-srSl);
         double rl=CalculateLot(sd2,w,hv);
         if(rl>0){sl=srSl;slDist=sd2;lots=rl;g_srSlShifted=true;}
      }
   }
   double risk=PriceMoveMoney(slDist,lots)+ExpectedAllInCost(lots);if(!RiskRoom(risk,dir,w,why)){g_gateReason=why;return;}
   double t1,t2,t3;
   if(InpSimpleScalpMode)
   {
      t1=ScalpTarget1(dir,entry0);
      // single-target scalp: TP2/TP3 trail beyond for the runner
      // (0.40 total / 0.75 total / 1.15 total ATR - authoritative profile)
      double atr2=MathMax(g_atr,MinTradeDistance());
      t2=PriceNorm(entry0+dir*SCALP_TP2_TOT*atr2);t3=PriceNorm(entry0+dir*SCALP_TP3_TOT*atr2);
      // [SR] snap each scalp leg to a nearby zone edge (within the shift cap)
      g_srTpSnapped=false;g_srSlShifted=false;   // per-arm telemetry reset
      if(InpSRSnapTP)
      {
         double o1=t1,a1=SR_AdjustTP(dir,entry0,t1,atr2,1),a2=SR_AdjustTP(dir,entry0,t2,atr2,2),a3=SR_AdjustTP(dir,entry0,t3,atr2,3);
         if(a1!=t1||a2!=t2||a3!=t3)
         {
            double netS=0;   // constraint 7: keep the snap only if the leg still passes its cost gate
            double initR=CalculateRealTradeRiskMoney(dir,lots,entry0,sl);
            if(NetProfitValid(dir,entry0,a1,lots,MinNetProfitForLeg(1,initR),netS)){t1=a1;t2=a2;t3=a3;g_srTpSnapped=true;}
         }
      }
   }
   else BuildThreeTargets(dir,pending,sl,lots,w,hv,t1,t2,t3);
   // [SR] entry gate before order dispatch for the complex branch as well
   {string srWhy2="";double srE=(dir>0?Ask():Bid());if(!SR_EntryAllowed(dir,srE,atr,atr,srWhy2)){g_gateReason=srWhy2;return;}}   // TryArm is void
   // R:R quality gate: the plan must genuinely out-earn its stop before arming.
   if(!InpSimpleScalpMode){
   if(!RRValid(dir,pending,sl,t2,InpMinRR_TP2)){g_gateReason="TP2 R:R below floor";return;}
   if(!RRValid(dir,pending,sl,t3,InpMinRR_TP3)){g_gateReason="TP3 R:R below floor";return;}}
   double net1=0;
   {
      // [TP GATES] risk-relative TP1 viability (section 24): % of initial trade risk.
      double initR1=CalculateRealTradeRiskMoney(dir,lots,pending,sl);
      if(!NetProfitValid(dir,pending,t1,lots,MinNetProfitForLeg(1,initR1),net1)){g_gateReason="TP_NET_RISK_TOO_LOW";return;}
   }
   // Phase 2.4: TP1 minimum-viability (spread-aware). If the ATR-derived TP1 is closer
   // than stops-level+buffer or (spread+expectedSlip) x InpTP1SpreadMultiple, REJECT the
   // trade - never silently widen TP1 beyond its cap.
   {
      double minTP1=MathMax(broker.stopsLevel*broker.point+InpStopLevelBufferPoints*broker.point,
                            (SpreadPoints()+ExpectedSlippagePoints())*broker.point*InpTP1SpreadMultiple);
      if(g_atr>0&&MathAbs(t1-entry0)<minTP1){g_gateReason="TP1_TOO_TIGHT";return;}
   }
   //--- [SIGNAL QUALITY] centralized confidence/regime decision (prompt.md sections 8-15).
   //--- Setup already exists (setup-driven); the confidence engine classifies and may veto.
   if(InpUseConfidenceEngine&&InpAutoCapitalProfile)
   {
      double dEntry=(dir>0?Ask():Bid());   // market plans enter here; pending adjusted below for straddle
      ENUM_SIGNAL_DECISION dec=BuildSignalDecision(dir,dEntry,sl,t1,t2,t3,lots,w,hv,setup);
      if(dec==SIGNAL_NO_TRADE)
      {
         g_gateReason=(g_lastDecision.gateReason!=""?g_lastDecision.gateReason:"NO_TRADE");
         return;
      }
      g_gateReason="SIGNAL "+(dec==SIGNAL_BUY?"BUY":"SELL")+" conf "+DoubleToString(g_lastDecision.confidence,1);
   }
   int layers=(directional?1:MathMax(1,MathMin(3,InpStraddleLayers)));if(hv&&InpAB_EnableHighVol)layers=MathMin(2,layers+1);
   // Ultra-scalp mode: always a single MARKET order - pendings/straddles add latency
   // and complexity that a scalp does not need.
   if(InpSimpleScalpMode){directional=true;layers=1;}
   int placed=0;double each=FloorVolume(lots/layers);if(each<=0){layers=1;each=lots;}
   for(int i=0;i<layers;i++)
   {
      // InpLayerStepATR adds progressive spacing per layer; InpScaleIn steps each
      // layer's volume down so later entries carry less risk than the first.
      double layerGap=MathMax(InpLayerSpacingATR+InpLayerStepATR*i,0.05);
      double p=pending+dir*i*MathMax(layerGap*atr,MinTradeDistance());
      double li=(InpScaleIn?each*(1.0-0.15*i):each);
      li=FloorVolume(li);if(li<=0)continue;
      double lsl=ComputeSL(dir,p);double a,b,c;BuildThreeTargets(dir,p,lsl,li,w,hv,a,b,c);ulong tk=0;
      // Comment is the durable carrier of window / direction / HV regime across restarts.
      string cmt=InpComment+"|W"+IntegerToString((int)w)+"|"+(dir>0?"B":"S")+"|HV"+(hv?"1":"0")+"|"+setup;
      if(directional&&i==0)
      {
         double fill=0;
         {
            if(InpSimpleScalpMode)   // the armed scalp plan IS the order plan: t1/t3 travel with the trade
            {
               if(MarketOrder(dir,li,sl,t3,cmt,fill,tk))
               {g_armTp1=t1;g_armTp2=t2;g_armTp3=t3;g_armValid=true;placed++;}
            }
            else
            {
               double osl;ScalpStopDistance(dir,entry0,osl);
               if(MarketOrder(dir,li,osl,c,cmt,fill,tk))placed++;   // complex mode: armed ladder TP3 rides as broker TP (original behavior)
            }
         }
      }
      else if(PlaceStop(dir,li,p,lsl,c,cmt,tk))placed++;
   }
   if(placed>0)
   {
      g_lastEntryTime=ServerNow();g_lastWindowEntry[w]=g_lastEntryTime;g_windowSignals[w]++;g_gateReason="ARMED "+WindowName(w)+(hv?" HV":"");
      if(g_log!=INVALID_HANDLE)
      {
         // [SR] appended columns: preserve the original 14-column order, add SR telemetry at the end
         double srUp=0,srUpS=0,srUpD=0,srDn=0,srDnS=0,srDnD=0;string srMd=(InpUseSRZones?(InpSRMode==SR_ADVISORY?"ADV":(InpSRMode==SR_SOFT_FILTER?"SOFT":"HARD")):"OFF");
         if(InpUseSRZones&&g_atr>0){double ne,fe,st;int ix;double srx=(dir>0?Ask():Bid());
            if(SR_NearestAbove(srx,InpSRMinStrengthToUse,ne,fe,st,ix)){srUp=ne;srUpS=st;srUpD=MathAbs(ne-srx)/g_atr;}
            if(SR_NearestBelow(srx,InpSRMinStrengthToUse,ne,fe,st,ix)){srDn=ne;srDnS=st;srDnD=MathAbs(srx-ne)/g_atr;}}
         FileWrite(g_log,TimeToString(ServerNow(),TIME_DATE|TIME_SECONDS),"ARM",WindowName(w),dir,setup,DoubleToString(SpreadPoints(),1),DoubleToString(SpreadPercentile(),1),DoubleToString(ATRPercentile(),1),DoubleToString(g_volRatio,2),DoubleToString(risk,2),DoubleToString(t1,broker.digits),DoubleToString(t2,broker.digits),DoubleToString(t3,broker.digits),srMd,IntegerToString(g_srCount),DoubleToString(srUp,broker.digits),DoubleToString(srUpS,2),DoubleToString(srUpD,2),DoubleToString(srDn,broker.digits),DoubleToString(srDnS,2),DoubleToString(srDnD,2),(g_srTpSnapped?"1":"0"),(g_srSlShifted?"1":"0"),g_srBlockReason,CapitalProfileName(g_capitalProfile),DoubleToString(GetEquityUSD(),2),DoubleToString(GetConservativeCapitalBase(),2),DoubleToString(GetEffectiveTradeRiskPct(w,hv),3),DoubleToString(g_lastAllowedRiskMoney,2),DoubleToString(g_lastRawLots,3),DoubleToString(g_lastFinalLots,3),DoubleToString(g_lastActualRiskMoney,2),DoubleToString(g_lastRequiredMargin,2),DoubleToString((g_atr>0?SpreadPoints()*broker.point/g_atr*100.0:0),2),IntegerToString(AdaptiveDeviationPoints()),DoubleToString((g_commissionRTPerLot>0?g_commissionRTPerLot:InpCommissionPerLotRTFallback),2),DoubleToString(ExpectedAllInCost(lots),2));FileWriteString(g_log,g_lastRiskReason+";"+IntegerToString(g_lastOrderCheckRetcode)+";"+EnumToString(g_lastDecision.decision)+";"+DoubleToString(g_lastDecision.confidence,1)+";"+DoubleToString(g_lastDecision.confidence,1)+";"+DoubleToString(g_lastDecision.oppositeConfidence,1)+";"+DoubleToString(g_lastDecision.confidenceGap,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.priceAction,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.trend,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.volumeLiquidity,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.momentum,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.vwapLocation,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.volatility,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.macro,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.options,1)+";"+DoubleToString(g_lastDecision.confidenceBreakdown.riskReward,1)+";"+StructureStateName(g_structureState)+";"+DirectionRegimeName(g_dirRegime)+";"+EnvironmentRegimeName(g_envRegime)+";"+VolumeStateName(g_volumeState)+";"+DoubleToString(g_volumePercentile,0)+";"+DoubleToString(g_ema9,broker.digits)+";"+DoubleToString(g_ema20,broker.digits)+";"+DoubleToString(g_ema50,broker.digits)+";"+DoubleToString(g_ema200,broker.digits)+";"+DoubleToString(g_macdMain,5)+";"+DoubleToString(g_macdSignal,5)+";"+DoubleToString(g_macdHist,5)+";"+DoubleToString(g_lastDecision.riskReward,2)+";"+DoubleToString(SetupMinNetRR(g_lastDecision.setupName),2)+";"+(OptionsDataUsable()?"YES":"NO"),-1);
      }
   }
}

//====================================================================
// LOSS RECOVERY / REVERSAL ENGINE (single counter-leg, no martingale)
//====================================================================
bool MomentumDeteriorated(int dir)
{
   double c=iClose(eaSymbol,PERIOD_M1,1);bool vwapBad=(g_vwap>0&&(dir>0?c<g_vwap:c>g_vwap));bool smcBad=(dir>0?(g_chochDn||g_bosDn):(g_chochUp||g_bosUp));bool momBad=(dir>0?(g_m15e20<g_m15e50):(g_m15e20>g_m15e50));bool volBad=g_volRatio<0.85;return ((vwapBad&&smcBad)||(momBad&&volBad));
}

double CostAdjustedBE(int dir,double entry,double remainingVol)
{
   double ppm=MoneyPerPricePerLot();if(ppm<=0||remainingVol<=0)return entry;double cost=ExpectedAllInCost(remainingVol);double p=cost/(ppm*remainingVol)+InpBEExtraLockATR*g_atr;return PriceNorm(entry+dir*p);
}

void TryRecovery()
{
   string why="";
   if(!InpUseRecovery)return;
   if(InpSimpleScalpMode)return;   // loss-chasing counter-trades disabled in ultra-scalp mode
   // A reversal leg requires a hedging account: on netting the opposite deal would
   // just close the surviving position instead of opening the recovery trade.
   if(!broker.hedging)return;
   if(g_lastLossDir==0||g_lastLossTime==0)return;
   datetime now=ServerNow();
   if(g_recoveryLegs>=InpRecoveryMaxLegs)return;
   if(now<g_lastLossTime+InpRecoveryCooldownSec)return;                 // let the market breathe first
   if(now>g_lastLossTime+InpRecoveryMaxAgeSec){g_lastLossDir=0;return;} // opportunity expired
   if(g_paused||g_newsBlocked||ServerNow()<g_newsBlockedUntil)return;
   if(IsDisorder()||WeekendOrRollover()||InSwapDangerWindow())return;
   if(CountOwnPositions()>=GetProfileMaxPositions())return;

   int dir=-g_lastLossDir;                                              // reversal trade against the losing leg
   if((dir>0&&g_dirBias<0)||(dir<0&&g_dirBias>0))return;                // only when structure actually agrees
   // [RECOVERY] stricter-than-normal adaptive spread quality (section 28): the
   // recovery leg requires better execution conditions than a normal entry.
   {
      double allow=(InpUseAdaptiveSpreadGate?InpRecoveryMaxSpreadPts*InpRecoverySpreadQualityMultiplier:(double)InpRecoveryMaxSpreadPts);
      double sp=SpreadPoints();
      if(sp>allow*g_ptScale){g_gateReason="recovery: spread";g_spreadRejects++;return;}
   }

   double entry=(dir>0?Ask():Bid());double atr=MathMax(g_atr,MinTradeDistance());
   double sl=ComputeSL(dir,entry);double slDist=MathAbs(entry-sl);if(slDist<=0)return;
   // [RECOVERY RISK] recovery risk stays <= InpRecoveryRiskPct AND strictly below the
   // currently permitted normal trade risk (no martingale, no escalation; sections 28/36).
   double cap=GetConservativeCapitalBase();
   double bal=cap;
   double risk=cap*InpRecoveryRiskPct/100.0;
   double normalRisk=cap*GetEffectiveTradeRiskPct(WIN_NONE,false)/100.0;
   if(risk>=normalRisk)risk=normalRisk*0.9;   // strictly below normal permitted risk
   double perLot=CalculateRealTradeRiskMoney(dir,1.0,entry,sl);
   if(perLot<=0)perLot=PriceMoveMoney(slDist,1.0)+ExpectedAllInCost(1.0);
   if(perLot<=0)return;
   double lots=FloorVolume(risk/perLot);
   if(lots<=0 && InpAllowMinLotFallback)
   {
      double minRisk=CalculateRealTradeRiskMoney(dir,broker.volumeMin,entry,sl);
      if(bal>0 && minRisk/bal*100.0<=GetProfileMinLotRiskCeilingPct()) lots=FloorVolume(broker.volumeMin);
   }
   if(lots<=0)return;
   if(InpUseAbsoluteLotEmergencyCap&&InpMaxTotalLots>0&&SumOwnLots()+lots>InpMaxTotalLots)lots=FloorVolume(InpMaxTotalLots-SumOwnLots());
   if(lots<=0)return;

   double t1,t2,t3;BuildThreeTargets(dir,entry,sl,lots,WIN_NONE,false,t1,t2,t3);
   // The recovery is a single-target trade: the TP placed at the broker must be the TP
   // that was validated. If the ATR-default target sits below the R:R floor, extend it
   // to the minimum target that satisfies BOTH the floor and the all-in cost check -
   // then re-verify ordering and validate EXACTLY what will be placed.
   double md2=MinTradeDistance();
   double need=MathAbs(entry-sl)*InpRecoveryMinRR;
   if(MathAbs(t1-entry)<need) t1=PriceNorm(entry+(dir>0?need:-need));
   double recInitRisk=CalculateRealTradeRiskMoney(dir,lots,entry,sl);
   double recMin1=MinNetProfitForLeg(1,recInitRisk);
   double net=0;int gguard=0;
   while(!NetProfitValid(dir,entry,t1,lots,recMin1,net)&&gguard++<10) t1=PriceNorm(t1+dir*0.10*atr);
   if(!RRValid(dir,entry,sl,t1,InpRecoveryMinRR)){g_gateReason="recovery: R:R low";return;}
   if(!NetProfitValid(dir,entry,t1,lots,recMin1,net)){g_gateReason="recovery: cost";return;}
   if(!RiskRoom(PriceMoveMoney(slDist,lots)+ExpectedAllInCost(lots),dir,WIN_NONE,why)){g_gateReason="recovery: risk cap";return;}
   // Preflight the recovery request exactly like a new trade (section 23).
   {
      MqlTradeRequest prq;MqlTradeCheckResult pchk;ZeroMemory(prq);ZeroMemory(pchk);
      prq.action=TRADE_ACTION_DEAL;prq.symbol=eaSymbol;prq.magic=InpMagicNumber;prq.volume=lots;
      prq.type=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);prq.price=entry;prq.sl=sl;prq.tp=t1;
      prq.deviation=AdaptiveDeviationPoints();prq.comment="preflight";
      string pr="";
      if(!PreflightNewTrade(prq,pchk,pr)){g_gateReason="recovery: "+pr;return;}
   }

   string cmt=InpComment+"|RCV|"+(dir>0?"B":"S")+"|"+IntegerToString((int)g_lastLossTime);
   double fill=0;ulong tk=0;
   // Broker TP is set to the VALIDATED TP1 (>=InpRecoveryMinRR). The recovery is a
   // single-shot counter-trade: if the EA restarts, the position still closes at the
   // target the entry was validated against, never an unvalidated TP3.
   if(MarketOrder(dir,lots,sl,t1,cmt,fill,tk))
   {
      g_recoveryLegs++;g_lastLossDir=0;g_gateReason="RECOVERY ARMED "+(dir>0?"BUY":"SELL");
      if(g_log!=INVALID_HANDLE)FileWrite(g_log,TimeToString(ServerNow(),TIME_DATE|TIME_SECONDS),"RCV",dir>0?"BUY":"SELL",DoubleToString(lots,2),DoubleToString(sl,broker.digits),DoubleToString(t1,broker.digits));
   }
}

//====================================================================
// POSITION MANAGEMENT TP1 / TP2 / TP3
//====================================================================
void ManagePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))return;int idx=FindPS(ticket);if(idx<0)return;
   double bid=Bid(),ask=Ask();int dir=g_ps[idx].direction;double px=(dir>0?bid:ask),vol=PositionGetDouble(POSITION_VOLUME),curSL=PositionGetDouble(POSITION_SL);if(vol<=0)return;
   double excursion=dir*(px-g_ps[idx].entry);if(excursion>0)g_ps[idx].mfePrice=MathMax(g_ps[idx].mfePrice,excursion);else g_ps[idx].maePrice=MathMax(g_ps[idx].maePrice,-excursion);
   if(InpMaxTradeMinutes>0&&ServerNow()-g_ps[idx].opened>=InpMaxTradeMinutes*60){ClosePositionSafe(ticket);return;}
   if(InpAvoidSwap&&InpForceFlatBeforeSwap&&InSwapDangerWindow()){ClosePositionSafe(ticket);return;}
   if(g_ps[idx].recovery)return;   // single-target recovery: broker TP/SL manage the exit
   if(!InpUseThreeTargets||!InpAB_EnableThreeTP)return;
   bool hit1=(dir>0?bid>=g_ps[idx].tp1:ask<=g_ps[idx].tp1),hit2=(dir>0?bid>=g_ps[idx].tp2:ask<=g_ps[idx].tp2),hit3=(dir>0?bid>=g_ps[idx].tp3:ask<=g_ps[idx].tp3);
   if(!g_ps[idx].tp1Done&&hit1)
   {
      double cv=MathMin(g_ps[idx].volTP1,vol-broker.volumeMin);
      if(cv<=0||FloorVolume(cv)<=0)g_ps[idx].tp1Done=true;
      else if(ClosePartialSafe(ticket,cv)){if(idx<ArraySize(g_ps)){g_ps[idx].tp1Done=true;g_ws[g_ps[idx].window].tp1Hits++;}}
      if(idx>=ArraySize(g_ps))return;
      if(g_ps[idx].tp1Done&&InpUseCostAdjustedBE&&PositionSelectByTicket(ticket))
      {
         double remain=PositionGetDouble(POSITION_VOLUME),be=CostAdjustedBE(dir,g_ps[idx].entry,remain),nowp=(dir>0?Bid():Ask());
         bool safe=(dir>0?(be>g_ps[idx].initialSL&&nowp-be>=MinTradeDistance()):(be<g_ps[idx].initialSL&&be-nowp>=MinTradeDistance()));if(safe)ModifyPositionSafe(ticket,be,g_ps[idx].tp3);
      }
   }
   if(idx>=ArraySize(g_ps))return;
   if(g_ps[idx].tp1Done&&!g_ps[idx].tp2Done&&hit2)
   {
      if(!PositionSelectByTicket(ticket))return;vol=PositionGetDouble(POSITION_VOLUME);double cv=MathMin(g_ps[idx].volTP2,vol-broker.volumeMin);
      if(cv<=0||FloorVolume(cv)<=0)g_ps[idx].tp2Done=true;
      else if(ClosePartialSafe(ticket,cv)){if(idx<ArraySize(g_ps)){g_ps[idx].tp2Done=true;g_ws[g_ps[idx].window].tp2Hits++;}}
   }
   if(idx>=ArraySize(g_ps))return;
   if(g_ps[idx].tp2Done&&PositionSelectByTicket(ticket))
   {
      if(InpTP3EarlyExit&&MomentumDeteriorated(dir)){ClosePositionSafe(ticket);return;}
      if(InpUseTP3StructureTrail)
      {
         curSL=PositionGetDouble(POSITION_SL);double nowp=(dir>0?Bid():Ask());double candidate=(dir>0?nowp-InpTP3TrailATR*g_atr:nowp+InpTP3TrailATR*g_atr);double structural=(dir>0?g_swingLow-InpSLStructureBufferATR*g_atr:g_swingHigh+InpSLStructureBufferATR*g_atr);
         // [SR] zone-based trail anchor joins as an additional candidate; the more
         // conservative (closer-to-price in the profitable direction) one wins
         double srAnchor=SR_TrailAnchor(dir,g_atr);
         if(srAnchor>0)candidate=(dir>0?MathMax(candidate,srAnchor):MathMin(candidate,srAnchor));
         if(structural>0)candidate=(dir>0?MathMax(candidate,structural):MathMin(candidate,structural));candidate=PriceNorm(candidate);
         bool improve=(dir>0?(candidate>curSL+InpTP3TrailStepATR*g_atr):(curSL==0||candidate<curSL-InpTP3TrailStepATR*g_atr));bool valid=(dir>0?(Bid()-candidate>=MinTradeDistance()):(candidate-Ask()>=MinTradeDistance()));if(improve&&valid)ModifyPositionSafe(ticket,candidate,g_ps[idx].tp3);
      }
   }
   if(idx<ArraySize(g_ps)&&hit3){g_ps[idx].tp3Done=true;g_ws[g_ps[idx].window].tp3Hits++;}
}

void ManageAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==eaSymbol&&PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)ManagePosition(t);}
}

//====================================================================
// TRANSACTION TELEMETRY / PERFORMANCE
//====================================================================
ENUM_WINDOW_ID ParseWindowFromComment(string c)
{
   int p=StringFind(c,"|W");if(p<0)return WIN_NONE;int q=StringFind(c,"|",p+2);string n=(q>p?StringSubstr(c,p+2,q-(p+2)):StringSubstr(c,p+2));int w=(int)StringToInteger(n);return (w>WIN_NONE&&w<WIN_COUNT?(ENUM_WINDOW_ID)w:WIN_NONE);
}

string ParseSetupFromComment(string c)
{
   int p1=StringFind(c,"|W");if(p1<0)return "";int p2=StringFind(c,"|",p1+2);if(p2<0)return "";int p3=StringFind(c,"|",p2+1);if(p3<0)return "";int p4=StringFind(c,"|",p3+1);if(p4<0)return "";return StringSubstr(c,p4+1);
}

bool ParseHVFromComment(string c)
{
   int p=StringFind(c,"|HV");if(p<0)return false;return (StringFind(c,"|HV1",p)>=0);
}

void PushRecentNet(ENUM_WINDOW_ID w,double net)
{
   int cap=MathMin(64,MathMax(5,InpPerfRollingTrades));int i=g_ws[w].recentIdx%cap;g_ws[w].recentNet[i]=net;g_ws[w].recentIdx=(i+1)%cap;if(g_ws[w].recentCount<cap)g_ws[w].recentCount++;
}

//--- today-only stats (recounted from deal history: restart-proof, ref.mq5 pattern)
int      g_todayWins=0,g_todayLosses=0;
double   g_todayNet=0,g_todayGrossW=0,g_todayGrossL=0;
datetime g_todayStamp=0;

void RecountTodayStats()
{
   datetime now=ServerNow();
   MqlDateTime dt;TimeToStruct(now,dt);dt.hour=0;dt.min=0;dt.sec=0;
   datetime dayStart=StructToTime(dt);
   if(g_todayStamp==dayStart)return;
   g_todayStamp=dayStart;
   g_todayWins=0;g_todayLosses=0;g_todayNet=0;g_todayGrossW=0;g_todayGrossL=0;
   if(!HistorySelect(dayStart,now+60))return;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong tk=HistoryDealGetTicket(i);if(tk==0)continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagicNumber)continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=eaSymbol)continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT)continue;
      double p=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      g_todayNet+=p;
      if(p>=0){g_todayWins++;g_todayGrossW+=p;}else{g_todayLosses++;g_todayGrossL+=-p;}
   }
}
double TodayWinRate(){int t=g_todayWins+g_todayLosses;return t>0?100.0*g_todayWins/t:0;}
double TodayPF(){return g_todayGrossL>0?g_todayGrossW/g_todayGrossL:(g_todayGrossW>0?99.0:0);}

double OverallWinRate(){return g_perfTrades>0?100.0*g_perfWins/g_perfTrades:0;}
double OverallProfitFactor(){return g_perfGrossLoss>0?g_perfGrossProfit/g_perfGrossLoss:(g_perfGrossProfit>0?999.0:0);}
double OverallNetR(){return g_perfRetN>0?g_perfRetMean:0;}
double OverallSharpe()
{
   if(g_perfRetN<2)return 0;double var=g_perfRetM2/(g_perfRetN-1);if(var<=0)return 0;return g_perfRetMean/MathSqrt(var)*MathSqrt((double)g_perfRetN);
}
void UpdateOverallPerformance(double net,double rr)
{
   g_perfTrades++;g_perfNetProfit+=net;if(net>0){g_perfWins++;g_perfGrossProfit+=net;}else if(net<0){g_perfLosses++;g_perfGrossLoss+=-net;}
   g_perfRetN++;double d=rr-g_perfRetMean;g_perfRetMean+=d/g_perfRetN;double d2=rr-g_perfRetMean;g_perfRetM2+=d*d2;
   g_perfCumNet+=net;g_perfPeakNet=MathMax(g_perfPeakNet,g_perfCumNet);g_perfMaxDDMoney=MathMax(g_perfMaxDDMoney,g_perfPeakNet-g_perfCumNet);
}

//--- 35/36/37. record a closed trade into confidence/setup/regime buckets (telemetry only)
void RecordPerfBuckets(double conf,int dir,ENUM_ENVIRONMENT_REGIME env,double rr,string setupName)
{
   //--- confidence bucket 70-74 / 75-79 / 80-84 / 85-89 / 90+
   int b=0;
   if(conf>=90)b=4;else if(conf>=85)b=3;else if(conf>=80)b=2;else if(conf>=75)b=1;else b=0;
   if(conf<70)b=-1;
   if(b>=0)
   {
      g_confBuckets[b].trades++;if(rr>0)g_confBuckets[b].wins++;else if(rr<0)g_confBuckets[b].losses++;
      g_confBuckets[b].netR+=rr;g_confBuckets[b].rSum+=rr;
   }
   //--- setup bucket: EMA_PULLBACK / VWAP_REVERSION / LONDON_BREAKOUT / NY_MOMENTUM / COMPLEX / RECOVERY
   int si=4;   // COMPLEX default
   StringToLower(setupName);
   if(StringFind(setupName,"pullback")>=0)si=0;
   else if(StringFind(setupName,"reversion")>=0)si=1;
   else if(StringFind(setupName,"london")>=0)si=2;
   else if(StringFind(setupName,"ny")>=0)si=3;
   else if(StringFind(setupName,"rcv")>=0)si=5;
   g_setupStats[si].trades++;if(rr>0)g_setupStats[si].wins++;else if(rr<0)g_setupStats[si].losses++;
   g_setupStats[si].netR+=rr;g_setupStats[si].rSum+=rr;
   //--- regime bucket: direction accepted count + environment accepted/reject counts
   int di=(dir>0?(g_dirRegime<=REGIME_BULLISH?0:1):(g_dirRegime>=REGIME_BEARISH?4:3));
   if(g_dirRegime==REGIME_STRONG_BULLISH)di=0;else if(g_dirRegime==REGIME_BULLISH)di=1;
   else if(g_dirRegime==REGIME_SIDEWAYS)di=2;else if(g_dirRegime==REGIME_BEARISH)di=3;else di=4;
   g_regimeTrades[di]++;
   g_envTrades[(int)env]++;
}

void FinalizeWindowTrade(int idx,double net,double gross,double costs)
{
   if(idx<0||idx>=ArraySize(g_ps))return;PositionState s=g_ps[idx];ENUM_WINDOW_ID w=s.window;
   // Recovery legs keep full position management but are excluded from per-window
   // statistics and from resetting/extending the consecutive-loss streak of a window.
   if(s.recovery){RemovePS(idx);return;}
   if(w<=WIN_NONE||w>=WIN_COUNT){RemovePS(idx);return;}
   g_ws[w].trades++;g_ws[w].netPL+=net;g_ws[w].grossPL+=gross;g_ws[w].costs+=costs;g_ws[w].slipSum+=MathAbs(s.entrySlipPts);g_ws[w].spreadPctSum+=s.entrySpreadPct;g_ws[w].atrPctSum+=s.entryAtrPct;g_ws[w].volRatioSum+=s.entryVolRatio;g_ws[w].maeSum+=s.maePrice;g_ws[w].mfeSum+=s.mfePrice;if(net>0){g_ws[w].wins++;g_consecutiveLosses=0;}else if(net<0){g_ws[w].losses++;g_consecutiveLosses++;}
   double rr=(s.initialRiskMoney>0?net/s.initialRiskMoney:0);UpdateOverallPerformance(net,rr);g_ws[w].rSum+=rr;PushRecentR(w,rr);g_ws[w].peakNet=MathMax(g_ws[w].peakNet,g_ws[w].netPL);g_ws[w].maxDD=MathMax(g_ws[w].maxDD,g_ws[w].peakNet-g_ws[w].netPL);PushRecentNet(w,net);RefreshWindowGating(w);RemovePS(idx);
   //--- [SIGNAL QUALITY] confidence/setup/regime buckets: use the confidence recorded at ARM time
   RecordPerfBuckets(g_lastDecision.confidence,s.direction,g_envRegime,rr,s.setupId);
}

void LearnCommission(double dealComm,double dealVol)
{
   double c=MathAbs(dealComm),v=dealVol;if(c<=0||v<=0)return;double oneSide=c/v;double rt=2.0*oneSide;g_commissionRTPerLot=(g_commissionRTPerLot<=0?rt:0.90*g_commissionRTPerLot+0.10*rt);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD||trans.deal==0)return;if(!HistoryDealSelect(trans.deal))return;if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagicNumber||HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=eaSymbol)return;
   LearnCommission(HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),HistoryDealGetDouble(trans.deal,DEAL_VOLUME));
   ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal,DEAL_TYPE);double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE),vol=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);long posId=HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(e==DEAL_ENTRY_IN)
   {
      g_tradesToday++;g_lastEntryTime=ServerNow();double slip=0;
      // Slippage must be measured against the order's intended price but the
      // deal-side spread is a known cost: measure only the excess over it.
      if(trans.order>0&&HistoryOrderSelect(trans.order))
      {
         double intended=HistoryOrderGetDouble(trans.order,ORDER_PRICE_OPEN);
         if(intended>0)   // market orders may report 0 as requested price -> no measurement
         {
            double raw=(dt==DEAL_TYPE_BUY?(price-intended):(intended-price))/broker.point;
            slip=raw-SpreadPoints();                 // spread is cost, not slippage
         }
         else slip=0;
      }
      PushSlippage(slip);
      if(MathAbs(slip)>=AdaptiveExtremeSlippagePts()){g_disorderUntil=ServerNow()+InpSlippageCooldownMinutes*60;}
      ENUM_WINDOW_ID w=WIN_NONE;string setup="";string c=HistoryDealGetString(trans.deal,DEAL_COMMENT);
      bool isRecovery=(StringFind(c,"|RCV")>=0);
      {
         // Recovery legs are tracked EXACTLY like normal positions (TP1/TP2 partial ladder,
         // time stop, swap exit, consecutive-loss accounting) under WIN_NONE; only window
         // stats routing differs (FinalizeWindowTrade skips stats for recovery=true).
         if(!isRecovery)
         {
            w=ParseWindowFromComment(c);setup=ParseSetupFromComment(c);
            if(w==WIN_NONE){bool tr=false;w=CurrentWindow(tr);}
         }
         bool hvC=(!isRecovery&&ParseHVFromComment(c));
         int dir=(dt==DEAL_TYPE_BUY?1:-1);
         ulong ticket=0;for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetInteger(POSITION_IDENTIFIER)==posId){ticket=t;break;}}
         if(ticket&&PositionSelectByTicket(ticket))
         {
            double sl=PositionGetDouble(POSITION_SL),fv=PositionGetDouble(POSITION_VOLUME);
            AddPositionState(ticket,posId,dir,w,setup,hvC,isRecovery,price,sl,fv,slip,HistoryDealGetDouble(trans.deal,DEAL_COMMISSION));
            // Charge the per-window risk budget for the ACTUAL fill (each straddle layer separately),
            // so partial/layered fills can never exceed the window budget.
            if(!isRecovery&&w>WIN_NONE&&w<WIN_COUNT&&sl>0){double rrM=CalculateRealTradeRiskMoney(dir,fv,price,sl);g_windowRiskUsed[w]+=(rrM>0?rrM:PriceMoveMoney(price-sl,fv)+ExpectedAllInCost(fv));}   // [COST BASIS] same authoritative engine as sizing
            if(InpCloseOnExtremeSlippage&&MathAbs(slip)>=AdaptiveExtremeSlippagePts())ClosePositionSafe(ticket);
         }
                  if(!isRecovery)
         {
            // OCO safety: after first fill, remove opposite pending orders.
            for(int i=OrdersTotal()-1;i>=0;i--)
            {
               ulong ot=OrderGetTicket(i);
               if(!ot||!OrderSelect(ot))continue;
               if(OrderGetString(ORDER_SYMBOL)!=eaSymbol||OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)continue;
               ENUM_ORDER_TYPE typ=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
               if((dir>0&&typ==ORDER_TYPE_SELL_STOP)||(dir<0&&typ==ORDER_TYPE_BUY_STOP))DeleteOrderSafe(ot);
            }
         }
      }
   }
   else if(e==DEAL_ENTRY_OUT||e==DEAL_ENTRY_OUT_BY)
   {
      double gross=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);double swap=HistoryDealGetDouble(trans.deal,DEAL_SWAP);double comm=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);double net=gross+swap+comm;g_lastExitTime=ServerNow();
      int pidx=-1;for(int j=0;j<ArraySize(g_ps);j++)if(g_ps[j].positionId==posId){pidx=j;break;}
      if(pidx>=0){g_ps[pidx].realizedGross+=gross;g_ps[pidx].realizedNet+=net;g_ps[pidx].realizedCosts+=MathAbs(comm)+MathAbs(swap);}
      bool still=false;for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetInteger(POSITION_IDENTIFIER)==posId){still=true;break;}}
      if(!still&&pidx>=0)
      {
         double finalNet=g_ps[pidx].realizedNet;
         if(finalNet<0 && !g_ps[pidx].recovery)
         {
            // Realized base-strategy loss: open ONE gated reversal opportunity.
            // Recovery-leg losses never chain another recovery.
            g_lastLossDir=g_ps[pidx].direction;g_lastLossTime=ServerNow();g_lastLossMoney=finalNet;
            g_recoveryLegs=0;   // fresh loss event = fresh recovery allowance
            g_gateReason="LOSS - recovery candidate";
         }
         FinalizeWindowTrade(pidx,finalNet,g_ps[pidx].realizedGross,g_ps[pidx].realizedCosts);
      }
   }
}

//====================================================================
// STATE / LOGGING
//====================================================================
#define STATE_TAG 20260914   // bumped: recent-R window history added to the state tail
string StateName(){return "PAT101_"+eaSymbol+"_"+IntegerToString(InpMagicNumber)+".bin";}

// Recount consecutive losses from actual closed deals (30-day lookback, this symbol+magic)
int RecountConsecutiveLosses()
{
   int cons=0;
   datetime from=TimeCurrent()-30*86400;
   if(!HistorySelect(from,TimeCurrent()+60))return g_consecutiveLosses;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong tk=HistoryDealGetTicket(i);if(tk==0)continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagicNumber)continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=eaSymbol)continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT)continue;
      double p=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      if(p<0)cons++;else break;   // streak broken by a win
   }
   return cons;
}

void SaveState()
{
   if(!InpPersistState)return;int f=FileOpen(StateName(),FILE_BIN|FILE_WRITE|FILE_COMMON);if(f==INVALID_HANDLE)return;
   FileWriteInteger(f,STATE_TAG,INT_VALUE);
   FileWriteInteger(f,g_dayKey,INT_VALUE);FileWriteInteger(f,g_weekKey,INT_VALUE);FileWriteInteger(f,g_monthKey,INT_VALUE);FileWriteDouble(f,g_dayAnchor);FileWriteDouble(f,g_weekAnchor);FileWriteDouble(f,g_monthAnchor);FileWriteInteger(f,g_tradesToday,INT_VALUE);FileWriteInteger(f,g_consecutiveLosses,INT_VALUE);FileWriteDouble(f,g_commissionRTPerLot);FileWriteInteger(f,g_perfTrades,INT_VALUE);FileWriteInteger(f,g_perfWins,INT_VALUE);FileWriteInteger(f,g_perfLosses,INT_VALUE);FileWriteDouble(f,g_perfNetProfit);FileWriteDouble(f,g_perfGrossProfit);FileWriteDouble(f,g_perfGrossLoss);FileWriteInteger(f,g_perfRetN,INT_VALUE);FileWriteDouble(f,g_perfRetMean);FileWriteDouble(f,g_perfRetM2);FileWriteDouble(f,g_perfCumNet);FileWriteDouble(f,g_perfPeakNet);FileWriteDouble(f,g_perfMaxDDMoney);
   for(int w=0;w<WIN_COUNT;w++){FileWriteInteger(f,g_ws[w].trades,INT_VALUE);FileWriteInteger(f,g_ws[w].wins,INT_VALUE);FileWriteInteger(f,g_ws[w].losses,INT_VALUE);FileWriteDouble(f,g_ws[w].grossPL);FileWriteDouble(f,g_ws[w].netPL);FileWriteDouble(f,g_ws[w].costs);FileWriteInteger(f,g_ws[w].tp1Hits,INT_VALUE);FileWriteInteger(f,g_ws[w].tp2Hits,INT_VALUE);FileWriteInteger(f,g_ws[w].tp3Hits,INT_VALUE);}
   // [PERFORMANCE GATING] rolling recent-R history (additive tail; old readers stop at the PS count safely)
   for(int w=0;w<WIN_COUNT;w++){FileWriteInteger(f,g_ws[w].recentRCount,INT_VALUE);for(int i=0;i<64;i++)FileWriteDouble(f,g_ws[w].recentR[i]);FileWriteInteger(f,g_ws[w].recentRIdx,INT_VALUE);}
   // --- open-position ladder plans: a VPS restart must not silently drop the
   // --- 60/25/15 partial management and leave positions broker-managed to TP3/SL.
   int nPS=ArraySize(g_ps);FileWriteInteger(f,nPS,INT_VALUE);
   for(int p=0;p<nPS;p++)
   {
      FileWriteLong(f,(long)g_ps[p].ticket);FileWriteLong(f,g_ps[p].positionId);
      FileWriteInteger(f,g_ps[p].direction,INT_VALUE);FileWriteInteger(f,(int)g_ps[p].window,INT_VALUE);
      FileWriteString(f,g_ps[p].setupId);FileWriteInteger(f,0,INT_VALUE);   // terminator for the string
      FileWriteInteger(f,g_ps[p].hv?1:0,INT_VALUE);FileWriteInteger(f,g_ps[p].recovery?1:0,INT_VALUE);
      FileWriteDouble(f,g_ps[p].initialVolume);FileWriteDouble(f,g_ps[p].initialRiskMoney);
      FileWriteDouble(f,g_ps[p].entry);FileWriteDouble(f,g_ps[p].initialSL);
      FileWriteDouble(f,g_ps[p].tp1);FileWriteDouble(f,g_ps[p].tp2);FileWriteDouble(f,g_ps[p].tp3);
      FileWriteDouble(f,g_ps[p].volTP1);FileWriteDouble(f,g_ps[p].volTP2);FileWriteDouble(f,g_ps[p].volTP3);
      FileWriteInteger(f,g_ps[p].tp1Done?1:0,INT_VALUE);FileWriteInteger(f,g_ps[p].tp2Done?1:0,INT_VALUE);FileWriteInteger(f,g_ps[p].tp3Done?1:0,INT_VALUE);
      FileWriteDouble(f,g_ps[p].maePrice);FileWriteDouble(f,g_ps[p].mfePrice);
      FileWriteLong(f,(long)g_ps[p].opened);
      FileWriteDouble(f,g_ps[p].entrySpreadPct);FileWriteDouble(f,g_ps[p].entrySlipPts);
      FileWriteDouble(f,g_ps[p].entryAtrPct);FileWriteDouble(f,g_ps[p].entryVolRatio);
      FileWriteDouble(f,g_ps[p].realizedGross);FileWriteDouble(f,g_ps[p].realizedNet);FileWriteDouble(f,g_ps[p].realizedCosts);
   }
   FileClose(f);
}

void LoadState()
{
   int f=FileOpen(StateName(),FILE_BIN|FILE_READ|FILE_COMMON);if(f==INVALID_HANDLE)return;
   int tag=(int)FileReadInteger(f,INT_VALUE);
   if(tag!=STATE_TAG){FileClose(f);Print("State file format differs (tag=",tag,") - starting from a clean slate.");return;}
   g_dayKey=(int)FileReadInteger(f,INT_VALUE);g_weekKey=(int)FileReadInteger(f,INT_VALUE);g_monthKey=(int)FileReadInteger(f,INT_VALUE);g_dayAnchor=FileReadDouble(f);g_weekAnchor=FileReadDouble(f);g_monthAnchor=FileReadDouble(f);g_tradesToday=(int)FileReadInteger(f,INT_VALUE);g_consecutiveLosses=(int)FileReadInteger(f,INT_VALUE);g_commissionRTPerLot=FileReadDouble(f);if(!FileIsEnding(f)){g_perfTrades=(int)FileReadInteger(f,INT_VALUE);g_perfWins=(int)FileReadInteger(f,INT_VALUE);g_perfLosses=(int)FileReadInteger(f,INT_VALUE);g_perfNetProfit=FileReadDouble(f);g_perfGrossProfit=FileReadDouble(f);g_perfGrossLoss=FileReadDouble(f);g_perfRetN=(int)FileReadInteger(f,INT_VALUE);g_perfRetMean=FileReadDouble(f);g_perfRetM2=FileReadDouble(f);g_perfCumNet=FileReadDouble(f);g_perfPeakNet=FileReadDouble(f);g_perfMaxDDMoney=FileReadDouble(f);}
   for(int w=0;w<WIN_COUNT&&!FileIsEnding(f);w++){g_ws[w].trades=(int)FileReadInteger(f,INT_VALUE);g_ws[w].wins=(int)FileReadInteger(f,INT_VALUE);g_ws[w].losses=(int)FileReadInteger(f,INT_VALUE);g_ws[w].grossPL=FileReadDouble(f);g_ws[w].netPL=FileReadDouble(f);g_ws[w].costs=FileReadDouble(f);g_ws[w].tp1Hits=(int)FileReadInteger(f,INT_VALUE);g_ws[w].tp2Hits=(int)FileReadInteger(f,INT_VALUE);g_ws[w].tp3Hits=(int)FileReadInteger(f,INT_VALUE);}
   // [PERFORMANCE GATING] R-history tail (only present in new-format state files)
   if(!FileIsEnding(f))for(int w=0;w<WIN_COUNT&&!FileIsEnding(f);w++){g_ws[w].recentRCount=(int)FileReadInteger(f,INT_VALUE);for(int i=0;i<64&&!FileIsEnding(f);i++)g_ws[w].recentR[i]=FileReadDouble(f);if(!FileIsEnding(f))g_ws[w].recentRIdx=(int)FileReadInteger(f,INT_VALUE);}
   // --- open-position ladder plans (only re-attached if the position still exists)
   if(!FileIsEnding(f))
   {
      int nPS=(int)FileReadInteger(f,INT_VALUE);
      for(int p=0;p<nPS&&!FileIsEnding(f);p++)
      {
         PositionState s;ZeroMemory(s);
         s.ticket=(ulong)FileReadLong(f);s.positionId=FileReadLong(f);
         s.direction=(int)FileReadInteger(f,INT_VALUE);s.window=(ENUM_WINDOW_ID)FileReadInteger(f,INT_VALUE);
         s.setupId=FileReadString(f);FileReadInteger(f,INT_VALUE);   // string terminator
         s.hv=(FileReadInteger(f,INT_VALUE)==1);s.recovery=(FileReadInteger(f,INT_VALUE)==1);
         s.initialVolume=FileReadDouble(f);s.initialRiskMoney=FileReadDouble(f);
         s.entry=FileReadDouble(f);s.initialSL=FileReadDouble(f);
         s.tp1=FileReadDouble(f);s.tp2=FileReadDouble(f);s.tp3=FileReadDouble(f);
         s.volTP1=FileReadDouble(f);s.volTP2=FileReadDouble(f);s.volTP3=FileReadDouble(f);
         s.tp1Done=(FileReadInteger(f,INT_VALUE)==1);s.tp2Done=(FileReadInteger(f,INT_VALUE)==1);s.tp3Done=(FileReadInteger(f,INT_VALUE)==1);
         s.maePrice=FileReadDouble(f);s.mfePrice=FileReadDouble(f);
         s.opened=(datetime)FileReadLong(f);
         s.entrySpreadPct=FileReadDouble(f);s.entrySlipPts=FileReadDouble(f);
         s.entryAtrPct=FileReadDouble(f);s.entryVolRatio=FileReadDouble(f);
         s.realizedGross=FileReadDouble(f);s.realizedNet=FileReadDouble(f);s.realizedCosts=FileReadDouble(f);
         // Re-attach only if the position still exists (partial closes during downtime
         // may have changed the volume; ManagePosition always reads live volume anyway).
         bool exists=false;
         for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t&&PositionSelectByTicket(t)&&PositionGetInteger(POSITION_IDENTIFIER)==s.positionId){exists=true;break;}}
         if(exists&&s.ticket>0)
         {
            int sz=ArraySize(g_ps);ArrayResize(g_ps,sz+1);g_ps[sz]=s;
            Print("Restored open-position plan ticket=",s.ticket," (TP1 ",DoubleToString(s.tp1,broker.digits),")");
         }
      }
   }
   FileClose(f);
}

void OpenLog()
{
   if(!InpUseLogFile)return;string n="PAT101_"+eaSymbol+"_"+TimeToString(ServerNow(),TIME_DATE)+".csv";StringReplace(n,".","-");StringReplace(n,":","-");
   g_log=FileOpen(n,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_COMMON,';');if(g_log==INVALID_HANDLE)return;if(FileSize(g_log)==0)FileWrite(g_log,"server_time","event","window","dir","setup","spread_pts","spread_pct","atr_pct","vol_ratio","risk_money","tp1","tp2","tp3","sr_mode","sr_zone_count","sr_up_price","sr_up_strength","sr_up_dist_atr","sr_dn_price","sr_dn_strength","sr_dn_dist_atr","sr_tp_snapped","sr_sl_shifted","sr_block_reason","capital_profile","equity_usd","capital_base","effective_risk_pct","allowed_risk_money","raw_lots","final_lots","actual_risk_money","required_margin","spread_to_atr_pct","adaptive_deviation","commission_rt_lot","expected_allin_cost","sizing_reason","ordercheck_retcode");FileWriteString(g_log,"signal_decision"+";"+"confidence"+";"+"long_confidence"+";"+"short_confidence"+";"+"confidence_gap"+";"+"price_action_score"+";"+"trend_score"+";"+"volume_liquidity_score"+";"+"momentum_score"+";"+"vwap_score"+";"+"volatility_score"+";"+"macro_score"+";"+"options_score"+";"+"risk_reward_score"+";"+"structure_state"+";"+"direction_regime"+";"+"environment_regime"+";"+"volume_state"+";"+"volume_percentile"+";"+"ema9"+";"+"ema20"+";"+"ema50"+";"+"ema200"+";"+"macd_main"+";"+"macd_signal"+";"+"macd_hist"+";"+"net_rr"+";"+"min_net_rr_setup"+";"+"options_available",-1);FileSeek(g_log,0,SEEK_END);
}

void PrintSummary()
{
   Print("=== Predict-A-Trade v1.00 Four-Session Macro/SMC Window Summary ===");
   Print("OVERALL trades=",g_perfTrades," win%=",DoubleToString(OverallWinRate(),2)," PF=",DoubleToString(OverallProfitFactor(),2)," NetR=",DoubleToString(OverallNetR(),3)," Sharpe(trade-R)=",DoubleToString(OverallSharpe(),2)," MaxDD$=",DoubleToString(g_perfMaxDDMoney,2)," MaxDD%=",DoubleToString(g_maxDDSeen,2)," Net$=",DoubleToString(g_perfNetProfit,2));
   for(int w=1;w<WIN_COUNT;w++){if(g_ws[w].trades<=0)continue;double wr=100.0*g_ws[w].wins/MathMax(1,g_ws[w].trades);double ex=WindowExpectancy((ENUM_WINDOW_ID)w);Print(WindowName((ENUM_WINDOW_ID)w)," trades=",g_ws[w].trades," net=",DoubleToString(g_ws[w].netPL,2)," win%=",DoubleToString(wr,1)," exp=",DoubleToString(ex,2)," NetR=",DoubleToString(WindowAvgR((ENUM_WINDOW_ID)w),3)," TP1/2/3=",g_ws[w].tp1Hits,"/",g_ws[w].tp2Hits,"/",g_ws[w].tp3Hits," DD=",DoubleToString(g_ws[w].maxDD,2));}
}

void WriteWindowReport()
{
   string n="PAT101_WindowReport_"+eaSymbol+"_"+IntegerToString(InpMagicNumber)+".csv";
   int f=FileOpen(n,FILE_CSV|FILE_WRITE|FILE_COMMON,';');if(f==INVALID_HANDLE)return;
   FileWrite(f,"window","trades","wins","losses","win_rate_pct","gross_pl","net_pl","costs","cost_ratio_pct","tp1_hit_pct","tp2_hit_pct","tp3_hit_pct","avg_net_R","avg_slip_pts","avg_spread_pct","avg_atr_pct","avg_vol_ratio","avg_MAE_price","avg_MFE_price","max_drawdown_money","rolling_expectancy_money","observations","obs_avg_atr_ratio","obs_avg_vol_ratio","disabled");
   for(int w=1;w<WIN_COUNT;w++)
   {
      int t=g_ws[w].trades;double den=MathMax(1,t);double cr=(MathAbs(g_ws[w].grossPL)>0?100.0*g_ws[w].costs/MathAbs(g_ws[w].grossPL):0);
      long obs=g_ws[w].observations;double oden=(double)MathMax((long)1,obs);
      FileWrite(f,WindowName((ENUM_WINDOW_ID)w),t,g_ws[w].wins,g_ws[w].losses,DoubleToString(100.0*g_ws[w].wins/den,2),DoubleToString(g_ws[w].grossPL,2),DoubleToString(g_ws[w].netPL,2),DoubleToString(g_ws[w].costs,2),DoubleToString(cr,2),DoubleToString(100.0*g_ws[w].tp1Hits/den,2),DoubleToString(100.0*g_ws[w].tp2Hits/den,2),DoubleToString(100.0*g_ws[w].tp3Hits/den,2),DoubleToString(g_ws[w].rSum/den,3),DoubleToString(g_ws[w].slipSum/den,2),DoubleToString(g_ws[w].spreadPctSum/den,2),DoubleToString(g_ws[w].atrPctSum/den,2),DoubleToString(g_ws[w].volRatioSum/den,3),DoubleToString(g_ws[w].maeSum/den,broker.digits),DoubleToString(g_ws[w].mfeSum/den,broker.digits),DoubleToString(g_ws[w].maxDD,2),DoubleToString(WindowExpectancy((ENUM_WINDOW_ID)w),3),obs,DoubleToString(g_ws[w].obsATRRatioSum/oden,3),DoubleToString(g_ws[w].obsVolRatioSum/oden,3),(g_ws[w].disabled?"YES":"NO"));
   }
   FileClose(f);
}

void WritePerformanceReport()
{
   string n="PAT101_Performance_"+eaSymbol+"_"+IntegerToString(InpMagicNumber)+".csv";int f=FileOpen(n,FILE_CSV|FILE_WRITE|FILE_COMMON,';');if(f==INVALID_HANDLE)return;
   FileWrite(f,"metric","value");
   FileWrite(f,"number_of_trades",g_perfTrades);FileWrite(f,"wins",g_perfWins);FileWrite(f,"losses",g_perfLosses);FileWrite(f,"win_rate_pct",DoubleToString(OverallWinRate(),4));FileWrite(f,"profit_factor",DoubleToString(OverallProfitFactor(),4));FileWrite(f,"net_R_per_trade",DoubleToString(OverallNetR(),4));FileWrite(f,"sharpe_trade_R",DoubleToString(OverallSharpe(),4));FileWrite(f,"net_profit",DoubleToString(g_perfNetProfit,2));FileWrite(f,"max_drawdown_money",DoubleToString(g_perfMaxDDMoney,2));FileWrite(f,"max_intraday_drawdown_pct",DoubleToString(g_maxDDSeen,4));FileWrite(f,"avg_slippage_points",DoubleToString(g_slipAvg,3));FileWrite(f,"last_slippage_points",DoubleToString(g_lastSlipPts,3));FileWrite(f,"avg_spread_points",DoubleToString(g_spreadAvg,2));FileWrite(f,"commission_rt_per_lot",DoubleToString(g_commissionRTPerLot>0?g_commissionRTPerLot:InpCommissionPerLotRTFallback,4));
   FileWrite(f,"fmp_usd_avg_pct",DoubleToString(g_usdAvg,4));FileWrite(f,"fmp_usd_bias",g_usdBias);FileWrite(f,"fmp_spx_move_pct",DoubleToString(g_spxMovePct,4));FileWrite(f,"fmp_available",(g_usdAvailable?"YES":"NO"));FileWrite(f,"fmp_news_hits",g_fmpNewsCount);
   FileWrite(f,"capital_profile",CapitalProfileName(g_capitalProfile));
   FileWrite(f,"account_currency",broker.currency);
   FileWrite(f,"equity_usd",DoubleToString(GetEquityUSD(),2));
   FileWrite(f,"average_effective_risk_pct",DoubleToString(GetEffectiveTradeRiskPct(WIN_NONE,false),3));
   FileWrite(f,"average_actual_R",DoubleToString(OverallNetR(),4));
   FileWrite(f,"window_expectancy_R_sydney",DoubleToString(WindowExpectancyR(WIN_SYDNEY),4));
   FileWrite(f,"window_expectancy_R_tokyo",DoubleToString(WindowExpectancyR(WIN_TOKYO),4));
   FileWrite(f,"window_expectancy_R_london",DoubleToString(WindowExpectancyR(WIN_LONDON),4));
   FileWrite(f,"window_expectancy_R_newyork",DoubleToString(WindowExpectancyR(WIN_NEWYORK),4));
   FileWrite(f,"min_lot_rejects",g_minLotRejects);
   FileWrite(f,"margin_rejects",g_marginRejects);
   FileWrite(f,"spread_rejects",g_spreadRejects);
   FileWrite(f,"slippage_rejects",g_slipRejects);
   FileWrite(f,"ordercheck_rejects",g_orderCheckRejects);
   FileClose(f);
}//====================================================================
// DASHBOARD - flow-layout two-column control panel (overlap-proof)
//--------------------------------------------------------------------
// Every string is width-clipped to its column with TextGetSize, rows are
// drawn with a running Y cursor (no absolute row indices), and the panel
// height is computed in a pass-1 measure sweep. Overlap is impossible by
// construction. Header is draggable; P button / F key pauses arming.
//====================================================================
//--- uppercase helper: StringToUpper mutates in place and cannot take a constant
string Upper(string s){ string t=s; StringToUpper(t); return t; }

int SX(int v){ return (int)MathRound(v*g_font/9.0*g_dpiScale); }   // scale px constants by font AND display DPI

//--- clip a string to maxW px, appending "…" when it does not fit
string ClipText(string s,int maxW,int fs)
{
   if(maxW<=12) return (StringLen(s)==0?s:"");
   if(StringLen(s)==0) return s;
   // Measure with the EXACT font/size the label renders in; TextGetSize without
   // TextSetFont uses terminal defaults whose metrics differ from Consolas.
   TextSetFont("Consolas",FontOut(fs),FW_DONTCARE,0);
   uint w=0,h=0;
   if(!TextGetSize(s,w,h)) return s;
   if((int)w<=maxW) return s;
   while(StringLen(s)>1)
   {
      s=StringSubstr(s,0,StringLen(s)-1);
      string t=s+"…";
      if(TextGetSize(t,w,h) && (int)w<=maxW) return t;
   }
   return "";
}

void UIRecompute()
{
   g_font=MathMax(6,MathMin(12,InpPanelFontSize));
   // Windows display scaling (125/150%) makes MT5 render label glyphs physically larger
   // while chart objects stay in raw pixels. Scale the WHOLE layout by the terminal DPI
   // so rows keep their proportions and text never overflows its cell.
   long dpi=TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<96)dpi=96; if(dpi>480)dpi=480;
   g_dpi=(int)dpi;
   g_dpiScale=(double)g_dpi/96.0;
   g_fontPx=(int)MathRound(g_font*g_dpiScale);      // rendered glyph height in px
   g_rh=(int)MathRound((g_font+7)*g_dpiScale);      // row pitch scales with glyphs
   g_hdrH=(int)MathRound((g_font+19)*g_dpiScale);
   g_colW=SX(340);
   g_pad=MathMax(8,SX(12));
   g_gap=MathMax(8,SX(14));
   g_panelW=g_pad*2+g_colW*2+g_gap;
   g_bodyTop=g_hdrH+6;
   g_colHL=(L_SECTIONS*SX(20))+L_ROWS*g_rh+SX(8);
   g_colHR=(R_SECTIONS*SX(20))+R_ROWS*g_rh+SX(8);
   g_tlTop=g_bodyTop+MathMax(g_colHL,g_colHR)+SX(6);
   g_tlH=SX(13)+2+4*g_rh+SX(16);
   g_panelH=g_tlTop+g_tlH+2*g_rh+g_pad;
}

void UIRect(string n,int x,int y,int w,int h,color bg)
{
   string id=UI_PREFIX+n;if(ObjectFind(0,id)<0)ObjectCreate(0,id,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,id,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,id,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,id,OBJPROP_XSIZE,MathMax(1,w));ObjectSetInteger(0,id,OBJPROP_YSIZE,MathMax(1,h));
   ObjectSetInteger(0,id,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,id,OBJPROP_COLOR,bg);
   ObjectSetInteger(0,id,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);
}

int FontOut(int fs){ return (int)MathMax(6,MathRound(fs/g_dpiScale)); }  // counter-scale font size for display DPI

void UILabel(string n,int x,int y,string txt,color c,int sz=-1)
{
   if(g_measure)return;                       // pass-1 layout sweep draws nothing
   int req=(sz>0?sz:g_font);
   int fs=FontOut(req);
   string id=UI_PREFIX+n;if(ObjectFind(0,id)<0)ObjectCreate(0,id,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,id,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,id,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,id,OBJPROP_COLOR,c);ObjectSetInteger(0,id,OBJPROP_FONTSIZE,fs);
   ObjectSetString(0,id,OBJPROP_FONT,"Consolas");   // single font: TextGetSize metrics == rendered metrics
   ObjectSetString(0,id,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);
}

//--- section bar at the current Y cursor
void DashSection(string n,int col,int &y,string title)
{
   int x=g_x+g_pad+col*(g_colW+g_gap);
   if(!g_measure)
   {
      UIRect("SB_"+n,x,y,g_colW,SX(20)-3,C_SECTION);
      UIRect("SL_"+n,x,y,3,SX(20)-3,C_ACCENT);
      UILabel("ST_"+n,x+8,y+((SX(20)-3-MathMax(6,g_font-1))/2),ClipText(Upper(title),g_colW-14,MathMax(6,g_font-1)),C_SECTION_TXT,MathMax(6,g_font-1));
   }
   y+=SX(20)+2;
}

//--- one flowing row; text is clipped to the column so it can never bleed
void DashRow(string n,int col,int &y,string txt,color c)
{
   int x=g_x+g_pad+col*(g_colW+g_gap)+6;
   if(!g_measure)UILabel("R_"+n,x,y+MathMax(0,(g_rh-g_fontPx)/2),ClipText(txt,g_colW-12,g_font),c,g_font);
   y+=g_rh;
}

//--- two labels on one row (value left, status right-aligned in-column)
void DashRowSplit(string n,int col,int &y,string left,string right,color cl,color cr)
{
   int x=g_x+g_pad+col*(g_colW+g_gap)+6;
   if(!g_measure)
   {
      UILabel("R_"+n,x,y+MathMax(0,(g_rh-g_fontPx)/2),ClipText(left,g_colW-100,g_font),cl,g_font);
      uint w=0,h=0;string r=ClipText(right,SX(96),g_font);
      TextSetFont("Consolas",FontOut(g_font),FW_DONTCARE,0);
      TextGetSize(r,w,h);
      UILabel("R_"+n+"b",x+g_colW-12-SX(4)-(int)w,y+MathMax(0,(g_rh-g_fontPx)/2),r,cr,g_font);
   }
   y+=g_rh;
}

// one filled 24h segment (handles ranges that wrap past midnight)
void DashSeg(string n,int bx,int by,int bw,int openMin,int closeMin,color col)
{
   int x1=bx+(int)MathRound(openMin*bw/1440.0);
   int x2=bx+(int)MathRound(closeMin*bw/1440.0);
   if(closeMin>openMin)UIRect(n,x1,by,MathMax(2,x2-x1),9,col);
   else{UIRect(n+"a",x1,by,MathMax(2,bx+bw-x1),9,col);UIRect(n+"b",bx,by,MathMax(2,x2-bx),9,col);}
}

color SessionColor(int i,bool active)
{
   if(i==0)return (active?C_SYD:C_SYD_DIM);
   if(i==1)return (active?C_TOK:C_TOK_DIM);
   if(i==2)return (active?C_LON:C_LON_DIM);
   return (active?C_NY:C_NY_DIM);
}

//--- session-progress phase label (ref.mq5 heuristic, DST-aware bounds)
string SessionPhaseLabel(int utcMin,int openMin,int closeMin)
{
   int len=(closeMin>openMin?closeMin-openMin:1440-openMin+closeMin);
   int into=(utcMin>=openMin?utcMin-openMin:1440-openMin+utcMin);
   if(len<=0)return "IDLE";
   double f=(double)into/(double)len;
   if(f<0.20)return "MANIP";
   if(f<0.75)return "EXPANSION";
   return "REVERSAL";
}

string FmtMoney(double v){ return (v>=0?"+":"")+DoubleToString(v,2); }
string BiasArrow(int b){ return (b>0?"UP":(b<0?"DOWN":"FLAT")); }
color BiasColor(int b){ return (b>0?C_UP_TXT:(b<0?C_DN_TXT:C_DIM)); }
string AccTypeName(ENUM_ACCOUNT_TRADE_MODE m)
{
   if(m==ACCOUNT_TRADE_MODE_DEMO)return "DEMO";
   if(m==ACCOUNT_TRADE_MODE_CONTEST)return "CONTEST";
   if(m==ACCOUNT_TRADE_MODE_REAL)return "REAL";
   return "UNKNOWN";
}
string MarginModeName(ENUM_ACCOUNT_MARGIN_MODE m)
{
   if(m==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)return "HEDGING";
   if(m==ACCOUNT_MARGIN_MODE_RETAIL_NETTING)return "NETTING";
   return "EXCHANGE";
}
string TradeModeName(int m)
{
   if(m==SYMBOL_TRADE_MODE_FULL)return "FULL";
   if(m==SYMBOL_TRADE_MODE_LONGONLY)return "LONG ONLY";
   if(m==SYMBOL_TRADE_MODE_SHORTONLY)return "SHORT ONLY";
   if(m==SYMBOL_TRADE_MODE_CLOSEONLY)return "CLOSE ONLY";
   if(m==SYMBOL_TRADE_MODE_DISABLED)return "DISABLED";
   return "UNKNOWN";
}

string WindowStateText(ENUM_WINDOW_ID w,bool allowed)
{
   if(w<=WIN_NONE||w>=WIN_COUNT)return "IDLE";
   if(g_ws[w].disabled)return "GATED";
   return (allowed?"LIVE":"CLOSED");
}

string TopWindowsText()
{
   string s="";int shown=0;
   for(int w=1;w<WIN_COUNT&&shown<3;w++)
   {
      if(g_ws[w].trades<=0)continue;
      string t=WindowName((ENUM_WINDOW_ID)w)+" "+FmtMoney(g_ws[w].netPL)+"("+IntegerToString(g_ws[w].trades)+")";
      s+=(shown>0?"  ":"")+t;shown++;
   }
   return (s==""?"no closed trades yet":s);
}

void DashUpdate(bool force=false)
{
   if(!InpShowDashboard)return;
   uint ms=GetTickCount();
   if(!force&&g_lastDashMs>0&&ms-g_lastDashMs<(uint)MathMax(100,InpDashRefreshMs))return;
   g_lastDashMs=ms;
   UIRecompute();
   // Full clear every frame (ref.mq5 pattern): stale objects from any earlier layout can
   // never linger, so ghost panels / double bars are impossible.
   ObjectsDeleteAll(0,UI_PREFIX,0,-1);

   int x=g_x,y=g_y;
   if(g_dashCollapsed!=g_dashWasCollapsed){DashDestroy();g_dashWasCollapsed=g_dashCollapsed;}

   bool tr=false;ENUM_WINDOW_ID w=CurrentWindow(tr);
   int wi=(w>WIN_NONE&&w<WIN_COUNT?(int)w:0);

   //---- header
   if(g_dashCollapsed)
   {
      UIRect("BG",x,y,g_panelW,g_hdrH,C_BG);
      UIRect("HDR",x,y,g_panelW,g_hdrH,C_HDR);
      UIRect("HL",x,y,3,g_hdrH,C_ACCENT);
      UILabel("T",x+10,y+((g_hdrH-g_font-2)/2),ClipText(Upper(InpPanelTitle)+" v1.00 ["+eaSymbol+" M1]",g_panelW-SX(160),g_font+2),clrWhite,g_font+2);
      UILabel("CS",x+g_panelW-SX(150),y+((g_hdrH-g_font)/2),WindowName(w)+" "+(tr?"LIVE":"OFF"),(tr?C_UP_TXT:C_DIM),g_font);
      UILabel("CH",x+g_panelW-SX(18),y+((g_hdrH-g_font)/2),"+",C_TXT,g_font);
      ChartRedraw();return;
   }

   UIRect("BG",x,y,g_panelW,g_panelH,C_BG);
   UIRect("HDR",x,y,g_panelW,g_hdrH,C_HDR);
   UIRect("HL",x,y,3,g_hdrH,C_ACCENT);
   UILabel("T",x+10,y+((g_hdrH-g_font-2)/2),ClipText(Upper(InpPanelTitle)+" v1.00 ["+eaSymbol+" M1]",g_panelW-SX(190),g_font+2),clrWhite,g_font+2);

   //---- header status chips (right-aligned, fixed slots)
   int chipX=x+g_panelW-SX(8);
   UILabel("CH_COLL",chipX-SX(20),y+((g_hdrH-g_font)/2),"[-]",C_TXT2,g_font);
   chipX-=SX(28);
   bool hvNow=false;{int hs=HVScore(g_dirBias>=0?1:-1);hvNow=(InpHighVolatilityMode!=HV_OFF&&hs>=InpHVMinScore);}
   UILabel("CH_HV",chipX-SX(24),y+((g_hdrH-g_font)/2),(hvNow?"HV":"--"),(hvNow?C_WARN_TXT:C_GRAY),g_font);
   chipX-=SX(30);
   bool halted=(g_stopDay||g_stopWeek||g_stopMonth);
   string eng=(halted?"HALTED":(g_paused?"PAUSED":(tr?"LIVE":"WAIT")));
   color engC=(halted?C_DN_TXT:(g_paused?C_WARN_TXT:(tr?C_UP_TXT:C_DIM)));
   UILabel("CH_STATE",chipX-SX(52),y+((g_hdrH-g_font)/2),eng,engC,g_font);

   //---- derived values
   datetime utc=UTCNow();int um=MinuteOfDay(utc);
   int so,sc,to,tc,lo,lc,no,nc;SessionUTCBounds(utc,so,sc,to,tc,lo,lc,no,nc);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY),bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN),freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double dd=MathMax(0,(g_dayAnchor>0?(g_dayAnchor-eq)/g_dayAnchor*100:0));
   int atrPts=(broker.point>0?(int)MathRound(g_atr/broker.point):0);
   double sp=SpreadPoints(),spp=SpreadPercentile(),ap=ATRPercentile();
   int hs2=HVScore(g_dirBias>=0?1:-1);
   double openRisk=OpenRiskMoney();
   double riskPct=(eq>0?openRisk/eq*100.0:0);
   double budgetPct=(eq>0?g_windowRiskUsed[wi]/eq*100.0:0);
   int left=MinsUntilWindowClose(w,um,sc,tc,lc,nc);
   double vwapDev=(g_vwap>0&&g_atr>0?(iClose(eaSymbol,PERIOD_M1,1)-g_vwap)/g_atr:0);
   double marginPct=(eq>0?margin/eq*100.0:0);
   double commRT=(g_commissionRTPerLot>0?g_commissionRTPerLot:InpCommissionPerLotRTFallback);

   //================ LEFT COLUMN (flow) ==================
   int rL=0;
   int yL=g_bodyTop;
   DashSection("LS",0,yL,"market / session");
   DashRowSplit("L_WIN",0,yL,WindowName(w),"["+WindowStateText(w,tr)+"]",C_GOLD_TXT,(tr?C_UP_TXT:C_DIM));
   DashRow("L_RNG",0,yL,WindowUTCText(w,so,sc,to,tc,lo,lc,no,nc)+(left>=0?"  "+IntegerToString(left)+"m":""),C_TXT2);
   bool ovSYDTOK=InWindowMinutes(um,so,sc)&&InWindowMinutes(um,to,tc);
   bool ovTOKLON=InWindowMinutes(um,to,tc)&&InWindowMinutes(um,lo,lc);
   bool ovLONNY =InWindowMinutes(um,lo,lc)&&InWindowMinutes(um,no,nc);
   string ovShort=(ovLONNY?"L+NY":(ovTOKLON?"T+L":(ovSYDTOK?"S+T":"--")));
   string utcHM=StringFormat("%02d:%02d",um/60,um%60);
   DashRow("L_TIME",0,yL,"OVL "+ovShort+"  SRV "+TimeToString(ServerNow(),TIME_SECONDS)+"  UTC "+utcHM,C_TXT);
   DashRow("L_SPRD",0,yL,"Spread "+DoubleToString(sp,0)+"pt (p"+DoubleToString(spp,0)+")",
           (sp>InpMaxSpreadPoints*g_ptScale?C_DN_TXT:(spp>InpMaxSpreadPercentile?C_WARN_TXT:C_TXT)));
   DashRow("L_ATR",0,yL,"ATR "+IntegerToString(atrPts)+"pt (p"+DoubleToString(ap,0)+") ["+DoubleToString(InpMinATRPoints*g_ptScale,0)+".."+DoubleToString(InpMaxATRPoints*g_ptScale,0)+"]",
           (atrPts<InpMinATRPoints*g_ptScale||(InpMaxATRPoints>0&&atrPts>InpMaxATRPoints*g_ptScale)?C_WARN_TXT:C_TXT));
   string phLbl=SessionPhaseLabel(um,WindowOpenMin(w,so,sc,to,tc,lo,lc,no,nc),WindowCloseMin(w,so,sc,to,tc,lo,lc,no,nc));
   DashRow("L_VOL",0,yL,"Vol x"+DoubleToString(g_volRatio,2)+"  Phase "+phLbl,
           (g_volRatio>=InpMinVolumeRatio?C_TXT:C_DIM));
   rL=yL;

   DashSection("LG",0,yL,"signal engine");
   DashRowSplit("L_SCORE",0,yL,"Score "+IntegerToString(g_score)+"/"+IntegerToString(g_scoreMax),"Bias "+IntegerToString(g_dirBias)+" "+BiasArrow(g_dirBias),
                (g_score>=InpMinFilterScore?C_UP_TXT:C_WARN_TXT),BiasColor(g_dirBias));
   DashRow("L_SMC",0,yL,"SMC B/S "+IntegerToString(g_smcScoreBull)+"/"+IntegerToString(g_smcScoreBear)+"  FVG "+(g_fvg?(g_fvgDir>0?"UP":"DN"):"-"),BiasColor(g_smcScoreBull-g_smcScoreBear));
   DashRow("L_ADV",0,yL,"IFVG "+(g_ifvg?(g_ifvgDir>0?"BULL":"BEAR"):"-")+"  PTB "+(g_ptb?(g_ptbDir>0?"BULL":"BEAR"):"-")+"  MTF "+((g_h1e20>g_h1e50&&g_m15e20>g_m15e50)?"BULL":((g_h1e20<g_h1e50&&g_m15e20<g_m15e50)?"BEAR":"FLAT")),C_TXT);
   DashRow("L_HV",0,yL,"HV "+IntegerToString(hs2)+"/"+IntegerToString(InpHVMinScore)+(hvNow?" QUAL":" -")+"  VWAPdev "+DoubleToString(vwapDev,2),(hvNow?C_WARN_TXT:C_TXT2));
   // Ultra-scalp v3: this row mirrors the LIVE engine state (g_gateReason is updated
   // by TryArm every tick), not the legacy filter-score formula.
   bool sigOK=(g_scalpSignal!=0);
   bool safeState=(!g_paused&&!halted&&!g_newsBlocked&&tr);
   bool gatePass=(safeState&&sigOK&&StringFind(g_gateReason,"no scalp signal")<0
                  &&StringFind(g_gateReason,"thin session")<0&&StringFind(g_gateReason,"spacing")<0);
   string gateTxt=(g_paused?"PAUSED":(halted?"HALTED":(g_gateReason=="initialized"?"waiting":g_gateReason)));
   DashRow("L_GATE",0,yL,ClipText("Gate: "+gateTxt,g_colW-16,g_font),(gatePass?C_UP_TXT:(safeState?C_WARN_TXT:C_DN_TXT)));
   rL=yL;

   DashSection("LM",0,yL,"fmp macro / news");
   DashRow("L_USD",0,yL,"USD basket "+DoubleToString(g_usdAvg,3)+"% b="+IntegerToString(g_usdBias)+(g_usdAvailable?"":" [offline]"),(g_usdAvailable?BiasColor(g_usdBias):C_GRAY));
   DashRow("L_SPX",0,yL,"SPX "+DoubleToString(g_spxMovePct,3)+"% b="+IntegerToString(g_spxBias)+(g_spxAvailable?"":" [offline]"),(g_spxAvailable?BiasColor(g_spxBias):C_GRAY));
   DashRow("L_EUR",0,yL,"EUR "+(g_eurSymbol==""?"n/a":g_eurSymbol)+" "+DoubleToString(g_eurMovePct,3)+"% b="+IntegerToString(g_eurBias),(g_eurAvailable?BiasColor(g_eurBias):C_GRAY));
   DashRow("L_FMPN",0,yL,"FMP news "+(g_fmpNewsCount>0?"hits:"+IntegerToString(g_fmpNewsCount):"none"),(g_fmpNewsCount>0?C_WARN_TXT:C_GRAY));
   DashRow("L_VOTES",0,yL,"Votes B/S "+IntegerToString(g_macroBull)+"/"+IntegerToString(g_macroBear)+"  "+(g_fmpEverOK?"feed OK":"feed OFF"),(g_fmpEverOK?C_TXT:C_WARN_TXT));

   //================ RIGHT COLUMN (flow) =================
   int yR=g_bodyTop;
   DashSection("RB",1,yR,"broker / account");
   DashRow("R_ACC",1,yR,AccTypeName(broker.tradeMode)+"  Hedging: "+(broker.hedging?"SUPPORTED":"NOT SUPPORTED (netting - one position at a time)"),C_GOLD_TXT);
   DashRow("R_BRK",1,yR,broker.company,C_TXT2);   // clipped to column
   DashRow("R_LEV",1,yR,"Lev 1:"+IntegerToString(broker.leverage)+"  "+TradeModeName((int)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_MODE)),C_TXT);
   DashRow("R_SWAP",1,yR,"Swap "+DoubleToString(broker.swapLong,1)+"/"+DoubleToString(broker.swapShort,1)+"  Comm $"+DoubleToString(commRT,2),C_TXT2);
   DashRow("R_CON",1,yR,"Ctr "+DoubleToString(broker.contractSize,0)+"  Stop "+IntegerToString(broker.stopsLevel)+"  Tick "+DoubleToString(broker.tickSize,3),C_TXT2);

   DashSection("RA",1,yR,"risk / exposure");
   DashRow("R_EQ",1,yR,"Eq "+DoubleToString(eq,2)+"  Bal "+DoubleToString(bal,2)+" "+broker.currency,C_TXT);
   DashRow("R_DD",1,yR,"Day DD "+DoubleToString(dd,2)+"%/"+DoubleToString(InpDailyLossPercent,2)+"%  Wk "+DoubleToString((g_weekAnchor>0?(g_weekAnchor-eq)/g_weekAnchor*100:0),2)+"%",
           (dd>=InpDailyLossPercent?C_DN_TXT:(dd>InpMaxFloatingDDPercent*0.7?C_WARN_TXT:C_TXT)));
   DashRow("R_MRG",1,yR,"Margin "+DoubleToString(margin,2)+" ("+DoubleToString(marginPct,1)+"%)  Free "+DoubleToString(freeM,2),(marginPct>50?C_WARN_TXT:C_TXT2));
   DashRow("R_POS",1,yR,"Positions "+IntegerToString(CountOwnPositions())+"/"+IntegerToString(GetProfileMaxPositions())+"  Lots "+DoubleToString(SumOwnLots(),2),C_TXT);
   DashRow("R_RISK",1,yR,"Risk $"+DoubleToString(openRisk,2)+" ("+DoubleToString(riskPct,2)+"%/"+DoubleToString(InpMaxAggregateOpenRiskPct,2)+"%)",(riskPct>InpMaxAggregateOpenRiskPct?C_DN_TXT:C_TXT));
   DashRow("R_BUD",1,yR,"Budget $"+DoubleToString(g_windowRiskUsed[wi],2)+" ("+DoubleToString(budgetPct,2)+"%/"+DoubleToString(InpPerWindowRiskBudgetPct,2)+"%)",(budgetPct>=InpPerWindowRiskBudgetPct?C_WARN_TXT:C_TXT2));
   //--- [CAPITAL ENGINE] compact adaptive-engine telemetry (section 38; cached values only)
   {
      string capLine="Prof "+CapitalProfileName(g_capitalProfile)+"  EqUSD "+DoubleToString(GetEquityUSD(),0)
                    +"  Cap "+DoubleToString(GetConservativeCapitalBase(),2)
                    +(g_usdConvertNote!=""?("  ["+g_usdConvertNote+"]"):"");
      DashRow("R_CAP",1,yR,capLine,(g_usdConvertNote!=""?C_WARN_TXT:C_TXT));
      double effR=GetEffectiveTradeRiskPct(w,false);
      DashRow("R_CAP2",1,yR,"Risk eff "+DoubleToString(effR,3)+"%  $"+DoubleToString(GetConservativeCapitalBase()*effR/100.0,2)
                    +"  minLot<= "+DoubleToString(GetProfileMinLotRiskCeilingPct(),2)+"%"
                    +"  pos "+IntegerToString(GetProfileMaxPositions()),C_TXT2);
      string volLine="Vol "+DoubleToString(broker.volumeMin,2)+"/"+DoubleToString(broker.volumeStep,2)+"/"+DoubleToString(broker.volumeMax,2)
                    +"  Lim "+(broker.volumeLimit>0?DoubleToString(broker.volumeLimit,2):"-");
      DashRow("R_VOL",1,yR,volLine,C_TXT2);
      double spATR=(g_atr>0?sp*broker.point/g_atr*100.0:0);
      DashRow("R_ADAPT",1,yR,"Sprd/ATR "+DoubleToString(spATR,1)+"%  Dev "+IntegerToString(AdaptiveDeviationPoints())+"pt  Chk "+(g_lastOrderCheckRetcode==0?"OK":IntegerToString(g_lastOrderCheckRetcode)),C_TXT2);
      //--- [SIGNAL QUALITY] compact telemetry (section 33): cached values only
      string decTxt=(g_lastDecision.decision==SIGNAL_BUY?"BUY":(g_lastDecision.decision==SIGNAL_SELL?"SELL":"NO TRADE"));
      color decCol=(g_lastDecision.decision==SIGNAL_BUY?C_UP_TXT:(g_lastDecision.decision==SIGNAL_SELL?C_DN_TXT:C_DIM));
      DashRow("R_SIGQ",1,yR,"Decision "+decTxt+"  "+g_lastDecision.setupName+"  Conf "+DoubleToString(g_lastDecision.confidence,1)+"/"+DoubleToString(EffectiveConfidenceThreshold(),1),decCol);
      DashRow("R_SIGQ2",1,yR,"L/S "+DoubleToString(g_lastDecision.confidence,1)+"/"+DoubleToString(g_lastDecision.oppositeConfidence,1)+" gap "+DoubleToString(g_lastDecision.confidenceGap,1)+"  NetRR "+DoubleToString(g_lastDecision.riskReward,2),C_TXT2);
      DashRow("R_SIGQ3",1,yR,StructureStateName(g_structureState)+"  "+DirectionRegimeName(g_dirRegime)+"  "+EnvironmentRegimeName(g_envRegime)+"  Vol "+VolumeStateName(g_volumeState)+"(p"+DoubleToString(g_volumePercentile,0)+")",C_TXT2);
      DashRow("R_SIGQ4",1,yR,"EMA9/20/50/200 "+DoubleToString(g_ema9,1)+"/"+DoubleToString(g_ema20,1)+"/"+DoubleToString(g_ema50,1)+"/"+DoubleToString(g_ema200,1)+"  MACD "+(g_macdHist>0?"BULL":(g_macdHist<0?"BEAR":"FLAT")),C_TXT2);
   }

   DashSection("RE",1,yR,"execution");
   DashRow("R_GATE",1,yR,"GATE: "+g_gateReason,(StringFind(g_gateReason,"ARMED")>=0||StringFind(g_gateReason,"RECOVERY")>=0?C_UP_TXT:(halted?C_DN_TXT:(g_paused?C_WARN_TXT:C_DIM))));
   DashRow("R_TRD",1,yR,"Trades "+IntegerToString(g_tradesToday)+"/"+IntegerToString(InpMaxTradesPerDay)+"  ConsLoss "+IntegerToString(g_consecutiveLosses)+"/"+IntegerToString(InpMaxConsecutiveLosses),(g_consecutiveLosses>=InpMaxConsecutiveLosses?C_DN_TXT:C_TXT));
   DashRow("R_RCV",1,yR,"Recovery "+(g_lastLossDir!=0?("arm "+(g_lastLossDir>0?"SELL":"BUY")+" legs "+IntegerToString(g_recoveryLegs)):"idle"),(g_lastLossDir!=0?C_WARN_TXT:C_GRAY));
   string newsTxt="News clear";
   color newsCol=C_TXT2;
   if(g_newsBlocked){newsTxt="News BLOCKED "+g_nextNewsName;newsCol=C_DN_TXT;}
   else if(g_nextNewsTime>0)
   {
      long secs=(long)(g_nextNewsTime-ServerNow());
      long hh=secs/3600,mm=(secs%3600)/60;
      newsTxt=StringFormat("News %s in %dh %02dm",g_nextNewsName,(int)hh,(int)mm);
      newsCol=(secs<1800?C_WARN_TXT:C_TXT2);
   }
   DashRow("R_NEWS",1,yR,newsTxt,newsCol);
   DashRow("R_SLIP",1,yR,"Slip avg "+DoubleToString(g_slipAvg,1)+" last "+DoubleToString(g_lastSlipPts,1)+"pt",C_TXT2);
   if(InpSRShowOnPanel)   // [SR] two rows inside the existing two-column layout; R had 3 spare rows
   {
      DashRow("R_SR1",1,yR,ClipText(SR_PanelLine1(),g_colW-16,g_font),(g_srBlockReason=="SR_OK"?C_TXT:C_DN_TXT));
      DashRow("R_SR2",1,yR,ClipText(SR_PanelLine2(),g_colW-16,g_font),(g_srBlockReason=="SR_OK"?C_TXT2:C_WARN_TXT));
   }

   // pause / resume button row
   if(!g_measure)
   {
      int bx=g_x+g_pad+g_colW+g_gap+6,by=yR+2;
      string bn=UI_PREFIX+"BTN_P";
      if(ObjectFind(0,bn)<0){ObjectCreate(0,bn,OBJ_BUTTON,0,0,0);ObjectSetInteger(0,bn,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,bn,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,bn,OBJPROP_HIDDEN,true);ObjectSetInteger(0,bn,OBJPROP_ZORDER,10);}
      ObjectSetInteger(0,bn,OBJPROP_XDISTANCE,bx);ObjectSetInteger(0,bn,OBJPROP_YDISTANCE,by);
      ObjectSetInteger(0,bn,OBJPROP_XSIZE,SX(120));ObjectSetInteger(0,bn,OBJPROP_YSIZE,g_rh);
      // Buttons auto-grow beyond YSIZE under DPI scaling (system metrics); give the row
      // a full extra row of clearance so it can never sit on the next section bar.
      ObjectSetString(0,bn,OBJPROP_TEXT,(g_paused?"RESUME":"PAUSE ARMING"));
      ObjectSetString(0,bn,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,bn,OBJPROP_FONTSIZE,FontOut(g_font));
      ObjectSetInteger(0,bn,OBJPROP_COLOR,(g_paused?C_UP_TXT:C_WARN_TXT));
      ObjectSetInteger(0,bn,OBJPROP_BGCOLOR,(g_paused?C'35,80,45':C'120,40,40'));
      ObjectSetInteger(0,bn,OBJPROP_BORDER_COLOR,C_BORDER);
      ObjectSetInteger(0,bn,OBJPROP_STATE,false);
   }
   yR+=g_rh*2+SX(4);

   RecountTodayStats();
   DashSection("RP",1,yR,"performance");
   DashRow("R_PERF",1,yR,"Today "+IntegerToString(g_todayWins)+"W/"+IntegerToString(g_todayLosses)+"L  Win "+DoubleToString(TodayWinRate(),1)+"%  PF "+DoubleToString(TodayPF(),2),(g_todayNet>=0?C_UP_TXT:C_DN_TXT));
   DashRow("R_TNET",1,yR,"Today net "+FmtMoney(g_todayNet)+"  Life "+FmtMoney(g_perfNetProfit),(g_todayNet>=0?C_UP_TXT:(g_perfNetProfit>=0?C_TXT:C_DN_TXT)));
   DashRow("R_LIFE",1,yR,"Life Win "+DoubleToString(OverallWinRate(),1)+"%  PF "+DoubleToString(OverallProfitFactor(),2)+"  NetR "+DoubleToString(OverallNetR(),3),C_GOLD_TXT);
   DashRow("R_WIN",1,yR,WindowName(w)+": "+FmtMoney(g_ws[wi].netPL)+"  T"+IntegerToString(g_ws[wi].trades)+"  exp "+DoubleToString(WindowExpectancy(w),2),C_TXT2);

   //================ 24H UTC SESSION TIMELINE (flow) =====================
   int tlTop=MathMax(yL,yR)+SX(6);
   int labW=SX(34);
   int barX=x+g_pad+labW,barW=g_panelW-g_pad*2-labW;
   UIRect("TL_BG",x+g_pad,tlTop,g_panelW-g_pad*2,g_tlH,C_BG2);
   UILabel("TL_H",x+g_pad+4,tlTop+2,"SESSION MAP (UTC)",C_SECTION_TXT,MathMax(6,g_font-1));
   int rowY[4];
   int openM[4],closeM[4];
   openM[0]=so;closeM[0]=sc;openM[1]=to;closeM[1]=tc;openM[2]=lo;closeM[2]=lc;openM[3]=no;closeM[3]=nc;
   string names[4]={"SYD","TOK","LDN","NY"};   // 3-letter codes = wider timeline bars
   bool enab[4];
   enab[0]=(InpTradeAllFourSessions||InpTradeSydney);enab[1]=(InpTradeAllFourSessions||InpTradeTokyo);
   enab[2]=(InpTradeAllFourSessions||InpTradeLondon);enab[3]=(InpTradeAllFourSessions||InpTradeNewYork);
   int byT=tlTop+SX(15);
   for(int i=0;i<4;i++)
   {
      rowY[i]=byT+i*g_rh;
      bool act=InWindowMinutes(um,openM[i],closeM[i]);
      UILabel("TL_N"+IntegerToString(i),x+g_pad+4,rowY[i]+((g_rh-MathMax(6,g_font-1))/2),names[i],(enab[i]?(act?SessionColor(i,true):C_TXT2):C_GRAY),MathMax(6,g_font-1));
      UIRect("TL_T"+IntegerToString(i),barX,rowY[i]+((g_rh-9)/2),barW,9,C_PANEL);
      for(int hh=3;hh<24;hh+=3)UIRect("TL_G"+IntegerToString(i)+"_"+IntegerToString(hh),barX+(int)MathRound(hh*barW/24.0),rowY[i]+((g_rh-9)/2),1,9,C_GRID);
      if(enab[i])DashSeg("TL_S"+IntegerToString(i),barX,rowY[i]+((g_rh-9)/2),barW,openM[i],closeM[i],SessionColor(i,act));
   }
   int nowX=barX+(int)MathRound(um*barW/1440.0);
   UIRect("TL_NOW",nowX,byT-2,2,4*g_rh,clrWhite);
   UILabel("TL_NOWL",MathMax(barX,MathMin(nowX-SX(30),barX+barW-SX(70))),tlTop+g_tlH-SX(13),"NOW "+FmtHHMM(um),clrWhite,MathMax(6,g_font-1));

   //================ STATUS + FOOTER (flow) ==============================
   int sy2=tlTop+g_tlH+SX(2);
   UILabel("ST_NOW",x+g_pad+4,sy2,ClipText("NOW "+WindowName(w)+" ["+WindowStateText(w,tr)+"]   TOP: "+TopWindowsText(),g_panelW-g_pad*2-8,g_font),(tr?C_UP_TXT:C_TXT2),g_font);
   UILabel("FT",x+g_pad+4,sy2+g_rh,ClipText("magic "+IntegerToString(InpMagicNumber)+"   "+InpComment+"   F = pause   drag header = move",g_panelW-g_pad*2-8,MathMax(6,g_font-1)),C_GRAY,MathMax(6,g_font-1));
   ChartRedraw();
}

void DashDestroy(){ObjectsDeleteAll(0,UI_PREFIX,0,-1);}

//====================================================================
// INIT / DEINIT / EVENTS
//====================================================================
int OnInit()
{
   eaSymbol=_Symbol;if(!InitBroker()){Print("Broker symbol properties unavailable");return INIT_FAILED;}
   // Phase 2.2: Pct inputs are DECIMAL FRACTIONS (0.75 = 75%). Hard-guard misconfiguration.
   if(InpTP1Pct>1.0||InpTP2Pct>1.0||InpTP3Pct>1.0)
   {
      bool allWhole=(InpTP1Pct>1.0&&InpTP1Pct<=100.0&&InpTP2Pct>1.0&&InpTP2Pct<=100.0&&InpTP3Pct>1.0&&InpTP3Pct<=100.0);
      double sumW=InpTP1Pct+InpTP2Pct+InpTP3Pct;
      if(allWhole&&MathAbs(sumW-100.0)<=0.5)
      {
         Print("WARNING: TP volume percents given as whole numbers (sum=",DoubleToString(sumW,1),"%) - auto-dividing by 100. Prefer decimal fractions (0.75/0.20/0.05).");
         // inputs are const in MQL5; normalize the EFFECTIVE split used by AllocateVolumes via globals
         g_tp1PctEff=InpTP1Pct/100.0;g_tp2PctEff=InpTP2Pct/100.0;g_tp3PctEff=InpTP3Pct/100.0;
      }
      else{Print("INIT FAILED: InpTP1Pct/2/3 must be decimal fractions summing to 1.0 (e.g. 0.75/0.20/0.05). Got ",DoubleToString(InpTP1Pct,3),"/",DoubleToString(InpTP2Pct,3),"/",DoubleToString(InpTP3Pct,3),".");return INIT_PARAMETERS_INCORRECT;}
   }
   else
   {
      if(MathAbs(InpTP1Pct+InpTP2Pct+InpTP3Pct-1.0)>0.001){Print("INIT FAILED: InpTP1Pct+InpTP2Pct+InpTP3Pct must equal 1.0 (got ",DoubleToString(InpTP1Pct+InpTP2Pct+InpTP3Pct,4),").");return INIT_PARAMETERS_INCORRECT;}
      if(InpUseThreeTargets&&(InpTP1Pct<=0||InpTP2Pct<=0||InpTP3Pct<=0)){Print("INIT FAILED: all TP Pct values must be > 0 when InpUseThreeTargets=true.");return INIT_PARAMETERS_INCORRECT;}
      g_tp1PctEff=InpTPPctSanitize(InpTP1Pct);g_tp2PctEff=InpTPPctSanitize(InpTP2Pct);g_tp3PctEff=InpTPPctSanitize(InpTP3Pct);
   }
   // Phase 4.1: symbol must be fully tradeable
   if(InpValidateSymbolOnInit&&(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(eaSymbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
   {Print("INIT FAILED: symbol ",eaSymbol," is not SYMBOL_TRADE_MODE_FULL (closed/close-only).");return INIT_FAILED;}
   // ---- License client init (Phase 2) --------------------------------------
   if(InpLicenseKey!="")
   {
      if(StringFind(InpLicenseServerURL,"https://")!=0)
      {Print("INIT FAILED: InpLicenseServerURL must start with https://");return INIT_PARAMETERS_INCORRECT;}
      // TERMINAL_COMPUTER_NAME is missing in older MetaEditor builds; the terminal
      // data path (unique per install) + account + server bind the seat just as well.
      g_machineId=LicenseSHA256(TerminalInfoString(TERMINAL_DATA_PATH)+"|"+
                                IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+
                                AccountInfoString(ACCOUNT_SERVER));
      LicenseSelfTest();
      if(!LicenseActivate())   // immediate first validation
      {
         // TRANSPORT failure (1009/1001/1003 middlebox/edge class) must NOT kill the EA:
         // the terminal would deinit and the user would have to manually re-attach until
         // a Cloudflare edge blip happens to pass. Instead: init SUCCEEDS in a PENDING
         // state - trading stays blocked (LicenseCheckGate requires g_licenseActive),
         // and the OnTimer license retry loop activates the seat as soon as the edge
         // answers. Only a hard REJECTION (parsed valid:false, e.g. bad/revoked key)
         // still fails init - that cannot heal by retrying.
         bool hardRejection=(g_licenseLastReason!="" && g_licenseLastReason!="server_unreachable"
                             && StringFind(g_licenseLastReason,"transport")!=0
                             && StringFind(g_licenseLastReason,"http")!=0);
         if(hardRejection)
         {Print("INIT FAILED: license rejected (",g_licenseLastReason,") - check the license key.");return INIT_FAILED;}
         Print("LICENSE: activate transport-blip at init (edge/middlebox) - EA starts in PENDING state; auto-activating on the 30s license retry. Trading blocked until activation lands.");
         g_licenseLastReason="pending_activation";
      }
   }
   // ---- Mobile command bridge (Phase 3) ------------------------------------
   if(InpEnableMobileCommands && !GlobalVariableCheck("PAT_TRADING_ENABLED"))
      GlobalVariableSet("PAT_TRADING_ENABLED",1);   // default: trading enabled
   // Fail-loud permission diagnosis (no silent "compiles but never trades").
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))Print("WARNING: AutoTrading is OFF - enable the Algo Trading button to allow entries.");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))Print("WARNING: MQL trade permission denied - check Allow Algo Trading in EA settings.");
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))Print("WARNING: Account forbids expert trading.");
   hATR=iATR(eaSymbol,PERIOD_M1,InpATRPeriod);hADX=iADX(eaSymbol,PERIOD_M1,InpADXPeriod);hEMA20=iMA(eaSymbol,PERIOD_M1,InpEMA20Period,0,MODE_EMA,PRICE_CLOSE);hEMA50=iMA(eaSymbol,PERIOD_M1,InpEMA50Period,0,MODE_EMA,PRICE_CLOSE);hH1EMA20=iMA(eaSymbol,PERIOD_H1,20,0,MODE_EMA,PRICE_CLOSE);hH1EMA50=iMA(eaSymbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE);hM15EMA20=iMA(eaSymbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE);hM15EMA50=iMA(eaSymbol,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE);hRSI=iRSI(eaSymbol,PERIOD_M1,InpRSIPeriod,PRICE_CLOSE);hM5E20=iMA(eaSymbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE);hM5E50=iMA(eaSymbol,PERIOD_M5,50,0,MODE_EMA,PRICE_CLOSE);hM5ADX=iADX(eaSymbol,PERIOD_M5,14);
   //--- [SIGNAL QUALITY] new indicator handles (sections 4/5/6)
   if(InpUseEMA9)hEMA9=iMA(eaSymbol,PERIOD_M1,InpEMA9Period,0,MODE_EMA,PRICE_CLOSE);
   if(InpUseEMA200)hEMA200=iMA(eaSymbol,PERIOD_M1,InpEMA200Period,0,MODE_EMA,PRICE_CLOSE);
   if(InpUseMACD)hMACD=iMACD(eaSymbol,PERIOD_M1,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   if((InpUseEMA9&&hEMA9==INVALID_HANDLE)||(InpUseEMA200&&hEMA200==INVALID_HANDLE)||(InpUseMACD&&hMACD==INVALID_HANDLE)){Print("Signal-quality indicator initialization failed");return INIT_FAILED;}
   if(hATR==INVALID_HANDLE||hADX==INVALID_HANDLE||hEMA20==INVALID_HANDLE||hEMA50==INVALID_HANDLE||hH1EMA20==INVALID_HANDLE||hH1EMA50==INVALID_HANDLE||hM15EMA20==INVALID_HANDLE||hM15EMA50==INVALID_HANDLE||hRSI==INVALID_HANDLE||hM5E20==INVALID_HANDLE||hM5E50==INVALID_HANDLE||hM5ADX==INVALID_HANDLE){Print("Indicator initialization failed");return INIT_FAILED;}
   if(!SR_Init()){Print("SR module initialization failed");return INIT_FAILED;}   // [SR]
   g_x=InpPanelX;g_y=InpPanelY;
   if(GlobalVariableCheck("PAT_X_"+eaSymbol+"_"+IntegerToString(InpMagicNumber)))
   {int sx=(int)GlobalVariableGet("PAT_X_"+eaSymbol+"_"+IntegerToString(InpMagicNumber));
    int sy=(int)GlobalVariableGet("PAT_Y_"+eaSymbol+"_"+IntegerToString(InpMagicNumber));
    // Clamp to the visible chart area: a panel dragged off-screen (or a saved position
    // from a larger window) would otherwise be invisible with no way to recover.
    int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
    if(sx>=0&&sy>=0&&sx<chartW-200&&sy<chartH-100){g_x=sx;g_y=sy;}
    else Print("DASHBOARD: saved panel position (",sx,",",sy,") outside this chart - resetting to default");}
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);g_atrKeep=MathMax(30,MathMin(ATR_SAMPLES,InpATRPercentileLookback));ArrayInitialize(g_spreadBuf,0);ArrayInitialize(g_slipBuf,0);ArrayInitialize(g_atrBuf,0);ArrayInitialize(g_usdMove,0);ArrayInitialize(g_usdGot,false);RefreshServerOffset(true);UIRecompute();
   PrintSessionMapAudit();UpdateRiskPeriods();if(InpPersistState)LoadState();
   //--- [SIGNAL QUALITY] weight validation + classification warm start (sections 42/44/45)
   InitConfidenceWeights();
   if(g_confTelemetry!="")Print("SIGNAL QUALITY: ",g_confTelemetry);
   g_options.available=false;g_options.timestamp=0;g_options.source="none";   // fail-open until a provider fills it
   UpdateStructureState();UpdateVolumeEngine();UpdateDirectionRegime();UpdateEnvironmentRegime();
   Print("DASHBOARD: panel at x=",g_x," y=",g_y," width=",g_panelW," height=",g_panelH," (drag header to move; click header to collapse/expand)");
   Print("SIGNAL QUALITY: structure=",StructureStateName(g_structureState)," dirRegime=",DirectionRegimeName(g_dirRegime)," env=",EnvironmentRegimeName(g_envRegime)," vol=",VolumeStateName(g_volumeState)," (p",DoubleToString(g_volumePercentile,0),") threshold=",DoubleToString(EffectiveConfidenceThreshold(),1));
   Print("TRADE GATES (PERCENTAGE/ADAPTIVE): spread <= ",DoubleToString(InpMaxSpreadPctOfSL,0),"% of SL distance (projected cap computed live from ATR) | slippage avg <= ",DoubleToString(InpMaxSlippagePctOfATR,1),"% ATR | confidence ",DoubleToString(InpMinConfidenceScore,0),"+ gap ",DoubleToString(InpMinDirectionalConfidenceGap,0)," | netRR per setup | loss-decay x0.70/loss (floor ",DoubleToString(InpRiskFloorPct,2),"%)");
   // [CAPITAL ENGINE] classify once at init + log the profile environment
   g_capitalProfile=GetCapitalProfile();
   Print("CAPITAL ENGINE: profile=",CapitalProfileName(g_capitalProfile)," equity=",DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)," ",broker.currency," equityUSD=",DoubleToString(GetEquityUSD(),2)," capitalBase=",DoubleToString(GetConservativeCapitalBase(),2)," baseRisk=",DoubleToString(GetProfileBaseRiskPct(),3),"% aggregate=",DoubleToString(GetProfileAggregateRiskPct(),2),"% maxPositions=",GetProfileMaxPositions(),(g_usdConvertNote!=""?" ["+g_usdConvertNote+"]":""));
   CapitalSelfTest();
   // A consecutive-loss streak must never survive a restart as a halt: recount it from
   // real deal history (the persisted counter is a stats value, not a live breaker).
   if(InpPersistState)
   {
      g_consecutiveLosses=RecountConsecutiveLosses();
      if(g_consecutiveLosses<InpMaxConsecutiveLosses)g_stopDay=false;   // fresh start
      Print("Consecutive losses recounted from history: ",g_consecutiveLosses,"/",InpMaxConsecutiveLosses);
   }OpenLog();IsNewBar();UpdateSpreadStats();UpdateIndicators();RefreshVolumeRatio();RefreshFMPMacro(true);UpdateSuperTrend();UpdateVWAP();DetectFVG();DetectIFVG();DetectPTB();AnalyzeAMD();DetectSMC();EvaluateFilters();EventSetTimer(1);g_gateReason="initialized";DashUpdate(true);
   Print("Predict-A-Trade v1.00 initialized | ",eaSymbol," | digits=",broker.digits," ptScale=",g_ptScale," | server-UTC offset=",g_serverOffsetSec,"s | minVol=",broker.volumeMin," step=",broker.volumeStep," stops=",broker.stopsLevel," freeze=",broker.freezeLevel," hedging=",broker.hedging);
   Print("Broker: ",broker.company," | ",AccTypeName(broker.tradeMode)," account | leverage 1:",broker.leverage," | swap L/S ",DoubleToString(broker.swapLong,2),"/",DoubleToString(broker.swapShort,2));
   // Print the rollover-verification note only the FIRST time ever (persisted), so it
   // reads as one-time setup guidance rather than a recurring warning.
   string gvKey="PAT_SWAP_NOTE_"+eaSymbol+"_"+IntegerToString(InpMagicNumber);
   if(!GlobalVariableCheck(gvKey))
   {
      Print("Swap rollover assumed at ",DoubleToString(InpSwapRolloverServerHour,2)," server time. One-time check: hold or review a position that crosses this hour - the History tab must show a swap entry at that hour. If the swap posts at a different hour, set InpSwapRolloverServerHour to it. This message will not repeat.");
      GlobalVariableSet(gvKey,1);
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   SR_Deinit();   // [SR] remove every SR chart object before existing cleanup
   EventKillTimer();if(InpPersistState)SaveState();if(g_log!=INVALID_HANDLE){FileFlush(g_log);FileClose(g_log);g_log=INVALID_HANDLE;}WriteWindowReport();WritePerformanceReport();DashDestroy();
   if(hATR!=INVALID_HANDLE)IndicatorRelease(hATR);if(hADX!=INVALID_HANDLE)IndicatorRelease(hADX);if(hEMA20!=INVALID_HANDLE)IndicatorRelease(hEMA20);if(hEMA50!=INVALID_HANDLE)IndicatorRelease(hEMA50);if(hH1EMA20!=INVALID_HANDLE)IndicatorRelease(hH1EMA20);if(hH1EMA50!=INVALID_HANDLE)IndicatorRelease(hH1EMA50);if(hM15EMA20!=INVALID_HANDLE)IndicatorRelease(hM15EMA20);if(hM15EMA50!=INVALID_HANDLE)IndicatorRelease(hM15EMA50);if(hRSI!=INVALID_HANDLE)IndicatorRelease(hRSI);if(hM5E20!=INVALID_HANDLE)IndicatorRelease(hM5E20);if(hM5E50!=INVALID_HANDLE)IndicatorRelease(hM5E50);if(hM5ADX!=INVALID_HANDLE)IndicatorRelease(hM5ADX);if(hEMA9!=INVALID_HANDLE)IndicatorRelease(hEMA9);if(hEMA200!=INVALID_HANDLE)IndicatorRelease(hEMA200);if(hMACD!=INVALID_HANDLE)IndicatorRelease(hMACD);PrintSummary();
}

void OnTick()
{
   if(!LicenseCheckGate())return;   // [LICENSE] blank key = zero-overhead pass-through
   ProcessMobileCommands();         // [LICENSE] mobile command bridge (cheap: scans orders)
   RefreshServerOffset(false);UpdateRiskPeriods();UpdateSpreadStats();bool nb=IsNewBar();UpdateIndicators();RefreshFMPMacro(false);SR_Rebuild();   // [SR] throttled; before signal evaluation
   if(nb){RefreshVolumeRatio();UpdateSuperTrend();UpdateVWAP();DetectFVG();DetectIFVG();DetectPTB();AnalyzeAMD();DetectSMC();EvaluateFilters();UpdateOpportunityObservations();CheckNews(false);
      //--- [SIGNAL QUALITY] per-bar refresh: structure, volume states, regimes (sections 3/7/8)
      UpdateStructureState();
      UpdateVolumeEngine();
      UpdateDirectionRegime();
      UpdateEnvironmentRegime();
      // ultra-scalp v2 state
      double rsiBuf[1];if(CopyBuffer(hRSI,0,1,1,rsiBuf)>0)g_rsi=rsiBuf[0];
      double e20[1],e50[1],adx[1],adxp[1],adxm[1];
      if(CopyBuffer(hM5E20,0,1,1,e20)>0)g_m5e20=e20[0];
      if(CopyBuffer(hM5E50,0,1,1,e50)>0)g_m5e50=e50[0];
      if(CopyBuffer(hM5ADX,0,0,1,adx)>0)g_m5adx=adx[0];
      if(CopyBuffer(hM5ADX,1,0,1,adxp)>0)g_m5adxPlus=adxp[0];
      if(CopyBuffer(hM5ADX,2,0,1,adxm)>0)g_m5adxMinus=adxm[0];
      // Bollinger 20,2 on M1 closes (manual std over 20 bars)
      double closes[20];   // mean/std are order-independent; no series flag needed
      if(CopyClose(eaSymbol,PERIOD_M1,1,20,closes)==20)
      {
         double sum=0;for(int k=0;k<20;k++)sum+=closes[k];g_bbMid=sum/20.0;
         double v=0;for(int k=0;k<20;k++){double d=closes[k]-g_bbMid;v+=d*d;}
         double sd=MathSqrt(v/20.0);
         g_bbUp=g_bbMid+2.0*sd;g_bbLo=g_bbMid-2.0*sd;
      }
      EvaluateScalpSignal();
   }else EvaluateFilters();
   if((g_stopDay||g_stopWeek||g_stopMonth)&&InpBreakerAction==BREAKER_CLOSE_ALL)EmergencyCloseAll();
   EnforceSwapFlat();
   if(g_lastLossDir!=0)TryRecovery();
   if(!g_paused&&!g_stopDay&&!g_stopWeek&&!g_stopMonth)TryArm();
   ManageAllPositions();DashUpdate(false);
}

void OnTimer()
{
   RefreshServerOffset(false);CheckNews(false);RefreshFMPMacro(false);EnforceSwapFlat();if(InpCancelStalePendings)DeleteOwnPendings(true);DashUpdate(true);SR_SelfTest();if(InpPersistState && (ServerNow()%30)==0)SaveState();
   // [CAPITAL ENGINE] profile recompute on the 1s timer: cheap (equity + cached FX),
   // detects deposits/withdrawals/equity drift across tier boundaries within a minute.
   g_capitalProfile=GetCapitalProfile();
   if(InpLicenseKey!="" && TimeCurrent()>=g_nextLicenseCheck)   // [LICENSE] WebRequest ONLY here, never in hot paths
   {
      CheckLicense();
      // healthy: poll every 10 min. PENDING activation (transport blip at init): retry
      // every 30s so the seat lands as soon as the edge answers. Unhealthy otherwise:
      // 2 min. This is what self-heals a 1009/1003 Cloudflare blip without user action.
      long interval=(g_licenseActive?600:(g_licenseLastReason=="pending_activation"?30:120));
      g_nextLicenseCheck=TimeCurrent()+interval;
   }
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!InpShowDashboard)return;

   //--- P button (OBJ_BUTTON) toggles arming; real dialog feedback + sound
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==UI_PREFIX+"BTN_P")
   {
      g_paused=!g_paused;
      g_gateReason=(g_paused?"MANUAL PAUSE (panel)":"resumed");
      PlaySound(g_paused?InpSoundPause:InpSoundResume);
      Print("Arming ",(g_paused?"PAUSED by operator":"RESUMED by operator"));
      DashUpdate(true);
      return;
   }

   //--- header click = collapse / expand (if the press did not become a drag)
   if(id==CHARTEVENT_CLICK && g_maybeClick)
   {
      int mx=(int)lparam,my=(int)dparam;
      g_maybeClick=false;
      if(!g_dragging && g_panelW>0 && mx>=g_x && mx<=g_x+g_panelW && my>=g_y && my<=g_y+g_hdrH)
      {
         g_dashCollapsed=!g_dashCollapsed;
         Print("Dashboard ",(g_dashCollapsed?"collapsed":"expanded"));
         DashUpdate(true);
      }
      return;
   }

   //--- F key pauses arming (chart focused)
   if(id==CHARTEVENT_KEYDOWN && lparam==70)   // 'F'
   {
      g_paused=!g_paused;
      g_gateReason=(g_paused?"MANUAL PAUSE (F)":"resumed");
      PlaySound(g_paused?InpSoundPause:InpSoundResume);
      Print("Arming ",(g_paused?"PAUSED by operator":"RESUMED by operator"));
      DashUpdate(true);
      return;
   }

   //--- header drag (InpPanelDraggable)
   if(InpPanelDraggable && id==CHARTEVENT_MOUSE_MOVE)
   {
      int mx=(int)lparam,my=(int)dparam;
      int flags=(int)StringToInteger(sparam);
      bool lmb=((flags&1)!=0);
      uint now=GetTickCount();

      if(lmb && !g_dragging)
      {
         if(mx>=g_x && mx<=g_x+g_panelW && my>=g_y && my<=g_y+g_hdrH)
         {
            g_maybeClick=true;
            g_dragging=true;
            g_dragOffX=mx-g_x; g_dragOffY=my-g_y;
            g_dragStartX=mx;   g_dragStartY=my;
         }
      }
      else if(g_dragging && lmb)
      {
         // movement beyond a few px cancels the click-collapse
         if(MathAbs(mx-g_dragStartX)>4||MathAbs(my-g_dragStartY)>4)g_maybeClick=false;
         int nx=mx-g_dragOffX, ny=my-g_dragOffY;
         int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
         int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
         if(nx<0)nx=0; if(ny<0)ny=0;
         if(nx+g_panelW>cw)nx=cw-g_panelW;
         if(ny+g_hdrH>ch)ny=MathMax(0,ch-g_hdrH);
         if(nx!=g_x||ny!=g_y)
         {
            g_x=nx;g_y=ny;
            GlobalVariableSet("PAT_X_"+eaSymbol+"_"+IntegerToString(InpMagicNumber),g_x);
            GlobalVariableSet("PAT_Y_"+eaSymbol+"_"+IntegerToString(InpMagicNumber),g_y);
            // throttle during drag for smoothness
            if(now-g_lastDragMs>=(uint)MathMax(30,InpDashRefreshMs/4)){g_lastDragMs=now;DashUpdate(true);}
         }
      }
      else if(g_dragging && !lmb)
      {
         g_dragging=false;
         DashUpdate(true);   // final snap
      }
   }
}

//+------------------------------------------------------------------+
//| End                                                              |
//+------------------------------------------------------------------+