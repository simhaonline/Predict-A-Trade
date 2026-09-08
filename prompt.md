# CODEX CLI TASK — Predict-A-Trade EA: XAUUSD M1 Ultra-Scalp Build, SR Zones Module, and Pro-Trader Hardening

## 0. ROLE & MISSION

You are a senior **MQL5 / MetaTrader 5 Expert Advisor architect, quant risk engineer, and code auditor**.

You are working inside this repository on the **Predict-A-Trade** EA (XAUUSD M1 ultra-scalper).

Deliver **five phases** in order:

| Phase | Scope |
|---|---|
| **1** | Apply the authoritative XAUUSD M1 ultra-scalp parameter profile and emit `.set` presets |
| **2** | Enforce the TP/SL methodology (ATR-based distance + percentage volume split) and align hardcoded simple-mode values |
| **3** | Build a dedicated, additive HTF Support & Resistance (SR) module |
| **4** | Pro-Trader hardening: broker/account/execution/compliance/telemetry robustness |
| **5** | Validation, self-test, and backtest protocol |

Work incrementally. **Commit each phase separately** with a clear message. Do not proceed to the next phase until the current one compiles clean.

---

## 1. REPOSITORY DISCOVERY (do this first)

Before writing any code:

1. Locate the main `.mq5` file and any `.mqh` includes.
2. Enumerate **every** `input`/`sinput` declaration with its exact name, type, and current default.
3. Map these functions (or their equivalents) and record file + line:
   - `OnInit`, `OnDeinit`, `OnTick`, `OnTradeTransaction`, `OnTimer`, `OnChartEvent`
   - `TryArm`, `CanEnter`, `TryRecovery`
   - `ScalpTarget1`, `ScalpStopDistance`, `BuildThreeTargets`, `ComputeSL`
   - `NearestLiquidityTarget`, `DetectSMC`, `CurrentRiskPct`, `LearnCommission`
   - Lot-sizing, partial-close, trailing, breakeven, dashboard, CSV logging, state persistence
4. Identify which code paths are gated by `InpSimpleScalpMode == true`.
5. Produce `docs/00_Source_Map.md` with the above findings **before** editing anything.

If a named input/function below does **not** exist, do **not** invent trading logic — record it in the audit as `MISSING` and continue.

---

## 2. NON-NEGOTIABLE INVARIANTS

These may never be violated by any phase:

1. **No martingale.** `InpNoMartingale = true` is permanent.
2. **No averaging down.** `InpNoAveragingDown = true` is permanent. No new entry may size up while any position is underwater.
3. **No scale-in.** `InpScaleIn = false`.
4. **No loss-chasing recovery in simple mode.** Recovery stays disabled when `InpSimpleScalpMode == true`.
5. **Risk per trade may never exceed `InpRiskPercent`.** Any logic that widens a stop must recompute lot size so realized risk is unchanged.
6. **A stop may never move against an open position.** Trailing and breakeven are strictly monotonic.
7. **The EA must remain tradeable when external data fails.** FMP/calendar/HTF-history outages degrade gracefully, never hard-stop.
8. **`InpSimpleScalpMode` stays `true`.** Do not switch the EA to complex mode.
9. **Every new subsystem is additive and default-safe.** With its master switch off, behaviour must be bit-identical to the pre-change build.
10. **Zero compile errors, zero compile warnings**, MQL5 strict mode, on every commit.

---

# PHASE 1 — AUTHORITATIVE ULTRA-SCALP PARAMETER PROFILE

Apply these values. This profile is the reconciliation of two earlier drafts; where they conflicted, the **stricter capital-protection value wins**.

### Core mode
```
InpSimpleScalpMode           = true
InpScalpMinMomentumATR       = 0.08
```

### Capital protection
```
InpDailyLossPercent          = 2.5
InpMaxFloatingDDPercent      = 3.0
InpWeeklyLossLimit           = 6.0
InpMonthlyLossLimit          = 10.0
InpRiskPercent               = 0.35
InpRiskStepDownOnDD          = 0.15
InpMaxConsecutiveLosses      = 3
InpMaxTradesPerDay           = 25
InpAllowMinLotFallback       = true
InpMinLotMaxRiskPct          = 1.5
InpMaxAggregateOpenRiskPct   = 2.5
InpMaxDirectionalRiskPct     = 1.5
InpBreakerAction             = BREAKER_CLOSE_ALL
InpNoMartingale              = true
InpNoAveragingDown           = true
```

### Broker / cost model
```
InpMaxSpreadPoints           = 35
InpSpreadSpikeRatio          = 2.0
InpMaxSpreadPercentile       = 90.0
InpMaxSlippagePoints         = 25
InpCommissionPerLotRTFallback= 7.00
InpExpectedSlipPtsFallback   = 3.5
InpMaxCostToTP1Pct           = 40.0
InpMinNetProfitTP1Money      = 0.30
InpMinNetProfitTP2Money      = 0.50
InpMinNetProfitTP3Money      = 0.70
InpOrderRetry                = 2
InpMaxAverageSlippagePoints  = 15.0
InpExtremeSlippagePoints     = 25.0
```

### Risk-reward validation
```
InpMinRR_TP2                 = 0.55
InpMinRR_TP3                 = 1.10
```

### Execution / anti-overtrading
```
InpExecutionMode             = EXEC_DIRECTIONAL
InpStraddleLayers            = 1
InpLayerStepATR              = 0.35
InpMaxConcurrentPositions    = 3
InpMaxTotalLots              = 1.20
InpArmWhileInTrade           = true
InpScaleIn                   = false
InpMinSecondsBetweenEntries  = 20
InpMinBarsFreshStructure     = 2
InpMaxSignalsPerWindow       = 10
InpPerWindowRiskBudgetPct    = 1.5
InpOncePerValidatedEvent     = true
InpCancelStalePendings       = true
InpPendingExpiryMinutes      = 3
InpDistance                  = 1.00
InpUseATRForDistance         = true
InpATRMultiplier             = 0.22
InpLayerSpacingATR           = 0.25
InpLotSize                   = 0.05
```

### Filters / SMC
```
InpFilterMode                = FILTER_SCORING
InpMinFilterScore            = 5
InpUseEMA20                  = true
InpUseEMA50                  = true
InpUseSuperTrend             = true
InpUseADX                    = true
InpUseVWAP                   = true
InpUseFVG                    = true
InpUseAMD                    = true
InpUseVolumeFilter           = true
InpUseLiquidityFilter        = true
InpUseRSI                    = true
InpUseSMC                    = true
InpMinDirBias                = 2
InpMinSMCConfluence          = 1
InpSwingLookback             = 12
InpFVGLookbackBars           = 12
InpFVGMinGapATR              = 0.05
InpAMDLookbackBars           = 20
InpAMDCoilRatio              = 0.80
```

### Indicators / volatility
```
InpEMA20Period               = 20
InpEMA50Period               = 50
InpSuperTrendPeriod          = 10
InpSuperTrendMultiplier      = 3.0
InpADXPeriod                 = 14
InpMinADX                    = 20.0
InpATRPeriod                 = 14
InpMinATRPoints              = 22
InpMaxATRPoints              = 550
InpATRPercentileLookback     = 240
InpHVMinATRPercentile        = 65.0
InpVolumeMA                  = 25
InpMinVolumeRatio            = 1.15
InpHVMinVolumeRatio          = 1.30
InpMinLiquidityLevel         = 0.90
InpRSIPeriod                 = 9
InpRSIOverbought             = 75
InpRSIOversold               = 25
InpVWAPAnchor                = VWAP_BROKER_DAY
```

### Session / overlap engine
```
InpUseSessionFilter          = true
InpTradeAllFourSessions      = true
InpTradeSydney               = true
InpTradeTokyo                = true
InpTradeLondon               = true
InpTradeNewYork              = true
InpTradeSydneyTokyo          = true
InpTradeTokyoLondon          = true
InpTradeLondonOpen           = true
InpTradeLondonNY             = true
InpTradeNYOpen               = true
InpTradeVerifiedExpansion    = true
InpNeverDisablePrimarySessions = true
InpSydneyLocalOpenMin        = 480
InpSydneyLocalCloseMin       = 1020
InpTokyoLocalOpenMin         = 540
InpTokyoLocalCloseMin        = 1080
InpLondonLocalOpenMin        = 480
InpLondonLocalCloseMin       = 990
InpNewYorkLocalOpenMin       = 480
InpNewYorkLocalCloseMin      = 1020
InpLondonOpenWindowMin       = 75
InpNYOpenWindowMin           = 60
InpOverlapPadMinutes         = 0
InpFridayCutoffServer        = 19.0
InpAutoDetectServerOffset    = true
InpManualServerOffsetHours   = 3
InpServerOffsetRefreshSec    = 60
```

### High-volatility mode
```
InpHighVolatilityMode        = HV_AUTO
InpHVMinScore                = 6
InpHVMinDisplacementATR      = 0.60
InpHVMaxDisorderATR          = 2.50
InpHVMinVWAPDeviationATR     = 0.10
InpSessionBreakoutLookback   = 30
InpHVExtraSignalRiskMult     = 0.70
InpVerifiedBucketMinSamples  = 30
InpVerifiedBucketATRRatio    = 1.15
InpVerifiedBucketVolRatio    = 1.10
```

### TP ladder / exit engine
```
InpUseThreeTargets           = true
InpTP1Pct                    = 0.75
InpTP2Pct                    = 0.20
InpTP3Pct                    = 0.05
InpSL_ATR_Multiplier         = 0.80
InpSLStructureBufferATR      = 0.12
InpTP1_ATR_Floor             = 0.25
InpTP1_ATR_Cap               = 0.40
InpTP2_ATR_Floor             = 0.60
InpTP2_ATR_Cap               = 1.10
InpTP3_ATR_Floor             = 1.00
InpTP3_ATR_Cap               = 1.80
InpUseCostAdjustedBE         = true
InpBEExtraLockATR            = 0.02
InpUseTP3StructureTrail      = true
InpTP3TrailATR               = 0.50
InpTP3TrailStepATR           = 0.10
InpTP3EarlyExit              = true
InpMaxTradeMinutes           = 10
```

### News / disorder protection
```
InpUseNewsFilter             = true
InpNewsBufferMinutes         = 10
InpNewsLookaheadMin          = 120
InpPostNewsStabilizeMinutes  = 5
InpDisorderSpreadPct         = 95.0
InpMaxChaseCandleATR         = 2.20
InpMaxEntryVWAPDeviationATR  = 2.00
InpDisorderSlipPts           = 18.0
InpDisorderCooldownMinutes   = 5
```

### FMP macro / external data
```
InpUseFMP                    = true
InpFMPRefreshSec             = 600
InpFMPTimeoutMs              = 5000
InpFMPUSDPairMinPct          = 0.020
InpFMPIncludeSPX             = true
InpFMPSPXMinPct              = 0.30
InpFMPNewsHardBlock          = false
InpFMPNewsLimit              = 25
InpAllowBrokerMacroFallback  = true
InpMacroTF                   = PERIOD_M5
InpMacroMomentumBars         = 6
InpUseEURUSD                 = true
InpEURUSDSymbol              = ""
InpEURUSDMinMovePct          = 0.020
InpMacroMinConfluence        = 0
InpRequireExternalData       = false
```

### IFVG / propulsion block
```
InpUseIFVG                   = true
InpIFVGLookbackBars          = 40
InpIFVGMinGapATR             = 0.05
InpUsePTB                    = true
InpPTBLookbackBars           = 40
InpPTBMinDisplacementATR     = 0.55
InpMinAdvancedSMCConfluence  = 0
```

### Loss recovery
```
InpUseRecovery               = true
InpRecoveryMaxLegs           = 1
InpRecoveryRiskPct           = 0.15
InpRecoveryMinRR             = 1.50
InpRecoveryCooldownSec       = 300
InpRecoveryMaxAgeSec         = 600
InpRecoveryMaxSpreadPts      = 30
```

### Slippage / swap
```
InpCloseOnExtremeSlippage    = false
InpSlippageCooldownMinutes   = 3
InpAvoidSwap                 = true
InpForceFlatBeforeSwap       = true
InpSwapRolloverServerHour    = 0.0
InpSwapBlockMinutesBefore    = 60
InpSwapBlockMinutesAfter     = 10
```

### Performance gating / A-B
```
InpEnablePerformanceGating   = true
InpPerfMinTrades             = 20
InpPerfRollingTrades         = 40
InpDisableExpectancyMoney    = -0.15
InpRiskReduceExpectancyMoney = 0.08
InpWeakWindowRiskMultiplier  = 0.50
InpAB_EnableBase             = true
InpAB_EnableHighVol          = true
InpAB_EnableThreeTP          = true
```

### Logging / dashboard / identity
```
InpUseLogFile                = true
InpPersistState              = true
InpShowDashboard             = true
InpPanelX                    = 430
InpPanelY                    = 30
InpPanelFontSize             = 8
InpDashRefreshMs             = 400
InpPanelTitle                = "PREDICT-A-TRADE GOLD"
InpPanelDraggable            = true
InpSoundPause                = "alert2.wav"
InpSoundResume               = "alert.wav"
InpMagicNumber               = 20260911
InpComment                   = "Predict-A-Trade v4"
```

---

# PHASE 2 — TP/SL METHODOLOGY ENFORCEMENT

## 2.1 The rule (implement and document exactly this)

> **Target DISTANCE = fixed ATR multiple (volatility-adjusted).**
> **Target VOLUME SPLIT = decimal percentage fraction of position size.**
> Never fixed points. Never a percentage of gold price. Never fixed lots.

| Concern | Method | Format | Example |
|---|---|---|---|
| Where TP/SL sits | ATR multiple | decimal multiple | `0.40` = 0.40 × ATR |
| How much closes there | % of position volume | decimal fraction | `0.75` = **75%** |
| Minimum viability | absolute money in **account currency** | currency amount | `0.30` |

**Rationale to embed in docs:**
- Gold M1 ATR swings from ~30 pts (Sydney/Tokyo) to ~150 pts (London/NY). Fixed points are too wide in Asia and too tight in NY.
- A % of price is nonsense at scalp scale: 0.05% of 3400 = **170 points** = swing trade.
- Because SL is ATR-based, ATR-based TP keeps R:R stable:
  - TP1 `0.40 / 0.80` = **0.50R**
  - TP2 `0.75 / 0.80` = **0.94R**
  - TP3 `1.15 / 0.80` = **1.44R**
- `InpMaxCostToTP1Pct = 40` only behaves correctly if TP1 scales with volatility.

## 2.2 Percentage-input validation (add a hard guard)

`InpTP1Pct`, `InpTP2Pct`, `InpTP3Pct` are **decimal fractions**, not whole percentages.

Add to `OnInit`:
- If any `Pct` input is `> 1.0`, treat it as a misconfiguration.
  - If all three are in the range `(1.0, 100.0]` **and** sum to `100 ± 0.5`, auto-divide by 100 and log a loud warning.
  - Otherwise `return INIT_PARAMETERS_INCORRECT` with an explicit message.
- Validate `|TP1Pct + TP2Pct + TP3Pct − 1.0| <= 0.001`, else `INIT_PARAMETERS_INCORRECT`.
- Validate each `Pct > 0` when `InpUseThreeTargets = true`.

## 2.3 Simple-mode hardcoded TP/SL alignment

Inspect `TryArm()` simple-mode branch, `ScalpTarget1()`, `ScalpStopDistance()`.

**Current (approx.) hardcoded profile:**
```
Normal TP1 = 0.55 ATR
Normal TP2 = 0.95 ATR total
Normal TP3 = 1.40 ATR total
Normal SL  = 0.90 ATR
Reversion SL = 0.50 ATR beyond extreme
London breakout SL = 1.00 ATR
```

**Replace effective distances with:**
```
Normal TP1 = 0.40 ATR
Normal TP2 = 0.75 ATR total
Normal TP3 = 1.15 ATR total
Normal SL  = 0.80 ATR
Reversion SL = 0.45 ATR beyond extreme
London breakout SL = 0.85 ATR
```

Rules:
- Replace **only** these numeric multipliers.
- Preserve all existing normalization, direction handling, spread/cost checks, and signal-specific target behaviour.
- Expose the new constants as named `const double` (e.g. `SCALP_TP1_ATR`) at the top of the module, with a comment linking them to the complex-mode input equivalents.
- **If** the source already honours `InpTP1_ATR_*`, `InpTP2_ATR_*`, `InpTP3_ATR_*`, and `InpSL_ATR_Multiplier` in simple mode, **skip this replacement** and only ensure the `.set` uses the Phase 1 values. Record which branch you took in the audit.

## 2.4 TP1 minimum-viability guard (spread-aware)

Before accepting TP1:
```
minTP1Distance = MAX(
    SYMBOL_TRADE_STOPS_LEVEL * point + InpStopLevelBufferPoints * point,
    (currentSpread + expectedSlippage) * point * InpTP1SpreadMultiple
)
```
- Add input `InpTP1SpreadMultiple = 2.0`.
- If the ATR-derived TP1 is closer than `minTP1Distance`, **reject the trade** (do not silently widen TP1 beyond `InpTP1_ATR_Cap`). Log reason `TP1_TOO_TIGHT`.

## 2.5 **Lot-ladder feasibility** (critical, previously missing)

A 3-leg ladder is impossible when the position is too small.

Add `LadderPlan` computation before order send:

```
volMin  = SYMBOL_VOLUME_MIN
volStep = SYMBOL_VOLUME_STEP
lot     = risk-derived lot

leg1 = RoundDownToStep(lot * InpTP1Pct)
leg2 = RoundDownToStep(lot * InpTP2Pct)
leg3 = lot - leg1 - leg2   // remainder carries rounding error
```

Feasibility rules:
- Every leg used must be `>= volMin` and a multiple of `volStep`.
- Every **residual after a partial close** must also be `>= volMin` (a broker will reject a close that leaves a sub-minimum remainder).

New inputs:
```
InpAutoDegradeTPLadder       = true
InpLadderRoundingMode        = LADDER_FAVOR_TP1     // enum: LADDER_FAVOR_TP1 | LADDER_FAVOR_RUNNER | LADDER_PROPORTIONAL
InpTP1SpreadMultiple         = 2.0
```

Degradation cascade when 3 legs are infeasible:
1. **3-leg** → if invalid →
2. **2-leg** (`TP1Pct` renormalized against `TP2Pct+TP3Pct`, exit at TP1 then TP2) → if invalid →
3. **1-leg** (single TP at the volume-weighted blended target, default TP1) → if invalid →
4. **Reject trade**, log `LADDER_INFEASIBLE`.

Log the chosen plan on every entry: `LADDER=3LEG 0.03/0.01/0.01` etc.

Document explicitly: at `volMin = 0.01`, a 3-leg 75/20/5 ladder needs at least **0.20 lots** for exact proportions; below that the EA degrades. Add this to the docs with a table for 0.01–0.50 lot sizes.

## 2.6 Recommended split (document as the default)

```
InpTP1Pct = 0.75   // 75% banked at TP1 — covers cost, locks micro-profit
InpTP2Pct = 0.20   // 20%
InpTP3Pct = 0.05   //  5% runner, trailed by InpTP3TrailATR
```
Document `0.75 / 0.15 / 0.10` as the acceptable alternative for a larger runner, and state that 75/20/5 is the stricter capital-protection choice given `InpMaxTradeMinutes = 10`.

---

# PHASE 3 — HTF SUPPORT & RESISTANCE MODULE (ADDITIVE)

## 3.1 Context

The EA currently has **no standalone S/R layer**. S/R exists only implicitly via `DetectSMC()` swing high/low, `NearestLiquidityTarget()` TP snapping, BOS/CHoCH/sweeps, FVG/IFVG/PTB, VWAP ±1σ, Bollinger bands, and the TP3 structure trail.

Missing: multi-timeframe levels, zone thickness, touch counting, strength scoring, round numbers, prior day/week/session levels, confluence scoring, S/R proximity gating, S/R-aware stops in simple mode.

## 3.2 Hard constraints

1. Additive. With `InpUseSRZones = false`, behaviour is **bit-identical** and per-tick CPU cost is zero.
2. **SR must never generate an entry signal.** It may only filter, score, snap targets, refine stops, refine trailing, and display.
3. SR must never increase risk. A wider SR stop forces lot recomputation; if that fails validation, revert to the base stop.
4. Any SR-adjusted TP must re-pass `InpMaxCostToTP1Pct`, all `InpMinNetProfitTP*Money` gates, broker stop level and freeze level. On failure, revert.
5. Never move a stop against an open position.

## 3.3 File layout

- If includes exist: `Include/PredictATrade/SRZones.mqh`.
- Else: one contiguous block delimited by
  `//================ SR MODULE BEGIN ================` / `//================ SR MODULE END ==================`
- All inputs in group `"=== SUPPORT & RESISTANCE (HTF ZONES) ==="`.

## 3.4 Data model

```mql5
enum ENUM_SR_MODE
{
   SR_ADVISORY    = 0,   // score + display only, never blocks
   SR_SOFT_FILTER = 1,   // blocks entries into strong opposing walls
   SR_HARD_FILTER = 2    // additionally requires TP1 headroom
};

enum ENUM_SR_SRC
{
   SRSRC_PIVOT     = 1,
   SRSRC_PREVDAY   = 2,
   SRSRC_PREVWEEK  = 4,
   SRSRC_SESSION   = 8,
   SRSRC_ROUND     = 16,
   SRSRC_DAILYOPEN = 32,
   SRSRC_FVG       = 64,
   SRSRC_IFVG      = 128,
   SRSRC_PTB       = 256,
   SRSRC_VWAP      = 512
};

struct SRZone
{
   double   lower, upper, anchor;
   int      side;          // +1 resistance (above), -1 support (below)
   double   strength, rawStrength;
   int      touches, rejections, breaks;
   bool     broken, fresh;
   datetime lastTouch, created;
   int      tfMask, srcMask;
};
```

Fixed-size static array capped by `InpSRMaxTotalZones`. **No dynamic reallocation per tick.**

## 3.5 Inputs (exact names and defaults)

**Master**
```
InpUseSRZones                = true
InpSRMode                    = SR_SOFT_FILTER
InpSRRefreshSeconds          = 15
InpSRRebuildOnNewHTFBar      = true
```

**Timeframes / history**
```
InpSR_TF1 = PERIOD_M15    InpSR_BarsTF1 = 300
InpSR_TF2 = PERIOD_H1     InpSR_BarsTF2 = 300
InpSR_TF3 = PERIOD_H4     InpSR_BarsTF3 = 240
InpSR_TF4 = PERIOD_D1     InpSR_BarsTF4 = 90
InpSRFractalLeft  = 2
InpSRFractalRight = 2
```

**Level sources**
```
InpSRUsePivotSwings   = true
InpSRUsePrevDayHL     = true
InpSRUsePrevWeekHL    = true
InpSRUseSessionHL     = true
InpSRUseDailyOpen     = true
InpSRUseRoundNumbers  = true
InpSRRoundStepUSD     = 10.0
InpSRRoundSubStepUSD  = 5.0
InpSRRoundMaxLevels   = 6
InpSRUseFVGConfluence = true
InpSRUseVWAPConfluence= false
```

**Zone geometry**
```
InpSRZoneATRTF        = PERIOD_M15
InpSRZoneThicknessATR = 0.35
InpSRZoneMinPoints    = 20
InpSRZoneMaxPoints    = 150
InpSRMergeOverlapATR  = 0.25
InpSRMaxZonesPerSide  = 6
InpSRMaxTotalZones    = 24
InpSRMaxDistanceATR   = 12.0
```

**Strength scoring**
```
InpSRTouchToleranceATR   = 0.20
InpSRMinTouches          = 1
InpSRWeightTouch         = 1.00
InpSRWeightRejection     = 0.50
InpSRWeightTF_M15        = 1.00
InpSRWeightTF_H1         = 2.00
InpSRWeightTF_H4         = 3.00
InpSRWeightTF_D1         = 4.00
InpSRWeightPrevDay       = 2.00
InpSRWeightPrevWeek      = 2.50
InpSRWeightSession       = 1.50
InpSRWeightRound         = 1.00
InpSRWeightDailyOpen     = 1.00
InpSRWeightFVG           = 1.00
InpSRWeightVWAP          = 1.00
InpSRFreshBonus          = 0.50
InpSRBreakPenalty        = 1.50
InpSRRecencyHalfLifeBars = 400
InpSRMinStrengthToUse    = 3.00
```

**Entry gating**
```
InpSRWallMinStrength     = 5.00
InpSRBlockIntoWallATR    = 0.45
InpSRRequireHeadroomTP1  = true
InpSRHeadroomFactor      = 1.10
InpSRAllowBreakoutThrough= true
InpSRBreakoutBufferATR   = 0.15
InpSRScoreBonus          = 1
InpSRScorePenalty        = 1
```

**Exit integration**
```
InpSRSnapTP              = true
InpSRSnapTPMaxShiftATR   = 0.25
InpSRTPFrontRunPoints    = 8
InpSRSLBehindZone        = true
InpSRSLBufferATR         = 0.10
InpSRSLMaxExtraATR       = 0.30
InpSRTrailUseZones       = true
```

**Display / logging**
```
InpSRDrawZones        = true
InpSRMaxDrawZones     = 12
InpSRColorResistance  = clrIndianRed
InpSRColorSupport     = clrMediumSeaGreen
InpSRColorBroken      = clrDimGray
InpSRZoneFill         = true
InpSRShowLabels       = true
InpSRShowOnPanel      = true
InpSRLogLevels        = true
InpSRLogEveryNSeconds = 300
InpSRObjPrefix        = "PAT_SR_"
```

## 3.6 Functions

**Lifecycle:** `SR_Init()`, `SR_Deinit()`, `SR_Reset()`, `SR_Rebuild(bool force=false)`

**Collection:** `SR_CollectPivots(tf,bars,tfWeight)`, `SR_CollectPrevDayHL()`, `SR_CollectPrevWeekHL()`, `SR_CollectSessionHL()`, `SR_CollectDailyOpen()`, `SR_CollectRoundNumbers(price,atr)`, `SR_CollectStructureConfluence()`

**Processing:** `SR_MergeZones(atr)`, `SR_CountTouches(atr)`, `SR_ApplyRecencyDecay()`, `SR_ScoreZones(atr)`, `SR_ClassifySides(price)`, `SR_PruneWeakAndDistant(price,atr)`

**Queries (O(n), no `CopyRates`):** `SR_NearestAbove(...)`, `SR_NearestBelow(...)`, `SR_HeadroomPrice(dir,entry,minStrength)`, `SR_HeadroomATR(...)`, `SR_PriceInsideZone(price,&idx)`, `SR_BreakoutConfirmed(dir,atr)`

**Decisions:** `SR_EntryAllowed(dir,entry,atr,tp1Distance,&reason)`, `SR_DirectionalVote(dir,entry,atr)`, `SR_AdjustTP(dir,entry,tpIn,atr,legIndex)`, `SR_AdjustSL(dir,entry,slIn,atr)`, `SR_TrailAnchor(dir,atr)`

**Presentation:** `SR_Draw()`, `SR_ClearObjects()`, `SR_PanelLine1()`, `SR_PanelLine2()`, `SR_LogSnapshot()`, `SR_SelfTest()`

## 3.7 Algorithm spec

**Rebuild trigger** — forced, OR `InpSRRefreshSeconds` elapsed, OR new bar on any enabled SR TF. Max once per tick. Time with `GetMicrosecondCount()`; throttled warning if a rebuild exceeds **20 000 µs**.

**Pivots** — one `CopyRates` per TF per rebuild. Pivot high at `i` requires `high[i] >= ` highs of previous `InpSRFractalLeft` and next `InpSRFractalRight` bars; mirror for lows. Skip index 0. Insufficient history → skip TF silently (log once per session).

**Thickness** —
```
thickness = clamp(InpSRZoneThicknessATR * ATR(InpSRZoneATRTF),
                  InpSRZoneMinPoints * _Point,
                  InpSRZoneMaxPoints * _Point)
lower = anchor - thickness/2 ; upper = anchor + thickness/2   (normalized)
```

**Merging** — merge on edge overlap OR anchors within `InpSRMergeOverlapATR * ATR`. Merged: anchor = strength-weighted mean; `lower = min`, `upper = max`; touches/rejections summed; `breaks = max`; masks OR'd; same-TF contribution capped at 2×; `created = earliest`, `lastTouch = latest`. Repeat until stable, max 3 passes.

**Touch counting** — over the last `max(InpSR_BarsTF1, 500)` M1 bars, with `tol = InpSRTouchToleranceATR * ATR`:
- *Touch*: bar high enters `[lower-tol, upper+tol]` (resistance) / bar low equivalent (support).
- *Rejection*: touch that closes back outside in the opposing direction.
- *Break*: close fully beyond the zone by `> InpSRBreakoutBufferATR * ATR`.
- Consecutive touches within 3 bars count once.
- `broken = (breaks >= 1 && lastBreak > lastRejection)`.

**Scoring** —
```
rawStrength = InpSRWeightTouch*touches
            + InpSRWeightRejection*rejections
            + Σ(timeframe weights from tfMask)
            + Σ(source weights from srcMask)
            + (fresh ? InpSRFreshBonus : 0)
            - InpSRBreakPenalty*breaks

strength = max(0, rawStrength * pow(0.5, barsSinceLastTouch / InpSRRecencyHalfLifeBars))
```
A broken zone keeps at most **50%** strength and may flip side (broken resistance → support) **only** if it has ≥1 post-break rejection.

**Pruning** — drop if `strength < InpSRMinStrengthToUse`, or `touches < InpSRMinTouches` with `srcMask == SRSRC_ROUND` only, or distance `> InpSRMaxDistanceATR * ATR`. Keep strongest `InpSRMaxZonesPerSide` per side, never exceed `InpSRMaxTotalZones`.

**Entry gate (`SR_EntryAllowed`)**
- `SR_ADVISORY` → always `true`, still fills `reason`.
- `SR_SOFT_FILTER` → `false` if an opposing zone with `strength >= InpSRWallMinStrength` has its near edge within `InpSRBlockIntoWallATR * ATR` of entry — **unless** `InpSRAllowBreakoutThrough && SR_BreakoutConfirmed(dir,atr)`.
- `SR_HARD_FILTER` → the above **plus** `headroom >= tp1Distance * InpSRHeadroomFactor`.
- Reasons are machine-parsable: `SR_OK`, `SR_WALL_5.8@0.31A`, `SR_NO_HEADROOM`.
- Never block when no qualifying zone exists, when `ATR <= 0`, or on missing data.

**TP adjustment (`SR_AdjustTP`)** — buy: `candidate = zone.lower - InpSRTPFrontRunPoints*_Point`; sell mirrors. Accept only if shift `<= InpSRSnapTPMaxShiftATR * ATR`, beyond stop/freeze distance, leg still passes its net-profit gate (and `InpMaxCostToTP1Pct` for leg 1), and monotonic ordering holds (buys `t1<t2<t3`, sells `t1>t2>t3`). Runs **after** `NearestLiquidityTarget()`; on conflict prefer the higher-strength SR zone when strengths are comparable, else the closer valid target.

**SL adjustment (`SR_AdjustSL`)** — only when `InpSRSLBehindZone`. Move stop behind the zone by `InpSRSLBufferATR * ATR`. Reject if wider than base by `> InpSRSLMaxExtraATR * ATR`, if it violates stop/freeze level, or if the identical-risk lot recomputation is invalid. Never tighten inside the entry-candle extreme used by simple mode. **Recompute lot before order send after any accepted widening.**

**Trailing** — when `InpSRTrailUseZones` and the TP3 runner is live, feed `SR_TrailAnchor()` as an additional candidate to the existing TP3 structure trail; pick the more conservative anchor; respect `InpTP3TrailATR` / `InpTP3TrailStepATR`; strictly monotonic.

**Complex-mode vote** — when `InpSimpleScalpMode = false` and `InpFilterMode = FILTER_SCORING`, add `SR_DirectionalVote()` to the score. It must **never** be able to satisfy `InpMinFilterScore` alone. Document this.

## 3.8 Integration points (mark every edit `// [SR]`)

1. `OnInit` → `SR_Init()` after indicator handles exist.
2. `OnDeinit` → `SR_Deinit()` before existing cleanup.
3. `OnTick` → `SR_Rebuild()` after state refresh, before signal evaluation.
4. Entry path (`CanEnter` / `TryArm` simple-mode branch) → `SR_EntryAllowed()` immediately before dispatch, **after** all existing cost/spread/session/news gates.
5. Targets → `SR_AdjustTP()` on `t1/t2/t3` in both the simple-mode branch and `BuildThreeTargets()`, then re-run existing validation.
6. Stops → `SR_AdjustSL()` on the simple-mode stop and `ComputeSL()`, then recompute lot.
7. TP3 trail → integrate `SR_TrailAnchor()`.
8. Dashboard → two rows from `SR_PanelLine1()/2()` when `InpSRShowOnPanel`; respect `InpDashRefreshMs` and the two-column layout.
9. CSV → append **at the end only**: `sr_mode, sr_zone_count, sr_up_price, sr_up_strength, sr_up_dist_atr, sr_dn_price, sr_dn_strength, sr_dn_dist_atr, sr_tp_snapped, sr_sl_shifted, sr_block_reason`. Update the header writer.

## 3.9 Performance & safety

- No `CopyRates`/`iCustom` in hot paths; all history reads inside `SR_Rebuild()`.
- Static buffers only; no per-tick resizing.
- Guard every division by ATR, point, tick size, bar count.
- Handle `ATR <= 0`, insufficient bars, unsynced history, `CopyRates == -1` by skipping the source without log spam.
- Objects: created once, updated in place, prefixed `InpSRObjPrefix`, `OBJPROP_BACK=true`, `OBJPROP_SELECTABLE=false`, `OBJPROP_HIDDEN=true`. `ChartRedraw` throttled to `InpDashRefreshMs`.
- Skip all drawing when `MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)`.
- `SR_Deinit()` removes **every** created object, including on parameter change and chart close.
- Target < ~2 ms per rebuild; throttled warning otherwise.

---

# PHASE 4 — PRO-TRADER HARDENING (previously unconsidered)

Everything in this phase is **default-safe** and must be individually switchable.

## 4.1 Symbol & broker auto-adaptation

```
InpSymbolOverride            = ""        // blank = use chart symbol
InpAutoScaleForDigits        = true      // 2 vs 3-digit gold point scaling
InpRespectStopLevel          = true
InpStopLevelBufferPoints     = 5
InpRespectFreezeLevel        = true
InpFillPolicy                = FILL_AUTO // FILL_AUTO | FILL_FOK | FILL_IOC | FILL_RETURN
InpValidateSymbolOnInit      = true
```

On `OnInit`, read and cache:
`SYMBOL_DIGITS`, `SYMBOL_POINT`, `SYMBOL_TRADE_TICK_SIZE`, `SYMBOL_TRADE_TICK_VALUE`, `SYMBOL_TRADE_CONTRACT_SIZE`, `SYMBOL_VOLUME_MIN/MAX/STEP`, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL`, `SYMBOL_FILLING_MODE`, `SYMBOL_TRADE_MODE`, `SYMBOL_TRADE_EXEMODE`, `SYMBOL_MARGIN_MODE`, `SYMBOL_SWAP_MODE`, `SYMBOL_SWAP_ROLLOVER3DAYS`.

- Reject init if `SYMBOL_TRADE_MODE != SYMBOL_TRADE_MODE_FULL`.
- Auto-scale all point-based inputs (`InpMaxSpreadPoints`, `InpMinATRPoints`, `InpMaxATRPoints`, slippage, `InpSRZoneMin/MaxPoints`, `InpSRTPFrontRunPoints`, `InpStopLevelBufferPoints`) by `10×` when gold quotes 3 digits vs 2. Log the applied factor once.
- Select the filling mode actually supported by the symbol; do not hardcode FOK.
- Print a **BROKER PROFILE** block at init: digits, point, tick value, contract size, min/step lot, stops level, freeze level, spread now/avg, swap long/short, commission source (learned vs fallback).

## 4.2 Account mode — **netting vs hedging** (critical, previously unconsidered)

`InpMaxConcurrentPositions = 3` is **impossible on a netting account** — MT5 merges same-symbol positions and partial closes behave differently.

```
InpNettingModeAction         = NETTING_REDUCE_TO_ONE   // NETTING_BLOCK | NETTING_REDUCE_TO_ONE
InpFIFOCompliance            = false                   // true for US brokers
```

On init, read `ACCOUNT_MARGIN_MODE`:
- `RETAIL_HEDGING` → full functionality.
- `RETAIL_NETTING` / `EXCHANGE`:
  - If `NETTING_BLOCK` → `INIT_FAILED` with a clear message.
  - If `NETTING_REDUCE_TO_ONE` → force `MaxConcurrentPositions = 1`, disable multi-position aggregate logic, and warn loudly on the panel and in the log.
- If `InpFIFOCompliance = true`, close positions in strict FIFO order and disable partial closes that would violate FIFO; degrade the ladder accordingly.

## 4.3 Order execution robustness

```
InpMaxLatencyMs              = 350
InpStaleTickMs               = 2500
InpMaxPriceDriftPoints       = 12
InpRetryBackoffMs            = 250
InpEnforceSingleInstance     = true
```

- Measure and log `OrderSend` round-trip latency; block new entries if the rolling average exceeds `InpMaxLatencyMs` (with a cooldown).
- Reject entry if the last tick is older than `InpStaleTickMs`.
- Re-read the current Ask/Bid immediately before send; if price drifted more than `InpMaxPriceDriftPoints` from the signal price, **abort** (do not chase). Log `PRICE_DRIFT`.
- Use correct side pricing everywhere: **Buy entries/TP compare against Ask; SL against Bid** (and mirrored for sells). Audit and fix any place using a single price for both.
- Implement an explicit `retcode` handler with backoff for: `TRADE_RETCODE_REQUOTE`, `PRICE_CHANGED`, `PRICE_OFF`, `TIMEOUT`, `CONNECTION`, `TOO_MANY_REQUESTS`, `INVALID_STOPS`, `INVALID_VOLUME`, `NO_MONEY`, `MARKET_CLOSED`, `TRADE_DISABLED`. Non-retryable codes must abort immediately, not loop.
- `InpEnforceSingleInstance`: on init, scan for another EA instance using the same `InpMagicNumber` on the same symbol; if found, `INIT_FAILED`.
- Verify free margin **and** projected margin (`OrderCalcMargin`) before every send.

## 4.4 Money & currency correctness

```
InpMoneyGatesCurrency        = MONEY_ACCOUNT_CCY  // MONEY_ACCOUNT_CCY | MONEY_USD
InpAutoConvertMoneyGates     = true
```

`InpMinNetProfitTP1/2/3Money` and `InpDisableExpectancyMoney` are currently implicitly USD. If the account currency is not USD and `InpAutoConvertMoneyGates = true`, convert via the broker's conversion pair and log the applied rate. All P&L math must use `OrderCalcProfit` / tick value, never a hardcoded `$1 per point`.

## 4.5 True consecutive-loss pause (previously identified gap)

The current code only decays risk `×0.70` per loss; it never actually stops.

```
InpConsecLossPauseMinutes    = 30
InpConsecLossPauseEnabled    = true
InpMaxLossesPerSession       = 3
InpDailyProfitTargetPct      = 3.0
InpStopAfterDailyTarget      = true
```

- When consecutive losses reach `InpMaxConsecutiveLosses`, **hard-pause arming** for `InpConsecLossPauseMinutes`, reset the counter on the first win or after the pause expires. Surface `PAUSED (consec loss) mm:ss` on the panel.
- Track losses per session window; block that window after `InpMaxLossesPerSession`.
- When daily realized P&L reaches `+InpDailyProfitTargetPct` and `InpStopAfterDailyTarget = true`, stop opening new trades for the day (continue managing open positions). Log `DAILY_TARGET_REACHED`.

## 4.6 Risk accounting & prop-firm compliance

```
InpPropFirmMode              = false
InpPropDailyLossBasis        = PROP_BASIS_BALANCE_START  // PROP_BASIS_BALANCE_START | PROP_BASIS_EQUITY_PEAK
InpPropMaxTrailingDDPct      = 5.0
InpPropConsistencyMaxDayPct  = 40.0
InpDetectDepositWithdrawal   = true
InpEquityBaselineResetHour   = 0.0
```

- Daily loss must be measured against an explicit, persisted **day-start baseline**, not "whatever equity was when the EA started".
- `InpDetectDepositWithdrawal`: scan deal history for `DEAL_TYPE_BALANCE` / `DEAL_TYPE_CREDIT` and adjust baselines so a deposit doesn't mask a drawdown and a withdrawal doesn't fake one.
- `InpPropFirmMode = true` additionally enforces a **trailing max drawdown** from the equity high-water mark and warns when a single day exceeds `InpPropConsistencyMaxDayPct` of cumulative profit.
- Include **floating** P&L in the daily-loss calculation when `InpPropDailyLossBasis = PROP_BASIS_EQUITY_PEAK`.

## 4.7 Restart, reconciliation & state integrity

```
InpReconcileOnInit           = true
InpAdoptOrphanPositions      = true
InpStateChecksum             = true
InpStateSchemaVersion        = 4
```

- On `OnInit`, enumerate all live positions/orders matching `InpMagicNumber` + symbol and **rebuild internal trade state** (entry price, original SL, ladder progress, TP1-hit flag, BE status, trade open time).
- `InpAdoptOrphanPositions`: adopt matching positions found without state (VPS reboot, crash). If a position cannot be safely reconstructed, place a protective SL and mark it `MANAGED_MINIMAL` (time-stop + BE only, no ladder).
- State file: write **versioned** with a checksum. On mismatch or schema change, discard and rebuild from the terminal rather than loading corrupt values. Never load a state file from a different account number, symbol, or magic.
- Use `OnTradeTransaction` for authoritative fill/partial-close accounting; do not rely on `OnTick` polling alone.

## 4.8 Time, calendar, and gold-specific events

```
InpUseHolidayFilter          = true
InpHolidayDatesCSV           = "12-24,12-25,12-26,12-31,01-01,01-02"
InpUseLondonFixFilter        = true
InpLondonFixBufferMin        = 3
InpBlockTripleSwapDay        = true
InpWeekendGapGuardMinutes    = 120
InpMondayOpenDelayMinutes    = 15
InpValidateServerOffsetOnInit= true
```

- **Holiday filter**: block trading on the listed `MM-DD` dates (thin liquidity, wide spreads).
- **London Fix**: block `InpLondonFixBufferMin` minutes around **10:30** and **15:00 London time** (DST-aware) — gold's two daily auction prints cause violent, unscalpable spikes.
- **Triple-swap day**: respect `SYMBOL_SWAP_ROLLOVER3DAYS`; extend the swap block window on that weekday.
- **Weekend gap guard**: block entries for `InpWeekendGapGuardMinutes` after the Sunday/Monday open, and `InpMondayOpenDelayMinutes` before normal operation resumes.
- **Server offset validation**: cross-check `InpManualServerOffsetHours` against `TimeGMT()` vs `TimeCurrent()`; if the delta disagrees by more than 1 hour, log a **loud** warning and prefer the auto-detected value when `InpAutoDetectServerOffset = true`.
- Handle US vs EU DST transitions independently (they do not switch on the same dates).

## 4.9 News & external-data resilience

```
InpCalendarSource            = CAL_AUTO      // CAL_MQL5 | CAL_FMP | CAL_BOTH | CAL_AUTO
InpCalendarFailAction        = CALFAIL_TRADE_ON  // CALFAIL_TRADE_ON | CALFAIL_BLOCK
InpTesterNewsFallback        = true
InpFMPMaxConsecutiveFailures = 5
```

- The MQL5 economic calendar is **unavailable in the Strategy Tester**. When `MQL_TESTER` is true and `InpTesterNewsFallback = true`, fall back to a static high-impact schedule (NFP: first Friday 13:30 UTC; CPI/FOMC approximations) so backtests are not unrealistically optimistic. Document that tester news filtering is approximate.
- After `InpFMPMaxConsecutiveFailures`, disable FMP for `InpFMPRefreshSec × 5` and fall back to broker macro. Never block trading purely because FMP is down (`InpRequireExternalData = false`).
- Never place an API key in a public commit; read it from an input and mask it in all logs.
- Ensure `WebRequest` is fully non-blocking-safe: never call it inside `OnTick`'s critical path — move it to `OnTimer`.

## 4.10 Kill switch, alerts & manual control

```
InpKillSwitchFile            = "PAT_KILL.txt"
InpKillSwitchCheckSec        = 5
InpEnablePushAlerts          = true
InpAlertOnBreaker            = true
InpAlertOnDisorder           = true
InpAlertOnReconnect          = true
InpHeartbeatMinutes          = 15
```

- If `MQL5/Files/<InpKillSwitchFile>` exists → immediately stop new entries; if it contains the word `FLAT`, also close all positions. Panel shows `KILL SWITCH ACTIVE`.
- Push/email alerts on breaker trips, disorder cooldowns, extreme slippage, terminal reconnect, and daily-target stop.
- Heartbeat message every `InpHeartbeatMinutes` confirming the EA is alive (essential for unattended VPS).
- Panel must expose read-only status for: kill switch, pause reason, remaining daily risk budget, remaining trades today, consecutive-loss pause timer, SR block state, netting warning.

## 4.11 Telemetry, analytics & journaling

```
InpTrackMAEMFE               = true
InpLogRMultiple              = true
InpJSONLog                   = false
InpTelemetryFlushSec         = 30
InpTagTradesWithContext      = true
```

Per closed trade, record: signal mode (A/A2/B/C/D), session window, HV flag, SR context, entry/exit prices, spread at entry, realized slippage, commission, swap, **MAE, MFE, R-multiple**, ladder plan used, time-in-trade, and exit reason (TP1/TP2/TP3/SL/BE/time-stop/breaker/disorder).

Maintain and display a rolling **expectancy matrix** keyed by `session × signal mode × SR context` so weak combinations can be gated by the existing performance-gating engine. Write CSV always; write JSON when `InpJSONLog = true`.

## 4.12 Performance, memory & leaks

```
InpMaxOnTickMicros           = 3000
InpProfileHotPaths           = false
```

- Release **every** indicator handle in `OnDeinit`; assert no handle leak on `REASON_PARAMETERS` re-init.
- Delete every chart object created by the EA (dashboard + SR) on deinit; verify `ObjectsTotal(prefix) == 0`.
- Profile `OnTick` when `InpProfileHotPaths = true`; log a throttled warning above `InpMaxOnTickMicros`.
- No `Sleep()` in `OnTick`. No blocking calls in the tick path.
- Bound every loop; no unbounded `while`.

## 4.13 Self-test harness

```
InpRunSelfTestOnInit         = true
```

`SelfTest()` must validate and print PASS/FAIL for:
1. All `Pct` inputs sum to 1.0 and are fractions.
2. TP ordering monotonic for both directions.
3. Lot ladder feasible at min lot, 0.02, 0.05, 0.10, 0.50, and `InpMaxTotalLots`.
4. Risk math: for a known ATR/SL, computed lot risks exactly `InpRiskPercent` (±1 tick).
5. Point scaling correct for 2-digit and 3-digit gold.
6. Stop/freeze-level compliance for TP1 at minimum ATR.
7. SR module returns sane results with zero zones, one zone, and `InpSRMaxTotalZones` zones.
8. `SR_EntryAllowed` never blocks in `SR_ADVISORY` mode.
9. Netting/hedging detection reports the correct mode.
10. Money-gate currency conversion round-trips correctly.

`INIT_FAILED` only on category 1–4 failures; warn on the rest.

---

# PHASE 5 — VALIDATION & BACKTEST PROTOCOL

Produce `docs/05_Validation_Protocol.md` specifying:

**Tester configuration**
- Model: **Every tick based on real ticks**, ≥ 99% quality.
- Symbol: broker's actual gold symbol; **real variable spread**, not fixed.
- Include commission and swap in the tester symbol settings.
- Minimum 6 months, ideally 12–24 months of M1 data spanning at least one high-volatility regime.

**Required runs**
| Run | Purpose |
|---|---|
| A | `InpUseSRZones = false` — baseline, must match pre-change build trade-for-trade |
| B | `InpUseSRZones = true`, `InpSRMode = SR_ADVISORY` — entry count unchanged vs A |
| C | `InpUseSRZones = true`, `InpSRMode = SR_SOFT_FILTER` — production candidate |
| D | `InpSRMode = SR_HARD_FILTER` — sensitivity check |

**Robustness checks**
- Walk-forward: 70% in-sample / 30% out-of-sample, rolled at least 3 times.
- Parameter sensitivity: ±20% on `InpSL_ATR_Multiplier`, `InpScalpMinMomentumATR`, `InpMaxSpreadPoints`, `InpSRWallMinStrength`. Performance must degrade **smoothly**; a cliff indicates overfitting.
- Spread stress: rerun with spread ×1.5 and ×2.0 — a true scalp edge must survive ×1.5.
- Commission stress: `InpCommissionPerLotRTFallback` at 7 / 10 / 14.
- Monte Carlo: 1000 trade-order shuffles → report median and 5th-percentile max drawdown.
- Per-session and per-signal-mode breakdown (expectancy, PF, win rate, avg R).

**Reporting metrics** — net profit, profit factor, expectancy per trade ($ and R), max DD (% and $), longest losing streak, average time-in-trade, TP1/TP2/TP3 hit rates, SL hit rate, time-stop rate, average realized slippage, cost as % of gross profit.

**Go-live gate** — no live capital until Run C shows: profit factor ≥ 1.25 out-of-sample, max DD ≤ 10%, ≥ 200 trades, cost ≤ 40% of gross profit, and **2–4 weeks of forward demo on the live broker feed** matching backtest expectancy within 30%.

---

## DELIVERABLES

### Code
1. Phase 2 TP/SL alignment + `Pct` validation + lot-ladder feasibility.
2. Phase 3 SR module (`SRZones.mqh` or delimited block) + integration points, each marked `// [SR]`.
3. Phase 4 hardening modules, each behind its own switch.
4. Version stamp bumped; `#property version` updated.

### Presets (`presets/`)
| File | Purpose |
|---|---|
| `XAUUSD_M1_UltraScalp.set` | Production: all Phase 1 values + SR on (`SR_SOFT_FILTER`) + Phase 4 defaults |
| `XAUUSD_M1_UltraScalp_SR_Off.set` | Identical but `InpUseSRZones = false` — A/B baseline |
| `XAUUSD_M1_UltraScalp_Advisory.set` | Identical but `InpSRMode = SR_ADVISORY` |
| `XAUUSD_M1_UltraScalp_PropFirm.set` | Production + `InpPropFirmMode = true`, `InpDailyLossPercent = 2.0`, `InpPropMaxTrailingDDPct = 4.0`, `InpMaxTradesPerDay = 15` |

Every `.set` must contain **every** input the EA declares, with correct types, and must load without "unknown parameter" errors.

### Documentation (`docs/`)
1. `00_Source_Map.md` — discovery output.
2. `XAUUSD_M1_UltraScalp_Audit.md` — per-input table: name / exists? / value applied / **effective in simple mode?** / overridden by hardcode? / notes.
3. `TP_Methodology.md` — ATR distance vs percentage volume, the `0.75/0.20/0.05` rule, the decimal-fraction warning, the R-multiple table, and the lot-ladder feasibility table for 0.01–0.50 lots.
4. `SR_Zones_Module.md` — architecture, data flow, full input reference, worked XAUUSD scoring example, integration points, explicit statement that SR never generates entries and never increases risk, known limitations.
5. `Pro_Trader_Hardening.md` — every Phase 4 subsystem, why it matters, and how to verify it.
6. `05_Validation_Protocol.md` — as above.
7. `Broker_Checklist.md` — the values the operator **must** verify before going live.
8. `CHANGELOG.md`.

### Diffs
A minimal unified diff summary per phase.

---

## BROKER-SPECIFIC WARNINGS (must appear in the audit **and** print at init)

| Input | Why it must be verified |
|---|---|
| `InpManualServerOffsetHours` | Wrong offset silently destroys every session window and the news filter |
| `InpSwapRolloverServerHour` | Must match the broker journal, not an assumption |
| `InpMaxSpreadPoints` | Depends on account type; auto-scales for 3-digit gold |
| `InpCommissionPerLotRTFallback` | Overridden by learned commission once deals exist |
| `InpExpectedSlipPtsFallback` | Overridden by the live rolling average after 5 fills |
| `InpMagicNumber` | Must be unique per EA instance per account |
| **Account margin mode** | `MaxConcurrentPositions > 1` requires a **hedging** account |
| **Symbol name** | Gold may be `XAUUSD`, `GOLD`, `XAUUSD.m`, `XAUUSDx` — verify or set `InpSymbolOverride` |
| **Filling mode** | Must match `SYMBOL_FILLING_MODE`; hardcoded FOK will fail on many ECNs |
| **Min/step lot** | Determines whether the 3-leg ladder is even possible |

---

## ACCEPTANCE CRITERIA

**Build**
- Zero compile errors, zero warnings, MQL5 strict mode.
- `SelfTest()` passes all categories 1–4 on init.

**Behavioural equivalence**
- `InpUseSRZones = false` → Strategy Tester output is **trade-for-trade identical** to the pre-change build over the same period and settings.
- `InpSRMode = SR_ADVISORY` → entry count identical to SR off; only logging, panel, and optional TP snapping differ.

**Invariants**
- `InpSimpleScalpMode = true`; `InpNoMartingale = true`; `InpNoAveragingDown = true`; `InpScaleIn = false`.
- `InpUseRecovery = true` but recovery is provably skipped in simple mode.
- `InpRequireExternalData = false`; the EA trades normally with FMP and the calendar unreachable.
- No code path can raise realized per-trade risk above `InpRiskPercent`.
- No code path can move a stop against an open position.
- `InpTP1Pct + InpTP2Pct + InpTP3Pct == 1.0` is enforced at init.

**Robustness**
- EA survives: restart mid-trade, VPS reboot, parameter change, terminal reconnect, weekend gap, missing HTF history on a fresh chart, and a netting account (with the documented degradation).
- All chart objects removed on deinit (`ObjectsTotal(prefix) == 0`).
- No indicator-handle leak across re-init.

**Presets**
- All four `.set` files load with zero unknown-parameter errors.

---

## GUARDRAILS — DO NOT

- Do **not** switch the EA to complex mode.
- Do **not** add new entry signals, trade modes, or exit strategies beyond those explicitly specified.
- Do **not** modify session open/close logic, news-window logic, or breaker logic except for the values and additions listed.
- Do **not** refactor unrelated code, rename existing inputs, or reorder existing CSV columns.
- Do **not** optimize any parameter not listed here.
- Do **not** add external dependencies, DLLs, or new network calls beyond the existing FMP adapter.
- Do **not** commit API keys, account numbers, or broker credentials.
- Do **not** silently change a default — every deviation must appear in `CHANGELOG.md`.

---

## EXECUTION ORDER

```
1. Discovery        → docs/00_Source_Map.md            → commit "chore: source map"
2. Phase 1 presets  → presets/*.set + audit skeleton   → commit "feat: ultra-scalp profile"
3. Phase 2 TP/SL    → code + TP_Methodology.md         → commit "feat: ATR TP/SL + ladder feasibility"
4. Phase 3 SR       → module + integration + docs      → commit "feat: HTF SR zones module"
5. Phase 4 hardening→ subsystems + docs                → commit "feat: pro-trader hardening"
6. Phase 5 protocol → docs + self-test results         → commit "docs: validation protocol"
```

After each commit, report: files changed, LOC added/removed, compile status, and any `MISSING` inputs discovered.