# TP Methodology — ATR Distance × Percentage Volume

The exit engine's single governing rule:

> **Target DISTANCE = fixed ATR multiple (volatility-adjusted).**
> **Target VOLUME SPLIT = decimal percentage fraction of position size.**
> **Minimum viability = absolute money in account currency.**
> Never fixed points. Never a percentage of gold price. Never fixed lots.

## Why each format

| Concern | Method | Why not the alternative |
|---|---|---|
| Where TP/SL sits | ATR multiple (`0.40` = 0.40 × ATR) | Fixed points are too wide in Asia (ATR ~30 pt) and too tight in London/NY (~150 pt); a % of price is absurd at scalp scale — 0.05% of 3400 = 170 pt = swing trade |
| How much closes there | decimal fraction (`0.75` = 75%) | Whole-number inputs (75) are a classic misconfiguration → guarded at init (auto-divide + loud warning, or `INIT_PARAMETERS_INCORRECT`) |
| Minimum viability | account currency (`0.30`) | A fixed-money floor must be checked against the REAL costs, which scale with volume and spread — hence the cost gate rather than a fixed TP |

Because the stop is ATR-based, ATR targets keep R:R stable across volatility regimes:

| Leg | Distance | Split | R:R (SL = 0.80 ATR) |
|---|---|---|---|
| TP1 | `SCALP_TP1_ATR` = 0.40 | 0.75 | 0.50R |
| TP2 | `SCALP_TP2_TOT` = 0.75 | 0.20 | 0.94R |
| TP3 | `SCALP_TP3_TOT` = 1.15 | 0.05 (runner, trailed) | 1.44R |

`InpMaxCostToTP1Pct = 40` only behaves correctly when TP1 scales with volatility — a
fixed TP would silently break the cost gate in wide-spread hours.

## Simple-mode constants (audit-locked)

Declared once, top of the engine (`SCALP_*`), each commented with its complex-mode
input analogue:

| Constant | Value | Complex-mode analogue |
|---|---|---|
| `SCALP_TP1_ATR` | 0.40 | `InpTP1_ATR_Floor 0.25 .. Cap 0.40` |
| `SCALP_TP2_TOT` | 0.75 | `InpTP2_ATR_Floor 0.60 .. Cap 1.10` |
| `SCALP_TP3_TOT` | 1.15 | `InpTP3_ATR_Floor 1.00 .. Cap 1.80` |
| `SCALP_SL_ATR` | 0.80 | `InpSL_ATR_Multiplier` |
| `SCALP_SL_REV` | 0.45 (beyond the extreme) | — |
| `SCALP_SL_BRK` | 0.85 | — |

Signal-specific behavior preserved: VWAP-reversion TP1 still targets the mean (min
0.6 ATR away); all normalization / min-distance / spread-cost logic untouched.

## Recommended split (default) and alternative

- **0.75 / 0.20 / 0.05** — default, stricter capital protection: covers costs and
  banks at TP1, tiny runner (suited to `InpMaxTradeMinutes = 10`).
- **0.75 / 0.15 / 0.10** — acceptable alternative for a larger trailed runner.

## Percentage-input validation (init)

- Any `Pct > 1.0` → misconfiguration. If all three are in (1.0, 100] and sum to
  100 ± 0.5 → auto-divide by 100 with a loud warning; otherwise
  `INIT_PARAMETERS_INCORRECT`.
- Fractions must satisfy `|TP1+TP2+TP3 − 1.0| ≤ 0.001` and be > 0 when
  `InpUseThreeTargets=true`.

## Lot-ladder feasibility (broker minimums)

Every leg must be ≥ `SYMBOL_VOLUME_MIN`, a multiple of `SYMBOL_VOLUME_STEP`, and every
**residual after a partial close** must also be ≥ min lot (a broker rejects a close
that leaves a sub-minimum remainder). Legacy volume split: `leg1 = roundDown(lot×pct1)`,
`leg2 = roundDown(lot×pct2)`, `leg3 = remainder` (carries rounding error).

At `volMin = 0.01` the exact 75/20/5 ladder needs ≥ **0.20 lots**:

| Position lot | 0.01 | 0.02 | 0.05 | 0.10 | 0.20 | 0.50 |
|---|---|---|---|---|---|---|
| 3-leg 75/20/5 | ✗ | ✗ | ✗ | ✗ (leg3 < min) | ✓ exact | ✓ exact |
| Effective plan | 1-leg | 1-leg | 1-leg | 2-leg | 3-leg | 3-leg |

Degradation cascade (`InpAutoDegradeTPLadder = true`):
1. 3-leg invalid → **2-leg** (TP1 then TP2, split renormalized)
2. → **1-leg** (whole position at TP1)
3. → **reject** (`LADDER_INFEASIBLE`).

Residue placement follows `InpLadderRoundingMode`: `LADDER_FAVOR_TP1` (default),
`LADDER_FAVOR_RUNNER`, or `LADDER_PROPORTIONAL`. The chosen plan is logged on every
entry: `LADDER=3LEG 0.03/0.01/0.01`.

## TP1 minimum-viability guard (spread-aware)

```
minTP1Distance = MAX( (stopsLevel + InpStopLevelBufferPoints) × point,
                      (currentSpread + expectedSlippage) × point × InpTP1SpreadMultiple )
```

If the ATR-derived TP1 sits closer than this, the trade is **rejected** (`TP1_TOO_TIGHT`
on the panel/log) — TP1 is never silently widened beyond its cap. This protects the
0.50R plan from dead-spread hours where the whole ladder would be cost-noise.