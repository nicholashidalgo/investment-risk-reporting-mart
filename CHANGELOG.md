# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.1.0] - 2026-05-02

### Added

- **Bronze schema** — 6 source tables: `raw_security_master`, `raw_positions`, `raw_prices`, `raw_benchmarks`, `raw_ratings`, `raw_stress_scenarios`
- **Ops schema** — `ops.run_log` for ingestion audit trail with row count, lag days, SLA status, and failure message
- **Ingestion script** — `scripts/ingest_seed_data.py`: pulls 1 year of daily prices for 11 S&P 500 equities and 2 benchmark ETFs via yfinance; synthesizes 10 corporate bond positions with realistic ratings distribution; generates positions across PORT_CORE ($100M) and PORT_FLEX ($50M) with capped-weight algorithm (8% equity, 6% bond); inserts 5 stress scenarios and 120 point-in-time ratings rows
- **Silver layer** — 4 dimensions (`dim_security`, `dim_portfolio`, `dim_benchmark`, `dim_date`) and 3 fact tables (`fct_position_daily`, `fct_price_daily`, `fct_benchmark_return_daily`)
- **7 risk marts**: `mart_portfolio_exposure`, `mart_credit_exposure`, `mart_duration_summary`, `mart_var_parametric`, `mart_tracking_error`, `mart_scenario_impact`, `mart_concentration_limits`
- **4 reconciliation gates**: `recon_position_to_nav`, `recon_benchmark_coverage`, `recon_stale_prices`, `recon_rating_coverage`
- **108 dbt tests** across `not_null` (36), `unique` (18), `accepted_values` (12), `dbt_utils.expression_is_true` (42)
- **Static HTML dashboard** (`dashboard/index.html`) — single-file, dark theme, Chart.js, portfolio toggle, KPI scorecard, donut/bar/stacked-bar charts, scenario and concentration tables, recon gate status badges
- **README.md** — architecture Mermaid diagram, model inventory, methodology comparison table, setup instructions
- **DATA_CONTRACT.md** — grain, KPI definitions, formulas, source dependencies, test coverage for all 24 models
- **METHODOLOGY.md** — explicit caveats for VaR, tracking error, stress scenarios, duration, concentration limits, private credit, and data sources
- **CHANGELOG.md** — this file
- **profiles/profiles.yml.template** — dbt profile template using environment variables
- **.gitignore** — Python, dbt, macOS, IDE, secrets, local data exports, personal prep docs
