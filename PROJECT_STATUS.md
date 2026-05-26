# Project Status

**Last updated:** 2026-05-26 (v0.4 governance-readiness release — 192/192 tests passing)
**Owner:** Nicholas Hidalgo
**Current state:** v0.4 (governance scorecard + certification registry + relationship tests + source freshness)

## Current Build

| Layer | Count | Status |
|---|---:|---|
| Bronze staging views | 6 | Built, no tests |
| Silver dimensions | 8 | Built, tested (incl. dim_security_history, dim_security_current, dim_investment_manager) |
| Silver facts | 4 | Built, tested (incl. fct_manager_holding; FK relationship tests on all 3 fact tables) |
| Risk marts (gold) | 7 | Built, tested |
| Governance marts | 2 | Built, tested (`governance_scorecard` + `certification_registry` seed) |
| Reconciliation gates | 7 | Built, output to `recon` schema |
| dbt snapshots | 1 | dim_security_snapshot (strategy: check) |
| dbt seeds | 2 | yfinance_to_cusip (bronze schema), certification_registry (marts schema) |
| Total dbt models | 32 | All compiling (`dbt ls --resource-type model` verified) |
| Total dbt tests | 192 | All blocking, 192 of 192 passing as of 2026-05-26 |

## What Exists

- 32 dbt models across 5 layers (bronze, silver, marts/governance, recon) + 1 snapshot + 2 seeds
- 192 blocking dbt tests, 192 of 192 passing as of 2026-05-26
- **v0.4 governance additions:**
  - `governance_scorecard` dbt model: 8 live KPIs computed from actual warehouse data
    - KPI-01: Filing reconciliation gate (GREEN — 0 FAIL rows)
    - KPI-02: Bronze-to-silver reconciliation gate (GREEN — 0 FAIL rows)
    - KPI-03: Price freshness (RED — 25 days stale; expected, no intraday yfinance refresh)
    - KPI-04: Holdings completeness (GREEN — 13,191 silver fact rows)
    - KPI-05: Security coverage (GREEN — 100% of 13F holdings map to dim_security)
    - KPI-06: Zero-value holdings flagged (INFO — 18 rows, valid SEC sub-rounding)
    - KPI-07: Concentration limit compliance (RED — 22/42 synthetic portfolio positions exceed 5% threshold)
    - KPI-08: Composite readiness (BLOCKED — due to KPI-03 and KPI-07 non-GREEN)
  - `certification_registry.csv` seed: 10-row model certification register (roles, not names)
  - 14 FK relationship tests across all silver fact tables (fct_position_daily, fct_price_daily, fct_benchmark_return_daily, fct_manager_holding)
  - 1 active source freshness gate: `raw_13f_filings` (120d warn / 180d error via `_ingested_at TIMESTAMPTZ`)
  - Additional accepted_values and expression_is_true tests on silver dimensions and facts
- **v0.3 SEC 13F ingestion (unchanged):**
  - 5 institutional managers (State Street, Fidelity, Wellington, MFS, Loomis Sayles)
  - 30,135 raw holdings ingested to `bronze.raw_13f_holdings`
  - 13,191 silver fact rows in `fct_manager_holding` after manager-security-period aggregation
  - $5.906T total reported AUM across 5 managers, Q4 2025
  - 100% reconciliation against SEC cover-page totals
  - 18 zero-value/zero-share anomalies surfaced in `recon.recon_zero_value_holdings`
- EDGAR submissions API client, XML parser, bronze DDL + idempotent loader
- Two reconciliation gates: `recon_filing_totals_reconciliation`, `recon_bronze_to_silver_reconciliation`
- Singular tests enforcing zero FAIL rows in both recon gates
- Static HTML dashboard with Chart.js (`dashboard/index.html`)
- Type 2 SCD on dim_security via dbt snapshot
- `dim_security_history` and `dim_security_current` SCD models
- 7 architecture documents in `docs/architecture/` — all updated to v0.4 status

## What Does Not Exist (v0.5 Candidates)

- Source freshness on DATE-column sources (requires `_ingested_at TIMESTAMPTZ` addition to raw_security_master, raw_prices, raw_ratings, raw_benchmarks)
- Type 2 SCD on dim_issuer or dim_investment_manager
- CUSIP in dim_security_snapshot check_cols
- SCD history for 13F-sourced securities
- GitHub Actions CI
- Database role for read-only AI agent access
- AI interaction logging table
- Semantic layer definition (dbt Semantic Layer or view-based)
- Extended manager universe (Vanguard, BlackRock, T. Rowe Price, Putnam)

## Known Issues

- `logs/dbt.log` is tracked but ignored by current `.gitignore`. Owner must run `git rm --cached logs/dbt.log` before commit.
- `recon_bronze_to_silver_reconciliation` will FAIL if `dbt run -s dim_security` is not run before `fct_manager_holding`. Run order documented in DECISIONS.md.
- governance_scorecard KPI-08 is BLOCKED (not READY) because KPI-03 (price freshness) and KPI-07 (concentration limits) are RED. This is the correct honest output — synthetic portfolio deliberately exercises the 5% concentration limit rule.

## Repo Health

- Tag: `v0.1.0`, `pre-audit-2026-05-06`
- Branch: `main`, ahead of `origin/main` (pending owner commit)
- Working tree: modified — v0.4 governance files created/modified, awaiting owner commit
