# Measured Impact

This project is a governed investment data product built for portfolio holdings, exposure, and reconciliation reporting. Metrics on this page describe **measured technical controls and reporting readiness**, not production business outcomes.

## What This Document Is

A factual record of what the build currently demonstrates. Every value here is backed by an artifact in the repo — a dbt test, a model output, a reconciliation table, or a log line. If a metric cannot be verified from the repo, it does not appear on this page.

## What This Document Is Not

This is not a claim of production deployment, buy-side adoption, assets under management coverage, business cost savings, analyst time saved, or investment decision impact. The product demonstrates how I structure governed investment data. It does not claim market deployment.

## Current Measured Controls

*Last verified: 2026-05-26 — dbt build — 192 of 192 passing*

### Model Coverage

| Layer | Models | Purpose |
|---|---:|---|
| Bronze (staging views) | 6 | Raw source standardization |
| Silver dimensions | 7 | Conformed reference data (security + SCD history/current, manager, date, portfolio, benchmark) |
| Silver facts | 4 | Position, price, benchmark return, manager holding |
| Risk marts | 7 | Exposure, concentration, benchmark coverage, valuation |
| Governance marts | 1 | `governance_scorecard` — 8 live governance KPIs |
| Reconciliation gates | 7 | 4 synthetic-data gates + 3 SEC 13F gates |
| dbt snapshots | 1 | SCD capture (dim_security_snapshot, strategy: check) |
| dbt seeds | 2 | yfinance_to_cusip (CUSIP backfill); certification_registry (model certification status) |
| **Total models** | **32** | All compiling; verified via `dbt ls --resource-type model` |

*Note: Seeds are not counted in the 32-model total. dbt tracks seeds as a separate resource type.*

### Test Coverage

| Test Category | Count | Severity |
|---|---:|---|
| `not_null` | ~52 | Blocking |
| `unique` | ~25 | Blocking |
| `accepted_values` | ~22 | Blocking |
| `dbt_utils.expression_is_true` | ~45 | Blocking |
| `relationships` (FK) | 14 | Blocking |
| Custom singular tests | 6 | Blocking |
| Governance schema tests | ~8 | Blocking |
| Seed schema tests | ~9 | Blocking |
| SCD invariant tests | 2 | Blocking |
| **Total** | **192** | **All blocking, no warn-only overrides** |

**Most recent test run:** 192 of 192 passing (2026-05-26)

### v0.4 Governance Controls (new in this release)

| Control | Description | Status |
|---|---|---|
| Governance scorecard | `governance_scorecard` — 8 KPIs from live warehouse data | `[Implemented]` |
| KPI-01: Filing reconciliation | 0 FAIL rows in recon_filing_totals_reconciliation | GREEN |
| KPI-02: Bronze-to-silver reconciliation | 0 FAIL rows in recon_bronze_to_silver_reconciliation | GREEN |
| KPI-03: Price freshness | ~25 days since last yfinance refresh | RED |
| KPI-04: Holdings completeness | 13,191 fct_manager_holding rows | GREEN |
| KPI-05: Security coverage | 100% of 13F CUSIPs map to dim_security | GREEN |
| KPI-06: Zero-value holdings | 18 rows (valid SEC sub-rounding) | INFO |
| KPI-07: Concentration limits | 22/42 synthetic portfolio positions exceed 5% limit (by design) | RED |
| KPI-08: Composite readiness | BLOCKED (KPI-03 + KPI-07 RED) | BLOCKED |
| Certification registry | `certification_registry.csv` seed — 10 models, role-based tracking artifact | `[Implemented]` |
| FK relationship tests | 14 tests across all silver fact tables | `[Implemented]` |
| Source freshness gate | `raw_13f_filings` via `_ingested_at TIMESTAMPTZ` (120d warn / 180d error) | 1/1 PASS |

**On KPI-08 BLOCKED:** The composite scorecard is correctly BLOCKED. Stale yfinance prices (~25 days) and synthetic portfolio concentration breaches drive this status. In production, these would be triaged before report distribution. The scorecard surfaces honest data state, not a rubber-stamp READY.

**On certification_registry:** This is a role-based tracking artifact (Analytics Engineering Lead, Governance Reviewer, etc.), not a formal enterprise sign-off workflow. It documents certification status and open exceptions per model. No automated enforcement is attached.

### SEC 13F Integration (v0.3 — complete)

| Metric | Value |
|---|---|
| Institutional managers tracked | 5 (State Street, Fidelity, Wellington, MFS, Loomis Sayles) |
| Reporting quarter | Q4 2025 (period_of_report = 2025-12-31) |
| Raw bronze holdings ingested | 30,135 rows |
| Silver fact rows (fct_manager_holding) | 13,191 rows (aggregated to manager-security-period grain) |
| Total reported AUM across 5 managers | $5.906 trillion |
| Filing reconciliation | 5 of 5 PASS (≤ $1,000 rounding on Wellington, 0.0000% variance) |
| Bronze-to-silver reconciliation | 5 of 5 PASS (exact zero variance on all managers) |
| Zero-value/zero-share anomalies surfaced | 18 rows in recon.recon_zero_value_holdings (valid SEC data) |
| CUSIP coverage | 13 real tickers mapped via seed; 13F-only securities keyed by cusip |

Source: SEC EDGAR API. Data is public regulatory filings, not proprietary. All 30,135 holdings are real institutional positions filed with the SEC for Q4 2025.

### Type 2 SCD Coverage

| Dimension | SCD Implemented | Pattern |
|---|---|---|
| dim_security | Yes (v0.1) | dbt snapshot, check strategy on 6 attribute columns |
| dim_investment_manager | Not yet (v0.5 candidate) | Same pattern as dim_security |
| dim_issuer | Not yet (v0.5 candidate) | Same pattern as dim_security |
| dim_date | N/A | Conformed dimension, no history needed |

Surfaced via `dim_security_history` (table, full version history) and `dim_security_current` (view, current state).

### Source Freshness

| Source | Table | Freshness Gate | Status |
|---|---|---|---|
| SEC 13F filings | `raw_13f_filings` | 120d warn / 180d error via `_ingested_at` TIMESTAMPTZ | **1/1 PASS** |
| Security master | `raw_security_master` | Not yet — DATE column, requires DDL addition (v0.5) | `[Designed]` |
| Prices | `raw_prices` | Not yet — DATE column (v0.5) | `[Designed]` |
| Ratings | `raw_ratings` | Not yet — DATE column (v0.5) | `[Designed]` |
| Benchmarks | `raw_benchmarks` | Not yet — DATE column (v0.5) | `[Designed]` |

Price freshness is monitored at the recon layer via `recon_stale_prices` (not at the source freshness layer).

### Reconciliation Framework

Seven reconciliation models writing to the `recon` schema:

**Synthetic-data layer (4 gates):**
1. **Position-to-NAV** — validates fact-level holdings totals against fund NAV
2. **Benchmark coverage** — measures completeness of benchmark prices for in-portfolio securities
3. **Stale price detection** — flags securities with prices older than tolerance
4. **Rating coverage** — measures completeness of credit rating data for fixed-income holdings

**SEC 13F layer (3 gates):**
5. **Filing totals reconciliation** — `SUM(bronze holdings)` per filing vs SEC cover-page `tableValueTotal`; PASS if variance < 0.001%
6. **Bronze-to-silver reconciliation** — `SUM(fct_manager_holding)` vs `SUM(bronze holdings)` per manager; PASS only if variance = exactly 0
7. **Zero-value holdings** — surfaces holdings where value rounds to zero (< $500 position) or shares round to zero (fractional positions); informational, not a failure gate

Both SEC recon gates are backed by singular tests that fail the dbt build if any FAIL row appears.

### Data Provenance

| Source | Coverage | Type |
|---|---|---|
| yfinance equity prices | 11 equities + 2 ETF benchmarks, 1 year | Real — public market data via API |
| SEC EDGAR 13F filings | 5 managers, Q4 2025, 30,135 holdings | Real — public regulatory data |
| Bond prices | 10 synthetic bonds | Synthetic — deterministic RNG, seeded |
| Credit ratings | All securities | Synthetic — deterministic RNG, seeded |
| Portfolio positions | 2 portfolios | Synthetic — deterministic RNG, seeded |

### Reporting Layer

Static HTML dashboard (`dashboard/index.html`) renders all 7 risk marts and 4 original reconciliation gates using Chart.js 4.4.2.

## What These Metrics Demonstrate

- **Real public regulatory data pipeline.** 30,135 SEC 13F holdings from EDGAR fetched, cached, parsed, and loaded through a governed bronze→silver pipeline with source-to-curated reconciliation.
- **Data quality discipline before reporting publication.** 192 blocking tests — all passing. Includes FK referential integrity across all silver fact tables, Type 2 SCD invariants, and SEC filing-total reconciliation gates.
- **FK referential integrity enforced.** 14 relationship tests verify that all silver fact rows reference valid dimension rows (portfolio_id, security_id, date_id, manager_id, benchmark_id).
- **Live governance scorecard.** 8 KPIs queryable from the warehouse — not hardcoded values, computed from actual data. Scorecard honestly shows BLOCKED status when data conditions warrant it.
- **Reconciliation as a first-class concern.** Seven reconciliation gates span synthetic positions and real regulatory filings. Two gates enforce exact-match constraints with singular tests that block the build on any failure.
- **Traceable sourcing.** Every silver fact row traces to a specific SEC accession number, CIK, and period_of_report.
- **Reproducibility.** EDGAR data is public and fetchable by anyone with the User-Agent header. Synthetic data is deterministic. Anyone can rebuild this product end-to-end.

## What These Metrics Do Not Demonstrate

- Production deployment to a buy-side or insurance investment team
- Real-world assets under management coverage (the $5.906T is the managers' reported AUM, not the project's scope)
- Stakeholder adoption metrics
- Business outcomes (cost savings, time savings, decision quality)
- Formal enterprise certification sign-off (certification_registry is a tracking artifact, not an enforced workflow)
- Source freshness on price, position, rating, and benchmark sources (requires DDL addition, v0.5)
- SCD history for 13F-sourced securities (v0.5 scope)
- Type 2 SCD on dim_investment_manager or dim_issuer (v0.5 candidates)
- KPI-08 READY status (scorecard is BLOCKED; stale prices + synthetic concentration breaches)

## Roadmap to Stronger Claims

| Version | Adds | New Honest Claim |
|---|---|---|
| v0.5 | `_ingested_at` DDL on 4 sources, DB role for AI agent access, SCD on dim_manager | Full source freshness, AI read-only access controls, broader SCD coverage |
| v0.5 | SCD on dim_issuer, cusip in snapshot check_cols, 13F SCD history | Complete SCD framework |
| v0.6 | N-PORT, risk metrics, issuer normalization | Fund-level coverage, duration/credit metrics, cross-filing entity resolution |
| v0.7 | Power BI, multi-quarter history, additional managers | Alternative consumer layer, trend analysis, broader regulatory coverage |

## How to Verify Any Claim on This Page

Every metric here can be reproduced locally:

```bash
# Model and test counts
dbt ls --resource-type model | wc -l     # should return 32
dbt parse                                 # should show 32 models, 192 data tests, 2 seeds

# Run all tests
dbt build                                 # 192/192 PASS

# Source freshness
dbt source freshness                      # 1/1 PASS (raw_13f_filings)

# Governance scorecard
dbt show --select governance_scorecard    # 8 KPI rows

# Inspect SEC 13F reconciliation
psql -U nickhidalgo -d investment_risk -c "SELECT * FROM analytics_recon.recon_filing_totals_reconciliation;"
psql -U nickhidalgo -d investment_risk -c "SELECT * FROM analytics_recon.recon_bronze_to_silver_reconciliation;"

# Holdings total
psql -U nickhidalgo -d investment_risk -c "SELECT COUNT(*) FROM analytics_silver.fct_manager_holding;"
```

If anything in this document does not match the repo, the repo is the source of truth. File an issue or update this page.
