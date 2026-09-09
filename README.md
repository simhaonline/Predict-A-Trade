# Predict-A-Trade-Ultra — XAUUSD M1 Ultra-Scalping EA

**Predict-A-Trade-Ultra.mq5** · version 2.00 · a single-file MetaTrader 5 Expert Advisor
for gold (XAUUSD) M1 — plus a **mobile command
bridge** for distribution to subscribers.

Fully **self-contained on the trading side**: one `.mq5` file, zero `#include`, zero
DLLs, zero external scripts. All dependencies are native MQL5 or optional web data the
vendors — the EA runs identically without it.

```
Predict-A-Trade-Ultra.mq5      the EA (single file, ~6,319 lines)
tools/build_presets.py         self-contained .set generator (Python stdlib only)
presets/*.set                  4 ready-to-load presets (inputs each)
docs/                          audit, methodology, module & deployment docs
```

---

## 1. What this EA is

An ultra-scalper that trades XAUUSD M1 through a four-session opportunity engine
(Sydney, Tokyo, London, New York + their overlap windows), with:

- **Simple Scalp Mode** (default, recommended): a five-setup M1 engine — VWAP
  mean-reversion, London-open breakout, NY-open momentum, EMA-pullback, and an
  always-on EMA20 mean-reversion baseline — with an audit-locked ATR distance profile
  (`SCALP_*` constants).
- **Complex Mode** (`InpSimpleScalpMode=false`): the full multi-filter engine (EMA /
  SuperTrend / ADX / VWAP / FVG / AMD / volume / liquidity / RSI / SMC scoring) for
  research comparison.
- **TP1/TP2/TP3 exit ladder** with cost-aware partial closes, break-even lock, and a
  structure/zone trail on the runner. **Enabled in Simple Scalp Mode** (the 3-TP ladder
  was previously collapsed to a single TP1 close; see §2.3).
- **HTF Support/Resistance zones** (built-in SR module): filters entries into strong
  opposing zones, snaps targets to zone edges, refines stops behind zones, trails the
  runner — additive, switchable, never generates entries, never increases risk.
- **Capital protection**: daily/weekly/monthly loss breakers, floating-DD risk
  step-down, consecutive-loss decay + hard pause, daily trade cap, aggregate &
  directional risk caps, no-martingale / no-averaging-down sizing freeze.
- **Ops hardening**: broker profile detection & point auto-scaling, netting-account
  degradation, spread-aware TP1 viability guard, Pct misconfiguration guards, kill
  switch, push alerts, heartbeat, state persistence with reconciliation, self-test
  harness.
- **Mobile command bridge** (optional): control the EA from the MT5 iOS/Android app
  through pending-order comments — no native app needed.

## 2. Change log — what was fixed (in place, no subsystems removed)

The EA went through several live/backtest diagnoses. Every fix below was applied to
this single file; the original four setups are preserved and a fifth always-on baseline
was added. Grouped by root cause:

### 2.1 Zero signals on live / cold-attach (readiness gate)

The EA fired ~867 setups per 5 trading days in the Strategy Tester but showed **zero
signals live**, logging `ENTRY_GATE no scalp signal` on every bar.

1. **Readiness gate froze the engine (root cause).** `g_indicatorsReady` required the
   asynchronous M5 `CopyBuffer` to succeed in a single pass. In the tester history is
   pre-loaded; in LIVE / cold-attach the M5 series loads asynchronously and the gate
   stayed `false` forever — `OnTick` skipped `EvaluateScalpSignal`, so `g_scalpSignal`
   stayed `0`. **Fix:** readiness now needs only M1-core indicators
   (`ATR>0 && EMA20>0 && EMA50>0 && RSI>0`); M5/M15/M30/H1 are degraded-graceful —
   seeded from M1 EMAs when absent, retried per tick, and can never block the M1 scalp
   engine.
2. **Signal vetoes too strict to ever fire on gold M1.** VWAP reversion demanded
   `RSI≥70/≤30` + `ADX<45` + a 1.8σ extension; NY momentum demanded a 0.5×ATR body only
   news ticks satisfy. **Fix:** VWAP reversion now fires on a 1.2σ extension with a
   close-back confirmation (RSI/ADX are nudges only, Bollinger-mid fallback when the VWAP
   anchor is missing); NY momentum uses a proportional body with an absolute point floor;
   and a **new always-on EMA20 reversion baseline (codes 5/-5)** fires in *every* session
   on a ≥0.5 ATR stretch off EMA20 that closes back across it.
3. **Execution path could permanently latch.** A transient send risk-check mismatch or an
   `EXECUTION_UNCERTAIN` flag with no auto-recovery blocked all future trades. **Fix:**
   pre-flight now compares live send-time price with a 2% relative headroom against the
   armed plan; `EXECUTION_UNCERTAIN` auto-reconciles (clears if no pending entry order
   exists, or after a 90-second watchdog `g_uncertainSince`); a corrupt state file resets
   cleanly.
4. **Spread gate vetoed gold.** `InpMaxSpreadToATRPct` shipped at 20% (forex-major number);
   gold M1 routinely runs 50–150%. **Fix:** default raised to `150.0`.

### 2.2 Trades executed but lost money (win-rate near 0%)

After signals resumed, backtests/forward showed win% near 0 — systematic wrong-direction
entries, not bad luck.

1. **Sub-1R reward.** Simple-mode banked the whole position at TP1 = 0.55 ATR while the
   stop was 0.80 ATR → 0.69R win vs 1.0R loss, needing ~62% win rate just to break even.
   **Fix:** `SCALP_TP1_ATR` raised 0.55 → **0.85 ATR** (≥ SL, so ≥1R). The 3-TP ladder
   distances follow (TP2 1.40, TP3 2.10 ATR). VWAP-reversion target floor raised to
   0.8 ATR vs its 0.45 ATR stop.
2. **Mean-reversion fighting the trend.** The VWAP reversion faded *any* 1.5σ extension,
   including into a live trend. **Fix:** a down-extension fade (LONG) only fires when the
   trend is *not* down; an up-extension fade (SHORT) only when the trend is *not* up —
   turning blind fades into pullback entries.
3. **Book was 100% reversion.** NY momentum was hard-gated on M5 presence; when M5 was
   late/absent the whole book became reversion. **Fix:** momentum now fires on the
   M1-trend fallback too (`m5Present || g_ema20!=g_ema50`), so the with-trend setups
   participate.

### 2.3 Regression: trades stopped again (bias gate over-vetoed reversion)

A market-bias gate was added to stop the engine from fading the higher-timeframe trend —
but it was applied to **all** signals, including the mean-reversion book. Reversion is
counter-trend by design (it shorts extensions in an up-trend), so once the M15/H1 EMA
caches loaded the gate vetoed the entire reversion flow → trades stopped.

**Fix:** the bias gate is now **scoped to trend-following setups only** (London breakout,
NY momentum, EMA pullback). Reversion (VWAP 1/-1, EMA20 baseline 5/-5) is never vetoed
by it; reversion keeps its own VWAP trend-gate from §2.2.

### 2.4 Regression: "no scalp signal" recurred (signal-frequency collapse)

With the trend-filters from §2.2 plus narrow session windows, in a **trending market**
(your live `ATR=3.22` confirms trending/volatile gold) almost no bar qualified outside
the London/NY windows, so `g_scalpSignal` stayed 0 for most of the day.

**Fixes:**
1. **Always-on baseline made truly always-on.** It was gated by `g_ema20>g_ema50` /
   `<g_ema50`, which is self-contradictory in a trend (price sits one side of EMA20, so
   the required stretch-and-reclaim rarely matched the trend condition). The gate was
   removed — the directional reclaim (`resumedUp`/`resumedDn`) already encodes
   trend-alignment via price action. Baseline stretch loosened 0.6 → **0.5 ATR**.
2. **VWAP reversion threshold** 1.5σ → **1.2σ** so the reversion book actually fires.
3. **Softened the bias gate** default: it now requires **both** M15 and H1 to agree before
   blocking a trend-following entry (`InpSimpleBiasMinAlign` default 2; 1 = stricter; 0 =
   off). Turn it fully off with `InpSimpleBiasFilter=false`.

### 2.5 Live diagnostics added (so the next issue is never a guess)

- **`SCALP_RDY`** — prints every ~20s *even when not ready* (ready, atr, ema20, rsi,
  vwap, m5e20). If you ever see `SCALP_RDY ready=0`, that is a readiness problem and we
  chase that exact line.
- **`SCALP_DIAG`** — prints every ~20s when ready, showing `sig`, `vwapDev`, `m5Up/Dn`,
  `um` (session minute), `EMA20>50`, `c1-ema20`, `ATR` — the five preconditions that
  decide whether a signal fires.
- **`SIGDIAG`** — every 20,000 ticks in the tester (precondition sanity dump).

Net effect: same five setups, now genuinely always-on, with ≥1R reward and a working
3-TP ladder + break-even lock in simple mode.

## 3. Quick start

### Trading (individual trader)

1. Copy `Predict-A-Trade-Ultra.mq5` to `MQL5/Experts/`, compile in MetaEditor (F7).
   Expected: 0 errors, 0 warnings (strict mode).
2. Optional data feeds: whitelist `https://financialmodelingprep.com` under
   Tools → Options → Expert Advisors → Allow WebRequest. The EA trades fine without it.
3. Attach to an XAUUSD M1 chart. No preset needed — the EA's compiled-in defaults
   ARE the production ultra-scalp profile; change any input directly in the EA
   dialog. The `presets/` files remain as optional convenience snapshots.
4. Check the Journal for the BROKER PROFILE block and `self-test PASS` lines; the panel
   shows live session windows, gate reasons, and risk state.
5. **Demo first** — see the go-live gate in `docs/05_Validation_Protocol.md`.

### Verifying the signal layer is live

After compiling and attaching, watch the Journal. You should now see:

- `SCALP_RDY ready=1 atr=... ema20=... rsi=... vwap=...` — confirms indicators live.
- `SCALP_DIAG sig=N ...` — shows which setup fired (or why none did).
- `ENTRY_GATE ...` — should now show real reasons (`VWAP reversion SHORT`, `EMA pullback
  LONG`, `EMA20 reversion LONG`, `bias gate: HTF trend up, no short`, `TP1_TOO_TIGHT`,
  etc.) rather than a perpetual `no scalp signal`.
- A **GATE REJECTION HISTOGRAM** at the end of a test pass — the win/loss distribution
  per reason, for tuning.

If after compile it still shows zero signals, paste ONE `SCALP_DIAG` line and the
thresholds will be dialed per your broker's actual spread/ATR.

### Bias-gate tuning (new inputs)

| Input | Default | Meaning |
|---|---|---|
| `InpSimpleBiasFilter` | `true` | Soft guard for trend-following setups only. Set `false` to disable entirely. |
| `InpSimpleBiasMinAlign` | `2` | # of {M15,H1} EMA-stacked in-trend required to hard-block (2 = both must agree; 1 = either blocks = stricter; 0 = off). |

### Mobile control (anyone with the MT5 app)

Place a **pending order** on the chart with one of these comments; the EA executes it
and deletes the order:

| Comment | Effect |
|---|---|
| `STOP_EA` | stop opening new trades |
| `START_EA` | resume trading |
| `RISK_0.2` | risk override to 0.2% (capped at 5%) |

### Presets

| File | Use |
|---|---|
| `XAUUSD_M1_UltraScalp.set` | Production profile snapshot — identical to the EA's compiled-in defaults |
| `XAUUSD_M1_UltraScalp_SR_Off.set` | A/B baseline — SR module off (bit-identical legacy behavior) |
| `XAUUSD_M1_UltraScalp_Advisory.set` | SR observes & logs, never blocks |
| `XAUUSD_M1_UltraScalp_PropFirm.set` | Prop-firm guardrails: 2.0% daily loss, 4% trailing DD, 15 trades/day |

Regenerate all four after changing the profile or EA inputs:

```
python3 tools/build_presets.py
```

The generator embeds the authoritative profile (it does not depend on prompt.md's
current mission), parses the EA's own input declarations, serializes enums to MT5's
integer `.set` format, applies per-variant overrides, and verifies name parity with the
source. Stdlib Python only.

## 4. How the EA works

### 4.1 The trading loop (every tick)

```
OnTick
 ├─ mobile command bridge (order-comment scan)
 ├─ refresh server-UTC offset, risk periods, spread stats, indicators
 ├─ SR_Rebuild()                    (throttled zone engine, marked // [SR])
 ├─ on new M1 bar: FVG/IFVG/PTB/AMD/SMC structure, news check,
 │                 scalp signal evaluation
 ├─ breaker check (daily/weekly/monthly) → emergency flatten if CLOSE_ALL
 ├─ swap-rollover flat enforcement
 ├─ recovery leg (complex mode only — provably skipped in simple mode)
 ├─ TryArm()                        the entry pipeline (below)
 ├─ ManageAllPositions()            ladder, BE, trail, time-stop, swap exit
 └─ dashboard refresh
OnTimer (1 s): news re-check, FMP refresh, SR self-test, state autosave,
OnTradeTransaction: fills → slippage & commission learning, position state rebuild
OnChartEvent: panel drag / collapse / pause button
```

### 4.2 Entry pipeline (`TryArm` → `CanEnter`)

A trade fires only when **all** gates pass, in order:

1. **License gate** — removed during validation phase; trading governed by risk gates only.
2. A scalp signal exists (simple mode: `EvaluateScalpSignal` on the last closed M1 bar —
   see the five setups in §4.3).
3. **Bias gate (trend-following setups only, §2.4):** a trend-following signal
   (London/NY/EMA-pullback) is blocked if the H1/M15 EMA stack disagrees with its
   direction by `InpSimpleBiasMinAlign` frames. Reversion setups skip this gate.
4. Session gate: inside an enabled window (momentum / pullback signals prefer liquid
   hours; the EMA20-reversion baseline is allowed in all sessions).
5. News gate (MQL5 calendar + optional FMP headlines), stabilization window,
   swap-danger window, weekend/rollover guard.
6. Spread gate: relative `InpMaxSpreadToATRPct` (default 150%) + adaptive percentile /
   spike multipliers + broken-feed extreme check; ATR floor/chop ceiling.
7. Simple-mode guards: 60 s same-direction spacing, 0.35 ATR proximity to an open
   scalp, daily trade cap (25), position cap.
8. **SR entry gate** (`// [SR]`): blocks entries into an opposing zone with
   strength ≥ 5.0 within 0.45 ATR (unless a confirmed breakout); HARD mode adds TP1
   headroom ×1.10. Reasons are machine-parsable (`SR_WALL_5.8@0.31A`, `SR_NO_HEADROOM`).
9. Sizing: `InpRiskPercent` 0.35% → lot, with the no-martingale underwater freeze,
   min-lot fallback, aggregate/directional risk caps, and window budget.
10. **TP1 viability**: TP1 must exceed max(stops-level + buffer,
    (spread + expected slippage) × `InpTP1SpreadMultiple`) — else the trade is rejected
    (`TP1_TOO_TIGHT`), never silently widened.
11. Cost gate: TP1 must clear `InpMinNetProfitTP1Money` after spread + slippage +
    commission, with cost ≤ 40% of gross.
12. Pre-flight send check: live send-time price vs the armed `g_lastAllowedRiskMoney`
    plan, with a 2% relative headroom — rejects `PREFLIGHT_TRADE_RISK_CAP` drift instead
    of silently amplifying risk.
13. Dispatch: single market order; SL and broker TP = the armed scalp plan (snapshot
    travels to position management so the executed plan matches the validated one).

### 4.3 The five simple-mode setups (`EvaluateScalpSignal`)

| Code | Setup | Window | Trigger |
|---|---|---|---|
| 2 / -2 | **VWAP mean-reversion** | any session | price extends ≥1.2σ from VWAP (BB-mid fallback) then closes back across the mean (not into a strong trend) |
| 3 / -3 | **London-open breakout** | 07:00–08:15 UTC | close breaks the 00:00–06:45 UTC Asian range (≥0.8 ATR) in trend direction |
| 1 / -1 | **NY-open momentum** | 13:30–15:30 UTC | 15-bar high/low breakout close with M5 (or fallback M1) trend alignment |
| 4 / -4 | **EMA pullback** | liquid windows | last bar closed back across EMA20 in M5 trend direction after being on the wrong side |
| 5 / -5 | **EMA20 reversion baseline** | **every session** | price stretched ≥0.5 ATR off EMA20 then closed back across it (directional reclaim — inherently trend-aligned) |

Codes 1–4 confirm with a higher-timeframe trend bias (M5 when loaded, M1 EMA20/50 when
not) but that bias is confirmation only, never a hard veto — so a setup never silently
dies just because higher-TF data is late. Reversion (1/-1, 5/-5) is never vetoed by the
bias gate (§2.4). Code 5 requires only M1 core data and is the engine's guaranteed
backstop against silence.

### 4.4 The TP/SL methodology (the core rule)

> **Distance = ATR multiple. Volume split = decimal fraction. Minimums = account
> currency.** Never fixed points, never a % of gold price, never fixed lots.

**Simple-mode 3-TP ladder (now enabled — previously collapsed to a single TP1 close):**

| Leg | Distance from entry | Closes | R:R (SL = 0.80 ATR) |
|---|---|---|---|
| TP1 | **0.85 × ATR** (`SCALP_TP1_ATR`) | **75%** | **1.06R** |
| TP2 | **1.40 × ATR** total | **20%** | 1.75R |
| TP3 | **2.10 × ATR** total | **5%** runner, trailed | 2.62R |

Stop distances by setup: 0.80 ATR (momentum / pullback / EMA20 reversion),
0.45 ATR (VWAP reversion beyond the extreme, target floor 0.8 ATR), 0.85 ATR (London
breakout).

Why: gold M1 ATR swings ~30 pt (Asia) to ~150 pt (London/NY) — fixed points are wrong in
both regimes; a % of price (0.05% of 3400 = 170 pt) is a swing trade at scalp scale.
Because the stop is ATR-based, ATR targets keep R:R stable across regimes, and the 40%-cost
gate only behaves correctly when TP1 scales with volatility. With TP1 ≥ SL (≥1R) and the
break-even lock engaging once TP1 banks, a ~50%+ win rate is profitable rather than a
guaranteed bleed.

Split rules: `InpTP1Pct/2/3` are **decimal fractions** summing to 1.0 (75% / 20% / 5%
default). **Lot-ladder feasibility**: every leg ≥ broker min lot and every post-close
residual ≥ min lot — at 0.01 min lot the 75/20/5 ladder needs ≥ 0.20 lots, below that the
EA cascades 3-leg → 2-leg → 1-leg (`InpAutoDegradeTPLadder`).

### 4.5 The SR zones module

Delimited `//================ SR MODULE BEGIN ================` block, all hooks marked
`// [SR]`. With `InpUseSRZones=false` every hook returns immediately — bit-identical
legacy behavior, zero cost. Pipeline (throttled rebuild, timed, >20 ms warned):

M15/H1/H4/D1 fractal pivots + prev-day/prev-week/session H/L + daily open + round
numbers ($10/$5) + FVG/IFVG/PTB/VWAP confluence → ATR-thickness zones (20–150 pt clamp)
→ merge on overlap/proximity → touch/rejection/break counting on M1 history → recency
decay (half-life 400 bars) → weighted scoring → prune & rank.

```
strength = (touch·1.0 + rejection·0.5 + ΣTF-weights + Σsource-weights
            + fresh?0.5 − breaks·1.5) · 0.5^(barsSinceTouch/400)
```

Broken zones keep ≤50% strength and act only with a post-break rejection. Consumed by
the entry gate, TP snap (front-run 8 pt, ≤0.25 ATR shift, cost-gate revalidated), SL
behind zone (≤ +0.30 ATR, **identical-risk lot recompute** — invalid → base stop kept),
TP3 trail anchor (conservative pick vs the swing anchor), panel rows, CSV telemetry,
and a ±1 complex-mode vote that can never satisfy `InpMinFilterScore` alone.

### 4.6 Protection layers

| Layer | Mechanism |
|---|---|
| Per-trade risk | 0.35% → lot; ×0.70 decay per consecutive loss (floor 0.10%); step-down past half the floating-DD limit; SR-widened stops recompute the lot |
| Daily breaker | −2.5% day loss or 3 consecutive losses → breaker (CLOSE_ALL flattens) + hard pause |
| Weekly / monthly | −6% / −10% |
| Trade hygiene | 25 trades/day, single market order, 10-min time stop, swap-window flat, Friday cutoff 19:00 server |
| Entry quality | relative spread cap (default 150% of ATR), ATR floor/ceiling, TP1_TOO_TIGHT, TP1 cost-positivity, SR walls, bias gate (trend-following only) |
| Latch safety | `EXECUTION_UNCERTAIN` auto-reconciles (no pending order, or 90 s watchdog); corrupt state resets cleanly |
| External data | FMP down → broker EURUSD fallback; calendar unavailable → trading continues |

### 4.7 The dashboard

Two columns, draggable, collapsible, `PAUSE ARMING` button: session windows + UTC clock
+ overlaps, spread/ATR/volume percentiles, filter score & bias, SMC/IFVG/PTB, HV state,
positions/lots, risk vs caps, window budget, trades today + consecutive losses, news
countdown, slippage, SR zone summary (nearest R/S with strength & distance),
today/lifetime performance, per-window expectancy, and the 24 h UTC session map.

## 5. Repository layout

```
Predict-A-Trade-Ultra.mq5        the EA — drop into MQL5/Experts/
tools/build_presets.py           self-contained preset generator (stdlib only)
presets/                         4 load-ready .set files
docs/XAUUSD_M1_UltraScalp_Audit.md   per-input audit + effectiveness matrix
docs/SR_Zones_Module.md          SR architecture, inputs, worked scoring example
docs/TP_Methodology.md           ATR-vs-% methodology + ladder feasibility tables
docs/05_Validation_Protocol.md   backtest & go-live protocol
README.md                        this file
prompt.md                        vendor's task spec (rotates per mission)
```

## 6. Verification & backtest protocol (summary)

Full protocol: `docs/05_Validation_Protocol.md`.

- Strategy Tester: **Every tick based on real ticks** (≥99%), real variable spread,
  commission + swap configured, **≥3 months / ≥200 trades** of M1 data (a 1-week / 31-trade
  pass is noise — not a verdict).
- Required runs: **A** SR_Off baseline (trade-for-trade identical to the legacy build)
  → **B** SR advisory (entry count unchanged) → **C** SR soft (production candidate)
  → **D** SR hard (sensitivity).
- Robustness: walk-forward 70/30 rolled ≥3×, ±20% sensitivity on SL/momentum/spread/SR
  parameters (smooth degradation, no cliffs), spread ×1.5 stress, commission 7/10/14
  stress, 1000-shuffle Monte Carlo.
- **Go-live gate**: PF ≥ 1.25 out-of-sample, max DD ≤ 10%, ≥ 200 trades, cost ≤ 40% of
  gross, plus 2–4 weeks forward demo on the live broker feed within 30% of backtest
  expectancy.

## 7. Design constraints honored

- **Self-contained EA**: one .mq5, no includes, no DLLs, no CTrade — native
  `OrderSend`/`SymbolInfo*`/`Position*` throughout. The preset builder is stdlib
  (known-answer self-test at init) rather than calling any external tool.
  local mode; fail-safe grace for previously-validated copies; first-run failure blocks
  start; machine-bound seats; no secrets committed.
- **Trading invariants**: no martingale, no averaging down, no scale-in, no
  loss-chasing recovery in simple mode, stops never move against a position, realized
  risk never exceeds `InpRiskPercent` on any path, `InpSimpleScalpMode=true` default.

## 8. Known limitations

- FMP macro data needs a WebRequest whitelist + operator API key (never committed);
  the EA trades normally without it.
- Tester news filtering uses approximate high-impact event times (no MQL5 calendar in
  the Strategy Tester).
- SR `fresh` approximates "never touched" from touch counts, not full history.
- Session H/L mapping depends on a correct server-UTC offset (auto-detected; verify the
  one-time rollover note in the Journal).
- The bias gate is a soft, consensus-based guard on trend-following setups only; it is
  tunable (`InpSimpleBiasFilter`, `InpSimpleBiasMinAlign`) and fully disable-able.
  for self-containment; the server's response schema is small and stable.
- Stripe key delivery currently logs a redacted confirmation (email worker hook point
  is `mailerSend` in `internal/api/webhook_support.go`) — wire your transactional
  email provider there.

---

*Trade demo first. A backtest alone proves nothing — see the pre-deploy warning at the
top of the source and the go-live gate in the validation protocol.*
