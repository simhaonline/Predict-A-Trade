# Predict-A-Trade-Ultra — XAUUSD M1 Ultra-Scalping EA (Pure MQL5)

**Predict-A-Trade-Ultra.mq5** · version 2.00 · single-file MetaTrader 5 Expert Advisor for
gold (XAUUSD) on the M1 timeframe. Fully **self-contained**: one `.mq5` file, zero
`#include` directives, zero DLLs, zero external scripts. All dependencies are either
native MQL5 or optional web data that the EA degrades gracefully without.

```
Predict-A-Trade-Ultra.mq5      the EA (single file, ~4,100 lines)
tools/build_presets.py         self-contained .set generator (Python stdlib only)
presets/*.set                  4 ready-to-load presets (299 inputs each)
docs/                          audit, methodology, module & validation docs
```

---

## 1. What this EA is

An ultra-scalper that trades XAUUSD M1 through a four-session opportunity engine
(Sydney, Tokyo, London, New York + their overlap windows), with:

- **Simple Scalp Mode** (default, recommended): a four-signal M1 engine — VWAP
  mean-reversion, London-open breakout, NY-open momentum, EMA-pullback — with a
  hard-coded, audit-locked ATR distance profile.
- **Complex Mode** (`InpSimpleScalpMode=false`): the full multi-filter engine (EMA /
  SuperTrend / ADX / VWAP / FVG / AMD / volume / liquidity / RSI / SMC scoring) for
  research comparison. Not the recommended operating mode.
- **TP1/TP2/TP3 exit ladder** with cost-aware partial closes, break-even lock, and a
  structure trail on the runner.
- **HTF Support/Resistance zones** (built-in SR module) that filter entries, snap
  targets, refine stops, and trail behind zones — additive and switchable.
- **Capital protection**: daily/weekly/monthly loss breakers, floating-DD risk step-down,
  consecutive-loss decay + hard pause, daily trade cap, aggregate & directional risk caps,
  no-martingale / no-averaging-down sizing freeze.
- **Ops hardening**: broker profile detection & auto point-scaling, netting-account
  degradation, order-retry with backoff, spread-aware TP1 viability guard, Pct
  misconfiguration guards, symbol trade-mode validation, kill switch, push alerts,
  heartbeat, state persistence with reconciliation, and a self-test harness.

Everything trades through native `OrderSend` with a retcode-aware retry wrapper — no
`CTrade`, no `CSymbolInfo`, no external libraries.

## 2. Quick start

1. Copy `Predict-A-Trade-Ultra.mq5` to `MQL5/Experts/`, compile in MetaEditor (F7).
   Expected: 0 errors, 0 warnings (strict mode).
2. Whitelist WebRequest URLs **only if** you want the optional FMP macro feed:
   Tools → Options → Expert Advisors → Allow WebRequest → add
   `https://financialmodelingprep.com`. The EA trades fine without it (broker-side
   EURUSD momentum fallback + MQL5 economic calendar).
3. Load a preset: right-click chart → Expert List → drag the EA onto an XAUUSD M1
   chart → Load → pick a preset from `presets/`.
4. Verify the panel: BROKER PROFILE lines in the Journal, `SELFTEST` PASS lines,
   session map green, and `Gate:` showing live reasons.
5. **Demo first.** See the go-live gate in `docs/05_Validation_Protocol.md`.

### Presets

| File | Use |
|---|---|
| `XAUUSD_M1_UltraScalp.set` | Production profile — SR zones ON, soft filter |
| `XAUUSD_M1_UltraScalp_SR_Off.set` | A/B baseline — SR module fully off (bit-identical to legacy build) |
| `XAUUSD_M1_UltraScalp_Advisory.set` | SR observes & logs, never blocks |
| `XAUUSD_M1_UltraScalp_PropFirm.set` | Prop-firm mode: stricter daily loss (2.0%), trailing DD 4%, 15 trades/day cap |

Regenerate all four after changing prompt.md (Phase 1 values) or EA inputs:

```
python3 tools/build_presets.py
```

The script parses the authoritative profile from prompt.md plus the EA's own input
declarations, serializes enums to MT5's integer .set format, applies per-variant
overrides, and verifies every output row-set against the source. Stdlib only — no pip.

## 3. How it works

### 3.1 The trading loop (every tick)

```
OnTick
 ├─ refresh server-UTC offset, risk periods, spread stats, indicators
 ├─ SR_Rebuild()                     (throttled zone engine, marked // [SR])
 ├─ on new M1 bar: FVG/IFVG/PTB/AMD/SMC structure update, news check,
 │                 scalp signal evaluation (EvaluateScalpSignal)
 ├─ breaker check (daily/weekly/monthly) → emergency flatten if CLOSE_ALL
 ├─ swap-rollover flat enforcement
 ├─ recovery leg (complex mode only — skipped in simple mode)
 ├─ TryArm()                         the entry pipeline (below)
 ├─ ManageAllPositions()             ladder, BE, trail, time-stop, swap exit
 └─ dashboard refresh
OnTimer (1 s): news re-check, FMP refresh, SR self-test, state autosave
OnTradeTransaction: fills → slippage learning, commission learning, position state
```

### 3.2 Entry pipeline (`TryArm` → `CanEnter`)

A trade fires only when **all** of these pass, in order:

1. A scalp signal exists (simple mode: `EvaluateScalpSignal` on the last closed M1 bar —
   VWAP reversion / London breakout / NY momentum / EMA pullback).
2. Session gate: inside an enabled window (Sydney/Tokyo/London/NY + overlaps; momentum
   signals restricted to liquid hours).
3. News gate (MQL5 calendar + optional FMP headlines), stabilization window, swap-danger
   window, weekend/rollover.
4. Spread hard cap (35 pt profile) + broken-feed extreme check; ATR floor/chop ceiling.
5. Simple-mode extra guards: 60 s same-direction spacing, 0.35 ATR proximity to an open
   scalp, daily trade cap (25), position cap.
6. **SR entry gate** (`// [SR]`): blocks entries into an opposing strong zone
   (strength ≥ 5.0, within 0.45 ATR) unless a confirmed breakout, and in HARD mode
   requires TP1 headroom ×1.10. Machine-parsable reason (`SR_WALL_5.8@0.31A`).
7. Sizing: risk % → lot via `CalculateLot` (with the no-martingale underwater freeze,
   min-lot fallback for small accounts, aggregate/directional risk caps, window budget).
8. **TP1 viability** (Phase 2.4): TP1 must exceed max(stops-level+buffer,
   (spread+expected slippage) × `InpTP1SpreadMultiple`), else the trade is rejected
   (`TP1_TOO_TIGHT`) rather than widening the target.
9. Cost gate: TP1 must leave ≥ `InpMinNetProfitTP1Money` after spread + slippage +
   commission, with cost ≤ `InpMaxCostToTP1Pct` of gross.
10. Dispatch: single market order (simple mode), SL and broker TP = armed plan.

### 3.3 The TP/SL methodology (Phase 2 — the core rule)

> **Distance = ATR multiple. Volume split = decimal fraction. Minimums = account
> currency.** Never fixed points, never a % of gold price, never fixed lots.

| Leg | Distance from entry | Closes | R:R (SL = 0.80 ATR) |
|---|---|---|---|
| TP1 | **0.40 × ATR** (`SCALP_TP1_ATR`) | **75%** (`0.75`) | 0.50R |
| TP2 | **0.75 × ATR** total (`SCALP_TP2_TOT`) | **20%** (`0.20`) | 0.94R |
| TP3 | **1.15 × ATR** total (`SCALP_TP3_TOT`) | **5%** runner, trailed | 1.44R |

Why: gold M1 ATR swings ~30 pt (Asia) to ~150 pt (London/NY) — fixed points are wrong in
both regimes; 0.05% of price = 170 pt = a swing trade, nonsense at scalp scale. Because
the stop is ATR-based (0.80 normal / 0.45 reversion-beyond-extreme / 0.85 London
breakout), ATR targets keep R:R stable across volatility regimes, and the 40%-of-gross
cost gate only behaves correctly when TP1 scales with volatility.

These constants live at the top of the engine (`SCALP_*`, Phase 2.3) with comments
linking each to its complex-mode input analogue; the audit doc lists them as the
authoritative simple-mode distances.

**Volume split rules (Phase 2.2/2.5):**
- `InpTP1Pct/2/3` are **decimal fractions** (0.75 = 75%) and must sum to 1.0 — enforced
  at init (`INIT_PARAMETERS_INCORRECT` otherwise; whole-number input 75/20/5 auto-divides
  with a loud warning).
- **Lot-ladder feasibility**: every leg ≥ broker min lot AND every residual after a
  partial close ≥ min lot. When 3 legs don't fit (at 0.01 min lot, a 75/20/5 ladder
  needs ≥ 0.20 lots), `InpAutoDegradeTPLadder` cascades 3-leg → 2-leg → 1-leg; residue
  placement follows `InpLadderRoundingMode` (default `LADDER_FAVOR_TP1`).

| Position | 3-leg 75/20/5 | Degraded plan |
|---|---|---|
| 0.01 | ✗ | 1-leg (all out at TP1) |
| 0.02 | ✗ | 1-leg |
| 0.05 | ✗ | 1-leg |
| 0.10 | ✗ (leg3 < min) | 2-leg |
| 0.20 | ✓ exact | — |
| 0.50 | ✓ exact | — |

### 3.4 The SR zones module (Phase 3)

Marked `// [SR]` everywhere. With `InpUseSRZones=false` every hook returns immediately —
zero CPU cost, bit-identical legacy behavior. It **never generates entries and never
increases risk**; a widened SR stop forces an identical-risk lot recompute (invalid →
base stop kept) and every snapped TP re-passes the cost gates (fail → original TP).

Pipeline (throttled rebuild ≤ every 15 s or on a new HTF bar, timed, <20 ms warned):
M15/H1/H4/D1 fractal pivots + prev-day/prev-week/session H/L + daily open + round
numbers ($10/$5) + FVG/IFVG/PTB/VWAP confluence → ATR-thickness zones (clamped
20–150 pt) → merge on overlap/proximity → touch/rejection/break counting on M1 history
→ recency decay (half-life 400 bars) → weighted scoring → prune & rank.

```
strength = (touch·1.0 + rejection·0.5 + ΣTF-weights + Σsource-weights
            + fresh?0.5 − breaks·1.5) · 0.5^(barsSinceTouch/400)
```

Broken zones keep ≤50% strength and only act with a post-break rejection. Consumed by:
entry gate, TP snap (front-run 8 pt, ≤0.25 ATR shift), SL behind zone (≤ +0.30 ATR,
lot-recomputed), TP3 trail anchor (conservative pick vs the swing anchor), panel rows,
CSV telemetry, and the ±1 complex-mode score vote (never sufficient alone).

### 3.5 Protection layers (what stops you losing money)

| Layer | Mechanism |
|---|---|
| Per-trade risk | lot = f(`InpRiskPercent` 0.35%), decayed ×0.70 per consecutive loss (floor 0.10%), stepped down past half the floating-DD limit; SR-widened stops recompute the lot |
| Daily breaker | −2.5% day loss or 3 consecutive losses → breaker (CLOSE_ALL flattens) + hard pause `InpConsecLossPauseMinutes` |
| Weekly / monthly | −6% / −10% |
| Trade hygiene | 25 trades/day cap, single market order, 10-minute time stop, swap-window flat enforcement, Friday cutoff 19:00 server |
| Entry quality | spread cap 35 pt, ATR floor/ceiling, TP1_TOO_TIGHT, TP1 cost-positivity, SR walls |
| External data | FMP down → broker EURUSD fallback; calendar unavailable → trading continues (`InpRequireExternalData=false`) |

### 3.6 Broker & account adaptation (Phase 4 highlights)

- **BROKER PROFILE** printed at init: digits, point, tick value/size, contract size,
  min/step/max lot, stops & freeze levels, current/average spread, swap, commission
  source (learned vs fallback).
- Auto point-scaling for 2- vs 3-digit gold feeds; symbol must be
  `SYMBOL_TRADE_MODE_FULL` at init (fail-fast otherwise).
- **Netting accounts**: `MaxConcurrentPositions>1` is impossible on netting — the EA
  detects `ACCOUNT_MARGIN_MODE` and degrades to a single position with a loud warning.
- Fill policy auto-negotiated (`FOK` → `IOC` → `RETURN`), order latency and slippage
  measured, retcode-aware retry with backoff, non-retryable codes abort.
- Commission is **learned** from real fills and replaces the 7.00/lot fallback;
  slippage average replaces the 3.5 pt fallback after 5 fills.
- State persistence with account/symbol/magic binding; consecutive-loss streak recounted
  from real deal history at init (a stale streak can never halt a fresh attach).
- Kill switch: drop `MQL5/Files/PAT_KILL.txt` → entries stop; containing `FLAT` →
  everything closes. Push alerts on breaker/disorder/reconnect; heartbeat every 15 min.
- Self-test at init: Pct fractions & sum, ladder feasibility at 6 lot sizes, risk-math
  round trip, point scaling, stop-level compliance, SR sanity, netting detection,
  money-gate conversion. Categories 1–4 fail → `INIT_FAILED`.

## 4. The dashboard

Two columns, drag the header to move, click `[-]` to collapse, `PAUSE ARMING` button:

- **Left**: session window + UTC clock + overlap state, spread (p-avg), ATR
  (p-percentile), volume ratio + session phase, filter score/bias, SMC/IFVG/PTB, HV
  score, live gate reason.
- **Right**: account/broker, margin, positions/lots, risk $ vs aggregate cap, window
  budget, GATE state, trades today + consecutive losses, recovery state, news countdown,
  slippage, **SR zone summary** (R_SR1/R_SR2: nearest R/S with strength & distance),
  today/lifetime performance, per-window expectancy.
- Bottom: 24 h UTC session map.

## 5. Repository layout

```
Predict-A-Trade-Ultra.mq5        the EA — drop into MQL5/Experts/
tools/build_presets.py           self-contained preset generator (stdlib only)
presets/XAUUSD_M1_UltraScalp.set         production (SR soft filter)
presets/XAUUSD_M1_UltraScalp_SR_Off.set  SR off — A/B baseline
presets/XAUUSD_M1_UltraScalp_Advisory.set SR advisory (observe only)
presets/XAUUSD_M1_UltraScalp_PropFirm.set prop-firm guardrails
docs/XAUUSD_M1_UltraScalp_Audit.md       per-input audit + effectiveness matrix
docs/SR_Zones_Module.md                  SR architecture, inputs, worked example
docs/TP_Methodology.md                   ATR-vs-% methodology + ladder tables
docs/05_Validation_Protocol.md           backtest & go-live protocol
prompt.md                                authoritative build spec (phases)
```

## 6. Verification & backtest protocol (summary)

Full protocol: `docs/05_Validation_Protocol.md`. Non-negotiables:

- Strategy Tester: **Every tick based on real ticks** (≥99%), real variable spread,
  commission + swap configured, ≥6 months of M1 data.
- Required runs: **A** SR_Off baseline (must match the legacy build trade-for-trade) →
  **B** SR advisory (entry count unchanged vs A) → **C** SR soft (production candidate)
  → **D** SR hard (sensitivity).
- Robustness: walk-forward 70/30 rolled ≥3×, ±20% sensitivity on SL/momentum/spread/SR
  parameters (smooth degradation, no cliffs), spread ×1.5 stress, commission 7/10/14
  stress, 1000-shuffle Monte Carlo.
- **Go-live gate**: PF ≥ 1.25 out-of-sample, max DD ≤ 10%, ≥ 200 trades, cost ≤ 40% of
  gross, plus 2–4 weeks forward demo on the live broker feed within 30% of backtest
  expectancy.

## 7. Design constraints honored

- **Self-contained**: one .mq5, no includes, no DLLs, no CTrade/CSymbolInfo classes —
  native `OrderSend`/`SymbolInfo*`/`Position*` throughout. The preset builder is stdlib
  Python, versioned in `tools/`, so no external service or hand-editing is ever needed.
- **Invariants**: no martingale, no averaging down, no scale-in, no loss-chasing recovery
  in simple mode, no stop ever moves against a position, realized risk never exceeds
  `InpRiskPercent` on any code path, `InpSimpleScalpMode=true` by default.
- **Broker warnings** (verified at init / printed): `InpManualServerOffsetHours` (session
  accuracy), `InpSwapRolloverServerHour` (must match the journal), `InpMaxSpreadPoints`
  (auto-scales with digits), `InpCommissionPerLotRTFallback` (overridden by learned
  commission), `InpExpectedSlipPtsFallback` (overridden by the rolling average),
  `InpMagicNumber` (unique per instance), margin mode (netting degradation), symbol name
  variants, filling mode, min/step lot vs the ladder table.

## 8. Known limitations

- FMP macro data requires a WebRequest whitelist and an API key entered by the operator
  (never committed); the EA trades normally without it.
- Tester news filtering uses approximate high-impact event times (the MQL5 calendar is
  unavailable in the Strategy Tester).
- The SR `fresh` flag approximates "never touched" from touch counts, not full history.
- Session H/L mapping depends on a correct server-UTC offset (auto-detected; verify the
  one-time rollover note in the Journal).
- Simple mode hardcodes its entry spacing (60 s / 0.35 ATR) and signal thresholds; only
  `InpScalpMinMomentumATR` and the `SCALP_*` constants tune it.

---

*Trade demo first. A backtest alone proves nothing — see the pre-deploy warning at the
top of the source and the go-live gate in the validation protocol.*