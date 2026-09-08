# SR Zones Module — Predict-A-Trade

Self-contained HTF Support & Resistance layer inside Predict-A-Trade.mq5 (delimited by
`//================ SR MODULE BEGIN ================` / `END`). Pure MQL5, no includes, no
WebRequests, no external dependencies.

## Guarantees (prompt hard constraints)

- **Additive**: `InpUseSRZones=false` → every SR function returns immediately; the EA is
  bit-identical to the pre-SR build and pays zero per-tick SR cost. Verify with
  `presets/XAUUSD_M1_UltraScalp_SR_Off.set` — trade-for-trade identical results expected.
- **Never generates entries**: SR only filters, scores, snaps targets, refines stops,
  refines trailing, and draws.
- **Never increases risk**: any SR-widened stop triggers a lot recompute through the
  existing `CalculateLot()` so the risk % is unchanged; if the recompute yields zero lots
  the SR stop is rejected and the base stop kept. Sizing still honors
  `InpAllowMinLotFallback` / `InpMinLotMaxRiskPct`.
- **Never moves a stop against a position**: `SR_AdjustSL` never tightens; the trail
  anchor is monotonically gated by the existing `InpTP3TrailStepATR` improve/valid logic.
- Any snapped TP is re-validated through the existing monotonic ladder and
  `NetProfitValid` (cost gates `InpMaxCostToTP1Pct`, `InpMinNetProfitTP*Money`); a failed
  validation reverts to the original TP.
- Simple Scalp Mode is untouched as a mode: the same scalp signals, cost gates, risk
  engine and order path run; SR adds one gate call, optional TP/SL refinement and trail
  anchor.

## Architecture / data flow

```
SR_Init (OnInit, after handles) ──► SR_Rebuild(force)
OnTick ──► SR_Rebuild()  (throttled: ≥InpSRRefreshSeconds, or new bar on any SR TF,
                          max once per tick)
             ├─ SR_ZoneATRCalc            (M15 ATR for thickness)
             ├─ SR_CollectPivots          (TF1..TF4 fractal highs/lows, TF-weighted)
             ├─ SR_CollectPrevDayHL / PrevWeekHL / SessionHL / DailyOpen / RoundNumbers
             ├─ SR_CollectStructureConfluence (FVG/IFVG/PTB edges, VWAP ± bands)
             ├─ SR_MergeZones             (overlap OR anchor-proximity, ≤3 passes,
             │                             strength-weighted anchor, min/max edges)
             ├─ SR_CountTouches           (M1 history: touch / rejection / break,
             │                             consecutive-touch dedupe ≤3 bars)
             ├─ SR_ApplyRecencyDecay      (0.5^(bars/touch-half-life))
             ├─ SR_ScoreZones             (weights − break penalty − fresh bonus)
             ├─ SR_ClassifySides          (+1 above / −1 below price)
             └─ SR_PruneWeakAndDistant    (MinStrength, MinTouches for ROUND-only,
                                           MaxDistance; strongest-first; per-side caps)
Per-tick queries (O(n) over ≤InpSRMaxTotalZones, no CopyRates):
   SR_EntryAllowed (CanEnter, both branches)      SR_AdjustTP  (TryArm simple legs,
   SR_AdjustSL  (TryArm, both modes + recompute)   BuildThreeTargets)
   SR_TrailAnchor (ManagePosition TP3 trail)      SR_DirectionalVote (complex scoring)
   SR_PanelLine1/2 (dashboard)                    SR_Draw (chart objects)
OnTimer ──► SR_SelfTest (zone table every InpSRLogEveryNSeconds)
OnDeinit ──► SR_ClearObjects (all PAT_SR_* removed)
```

Integration points are marked `// [SR]` in the source: OnInit (SR_Init), OnDeinit
(SR_Deinit), OnTick (SR_Rebuild), OnTimer (SR_SelfTest), CanEnter simple branch + complex
branch (SR_EntryAllowed before dispatch), TryArm simple TP snap (cost-gated) and shared
SL adjust with lot recompute, BuildThreeTargets snap before revalidation, ComputeSL users
via TryArm, ManagePosition trail anchor, DashUpdate rows R_SR1/R_SR2, OpenLog/ARM-row CSV
columns.

## Scoring formula

```
rawStrength = InpSRWeightTouch·touches
            + InpSRWeightRejection·rejections
            + Σ TF weights present in tfMask (M15/H1/H4/D1)
            + Σ source weights in srcMask (prevDay, prevWeek, session, round,
                                            dailyOpen, FVG[+IFVG+PTB], VWAP)
            + (fresh ? InpSRFreshBonus : 0)
            − InpSRBreakPenalty·breaks
strength    = max(0, rawStrength · 0.5^(barsSinceLastTouch / InpSRRecencyHalfLifeBars))
broken zone → strength capped at 50 % of rawStrength (usable only with a post-break
rejection; flips side per classify-at-price)
```

**Worked example (XAUUSD):** a level found by H1 pivots (weight 2.0) and last week's high
(2.5), touched 4 times (4×1.0) with 2 rejections (2×0.5), never traded into (fresh
+0.5), 1 break (−1.5): raw = 2.0+2.5+4.0+1.0+0.5−1.5 = 8.5. Last touch 160 M1 bars ago
with half-life 400: strength = 8.5·0.5^(160/400) = 8.5·0.758 ≈ **6.4** → above
`InpSRWallMinStrength` 5.0, so it blocks buys within 0.45 ATR (unless a confirmed
breakout) and counts as headroom wall for HARD mode.

## Input reference (defaults in presets; tuning guidance)

| Group | Inputs | Guidance |
|---|---|---|
| Master | `InpUseSRZones`, `InpSRMode` (0=ADVISORY 1=SOFT 2=HARD), `InpSRRefreshSeconds` 15, `InpSRRebuildOnNewHTFBar` | Start SOFT; ADVISORY for observation; HARD demands clean TP1 headroom and will cut trade count |
| TF/history | `InpSR_TF1..4` M15/H1/H4/D1, bars 300/300/240/90, `InpSRFractalLeft/Right` 2/2 | 2/2 = tight pivots; 3/3 = stronger but fewer zones |
| Sources | `InpSRUse*` switches, `InpSRRoundStepUSD` 10, `InpSRRoundSubStepUSD` 5, `InpSRRoundMaxLevels` 6, FVG confluence on, VWAP off | Round numbers at 10 USD with 5 sub-levels dominate gold; disable if too noisy |
| Geometry | `InpSRZoneATRTF` M15, thickness 0.35 ATR, min/max 20/150 pt, merge 0.25 ATR, per-side 6, total 24, max distance 12 ATR | Thickness clamp keeps zones sane in dead and wild hours |
| Scoring | touch tol 0.20 ATR, min touches 1, touch 1.0, rejection 0.5, TF weights 1/2/3/4, prevDay 2.0, prevWeek 2.5, session 1.5, round 1.0, dailyOpen 1.0, FVG 1.0, VWAP 1.0, fresh 0.5, break 1.5, half-life 400, min strength 3.0 | Raise `InpSRMinStrengthToUse` to 4-5 for fewer, trusted zones |
| Gating | wall strength 5.0, block-into 0.45 ATR, headroom factor 1.10, allow-breakout true (buffer 0.15 ATR), vote ±1 | `InpSRAllowBreakoutThrough` keeps momentum trades alive through walls |
| Exits | snap TP on (max shift 0.25 ATR, front-run 8 pt), SL behind zone on (buffer 0.10, max extra 0.30 ATR), trail zones on | Snap respects cost gates; SL extra caps risk inflation |
| Display/log | draw on (max 12), colors, fill, labels, panel on, log on/300 s, prefix `PAT_SR_` | Tester non-visual mode skips drawing |

## CSV log

Existing 14 columns preserved in order; appended at the end:
`sr_mode, sr_zone_count, sr_up_price, sr_up_strength, sr_up_dist_atr, sr_dn_price,
sr_dn_strength, sr_dn_dist_atr, sr_tp_snapped, sr_sl_shifted, sr_block_reason`.
Header writer updated; a new log file picks the new schema up automatically.

## Performance & safety

- All history reads live inside `SR_Rebuild` (throttled, timed with
  `GetMicrosecondCount()`; >20 ms prints one throttled warning). Hot paths are O(n)
  scans of a fixed `SRZone g_srZones[64]` — no per-tick allocation, no CopyRates.
- Every ATR/point/bar-count division guarded; ATR≤0 / missing history / CopyRates −1
  degrade to fewer zones, never a hard stop.
- Chart objects: create-once/update-in-place, `OBJPROP_BACK`, non-selectable, hidden,
  prefix `PAT_SR_*`; `ChartRedraw` throttled to `InpDashRefreshMs`; skipped entirely in
  non-visual tester runs; `SR_Deinit` deletes every object (ObjectsTotal(prefix) → 0).
- The SR directional vote is bounded to ±1 and is added AFTER the FILTER_ALL_REQUIRED
  gate but BEFORE the FILTER_SCORING gate, so it can strengthen or weaken a complex-mode
  score but can never single-handedly satisfy `InpMinFilterScore` (≥2 by design here).

## Known limitations

- Session highs/lows use UTC-window mapping from the broker server offset; a wrong
  `InpManualServerOffsetHours` shifts which bars count as Asian/London/NY.
- `fresh` is approximated as "zero confirmed touches" rather than full history tracking.
- Zone side flips only at classify time; a broken zone's support↔resistance role is the
  price-relative classification, gated by the post-break-rejection rule.
- Round-number sub-levels add one candidate per main level (5.0 between each 10.0); no
  38.2/61.8 fib logic (out of spec).
- The module reads live globals (`g_atr`, `g_fvg`, `g_vwap`, …) from the main engine; it
  is self-contained in code but not independent of engine state.