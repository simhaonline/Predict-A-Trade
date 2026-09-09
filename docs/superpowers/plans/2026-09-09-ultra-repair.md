# Ultra EA repair plan

Goal: repair confirmed entry, execution and risk defects while preserving the user's existing edits and configured strategy limits.

Architecture: retain the standalone MQL5 EA. Exercise selected actual function bodies through the existing C++ terminal shim; native compilation and broker tests remain separate release gates.

- [ ] Resolve duplicate risk definition; verify mobile caps, environment multipliers, signed R:R and volume conservation with the existing five failing tests.
- [ ] Add failing regressions for late indicator readiness, broker TP preservation, quote slippage, and stop placement. Fix each cause and run tests.
- [ ] Audit dispatch, partial closes, restart state and loss breakers; repair confirmed defects with focused regressions.
- [ ] Run all local tests and diff checks; document actual blockers, remaining native MT5 checks and deployment instructions.

Scope: no live orders, no changes to risk thresholds to force trades, no profitability claims. Existing uncommitted changes stay intact except where a verified defect requires correction.
