# Investment Risk Reporting Mart

**Governed investment data product for portfolio holdings, exposure, and reconciliation reporting.**

A portfolio-grade demonstration of how I structure governed data products in the investment domain: published data contract, conformed dimensions and facts, blocking data quality gates, source-to-curated reconciliation, and a reporting-ready consumer layer. Built locally with PostgreSQL, dbt, and Python; rendered as a static HTML dashboard.

<p align="center">
  <a href="dashboard/index.html"><img src="https://img.shields.io/badge/Dashboard-View_Live-2563EB?style=for-the-badge" alt="Dashboard"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License"></a>&nbsp;
  <a href="https://github.com/nicholashidalgo/investment-risk-reporting-mart"><img src="https://img.shields.io/badge/Tests-108_passing-16a34a?style=for-the-badge" alt="Tests"></a>&nbsp;
  <a href="https://github.com/nicholashidalgo/investment-risk-reporting-mart"><img src="https://img.shields.io/badge/dbt_Models-24-7c3aed?style=for-the-badge" alt="Models"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.11+-3776AB?style=flat&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white" alt="PostgreSQL">
  <img src="https://img.shields.io/badge/dbt-FF694B?style=flat&logo=dbt&logoColor=white" alt="dbt">
  <img src="https://img.shields.io/badge/Chart.js-FF6384?style=flat" alt="Chart.js">
  <img src="https://img.shields.io/badge/yfinance-1A1A2E?style=flat" alt="yfinance">
</p>

---

## Current State

This product is built on a mix of real public market data (equity prices via yfinance) and deterministic synthetic data (bond prices, credit ratings, positions). The next upgrade replaces the synthetic source layer with public SEC 13F regulatory holdings data. Synthetic data will be retained only for seeded defect testing.

This is a portfolio artifact. It demonstrates a production-style operating model. It does not claim production buy-side adoption.

## What This Project Demonstrates

| Discipline | Evidence |
|---|---|
| Product scope and grain | `DATA_CONTRACT.md` |
| Stakeholder reporting needs | 7 risk marts (exposure, concentration, benchmark coverage, valuation) |
| Data quality gates before publication | 108 blocking dbt tests, 100% passing |
| Source-to-curated reconciliation | 4 reconciliation models in `recon` schema |
| Reporting readiness | Static HTML dashboard rendering all 7 marts and 4 reconciliation gates |
| Reproducibility | Deterministic synthetic seeds, documented public API sources, full dbt build chain |

## What This Project Does Not Claim

This repo does not claim production deployment, buy-side adoption, assets under management coverage, business cost savings, analyst time saved, or investment decision impact. It is portfolio evidence of an operating model, not a market deployment.

For full measured controls and roadmap, see `MEASURED_IMPACT.md`.

## Quick Stats

- **24** dbt models across 4 layers (bronze, silver, marts, recon)
- **108** blocking dbt tests, all passing as of last run
- **4** reconciliation gates writing to a dedicated `recon` schema
- **7** risk marts rendered in a static HTML dashboard

## Documents

- `DATA_CONTRACT.md` — published contract for grain, ownership, SLA, semantics
- `METHODOLOGY.md` — modeling approach, data quality philosophy, reconciliation logic
- `MEASURED_IMPACT.md` — current controls, test coverage, what this build demonstrates and does not claim
- `CHANGELOG.md` — version history
- `AGENTS.md` — operating rules for AI tools working on this repo
- `PROJECT_STATUS.md` — current build state
- `DECISIONS.md` — architectural decision log
- `NEXT_ACTIONS.md` — prioritized backlog
- `HANDOFF.md` — session-to-session continuity

## Roadmap

| Version | Adds |
|---|---|
| v0.2 | Type 2 SCD on dimensions, FK tests, bronze layer tests, GitHub Actions CI |
| v0.3 | Public SEC 13F ingestion, source-to-curated reconciliation summary |
| v0.4 | N-PORT integration, fixed-income risk metrics, alternative consumer layer |

---

### Architecture

```
yfinance (SPY, AGG, 11 equities)   Synthetic (10 corp bonds)
                  │                            │
                  └──────────────┬─────────────┘
                                 ▼
                        bronze schema (raw)
               raw_security_master · raw_positions · raw_prices
               raw_benchmarks · raw_ratings · raw_stress_scenarios
                                 │
                                 ▼
                    bronze_dbt schema (staging views)
               stg_security_master · stg_positions · stg_prices
               stg_benchmarks · stg_ratings · stg_stress_scenarios
                                 │
                                 ▼
                          silver schema
               dim_security · dim_portfolio · dim_benchmark · dim_date
               fct_position_daily · fct_price_daily · fct_benchmark_return_daily
                                 │
                                 ▼
                 marts schema            recon schema
          mart_portfolio_exposure    recon_position_to_nav
          mart_credit_exposure       recon_benchmark_coverage
          mart_duration_summary      recon_stale_prices
          mart_var_parametric        recon_rating_coverage
          mart_tracking_error
          mart_scenario_impact
          mart_concentration_limits
                                 │
                                 ▼
                     Static HTML Dashboard
```

---

### dbt Models

#### ![Bronze](https://img.shields.io/badge/BRONZE-b45309?style=for-the-badge) Raw source passthrough views

| Model | Grain | Purpose |
|:------|:------|:--------|
| [![stg_security_master](https://img.shields.io/badge/stg__security__master-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/bronze/stg_security_master.sql) | 1 row per sec_id | Passthrough for raw security attributes |
| [![stg_positions](https://img.shields.io/badge/stg__positions-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/bronze/stg_positions.sql) | 1 row per portfolio x security x date | Passthrough for daily portfolio holdings |
| [![stg_prices](https://img.shields.io/badge/stg__prices-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/bronze/stg_prices.sql) | 1 row per security x date | Passthrough for daily closing prices |
| [![stg_benchmarks](https://img.shields.io/badge/stg__benchmarks-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/bronze/stg_benchmarks.sql) | 1 row per benchmark x date | Passthrough for daily benchmark returns |
| [![stg_ratings](https://img.shields.io/badge/stg__ratings-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/bronze/stg_ratings.sql) | 1 row per security x date x agency | Passthrough for point-in-time credit ratings |
| [![stg_stress_scenarios](https://img.shields.io/badge/stg__stress__scenarios-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/bronze/stg_stress_scenarios.sql) | 1 row per scenario x factor | Passthrough for stress scenario definitions |

#### ![Silver](https://img.shields.io/badge/SILVER-6b7280?style=for-the-badge) Dimensions, facts, and conformed grain

| Model | Grain | Purpose |
|:------|:------|:--------|
| [![dim_security](https://img.shields.io/badge/dim__security-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/dim_security.sql) | 1 row per sec_id | Security attributes with latest rating resolved |
| [![dim_portfolio](https://img.shields.io/badge/dim__portfolio-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/dim_portfolio.sql) | 1 row per portfolio_id | Portfolio reference |
| [![dim_benchmark](https://img.shields.io/badge/dim__benchmark-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/dim_benchmark.sql) | 1 row per benchmark_id | Benchmark reference |
| [![dim_date](https://img.shields.io/badge/dim__date-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/dim_date.sql) | 1 row per date | Full date spine with calendar attributes |
| [![fct_position_daily](https://img.shields.io/badge/fct__position__daily-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/fct_position_daily.sql) | 1 row per portfolio x security x date | Denormalized position fact with asset class, sector, rating |
| [![fct_price_daily](https://img.shields.io/badge/fct__price__daily-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/fct_price_daily.sql) | 1 row per security x date | Daily closing price fact |
| [![fct_benchmark_return_daily](https://img.shields.io/badge/fct__benchmark__return__daily-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/silver/fct_benchmark_return_daily.sql) | 1 row per benchmark x date | Daily benchmark return fact |

#### ![Marts](https://img.shields.io/badge/MARTS-3fb950?style=for-the-badge) Consumption-ready risk analytics

| Model | Grain | Purpose |
|:------|:------|:--------|
| [![mart_portfolio_exposure](https://img.shields.io/badge/mart__portfolio__exposure-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_portfolio_exposure.sql) | 1 row per portfolio | NAV, asset class breakdown, sector breakdown, top-10 concentration |
| [![mart_credit_exposure](https://img.shields.io/badge/mart__credit__exposure-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_credit_exposure.sql) | 1 row per portfolio x rating bucket | Fixed income exposure by credit quality |
| [![mart_duration_summary](https://img.shields.io/badge/mart__duration__summary-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_duration_summary.sql) | 1 row per portfolio | Portfolio-weighted average modified duration |
| [![mart_var_parametric](https://img.shields.io/badge/mart__var__parametric-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_var_parametric.sql) | 1 row per portfolio | Parametric VaR at 95% and 99%, 1-day horizon |
| [![mart_tracking_error](https://img.shields.io/badge/mart__tracking__error-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_tracking_error.sql) | 1 row per portfolio x benchmark | Ex-post tracking error over 30/60/90 days |
| [![mart_scenario_impact](https://img.shields.io/badge/mart__scenario__impact-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_scenario_impact.sql) | 1 row per portfolio x scenario | Single-factor stress scenario P&L impact |
| [![mart_concentration_limits](https://img.shields.io/badge/mart__concentration__limits-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/marts/mart_concentration_limits.sql) | 1 row per portfolio x security | Breach flags for positions above 5% NAV |

#### ![Recon](https://img.shields.io/badge/RECON-f85149?style=for-the-badge) Governance and data quality gates

| Model | Grain | Gate Logic |
|:------|:------|:-----------|
| [![recon_position_to_nav](https://img.shields.io/badge/recon__position__to__nav-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/recon/recon_position_to_nav.sql) | 1 row per portfolio | PASS if sum-of-positions vs declared NAV within 0.1% |
| [![recon_benchmark_coverage](https://img.shields.io/badge/recon__benchmark__coverage-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/recon/recon_benchmark_coverage.sql) | 1 row per benchmark | PASS if 100% of constituents have prices |
| [![recon_stale_prices](https://img.shields.io/badge/recon__stale__prices-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/recon/recon_stale_prices.sql) | 1 row per security | PASS if days since last price is 3 or fewer |
| [![recon_rating_coverage](https://img.shields.io/badge/recon__rating__coverage-161b22?style=flat-square&logo=dbt&logoColor=FF694B)](models/recon/recon_rating_coverage.sql) | 1 row per FI security | PASS if at least one rating record exists |

---

### Pipeline Components

<p>
  <img src="https://img.shields.io/badge/Ingest-yfinance_%2B_Synthetic_Python-3776AB?style=flat-square" alt="Ingest">
  <img src="https://img.shields.io/badge/Stage-6_Bronze_Views-b45309?style=flat-square" alt="Stage">
  <img src="https://img.shields.io/badge/Transform-7_Silver_Tables-6b7280?style=flat-square" alt="Transform">
  <img src="https://img.shields.io/badge/Serve-7_Risk_Marts-3fb950?style=flat-square" alt="Serve">
  <img src="https://img.shields.io/badge/Govern-4_Recon_Gates-f85149?style=flat-square" alt="Govern">
  <img src="https://img.shields.io/badge/Render-Static_HTML_Dashboard-2563EB?style=flat-square" alt="Render">
</p>

---

### Risk Measures

| Measure | Implementation | Known Limitation |
|:--------|:---------------|:-----------------|
| ![VaR](https://img.shields.io/badge/VaR-2563EB?style=flat-square) | Parametric variance-covariance, zero cross-asset correlation | Understates tail risk; normal distribution ignores fat tails |
| ![Tracking Error](https://img.shields.io/badge/Tracking_Error-7c3aed?style=flat-square) | Ex-post realized, static current weights applied to full history | Overstates weight stability; not a forward-looking estimate |
| ![Scenarios](https://img.shields.io/badge/Stress_Scenarios-d29922?style=flat-square) | Single-factor linear shocks (equity %, rate bp, credit spread bp) | Ignores cross-asset contagion and non-linear payoffs |
| ![Duration](https://img.shields.io/badge/Duration-58a6ff?style=flat-square) | Synthetic bucket assignment by maturity band | Ignores coupon structure, convexity, and cash-flow timing |
| ![Concentration](https://img.shields.io/badge/Concentration-f85149?style=flat-square) | Single-dimension weight by market value, 5% soft / 8% hard cap | No sector, country, or counterparty netting |
| ![Credit](https://img.shields.io/badge/Credit-8b949e?style=flat-square) | Synthetic ratings and prices for all bond positions | No market price discovery or liquidity risk |

See [METHODOLOGY.md](METHODOLOGY.md) and [DATA_CONTRACT.md](DATA_CONTRACT.md) for full formula definitions and test coverage details.

---

### Quick Start

```bash
# 1. Clone
git clone https://github.com/nicholashidalgo/investment-risk-reporting-mart.git
cd investment-risk-reporting-mart

# 2. Create database
createdb investment_risk

# 3. Apply DDL
psql $DATABASE_URL -f scripts/01_ddl_bronze.sql
psql $DATABASE_URL -f scripts/02_ddl_ops.sql

# 4. Install Python dependencies
pip install -r requirements.txt

# 5. Set connection
export DATABASE_URL="postgresql://user:pass@localhost:5432/investment_risk"

# 6. Run ingestion
python scripts/ingest_seed_data.py

# 7. Configure dbt profile
cp profiles/profiles.yml.template ~/.dbt/profiles.yml
# Edit with your PGHOST, PGUSER, PGPASSWORD, PGDATABASE

# 8. Run dbt
dbt deps && dbt run && dbt test

# 9. Open dashboard
open dashboard/index.html
```

---

### Tech Stack

| Component | Technology |
|:----------|:-----------|
| ![DB](https://img.shields.io/badge/Database-4169E1?style=flat-square) | PostgreSQL 16 |
| ![Transform](https://img.shields.io/badge/Transforms-FF694B?style=flat-square) | dbt 1.x (bronze / silver / marts / recon) |
| ![Ingest](https://img.shields.io/badge/Ingest-3776AB?style=flat-square) | Python 3.11, yfinance, NumPy |
| ![Dashboard](https://img.shields.io/badge/Dashboard-FF6384?style=flat-square) | Static HTML, Chart.js 4.x (no build step) |
| ![Tests](https://img.shields.io/badge/Tests-16a34a?style=flat-square) | 108 dbt tests (not_null, unique, accepted_values, expression_is_true) |

---

### Tests

```bash
dbt test
```

108 dbt schema tests covering all primary keys, critical measure columns, accepted value sets for `asset_class`, `rating_bucket`, `factor`, and `status` columns, and numeric range guards across all seven risk marts and four recon gates. All 108 pass on the current dataset.

---

<p align="center">
  <a href="https://linkedin.com/in/nicholashidalgo"><img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white" alt="LinkedIn"></a>&nbsp;
  <a href="https://nicholashidalgo.com"><img src="https://img.shields.io/badge/Website-000000?style=for-the-badge&logo=About.me&logoColor=white" alt="Website"></a>&nbsp;
  <a href="mailto:analytics@nicholashidalgo.com"><img src="https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white" alt="Email"></a>
</p>
