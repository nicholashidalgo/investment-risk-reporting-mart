# Data Contract

**Project:** investment_risk_mart  
**Version:** 0.1.0  
**As of:** 2026-05-02  
**Author:** Nicholas Hidalgo

---

## 1. Purpose and Scope

This document defines the grain, column semantics, KPI formulas, source dependencies, and test coverage for all models in the `investment_risk_mart` dbt project. It serves as the authoritative reference for consumers of the mart and recon schemas.

Scope: bronze source tables, silver dimensions and facts, seven risk mart models, four reconciliation gate models.

Out of scope: ops.run_log (operational metadata, not an analytics output).

---

## 2. Refresh Cadence

| Layer | Cadence | Trigger |
|---|---|---|
| Bronze ingest | Manual | `python scripts/ingest_seed_data.py` |
| dbt run (all layers) | Manual after ingest | `dbt run` |
| dbt test | Manual after run | `dbt test` |
| Dashboard | Manual | Re-open `dashboard/index.html` after dbt run (static snapshot) |

The pipeline is designed for idempotent refresh: re-running ingest upserts all rows (no duplicates), and dbt drops and recreates all table materializations on each run.

---

## 3. Bronze Sources

All tables in the `bronze` schema are written by `scripts/ingest_seed_data.py`. They are the system of record for all upstream data.

### bronze.raw_security_master
**Grain:** One row per `sec_id`.

| Column | Type | Description |
|---|---|---|
| sec_id | TEXT PK | Unique security identifier (ticker for equities/ETFs, BOND_NNN for synthetics) |
| ticker | TEXT | Exchange ticker; equals sec_id for all securities in this dataset |
| asset_class | TEXT | Equity, Fixed Income, or Benchmark |
| sector | TEXT | GICS-aligned sector label |
| rating | TEXT | Credit rating at ingestion time; NR for equities and benchmarks |
| maturity | DATE | Maturity date for fixed income; NULL for equities |
| issue_date | DATE | Issue date for fixed income; NULL for equities |

### bronze.raw_positions
**Grain:** One row per `(portfolio_id, sec_id, position_date)`.

| Column | Type | Description |
|---|---|---|
| portfolio_id | TEXT | PORT_CORE or PORT_FLEX |
| sec_id | TEXT | Security identifier |
| position_date | DATE | As-of date for the holding snapshot |
| market_value | NUMERIC | Mark-to-market value in USD |
| par_value | NUMERIC | Face/par value in USD; equals market_value for equities |
| weight | NUMERIC | Position weight as a decimal fraction of portfolio NAV |

### bronze.raw_prices
**Grain:** One row per `(sec_id, price_date)`.

| Column | Type | Description |
|---|---|---|
| sec_id | TEXT | Security identifier |
| price_date | DATE | Price observation date (trading day) |
| price | NUMERIC | Closing price; auto-adjusted for splits/dividends for yfinance sources |
| source | TEXT | yfinance (real market data) or synthetic (simulated bond prices) |

**Freshness:** warn after 2 days, error after 7 days.

### bronze.raw_benchmarks
**Grain:** One row per `(benchmark_id, benchmark_date)`.

| Column | Type | Description |
|---|---|---|
| benchmark_id | TEXT | BENCH_SPY or BENCH_AGG |
| benchmark_date | DATE | Return observation date |
| return | NUMERIC | Daily total return as a decimal (e.g., 0.01234 = 1.234%) |

**Freshness:** warn after 2 days, error after 7 days.

### bronze.raw_ratings
**Grain:** One row per `(sec_id, rating_date, agency)`.

| Column | Type | Description |
|---|---|---|
| sec_id | TEXT | Security identifier |
| rating_date | DATE | Date the rating was assigned or confirmed |
| rating | TEXT | Credit rating symbol (AAA, AA, A, BBB, BB, NR, etc.) |
| agency | TEXT | Moody's, S&P, or Fitch |

### bronze.raw_stress_scenarios
**Grain:** One row per `(scenario_id, factor)`.

| Column | Type | Description |
|---|---|---|
| scenario_id | TEXT | Scenario name (e.g., STRESS_EQUITY_10) |
| factor | TEXT | equity, interest_rate, or credit_spread |
| shock_pct | NUMERIC | Shock magnitude; percentage points for equity, basis points for rates/spreads |

---

## 4. Silver Layer

### dim_security
**Grain:** One row per `sec_id`.  
**Materialization:** table  
**Dependencies:** stg_security_master, stg_ratings

| Column | Description |
|---|---|
| sec_id | Primary key |
| ticker | Exchange ticker |
| asset_class | Equity, Fixed Income, or Benchmark (SPY/AGG normalized to Benchmark) |
| sector | GICS-aligned sector |
| maturity | Fixed income maturity date |
| issue_date | Fixed income issue date |
| rating | Latest credit rating; coalesces from stg_ratings (latest by rating_date desc), falls back to raw security master rating |
| latest_rating_agency | Agency that issued the most recent rating |
| latest_rating_date | Date of the most recent rating |

### dim_portfolio
**Grain:** One row per `portfolio_id`.  
**Materialization:** table  
**Dependencies:** stg_positions

### dim_benchmark
**Grain:** One row per `benchmark_id`.  
**Materialization:** table  
**Dependencies:** stg_benchmarks

### dim_date
**Grain:** One row per `date_day`.  
**Materialization:** table  
**Dependencies:** stg_positions, stg_prices  
**Coverage:** Full date spine from minimum of (min position_date, min price_date) to maximum of (max position_date, max price_date). Includes weekends.

### fct_position_daily
**Grain:** One row per `(portfolio_id, sec_id, position_date)`.  
**Materialization:** table  
**Dependencies:** stg_positions, dim_security, dim_date

Denormalized with `asset_class`, `sector`, `rating`, `year`, `quarter`, `month` from dims.

### fct_price_daily
**Grain:** One row per `(sec_id, price_date)`.  
**Materialization:** table  
**Dependencies:** stg_prices, dim_security, dim_date

### fct_benchmark_return_daily
**Grain:** One row per `(benchmark_id, benchmark_date)`.  
**Materialization:** table  
**Dependencies:** stg_benchmarks, dim_date

---

## 5. Risk Marts

### mart_portfolio_exposure
**Grain:** One row per `portfolio_id` (latest position_date snapshot).

| Column | Formula / Description | Units | Expected Range |
|---|---|---|---|
| portfolio_id | Primary key | — | PORT_CORE, PORT_FLEX |
| position_date | Latest date with position data | — | — |
| total_nav | SUM(market_value) across all positions | USD | > 0 |
| top10_mv | SUM of market_value for top 10 positions by MV | USD | > 0 |
| top10_concentration_pct | top10_mv / total_nav × 100 | % | 0–100 |
| asset_class_breakdown | JSON array: [{asset_class, mv, pct}] ordered by mv desc | JSON | — |
| sector_breakdown | JSON array: [{sector, mv, pct}] ordered by mv desc | JSON | — |

**Known limitations:** JSON breakdown columns are not individually testable by dbt. Asset class percentages sum to 100% by construction.

### mart_credit_exposure
**Grain:** One row per `(portfolio_id, rating_bucket)` at latest position_date. Fixed income positions only.

| Column | Formula | Units | Expected Range |
|---|---|---|---|
| portfolio_id | — | — | — |
| position_date | Latest date | — | — |
| rating_bucket | Standardized bucket: AAA-AA, A, BBB, BB, B, CCC and below, NR | — | — |
| market_value | SUM(market_value) for positions in this bucket | USD | ≥ 0 |
| pct_of_fixed_income | market_value / SUM(all FI market_value) × 100 | % | 0–100 |
| pct_of_total_nav | market_value / total_nav × 100 | % | 0–100 |

**Known limitations:** Equities (asset_class = 'Equity') and benchmarks are excluded. Rating bucket assignment uses the `dim_security.rating` column, which coalesces to the most recent agency rating.

### mart_duration_summary
**Grain:** One row per `portfolio_id` at latest position_date. Fixed income only.

| Column | Formula | Units | Expected Range |
|---|---|---|---|
| portfolio_id | Primary key | — | — |
| position_date | Latest date | — | — |
| fi_nav | SUM(market_value) for FI positions | USD | > 0 |
| weighted_avg_duration | Σ(MVᵢ / fi_nav × Dᵢ) where Dᵢ is synthetic bucket duration | years | > 0 |

Synthetic duration buckets: 0–2y → 1.5, 2–5y → 3.5, 5–10y → 6.5, 10y+ → 12.0.  
**See METHODOLOGY.md §4 for limitations.**

### mart_var_parametric
**Grain:** One row per `portfolio_id` at latest position_date.

| Column | Formula | Units | Expected Range |
|---|---|---|---|
| portfolio_id | Primary key | — | — |
| position_date | Latest date | — | — |
| nav | SUM(market_value) | USD | > 0 |
| sigma_daily | sqrt(Σ(wᵢ × σᵢ)²) / NAV where σᵢ = stddev(log returns) | decimal fraction | > 0 |
| var_95_1d | 1.645 × sigma_daily × nav | USD | > 0 |
| var_99_1d | 2.326 × sigma_daily × nav | USD | > 0 |

Zero-correlation assumption. Securities without price history default to σ = 1%.  
**See METHODOLOGY.md §1 for limitations.**

### mart_tracking_error
**Grain:** One row per `(portfolio_id, benchmark_id)`.

| Column | Formula | Units | Expected Range |
|---|---|---|---|
| portfolio_id | Primary key | — | PORT_CORE, PORT_FLEX |
| benchmark_id | Mapped benchmark | — | BENCH_SPY, BENCH_AGG |
| te_30d | stddev(active_return trailing 30d) × sqrt(252) | decimal fraction | ≥ 0 |
| te_60d | stddev(active_return trailing 60d) × sqrt(252) | decimal fraction | ≥ 0 |
| te_90d | stddev(active_return trailing 90d) × sqrt(252) | decimal fraction | ≥ 0 |

Static weight approximation. Trailing windows measured from MAX(price_date).  
**See METHODOLOGY.md §2 for limitations.**

### mart_scenario_impact
**Grain:** One row per `(portfolio_id, scenario_id)`.

| Column | Formula | Units | Expected Range |
|---|---|---|---|
| portfolio_id | — | — | — |
| position_date | Latest date | — | — |
| scenario_id | Scenario identifier | — | — |
| factor | equity, interest_rate, credit_spread | — | — |
| shock_pct | Shock magnitude | % or bp | — |
| mv_change_usd | See formulas below | USD | −100% to +100% of NAV |
| mv_change_pct | mv_change_usd / total_nav × 100 | % | −100 to 100 |

Formulas by factor:
- `equity`: eq_mv × (shock_pct / 100)
- `interest_rate`: −weighted_avg_duration × (shock_pct / 10000) × fi_mv
- `credit_spread`: −weighted_avg_duration × (shock_pct / 10000) × bbb_plus_mv

**See METHODOLOGY.md §3 for limitations.**

### mart_concentration_limits
**Grain:** One row per `(portfolio_id, sec_id)` at latest position_date.

| Column | Formula | Units | Expected Range |
|---|---|---|---|
| portfolio_id | — | — | — |
| position_date | Latest date | — | — |
| sec_id | Security identifier | — | — |
| ticker | Exchange ticker | — | — |
| weight_pct | market_value / total_nav × 100 | % | 0–100 |
| breach_flag | weight_pct > 5.0 | boolean | — |
| breach_amount_over_5pct | MAX(weight_pct − 5.0, 0) | pp | ≥ 0 |

Watch threshold is 5%. Hard synthesis cap is 8% (equity) / 6% (bonds). Positions between 5–8% trigger review without mandatory reduction.

---

## 6. Reconciliation Gates

### recon_position_to_nav
**Grain:** One row per `portfolio_id`.

| Status | Condition |
|---|---|
| PASS | abs(sum_mv − declared_nav) / declared_nav ≤ 0.1% |
| FAIL | abs(sum_mv − declared_nav) / declared_nav > 0.1% |

Declared NAVs: PORT_CORE = $100,000,000; PORT_FLEX = $50,000,000.

### recon_benchmark_coverage
**Grain:** One row per `benchmark_id`.

| Status | Condition |
|---|---|
| PASS | priced_constituents = expected_constituents (100%) |
| WARN | priced_constituents / expected_constituents ≥ 95% |
| FAIL | priced_constituents / expected_constituents < 95% |

### recon_stale_prices
**Grain:** One row per `sec_id`.

| Status | Condition |
|---|---|
| PASS | days since last price ≤ 3 calendar days |
| WARN | days since last price = 4–5 calendar days |
| FAIL | days since last price > 5 calendar days |

**Note:** This gate uses calendar days, not business days. Prices observed on Friday will show days_since = 3 on Monday, which passes. A Friday → Wednesday gap (days_since = 5) returns WARN.

### recon_rating_coverage
**Grain:** One row per fixed income `sec_id`.

| Status | Condition |
|---|---|
| PASS | At least one row in stg_ratings for this sec_id |
| FAIL | No rating record found |

Equities and benchmarks (asset_class ≠ 'Fixed Income') are excluded from this gate.

---

## 7. Methodology Limitations Summary

| Area | Known Simplification | Impact |
|---|---|---|
| VaR | Zero cross-asset correlation | Understates portfolio VaR, especially in stress |
| VaR | Normal distribution | Underestimates tail risk (fat tails ignored) |
| Tracking error | Static current weights applied to full history | Overstates weight stability; ignores rebalancing |
| Tracking error | Ex-post only | Not a forward-looking risk estimate |
| Scenarios | Single-factor, linear | Ignores cross-asset contagion and convexity |
| Duration | Synthetic bucket assignment | Ignores coupon structure, convexity, cash flows |
| Concentration | Single-dimension (weight by MV) | No sector, country, or counterparty netting |
| Private credit | Fully synthetic prices and ratings | No market price discovery or liquidity risk |
| Position data | Single snapshot (one position_date) | No intraday marks, no historical weight series |
| Benchmark | Single index per portfolio | No blended benchmark for multi-asset portfolios |

---

## 8. Test Coverage

**Total dbt tests: 192** *(as of v0.4, 2026-05-26)*

| Category | Count | Models covered |
|---|---|---|
| `not_null` | ~52 | All PK and critical measure columns across all models |
| `unique` | ~25 | All PK columns |
| `accepted_values` | ~22 | asset_class, rating_bucket, factor, status, severity, kpi_category, investment_discretion, manager_type, _source_system |
| `dbt_utils.expression_is_true` | ~45 | Numeric range guards (> 0, ≥ 0, between 0 and 1, between 0 and 100, between −100 and 100) |
| `relationships` (FK) | 14 | All silver fact tables — portfolio_id, security_id, date_id, manager_id, benchmark_id |
| Custom singular tests | 6 | Recon gate FAIL rows, SCD invariants, holdings positivity |
| Governance / seed tests | ~28 | governance_scorecard columns, certification_registry columns |

Tests run with `dbt build` after every pipeline run. All 192 tests pass on the current dataset as of 2026-05-26.
