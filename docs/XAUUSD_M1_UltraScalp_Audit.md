# XAUUSD M1 UltraScalp — Code Audit

**EA:** Predict-A-Trade.mq5 · **Profile:** prompt.md "FINAL AUTHORITATIVE VALUES" (2026-09-08) · **Static check:** ALL GREEN (balance, 215/215 inputs referenced, no forbidden identifiers)

---

## 1. Deliverables

| Deliverable | Status |
|---|---|
| `presets/XAUUSD_M1_UltraScalp.set` | 215 rows, one per source input; enum values serialized as integers (BREAKER_CLOSE_ALL=1, EXEC_DIRECTIONAL=1, FILTER_SCORING=0, HV_AUTO=1, VWAP_BROKER_DAY=0, PERIOD_M5=5) |
| `docs/XAUUSD_M1_UltraScalp_Audit.md` | this file |
| Minimal source diff | applied — simple-mode TP/SL multipliers only + plan-wiring fix (§5) |

Every input name in the prompt exists in source (215/215, zero missing, zero extras).

## 2. Hardcoded simple-mode TP/SL — the mandated replacement (APPLIED)

The simple path did **not** read `InpTP*_ATR_*` or `InpSL_ATR_Multiplier`, so per the prompt the hardcoded multipliers were replaced:

| Signal | Distance | Before | After |
|---|---|---|---|
| All | TP1 (normal modes) | 0.55 ATR | **0.40 ATR** |
| All | TP2 (total) | 0.95 ATR (t1+0.40) | **0.75 ATR** |
| All | TP3 (total) | 1.40 ATR (t1+0.85) | **1.15 ATR** |
| NY momentum / EMA pullback | SL | 0.90 ATR | **0.80 ATR** |
| VWAP reversion | SL beyond extreme | 0.50 ATR | **0.45 ATR** |
| London breakout | SL | 1.00 ATR | **0.85 ATR** |

Locations: `ScalpStopDistance()` (SL), `ScalpTarget1()` (TP1), `TryArm()` (TP2/TP3). Unchanged by design: reversion TP1 still targets VWAP with the 0.6 ATR minimum (signal-specific target behavior), and all normalization / min-distance / spread-cost logic is untouched.

Implied R:R after the change: momentum ~0.50R at TP1, ~0.94R at TP2, ~1.44R at TP3; breakout 0.47 / 0.88 / 1.35; reversion improves ~0.89R→1.0R at TP1 (stop 0.45).

## 3. Plan-integrity invariant violation found and fixed

**The bug:** `TryArm()` computed the simple scalp ladder (t1/t2/t3) but only wrote it to the log. The actual market order carried broker TP = `c` from `BuildThreeTargets()` (the **complex-engine** ladder: 0.55/1.10/1.85 ATR clamped by the TP floor/cap inputs), and `AddPositionState()` rebuilt that same complex ladder for partial management. The simple-mode profile was silently overridden on every trade.

**The fix (minimal, no logic outside the listed scope):**
- `TryArm()` now sends the market order with SL = the validated scalp stop and TP = armed **t3** (catastrophe-safe final target, same convention the complex path uses), and snapshots t1/t2/t3 after a confirmed fill (`g_armTp1/2/3`, `g_armValid`).
- `AddPositionState()` consumes the snapshot when `InpSimpleScalpMode && g_armValid`: management uses the armed distances, volume split 100/0/0 (banks the whole position at TP1; a broker-min-lot remainder can still trail toward t3), then re-pins broker SL/TP to the armed values so the plan survives restarts. No snapshot (restart gap) → falls back to the previous behavior. Complex mode is byte-identical to before.

## 4. Input effectiveness in InpSimpleScalpMode=true

**Effective (read by the simple path, the OnTick loop, management, or protection):**
`InpSimpleScalpMode` · `InpScalpMinMomentumATR` (signal body floor) · `InpDailyLossPercent` · `InpMaxFloatingDDPercent` (also halves scalp risk ≥ half-limit) · `InpWeeklyLossLimit` · `InpMonthlyLossLimit` · `InpRiskStepDownOnDD` · `InpMaxConsecutiveLosses` (stats/display + halt recount) · `InpMaxTradesPerDay` · `InpAllowMinLotFallback` · `InpMinLotMaxRiskPct` · `InpMaxAggregateOpenRiskPct` · `InpMaxDirectionalRiskPct` · `InpBreakerAction` · `InpNoMartingale` · `InpNoAveragingDown` (sizing freeze) · `InpMaxSpreadPoints` (hard cap, both modes) · `InpMaxSlippagePoints` (order deviation) · `InpCommissionPerLotRTFallback` · `InpExpectedSlipPtsFallback` (cost model) · `InpMaxCostToTP1Pct` · `InpMinNetProfitTP1/2/3Money` (TP1 gate runs in simple mode) · `InpOrderRetry` · `InpExtremeSlippagePoints` (fill-quality cooldown) · `InpMaxConcurrentPositions` · `InpMaxTotalLots` · `InpArmWhileInTrade` · `InpMinSecondsBetweenEntries` (hardcoded 60s spacing also applies; the input governs fresh-structure bars) · `InpMinBarsFreshStructure` · `InpMaxSignalsPerWindow` (counter) · `InpPerWindowRiskBudgetPct` · `InpOncePerValidatedEvent` · `InpCancelStalePendings` · `InpPendingExpiryMinutes` · `InpLotSize` (only if `InpRiskPercent≤0`) · `InpUseSessionFilter` + all `InpTrade*` session/window switches · local open/close minute inputs · `InpLondonOpenWindowMin` · `InpNYOpenWindowMin` · `InpOverlapPadMinutes` · `InpFridayCutoffServer` · `InpAutoDetectServerOffset` · `InpManualServerOffsetHours` (fallback) · `InpServerOffsetRefreshSec` · `InpUseNewsFilter` · `InpNewsBufferMinutes` · `InpNewsLookaheadMin` · `InpPostNewsStabilizeMinutes` · `InpAvoidSwap` · `InpForceFlatBeforeSwap` · `InpSwapRolloverServerHour` · `InpSwapBlockMinutesBefore/After` · `InpMaxTradeMinutes` (time stop, simple mode included) · `InpUseFMP` + FMP refresh/timeout/thresholds (soft influence) · `InpAllowBrokerMacroFallback` · `InpRequireExternalData` · `InpMagicNumber` · `InpComment` · dashboard/log/persist inputs · `InpUseThreeTargets`+`InpAB_EnableThreeTP` (now honored via the armed plan; when disabled the full position runs to broker t3) · `InpUseCostAdjustedBE`+`InpBEExtraLockATR` (TP1 BE lock) · `InpTP3EarlyExit` (disorder early exit) · `InpUseTP3StructureTrail`+`InpTP3TrailATR`+`InpTP3TrailStepATR` (runner trail toward t3) · `InpSLStructureBufferATR` (trail structural bound) · `InpCloseOnExtremeSlippage` · `InpSlippageCooldownMinutes` · `InpEnablePerformanceGating` + `InpPerf*` + `InpWeakWindowRiskMultiplier` (window risk multipliers apply to scalp risk too).

**Ignored by design in simple mode** (complex engine only, retained in the .set for completeness; explicit note per prompt):
- **Recovery engine** — `TryRecovery()` returns immediately when `InpSimpleScalpMode`: **`InpUseRecovery=true` never executes recovery in simple mode** (acceptance criterion met; counter-trend "loss-chasing" legs disabled). `InpRecovery*` values are dormant.
- **RR validation** — the `RRValid` TP2/TP3 gate is complex-only; `InpMinRR_TP2/TP3` are not consulted (the scalp ladder's own R:R is a consequence of the §2 distances).
- **TP/SL ATR ladder inputs** — `InpSL_ATR_Multiplier`, `InpSLStructureBufferATR` (SL widening), `InpTP1/2/3_ATR_Floor/Cap` are not read for scalp sizing (only `InpSLStructureBufferATR` bounds the runner trail above).
- **Multi-filter machinery** — `InpFilterMode`, `InpMinFilterScore`, all `InpUse*` filter switches, `InpMinDirBias`, `InpMinSMCConfluence`, `InpMinAdvancedSMCConfluence`, lookback/coil inputs, indicator-period inputs, `InpMinADX`, `InpMin/MaxATRPoints` (only ATR-min applies via the shared pre-gate), volume/liquidity thresholds, HV qualification (`HVScore` path), `InpSpreadSpikeRatio`, `InpMaxSpreadPercentile`, `InpMaxAverageSlippagePoints`, disorder anti-chase caps, `InpVerifiedBucket*`, macro confluence voting, `InpExecutionMode`/`InpStraddleLayers`/`InpScaleIn`/`InpUseATRForDistance`/`InpATRMultiplier`/`InpDistance`/`InpLayerStepATR`/`InpLayerSpacingATR` (simple mode forces 1 market layer), `InpMinRR_TP2/TP3`, `InpTP*Pct` (superseded by the 100/0/0 split), `InpFMPNewsHardBlock` (news gate itself is shared and active), `InpEURUSD*` details, `InpMacroTF`/`InpMacroMomentumBars` (broker fallback math is shared).
- Note: `Disorder*` inputs are consulted via `IsDisorder()` in shared paths (news/recovery); the dedicated anti-chase entry gates are complex-only.

## 5. Hardcoded values that still override inputs (flagged, NOT changed)

- `CurrentRiskPct()`: scalp base risk is the literal `0.35` (matches the profile `InpRiskPercent=0.35`; in complex mode the input is read). Also `0.10` risk floor and `0.70`/`^n` consecutive-loss decay are literals.
- `EvaluateScalpSignal()`: 2σ VWAP extension, RSI 70/30, M5 ADX<35, 0.5 ATR momentum body, London window 07:00–08:15 UTC, Asian-range floor 0.8 ATR are literals — `InpScalpMinMomentumATR` is the only threshold input here.
- `TryArm()`: 60-second same-direction entry spacing (the input spacing applies to fresh structure), 0.35 ATR proximity to an open same-direction scalp.
- `CanEnter()` simple path: spread-extreme rule at hard-cap+20 points; `hv` forced false (HV engine complex-only).
- None of these conflict with the listed profile values; changing them was outside the authorized scope ("modify only those TP/SL multipliers").

## 6. Broker-specific warnings (Xelans ECN demo context)

- **`InpManualServerOffsetHours=3`** — fallback only; `InpAutoDetectServerOffset=true` derives the offset from tick timestamps. After DST transitions the auto value can be wrong for days; verify the panel's server-vs-UTC clock and correct the manual value if sessions shift. Xelans is GMT+3 year-round (no local DST), so 3 is correct today.
- **`InpSwapRolloverServerHour=0.0`** — midnight **server** time. Xelans GMT+3 keeps rollover at 00:00 server; if you ever move to a GMT/GMT+2 broker, update this or the swap-flat window protects the wrong hour.
- **`InpMaxSpreadPoints=35`** — Xelans ECN gold routinely prints 35–45 points (the source default was 45 for that reason). With 35 the EA will refuse entries during the upper half of this broker's normal spread range — intended for this profile, but expect visibly fewer trades in the Sydney/Tokyo hours. `g_ptScale` auto-handles 2-vs-3-digit feeds.
- **`InpCommissionPerLotRTFallback=7.00`** — cost model only until the EA learns the real round-turn commission from the first fills (`LearnCommission`); if your live schedule differs materially (e.g. $6 or $8 RT), sizing and the TP1 cost gate mis-estimate until ~fills accrue. The learned value then overrides the fallback automatically.
- **`InpExpectedSlipPtsFallback=3.5`** — assumed slippage in the cost model until 5+ measured fills exist. Gold ECN prints outside this during news; the fallback biases entry sizing slightly optimistic early in a session. Measured average takes over afterward.

## 7. Acceptance criteria

| Criterion | Status |
|---|---|
| .set loads without invalid-input errors | 215 names == 215 source inputs, exact match, enum ints |
| `InpSimpleScalpMode=true` | ✓ (row 1) |
| `InpNoMartingale=true` / `InpNoAveragingDown=true` | ✓ (enforced in sizing code, not just declared) |
| `InpScaleIn=false` | ✓ |
| `InpUseRecovery=true` but recovery skipped in simple mode | ✓ (`TryRecovery()` early-return) |
| `InpRequireExternalData=false` | ✓ (entry never depends on FMP/macro availability; broker EURUSD fallback optional) |
| Session open/close logic untouched | ✓ (values only) |
| Order-send logic untouched except listed values | ✓ (SL/TP values carried + plan wiring; `SendOrder` path unchanged) |
| No new filters / exit logic / mode switch | ✓ |

## 8. Verification

- `brace_check.py`: balanced (braces/parens/brackets).
- `verify_static.py`: **ALL GREEN** — balance OK, 215/215 inputs referenced ≥2×, no `#include`/CTrade-class identifiers, no credential leaks. (The script's comment-strip used to corrupt on `"https://"` string literals; the tokenizer is now single-pass, fixed in the skill repo — the EA was never at fault.)
- Not compiled locally (no MetaEditor on Linux): compile in MetaEditor (F7) and paste error.log if anything surfaces. Expected: 0 errors, 0 warnings; only globals `g_armTp1/2/3`, `g_armValid` and the two touched functions changed.