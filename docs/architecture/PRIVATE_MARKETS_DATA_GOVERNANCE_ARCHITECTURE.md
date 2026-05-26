# Private Markets Data Governance Architecture

> **Implementation Status Legend**
> `[Implemented]` — exists in this repo, tested, verified
> `[Designed]` — schema and logic defined, not yet executed
> `[Proposed]` — recommended approach, not yet designed
> `[Reference Architecture]` — industry-standard pattern documented for design guidance

---

## 1. Purpose

This document describes the data governance architecture for a governed investment data product built on public-market regulatory and pricing data. It defines ownership boundaries, data stewardship roles, quality controls, lineage, reconciliation checkpoints, and reporting certification pathways across a layered data platform.

The patterns here are directly applicable to investment operations contexts — whether managing public equity, fixed income, or multi-asset portfolios — and are demonstrated using real public data: SEC 13F institutional holdings filings (from the U.S. Securities and Exchange Commission's EDGAR system) and equity/benchmark pricing from Yahoo Finance.

---

## 2. Business Use Case

Investment operations teams need governed, certified reference data to:

- Produce accurate portfolio valuations and exposure reports
- Pass internal audit controls on position reconciliation
- Certify data for regulatory submissions (13F, N-PORT, AIFMD)
- Enable portfolio managers and risk officers to trust downstream analytics
- Support data lineage requests from compliance and external auditors

This repository implements a **governed investment data mart** that demonstrates how raw regulatory data flows from public sources through validation, transformation, reconciliation, and certified consumption layers — mirroring the control environment of institutional investment operations.

---

## 3. Data Sources

| Source | Type | Governance Status | Access Method |
|--------|------|-------------------|---------------|
| SEC EDGAR 13F-HR filings (Q4 2025) | Regulatory public data | Authoritative; no access controls | EDGAR submissions API + XML download |
| Yahoo Finance (yfinance) | Market data proxy | Best-effort; not production-grade | Python `yfinance` library |
| dbt `yfinance_to_cusip.csv` seed | Reference mapping | Repo-controlled; manually validated | dbt seed |
| Synthetic bond data (seed=42) | Placeholder structure | Clearly labeled; no business claims | Python RNG in `ingest_seed_data.py` |

**What this repo does not use:** Bloomberg, Refinitiv, ICE Data Services, FactSet, or any licensed market data. All data quality limitations of public sources are documented in `METHODOLOGY.md` and `MEASURED_IMPACT.md`.

---

## 4. Operating Model

### Roles and Responsibilities

| Role | Responsibility | Artifacts Owned |
|------|---------------|-----------------|
| **Data Engineer** | Ingestion, transformation, testing, pipeline maintenance | Bronze models, ingestion scripts, dbt build |
| **Data Steward** | Business term ownership, quality rule definitions, metadata completeness | Business glossary, schema.yml descriptions, recon gates |
| **Data Owner** | Approval authority for certified data products; executive accountability | Mart certification, reporting release sign-off |
| **Analyst / Consumer** | Query certified marts; escalate quality issues | Dashboard, mart queries |
| **Risk Officer** | Validates risk metrics methodology; approves VaR/tracking error definitions | `METHODOLOGY.md`, mart schema |
| **Compliance** | Reviews lineage evidence; confirms regulatory data chain of custody | Recon reports, lineage docs |

### Governance Cadence

| Activity | Frequency | Owner | Evidence |
|----------|-----------|-------|----------|
| dbt build + test run | Per pipeline execution | Data Engineer | Test run logs, 192 blocking tests |
| Recon gate review | Per build | Data Steward | `recon_*` model outputs |
| Filing totals validation | Per 13F ingestion | Data Engineer | `recon_filing_totals_reconciliation` |
| Bronze-to-silver variance check | Per dbt build | Data Engineer | `recon_bronze_to_silver_reconciliation` |
| Metadata completeness review | Quarterly | Data Steward | schema.yml coverage |
| Reporting certification | Per reporting period | Data Owner | Certification sign-off doc |

---

## 5. Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA GOVERNANCE ARCHITECTURE                         │
│                    Investment Risk Reporting Mart (v0.3)                      │
└─────────────────────────────────────────────────────────────────────────────┘

 External Sources                Ingestion               Governed Layers
 ─────────────────               ─────────               ───────────────
 
 SEC EDGAR EDGAR API ──────────► edgar_client.py ──────► BRONZE (raw_*)
 13F-HR XML files   ──────────► xml_parser.py          │  raw_13f_holdings
                                bronze_loader.py         │  raw_security_master
 Yahoo Finance API  ──────────► ingest_seed_data.py ───►│  raw_positions
 (11 equities, 2                                         │  raw_prices
  benchmarks)                                            │  raw_benchmarks
                                                         │  raw_stress_scenarios
 Synthetic Bonds ──────────────► ingest_seed_data.py ──►│  raw_ratings
 (RNG seed=42)                                           │
                                                         ▼
                                                       STAGING (bronze_dbt.stg_*)
                                                         │  stg_security_master
                                                         │  stg_positions
                                                         │  stg_prices
                                                         │  stg_ratings
                                                         │  stg_benchmarks
                                                         │  stg_stress_scenarios
                                                         │
                                  ┌──────────────────────┘
                                  ▼
                                SILVER (silver.dim_* / fct_*)
                                  │  dim_security [+CUSIP, +13F]     Type 2 SCD
                                  │  dim_security_history             via snapshot
                                  │  dim_investment_manager           (5 mgrs)
                                  │  dim_portfolio, dim_benchmark
                                  │  dim_date
                                  │  fct_position_daily
                                  │  fct_price_daily
                                  │  fct_benchmark_return_daily
                                  │  fct_manager_holding              13,191 rows
                                  │
                    ┌─────────────┴──────────────┐
                    ▼                            ▼
               MARTS (gold)               RECON LAYER
               7 risk models              7 gates
               ─────────────              ──────
               mart_portfolio_exposure    recon_position_to_nav
               mart_concentration_limits  recon_benchmark_coverage
               mart_credit_exposure       recon_stale_prices
               mart_duration_summary      recon_rating_coverage
               mart_var_parametric        recon_filing_totals_reconciliation
               mart_tracking_error        recon_bronze_to_silver_reconciliation
               mart_scenario_impact       recon_zero_value_holdings
                    │
                    ▼
               DASHBOARD (static HTML + Chart.js)
               Certified consumption layer
```

### Layer Definitions

| Layer | Schema | Purpose | Mutability |
|-------|--------|---------|-----------|
| Bronze | `bronze` | Raw source data as ingested; no transformations | Append-only; idempotent load |
| Staging | `bronze_dbt` | Cast, rename, light clean; 1-to-1 with bronze | Rebuilt on each run |
| Silver | `silver` | Conformed dimensions and facts; governed grain | Rebuilt; snapshot delta-tracked |
| Marts | `marts` | Pre-aggregated analytics; certified for consumption | Rebuilt; version-controlled |
| Recon | `recon` | Reconciliation gates; evidence of control | Rebuilt; results preserved in reports |

---

## 6. Data Controls

| Control | Layer | Type | Status |
|---------|-------|------|--------|
| Blocking `not_null` tests on all PKs | Bronze–Silver | Automated | `[Implemented]` |
| Blocking `unique` tests on all PKs | Silver–Marts | Automated | `[Implemented]` |
| `accepted_values` on asset_class, sector | Silver | Automated | `[Implemented]` |
| `expression_is_true` for non-negative values | Silver–Marts | Automated | `[Implemented]` |
| Filing totals reconciliation (0.001% tolerance) | Recon | Automated gate | `[Implemented]` |
| Bronze-to-silver zero-variance check | Recon | Automated gate | `[Implemented]` |
| Zero-value holdings surface (informational) | Recon | Automated gate | `[Implemented]` |
| SCD Type 2 on dim_security | Silver | Snapshot | `[Implemented]` |
| Custom SCD integrity tests (no overlap, one current) | Silver | Singular tests | `[Implemented]` |
| Foreign-key relationship tests (manager→security, fct_position_daily, fct_price_daily, fct_benchmark_return_daily) | Silver | Automated | `[Implemented]` |
| Stale price detection | Recon | Automated gate | `[Implemented]` |
| Rating coverage gate | Recon | Automated gate | `[Implemented]` |
| Lineage documentation | Docs | Manual | `[Implemented]` |
| Certification sign-off workflow | Operating model | Process | `[Proposed]` |
| CI/CD pipeline (GitHub Actions) | Pipeline | Automated | `[Designed]` |
| Governance scorecard model (governance_scorecard.sql) | Marts | Automated | `[Implemented]` |
| Certification registry seed (certification_registry.csv) | Seeds | Reference data | `[Implemented]` |
| Source freshness for raw_13f_filings (_ingested_at column) | Sources | Automated | `[Implemented]` |

---

## 7. Governance Workflow

```
  1. INTAKE
     └─► Source registration in sources.yml
         Owner assignment in schema.yml descriptions
         SLA and grain documented in DATA_CONTRACT.md

  2. INGESTION
     └─► Python pipeline (edgar_client.py, ingest_seed_data.py)
         Idempotent: DELETE WHERE accession_no = X then INSERT
         Quarantine log for malformed records (0 quarantined in v0.3)

  3. TRANSFORMATION (dbt build)
     └─► Staging → Silver → Marts → Recon
         All models version-controlled in models/
         schema.yml: column descriptions, tests, grain

  4. QUALITY GATES (192 blocking tests)
     └─► All tests must pass; build fails on any failure
         Recon gates produce PASS/FAIL/WARN per filing
         Singular tests block on violations

  5. STEWARDSHIP REVIEW
     └─► Data steward reviews recon outputs
         Flags anomalies in DECISIONS.md
         Updates glossary if new terms introduced

  6. CERTIFICATION
     └─► Data owner reviews recon evidence
         Signs off reporting period for mart consumption
         Certification documented (future: automated workflow)

  7. CONSUMPTION
     └─► Certified marts consumed by dashboard
         External consumers use only marts layer
         Bronze/silver direct access requires documented exception
```

---

## 8. Implementation Workflow

For adding a new data source to the governed pipeline:

1. **Register** source table in `models/sources.yml` with description and SLA
2. **Create** bronze staging view in `models/bronze/stg_{source}.sql`
3. **Add** column tests and descriptions to `models/bronze/schema.yml`
4. **Create** silver dimension or fact in `models/silver/`
5. **Add** reconciliation gate in `models/recon/` to compare source totals to silver
6. **Add** singular blocking test in `tests/` for the recon gate
7. **Update** `DATA_CONTRACT.md` with new grain and semantics
8. **Update** `LINEAGE_AND_RECONCILIATION_MODEL.md` with new lineage path
9. **Run** `dbt build` — all 192+ tests must pass

---

## 9. Operational Metrics

| Metric | Current Value | Target |
|--------|-------------|--------|
| Total dbt models | 32 SQL models + 1 governance (33 total) | — |
| Total blocking tests | 192 | ≥ 192 at all times |
| Test pass rate | 100% (227/227 in dbt build) | 100% |
| Relationship tests | 14 (fct_position_daily, fct_price_daily, fct_benchmark_return_daily, fct_manager_holding) | — |
| Source freshness gates | 1 (raw_13f_filings) | — |
| Recon gate coverage | 7 gates | ≥ 1 per major data source |
| SEC 13F filings reconciled | 5/5 (100%) | 100% per run |
| Bronze-to-silver variance | 0.000% | 0.000% |
| Filing totals variance | ≤ 0.001% | ≤ 0.001% |
| Schema.yml column coverage | Partial (priority columns) | 100% `[Designed]` |
| SCD coverage | dim_security only | All key dimensions `[Designed]` |

---

## 10. Workplace Application

This architecture directly maps to investment operations data governance in the following ways:

- **Reconciliation gates** mirror the daily NAV reconciliation controls run by fund administrators and operations teams against prime broker or custodian records
- **Bronze-to-silver zero-variance check** is the equivalent of a back-office position break report — any transformation that changes a total is a break that must be resolved before certification
- **Filing totals reconciliation** is the same control class as comparing a manager's reported AUM on a regulatory filing (13F, ADV) to internal records
- **Type 2 SCD on dim_security** mirrors the security master change tracking required to audit historical positions correctly (e.g., after a ticker change, merger, or CUSIP reassignment)
- **Blocking tests in CI** are the automated equivalent of a checklist that an operations analyst runs before releasing a report to the PM or to regulators

---

## 11. Limitations

- **Yahoo Finance** is not production-grade market data. Prices may have gaps, adjustments, or timing differences not suitable for NAV calculation or regulatory reporting.
- **Synthetic bond data** uses deterministic random generation. It has no connection to real market prices, credit spreads, or issuer characteristics.
- **Five institutional managers** represent a sample. Real 13F monitoring would cover dozens to hundreds of filers.
- **Single reporting period (Q4 2025)** limits trend analysis. Multi-period comparison is a v0.5 item.
- **Static HTML dashboard** is not a production BI tool and does not support interactive filtering, row-level security, or user access controls.
- **No production deployment.** This is a demonstration data product running locally against PostgreSQL.

---

## 12. What This Does Not Claim

- This repo does not claim to have been used in production investment operations.
- This repo does not claim to have produced regulatory filings or certified NAV for any fund.
- Yahoo Finance pricing data is not suitable for use in regulatory reporting, NAV calculation, or investment decision-making.
- Synthetic bond data does not represent any real issuer, fund, or portfolio.
- The governance framework described here is designed; not all elements are automated end-to-end.

---

## 13. Extension Path

| Version | Extension | Dependency |
|---------|-----------|-----------|
| v0.4 | FK tests on manager→security, security→position | **Completed** — 14 relationship tests across fct_position_daily, fct_price_daily, fct_benchmark_return_daily, fct_manager_holding |
| v0.4 | Governance scorecard view | **Completed** — implemented as models/marts/governance/governance_scorecard.sql |
| v0.5 | CI/CD via GitHub Actions (dbt build on PR) | .github/workflows/ |
| v0.4 | Extended SCD to dim_investment_manager | New bronze ingestion run |
| v0.4 | Reconciliation CSV export for audit evidence | dbt post-hook or Python script |
| v0.5 | Multi-quarter 13F history (4 quarters) | Re-run edgar_client.py per quarter |
| v0.5 | N-PORT integration (fund-level holdings) | New edgar_client module |
| v0.5 | Issuer normalization (LEI, FIGI) | External reference data |
| v0.5 | Row-level security on consumption layer | Database role configuration |

---

## 14. Interview Talking Points

**On governance architecture:**
> "The repo implements a layered governance model: bronze is raw-as-ingested and append-only, silver is conformed with Type 2 history on key dimensions, marts are certified for consumption, and a reconciliation layer runs 7 automated gates before any mart data is considered reportable. Every gate either blocks the build on failure or produces documented evidence for stewardship review."

**On reconciliation controls:**
> "The bronze-to-silver gate enforces exact zero variance — any transformation that changes a holding total fails the build immediately. That's the same class of control as a position break report in fund operations. The filing totals gate allows a 0.001% tolerance, which is the SEC's own rounding precision, and we've verified all 5 filings fall within it."

**On real data:**
> "The 13F holdings data is real regulatory data from EDGAR — 30,135 holdings from five institutional managers filing for Q4 2025. We ingest it via the EDGAR submissions API, parse the XML information tables, load to bronze with idempotency, and reconcile every step. That's a real data pipeline with real quality controls, not synthetic fixtures."

**On SCD and history:**
> "Type 2 SCD on dim_security tracks when a security's attributes change — ticker, asset class, sector, rating. The snapshot uses dbt's check strategy, which is how you'd implement this idiomatically in a modern data stack. We have custom tests that validate no overlapping validity periods and exactly one current row per security, which are the two things that typically go wrong in SCD implementations."
