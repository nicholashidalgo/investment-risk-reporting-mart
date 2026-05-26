# Next Actions

Listed by priority. One actionable item per line. When complete, move to "Done This Week" with date.

## Active

### Immediate (owner actions before next session)

- [ ] Commit v0.4 work (`git add` specific files, `git commit -m "feat: v0.4 governance-readiness release"`)
- [ ] Verify `dbt test` still shows 192/192 passing after commit (sanity check)
- [ ] Verify `dbt source freshness` shows 1/1 PASS after commit

### v0.5 Candidates (next 2–4 weeks)

**Source Freshness Expansion**
- [ ] Add `_ingested_at TIMESTAMPTZ DEFAULT now()` to `bronze.raw_security_master` DDL — unblocks freshness on yfinance price source
- [ ] Add `_ingested_at TIMESTAMPTZ DEFAULT now()` to `bronze.raw_prices`, `bronze.raw_ratings`, `bronze.raw_benchmarks` DDL
- [ ] Once columns exist: add source freshness blocks to `sources.yml` for all 4 DATE-column sources (currently documented as `[Designed]`)

**AI Governance Infrastructure**
- [ ] Database role for read-only AI agent access (marts + recon schemas only)
- [ ] AI interaction logging table in `recon` schema (prompt, data objects accessed, output, reviewer, approval_status)
- [ ] AI Use Case Registry document (`docs/architecture/AI_USE_CASE_REGISTRY.md`)
- [ ] Semantic layer definition (dbt Semantic Layer or view-based access controls)
- [ ] Evaluation gate checklist as runnable test suite

**SCD Expansion**
- [ ] Type 2 SCD on `dim_issuer` (same dbt snapshot pattern as dim_security)
- [ ] Type 2 SCD on `dim_investment_manager` (manager names/classifications can change)
- [ ] Add `cusip` to `dim_security_snapshot` check_cols to capture CUSIP changes in SCD history
- [ ] SCD history for 13F-sourced securities (currently excluded from dim_security_snapshot)

**Data Completeness**
- [ ] Extend manager universe beyond Boston 5 (Vanguard, BlackRock, T. Rowe Price, Putnam)
- [ ] Add put_call sub-classification to dim_security for option-holding managers
- [ ] Snapshot `stg_ratings` to enable true point-in-time rating history

**CI / Delivery**
- [ ] GitHub Actions CI workflow (`.github/workflows/dbt.yml`) — parse + build + test
- [ ] Generate `reports/dq_reconciliation_summary.csv` from real recon gate outputs
- [ ] Website case-study page at nicholashidalgo.com/investment-data-product

### v0.6 (60–90 days)

- [ ] N-PORT integration for fund-level holdings
- [ ] Risk metric layer expansion (duration, credit quality distribution)
- [ ] Issuer mapping and identifier normalization (LEI, FIGI cross-reference)
- [ ] Power BI build (alternative to static HTML dashboard)
- [ ] Benchmark-relative exposure marts
- [ ] NL query assistant scoped to certified marts (AI readiness v1)
- [ ] Anomaly detector for recon gate failures

## Done This Session (2026-05-26 — v0.4 Governance-Readiness Release)

- 2026-05-26: `governance_scorecard.sql` — 8-KPI governance model built and validated (8 live rows, correct severity outputs)
- 2026-05-26: `seeds/governance/certification_registry.csv` — 10-row certification register (roles, not names)
- 2026-05-26: `models/marts/governance/schema.yml` — tests for governance_scorecard (not_null, unique, accepted_values on severity + kpi_category)
- 2026-05-26: `seeds/governance/schema.yml` — tests for certification_registry
- 2026-05-26: `models/silver/schema.yml` — 7 new FK relationship tests across fct_position_daily, fct_price_daily, fct_benchmark_return_daily; added accepted_values and expression_is_true tests
- 2026-05-26: `models/sources.yml` — added source freshness for raw_13f_filings (`_ingested_at` TIMESTAMPTZ, 120d warn / 180d error); documented freshness absence on DATE-column sources
- 2026-05-26: `dbt_project.yml` — added governance seeds schema configuration
- 2026-05-26: `README.md` — updated to v0.4 (192 tests, 32 models, governance_scorecard, certification_registry)
- 2026-05-26: All 7 `docs/architecture/` files updated to reflect v0.4 status (governance_scorecard added, rule counts updated, extension paths updated)
- 2026-05-26: `dbt build` confirmed 192/192 PASS; `dbt source freshness` 1/1 PASS
- 2026-05-26: `dbt show --select governance_scorecard` confirmed 8 live KPI rows

## Done (Previous Sessions)

- 2026-05-07: SEC 13F ingestion complete (30,135 holdings, 5 managers, $5.906T AUM, 153/153 tests passing)
- 2026-05-07: recon_filing_totals_reconciliation, recon_bronze_to_silver_reconciliation, recon_zero_value_holdings
- 2026-05-06: Type 2 SCD on dim_security — snapshot + history + current + 19 tests, 127/127 passing
- 2026-05-06: Local backup, pre-audit tag, repo audit, governance architecture docs (7 files)
