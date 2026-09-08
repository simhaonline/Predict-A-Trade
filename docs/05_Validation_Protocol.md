# Validation & Backtest Protocol

How to prove the EA (and any change to it) before real capital. Full go-live gate at
the end — treat it as non-negotiable.

## 1. Tester configuration

- Model: **Every tick based on real ticks**, quality ≥ 99%.
- Symbol: your broker's actual gold symbol (verify the exact name; `InpValidateSymbolOnInit`
  fails fast on non-tradeable symbols).
- **Real variable spread** — never fixed; a scalp lives on spread.
- Include commission and swap in the tester symbol settings.
- Data window: ≥ 6 months, ideally 12–24 months of M1, spanning at least one
  high-volatility regime.
- Server time offset: verify the broker's GMT offset before trusting session results.

## 2. Required runs

| Run | Preset | Purpose | Pass condition |
|---|---|---|---|
| A | `XAUUSD_M1_UltraScalp_SR_Off.set` | baseline vs pre-SR build | trade-for-trade identical to the legacy build |
| B | `XAUUSD_M1_UltraScalp_Advisory.set` | SR observes, never blocks | entry count identical to run A |
| C | `XAUUSD_M1_UltraScalp.set` (SOFT) | production candidate | PF/DD targets below |
| D | HARD variant | sensitivity check | no instability cliff |

## 3. Robustness checks

- **Walk-forward**: optimize on 70% in-sample, validate on 30% out-of-sample, roll the
  window at least 3 times. Out-of-sample decay must be gradual.
- **Parameter sensitivity (±20%)**: `InpSL_ATR_Multiplier`, `InpScalpMinMomentumATR`,
  `InpMaxSpreadPoints`, `InpSRWallMinStrength`. Performance must degrade **smoothly** —
  a cliff means overfitting.
- **Spread stress**: rerun with spread ×1.5 and ×2.0. A true scalp edge survives ×1.5.
- **Commission stress**: `InpCommissionPerLotRTFallback` at 7 / 10 / 14.
- **Monte Carlo**: 1000 trade-order shuffles → report median and 5th-percentile max DD.
- **Breakdowns**: per-session and per-signal-mode expectancy/PF/win-rate/avg-R — the
  CSV log and per-window performance report feed this directly.

## 4. Reporting metrics

Net profit, profit factor, expectancy per trade ($ and R), max DD (% and $), longest
losing streak, average time-in-trade, TP1/TP2/TP3 hit rates, SL hit rate, time-stop
rate, average realized slippage, cost as % of gross profit. The EA's own telemetry
(CSV `ARM` rows + performance reports + MAE/MFE tracking) supplies all of these.

## 5. Go-live gate

No live capital until run C shows, **out-of-sample**:

- Profit factor ≥ 1.25
- Max DD ≤ 10%
- ≥ 200 trades
- Cost ≤ 40% of gross profit
- 2–4 weeks forward demo **on the live broker feed** matching backtest expectancy
  within 30%

Then start live at reduced risk (`InpRiskPercent` 0.35% is the ceiling; consider
half that for the first month), keep the daily breaker armed, and re-run run A after
every EA update to confirm behavioral equivalence claims.

## 6. EA-side self-tests (run on every attach)

`SelfTest()` / `LicenseSelfTest()` / SR self-test print PASS/FAIL to the Journal:
Pct fractions & sum, TP monotonicity, ladder feasibility at 6 lot sizes, risk-math
round trip (±1 tick), point scaling for 2/3-digit gold, stop/freeze compliance at
minimum ATR, SR sanity at 0/1/N zones, advisory never blocks, netting detection,
SHA256 known answers. Categories gating init fail loudly — never force-start past a
failed self-test.