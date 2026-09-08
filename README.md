# Predict-A-Trade-Ultra — XAUUSD M1 Ultra-Scalping EA + License Platform

**Predict-A-Trade-Ultra.mq5** · version 2.00 · a single-file MetaTrader 5 Expert Advisor
for gold (XAUUSD) M1 — plus an optional **Go license server** and **mobile command
bridge** for distribution to subscribers.

Fully **self-contained on the trading side**: one `.mq5` file, zero `#include`, zero
DLLs, zero external scripts. All dependencies are native MQL5 or optional web data the
EA degrades gracefully without. The license server is a separate, opt-in component for
vendors — the EA runs identically without it.

```
Predict-A-Trade-Ultra.mq5      the EA (single file, ~4,400 lines)
tools/build_presets.py         self-contained .set generator (Python stdlib only)
presets/*.set                  5 ready-to-load presets (304 inputs each)
license-server/                optional Go license backend (Gin + Redis + PostgreSQL)
docs/                          audit, methodology, module & deployment docs
```

---

## 1. What this EA is

An ultra-scalper that trades XAUUSD M1 through a four-session opportunity engine
(Sydney, Tokyo, London, New York + their overlap windows), with:

- **Simple Scalp Mode** (default, recommended): a four-signal M1 engine — VWAP
  mean-reversion, London-open breakout, NY-open momentum, EMA-pullback — with an
  audit-locked ATR distance profile (`SCALP_*` constants).
- **Complex Mode** (`InpSimpleScalpMode=false`): the full multi-filter engine (EMA /
  SuperTrend / ADX / VWAP / FVG / AMD / volume / liquidity / RSI / SMC scoring) for
  research comparison.
- **TP1/TP2/TP3 exit ladder** with cost-aware partial closes, break-even lock, and a
  structure/zone trail on the runner.
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
- **License client** (optional): machine-bound activation + heartbeat against the Go
  license server, with a fail-safe grace period. Blank key = unrestricted local mode.
- **Mobile command bridge** (optional): control the EA from the MT5 iOS/Android app
  through pending-order comments — no native app needed.

## 2. Quick start

### Trading (individual trader)

1. Copy `Predict-A-Trade-Ultra.mq5` to `MQL5/Experts/`, compile in MetaEditor (F7).
   Expected: 0 errors, 0 warnings (strict mode).
2. Optional data feeds: whitelist `https://financialmodelingprep.com` under
   Tools → Options → Expert Advisors → Allow WebRequest. The EA trades fine without it.
3. Attach to an XAUUSD M1 chart, load a preset from `presets/`.
4. Check the Journal for the BROKER PROFILE block and `self-test PASS` lines; the panel
   shows live session windows, gate reasons, and risk state.
5. **Demo first** — see the go-live gate in `docs/05_Validation_Protocol.md`.

### Subscriber (licensed copy)

Same as above plus: enter `InpLicenseKey`, whitelist the vendor's license URL, done.
First validation happens at init; the EA then heartbeats every 10 minutes from
`OnTimer` (never blocking the tick path). Server outages are covered by a 12-hour
default grace period. Full matrix in `docs/License_System_Guide.md`.

### Mobile control (anyone with the MT5 app)

Place a **pending order** on the chart with one of these comments; the EA executes it
and deletes the order:

| Comment | Effect |
|---|---|
| `STOP_EA` | stop opening new trades |
| `START_EA` | resume trading |
| `RISK_0.2` | risk override to 0.2% (capped at 5%) |

### Vendor (running the license server)

```bash
cd license-server
cp .env.example .env    # set DATABASE_URL, POSTGRES_PASSWORD, Stripe secrets
docker compose up -d    # API + Redis + Postgres; schema auto-applies
go test ./...           # routing/HTTPS/header smoke tests
```

Wire Stripe webhooks (`checkout.session.completed`,
`customer.subscription.deleted`) to `https://api.yourdomain.com/v1/webhook/stripe`;
keys are issued, hashed, and emailed automatically. Details:
`license-server/README.md` and `docs/License_System_Guide.md`.

### Presets

| File | Use |
|---|---|
| `XAUUSD_M1_UltraScalp.set` | Production profile — SR soft filter, license blank |
| `XAUUSD_M1_UltraScalp_SR_Off.set` | A/B baseline — SR module off (bit-identical legacy behavior) |
| `XAUUSD_M1_UltraScalp_Advisory.set` | SR observes & logs, never blocks |
| `XAUUSD_M1_UltraScalp_PropFirm.set` | Prop-firm guardrails: 2.0% daily loss, 4% trailing DD, 15 trades/day |
| `XAUUSD_M1_UltraScalp_Licensed.set` | Production + license inputs ready (key blank, grace 720 min) |

Regenerate all five after changing the profile or EA inputs:

```
python3 tools/build_presets.py
```

The generator embeds the authoritative profile (it does not depend on prompt.md's
current mission), parses the EA's own input declarations, serializes enums to MT5's
integer `.set` format, applies per-variant overrides, and verifies name parity with the
source. Stdlib Python only.

## 3. How the EA works

### 3.1 The trading loop (every tick)

```
OnTick
 ├─ LICENSE gate (blank key = pass-through)        // [LICENSE]
 ├─ mobile command bridge (order-comment scan)     // [LICENSE]
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
               license heartbeat (every 10 min — the ONLY place WebRequest runs)
OnTradeTransaction: fills → slippage & commission learning, position state rebuild
OnChartEvent: panel drag / collapse / pause button
```

### 3.2 Entry pipeline (`TryArm` → `CanEnter`)

A trade fires only when **all** gates pass, in order:

1. **License gate** — `LicenseCheckGate()` (blank key passes; otherwise requires an
   active license, `auto_trading_enabled`, and mobile `START` state).
2. A scalp signal exists (simple mode: `EvaluateScalpSignal` on the last closed M1 bar —
   VWAP reversion / London breakout / NY momentum / EMA pullback).
3. Session gate: inside an enabled window (momentum signals restricted to liquid hours).
4. News gate (MQL5 calendar + optional FMP headlines), stabilization window,
   swap-danger window, weekend/rollover guard.
5. Spread hard cap (35 pt) + broken-feed extreme check; ATR floor/chop ceiling.
6. Simple-mode guards: 60 s same-direction spacing, 0.35 ATR proximity to an open
   scalp, daily trade cap (25), position cap.
7. **SR entry gate** (`// [SR]`): blocks entries into an opposing zone with
   strength ≥ 5.0 within 0.45 ATR (unless a confirmed breakout); HARD mode adds TP1
   headroom ×1.10. Reasons are machine-parsable (`SR_WALL_5.8@0.31A`, `SR_NO_HEADROOM`).
8. Sizing: `InpRiskPercent` 0.35% → lot, with the no-martingale underwater freeze,
   min-lot fallback, aggregate/directional risk caps, and window budget.
9. **TP1 viability**: TP1 must exceed max(stops-level + buffer,
   (spread + expected slippage) × `InpTP1SpreadMultiple`) — else the trade is rejected
   (`TP1_TOO_TIGHT`), never silently widened.
10. Cost gate: TP1 must clear `InpMinNetProfitTP1Money` after spread + slippage +
    commission, with cost ≤ 40% of gross.
11. Dispatch: single market order; SL and broker TP = the armed scalp plan (snapshot
    travels to position management so the executed plan matches the validated one).

### 3.3 The TP/SL methodology (the core rule)

> **Distance = ATR multiple. Volume split = decimal fraction. Minimums = account
> currency.** Never fixed points, never a % of gold price, never fixed lots.

| Leg | Distance from entry | Closes | R:R (SL = 0.80 ATR) |
|---|---|---|---|
| TP1 | **0.40 × ATR** (`SCALP_TP1_ATR`) | **75%** | 0.50R |
| TP2 | **0.75 × ATR** total | **20%** | 0.94R |
| TP3 | **1.15 × ATR** total | **5%** runner, trailed | 1.44R |

Why: gold M1 ATR swings ~30 pt (Asia) to ~150 pt (London/NY) — fixed points are wrong in
both regimes; a % of price (0.05% of 3400 = 170 pt) is a swing trade at scalp scale.
Because the stop is ATR-based (0.80 momentum / 0.45 reversion-beyond-extreme / 0.85
London breakout), ATR targets keep R:R stable across regimes, and the 40%-cost gate only
behaves correctly when TP1 scales with volatility.

Split rules: `InpTP1Pct/2/3` are **decimal fractions** summing to 1.0 (enforced at
init; whole-number 75/20/5 auto-divides with a loud warning). **Lot-ladder
feasibility**: every leg ≥ broker min lot and every post-close residual ≥ min lot —
at 0.01 min lot the 75/20/5 ladder needs ≥ 0.20 lots, below that the EA cascades
3-leg → 2-leg → 1-leg (`InpAutoDegradeTPLadder`, residue via
`InpLadderRoundingMode`, default `LADDER_FAVOR_TP1`).

### 3.4 The SR zones module

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

### 3.5 Protection layers

| Layer | Mechanism |
|---|---|
| Per-trade risk | 0.35% → lot; ×0.70 decay per consecutive loss (floor 0.10%); step-down past half the floating-DD limit; SR-widened stops recompute the lot |
| Daily breaker | −2.5% day loss or 3 consecutive losses → breaker (CLOSE_ALL flattens) + hard pause |
| Weekly / monthly | −6% / −10% |
| Trade hygiene | 25 trades/day, single market order, 10-min time stop, swap-window flat, Friday cutoff 19:00 server |
| Entry quality | spread cap 35 pt, ATR floor/ceiling, TP1_TOO_TIGHT, TP1 cost-positivity, SR walls |
| External data | FMP down → broker EURUSD fallback; calendar unavailable → trading continues |
| License | invalid/expired → no new trades; optional flatten on revoke; grace period covers outages |

### 3.6 License system (how the pieces fit)

- **Server** (Go + Redis + Postgres): `POST /v1/activate` binds a seat
  `(license, machine, account, broker)` up to `max_activations`; `POST /v1/heartbeat`
  keeps it alive and serves settings bumps; `/v1/webhook/stripe` issues keys on
  checkout and revokes on cancellation. Redis caches validation (60 s heartbeat /
  1 h activation TTL) so PostgreSQL sees a fraction of the traffic — sized comfortably
  for 10k+ subscribers.
- **Client** (inside the EA): SHA256 machine fingerprint (self-tested against known
  answers), activate-on-init, 10-minute heartbeat from `OnTimer` only, JSON parsed
  without external libraries, grace-period fallback, optional flatten on revoke.
- **Security**: raw keys stored nowhere (SHA256 only), HTTPS enforced, per-IP and
  per-key rate limits, Stripe HMAC verification, no secrets in the repo.

### 3.7 The dashboard

Two columns, draggable, collapsible, `PAUSE ARMING` button: session windows + UTC clock
+ overlaps, spread/ATR/volume percentiles, filter score & bias, SMC/IFVG/PTB, HV state,
live gate reason (including `LICENSE: ...` and `SR_WALL_...`), account/margin,
positions/lots, risk vs caps, window budget, trades today + consecutive losses, news
countdown, slippage, SR zone summary (nearest R/S with strength & distance),
today/lifetime performance, per-window expectancy, and the 24 h UTC session map.

## 4. Repository layout

```
Predict-A-Trade-Ultra.mq5        the EA — drop into MQL5/Experts/
tools/build_presets.py           self-contained preset generator (stdlib only)
presets/                         5 load-ready .set files (304 inputs each)
license-server/                  optional Go license backend (compose stack, tests)
docs/XAUUSD_M1_UltraScalp_Audit.md   per-input audit + effectiveness matrix
docs/SR_Zones_Module.md          SR architecture, inputs, worked scoring example
docs/TP_Methodology.md           ATR-vs-% methodology + ladder feasibility tables
docs/License_System_Guide.md     deployment, Stripe, MT5 setup, mobile control, security
docs/05_Validation_Protocol.md   backtest & go-live protocol
README.md                        this file
prompt.md                        vendor's task spec (rotates per mission)
```

## 5. Verification & backtest protocol (summary)

Full protocol: `docs/05_Validation_Protocol.md`.

- Strategy Tester: **Every tick based on real ticks** (≥99%), real variable spread,
  commission + swap configured, ≥6 months of M1 data.
- Required runs: **A** SR_Off baseline (trade-for-trade identical to the legacy build)
  → **B** SR advisory (entry count unchanged) → **C** SR soft (production candidate)
  → **D** SR hard (sensitivity).
- Robustness: walk-forward 70/30 rolled ≥3×, ±20% sensitivity on SL/momentum/spread/SR
  parameters (smooth degradation, no cliffs), spread ×1.5 stress, commission 7/10/14
  stress, 1000-shuffle Monte Carlo.
- **Go-live gate**: PF ≥ 1.25 out-of-sample, max DD ≤ 10%, ≥ 200 trades, cost ≤ 40% of
  gross, plus 2–4 weeks forward demo on the live broker feed within 30% of backtest
  expectancy.

## 6. Design constraints honored

- **Self-contained EA**: one .mq5, no includes, no DLLs, no CTrade — native
  `OrderSend`/`SymbolInfo*`/`Position*` throughout. The preset builder is stdlib
  Python, versioned in `tools/`. The license client implements SHA256 natively in MQL5
  (known-answer self-test at init) rather than calling any external tool.
- **License invariants**: `WebRequest` only in `OnTimer`; blank key = zero-overhead
  local mode; fail-safe grace for previously-validated copies; first-run failure blocks
  start; machine-bound seats; no secrets committed.
- **Trading invariants**: no martingale, no averaging down, no scale-in, no
  loss-chasing recovery in simple mode, stops never move against a position, realized
  risk never exceeds `InpRiskPercent` on any path, `InpSimpleScalpMode=true` default.

## 7. Known limitations

- FMP macro data needs a WebRequest whitelist + operator API key (never committed);
  the EA trades normally without it.
- Tester news filtering uses approximate high-impact event times (no MQL5 calendar in
  the Strategy Tester).
- SR `fresh` approximates "never touched" from touch counts, not full history.
- Session H/L mapping depends on a correct server-UTC offset (auto-detected; verify the
  one-time rollover note in the Journal).
- Simple mode hardcodes entry spacing (60 s / 0.35 ATR) and signal thresholds; only
  `InpScalpMinMomentumATR` and the `SCALP_*` constants tune it.
- The license client's JSON parsing is deliberately rudimentary (`StringFind`-based)
  for self-containment; the server's response schema is small and stable.
- Stripe key delivery currently logs a redacted confirmation (email worker hook point
  is `mailerSend` in `internal/api/webhook_support.go`) — wire your transactional
  email provider there.

---

*Trade demo first. A backtest alone proves nothing — see the pre-deploy warning at the
top of the source and the go-live gate in the validation protocol.*