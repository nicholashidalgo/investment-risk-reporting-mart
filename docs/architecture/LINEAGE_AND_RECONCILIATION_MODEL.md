# Lineage and Reconciliation Model

> **Implementation Status Legend**
> `[Implemented]` — exists in this repo, tested, verified
> `[Designed]` — schema and logic defined, not yet executed
> `[Proposed]` — recommended approach, not yet designed

---

## 1. Purpose

This document describes the complete data lineage from raw public sources through transformation, validation, reconciliation, and governed consumption in the Investment Risk Reporting Mart. It maps every material transformation, identifies reconciliation checkpoints, and defines the evidence expected at each gate.

Lineage documentation is required to:
- Demonstrate that reported metrics can be traced back to authoritative source records
- Support audit requests: "Where does this number come from?"
- Identify which upstream source failures will propagate to which downstream marts
- Enable impact analysis when a source schema changes

---

## 2. Business Use Case

Investment regulators, fund auditors, and compliance officers routinely ask:

- "How do you know your reported AUM is accurate?"
- "What reconciles your internal position records to the custodian?"
- "If the security master changes, which reports are affected?"

This lineage model answers those questions for the data flows implemented in this repository. It documents the chain of custody from raw EDGAR XML or Yahoo Finance API call through to a certified mart row used in the dashboard.

---

## 3. Data Sources

| Source | Lineage Entry Point | Format | Ingestion Method |
|--------|--------------------|---------|--------------------|
| SEC EDGAR submissions API | `edgar_client.py` | JSON (submissions) + XML (information table) | Python HTTP → `bronze.raw_13f_holdings` |
| Yahoo Finance (`yfinance`) | `ingest_seed_data.py` | DataFrame → SQL INSERT | Python → `bronze.raw_*` tables |
| Synthetic bond data | `ingest_seed_data.py` | Python RNG (seed=42) → SQL INSERT | Python → `bronze.raw_*` tables |
| CUSIP seed file | `seeds/yfinance_to_cusip.csv` | CSV | dbt seed → `silver.yfinance_to_cusip` |

---

## 4. Operating Model

### Lineage Ownership

| Layer | Owner | Change Process |
|-------|-------|---------------|
| Source registration | Data Engineer | Update `models/sources.yml` |
| Bronze transformation | Data Engineer | Update `models/bronze/` SQL |
| Silver transformation | Data Engineer + Data Steward | Change reviewed against DATA_CONTRACT.md |
| Recon gate logic | Data Steward | Changes require documentation in DECISIONS.md |
| Mart logic | Data Engineer + Risk Officer | Methodology changes require METHODOLOGY.md update |

### When Lineage Must Be Updated

- New data source added
- Column rename or type change in any bronze model
- New join logic introduced in silver facts
- New mart or recon model added
- Grain change in any existing model (requires decision log entry)

---

## 5. Architecture — Full Lineage Map

```
╔══════════════════════════════════════════════════════════════════════════════╗
║              INVESTMENT RISK REPORTING MART — DATA LINEAGE MAP               ║
║                          v0.3 (2026-05-07)                                   ║
╚══════════════════════════════════════════════════════════════════════════════╝

STREAM A: SEC 13F INSTITUTIONAL HOLDINGS
────────────────────────────────────────

  [SOURCE] SEC EDGAR API
  GET /cgi-bin/browse-edgar?action=getcompany&CIK={cik}&type=13F-HR
  ↓
  edgar_client.py ──────────── fetches filing metadata, cover-page totals
  xml_parser.py ─────────────── parses 13F-HR Information Table XML
  bronze_loader.py ──────────── generates idempotent INSERT SQL
  ↓
  [BRONZE] bronze.raw_13f_holdings
  Grain: 1 row per (accession_no, nameOfIssuer, cusip, investmentDiscretion)
  Key columns: cik, accession_no, period_of_report, cusip, value, shares,
               investment_discretion, put_call, voting_authority_*
  Idempotency: DELETE WHERE accession_no = ? then INSERT
  ↓
  [RECON GATE 1] recon_filing_totals_reconciliation
  ├── Compares: SUM(bronze.value) per accession_no
  │   vs. cover-page total from edgar_client.py metadata
  ├── Tolerance: < 0.001% absolute variance
  ├── Result (Q4 2025): 5/5 PASS (Wellington: $1,000, 0.0000%)
  └── Evidence: recon/recon_filing_totals_reconciliation rows
  ↓
  [STAGING] bronze_dbt.stg_security_master (for CUSIP backfill)
  silver.yfinance_to_cusip (seed)
  ↓
  [SILVER] silver.dim_security
  ├── Source A: stg_security_master (yfinance equities, 23 rows)
  ├── Source B: bronze.raw_13f_holdings DISTINCT cusip (13F-only securities)
  ├── CUSIP join: yfinance_to_cusip seed → backfills CUSIP for 11 equities + 2 benchmarks
  └── Grain: 1 row per sec_id (current attributes; SCD history in dim_security_history)
  ↓
  [SILVER] silver.fct_manager_holding
  ├── Source: bronze.raw_13f_holdings (inner join to dim_security on cusip)
  ├── Grain: 1 row per (manager_id, security_id, period_of_report)
  ├── Aggregation: SUM(value), SUM(shares) across investment_discretion categories
  ├── Surrogate key: MD5(manager_id || security_id || period_of_report)
  └── Rows: 13,191 (Q4 2025)
  ↓
  [RECON GATE 2] recon_bronze_to_silver_reconciliation
  ├── Compares: SUM(fct_manager_holding.value_usd) per (cik, period)
  │   vs. SUM(raw_13f_holdings.value) per (cik, period)
  ├── Tolerance: exactly 0.000% (deterministic transform; any variance = bug)
  ├── Result (Q4 2025): 5/5 PASS (0.000% variance all managers)
  └── Evidence: recon/recon_bronze_to_silver_reconciliation rows
  ↓
  [RECON GATE 3] recon_zero_value_holdings (informational)
  ├── Identifies: holdings where value = 0 OR shares = 0 in bronze
  ├── Classification: '<500_usd_rounding', 'fractional_share', 'principal_amount_only'
  ├── Result (Q4 2025): 18 rows (all valid SEC data; not errors)
  └── Evidence: recon/recon_zero_value_holdings rows
  ↓
  [CONSUMPTION] Dashboard — Manager Holdings section
  Certified for use: all 3 13F recon gates PASS


STREAM B: YFINANCE EQUITY AND PRICING DATA
───────────────────────────────────────────

  [SOURCE] Yahoo Finance API (via yfinance Python library)
  Tickers: AAPL, MSFT, GOOGL, JPM, XOM, JNJ, PG, KO, NVDA, V, MA (11 equities)
           SPY, AGG (2 benchmarks)
  History: 1 year (rolling from ingest date)
  ↓
  ingest_seed_data.py ─────── fetches price history, security master data
  ↓
  [BRONZE] bronze.raw_security_master (23 rows: 11 equities + 2 benchmarks + 10 bonds)
  [BRONZE] bronze.raw_prices (daily OHLCV per security)
  [BRONZE] bronze.raw_benchmarks (daily benchmark prices)
  ↓
  [STAGING] bronze_dbt.stg_security_master
            bronze_dbt.stg_prices
            bronze_dbt.stg_benchmarks
  Transformations: cast, rename, light clean (no business logic)
  ↓
  [SILVER] silver.dim_security (yfinance subset)
  [SILVER] silver.fct_price_daily
  [SILVER] silver.fct_benchmark_return_daily
  ↓
  [RECON GATE 4] recon_stale_prices
  ├── Identifies: securities where max(price_date) > 5 business days stale
  └── Evidence: recon/recon_stale_prices rows
  ↓
  [MARTS] mart_portfolio_exposure, mart_concentration_limits,
          mart_var_parametric, mart_tracking_error, mart_scenario_impact
  ↓
  [CONSUMPTION] Dashboard — Portfolio Analytics sections


STREAM C: SYNTHETIC BOND AND POSITION DATA
───────────────────────────────────────────

  [SOURCE] Python RNG (seed=42, deterministic)
  Securities: BOND_001 through BOND_010
  Portfolios: PORT_CORE, PORT_FLEX (with equity + bond positions)
  ↓
  ingest_seed_data.py ─────── generates synthetic bonds, positions, ratings
  ↓
  [BRONZE] bronze.raw_security_master (bond rows)
           bronze.raw_positions (daily positions per portfolio)
           bronze.raw_ratings (per security, per agency)
           bronze.raw_stress_scenarios (scenario factor definitions)
  ↓
  [STAGING] bronze_dbt.stg_positions, stg_ratings, stg_stress_scenarios
  ↓
  [SILVER] silver.dim_portfolio, silver.fct_position_daily
  ↓
  [RECON GATE 5] recon_position_to_nav
  ├── Compares: SUM(market_value_usd) per portfolio per date
  │   vs. declared portfolio NAV
  └── Evidence: recon/recon_position_to_nav rows

  [RECON GATE 6] recon_rating_coverage
  ├── Checks: % of fixed-income holdings with ratings ≥ 80%
  └── Evidence: recon/recon_rating_coverage rows

  [RECON GATE 7] recon_benchmark_coverage
  ├── Checks: % of benchmark constituents with prices ≥ 95%
  └── Evidence: recon/recon_benchmark_coverage rows
  ↓
  [MARTS] mart_credit_exposure, mart_duration_summary, mart_scenario_impact
  ↓
  [CONSUMPTION] Dashboard — Risk Analytics sections


SCD LINEAGE: TYPE 2 SECURITY HISTORY
──────────────────────────────────────

  silver.dim_security (current attributes)
  ↓
  snapshots/dim_security_snapshot.sql
  ├── Strategy: check (detects changes in ticker, asset_class, sector,
  │   rating, maturity, issue_date)
  ├── Unique key: sec_id
  └── Output: snapshots.dim_security_snapshot
  ↓
  silver.dim_security_history
  ├── Columns: sec_id, scd_id (surrogate), dbt_valid_from, dbt_valid_to, is_current
  └── Tests: no overlapping periods, exactly one current row per sec_id
  ↓
  silver.dim_security_current (view, is_current = true)
  ↓
  [Usage] Any historical analysis requiring point-in-time security attributes


```

---

## 6. Data Controls

| Control Point | Type | Gate | Status |
|--------------|------|------|--------|
| Bronze ingestion idempotency | Process | DELETE + INSERT per accession_no | `[Implemented]` |
| Filing totals vs. SEC cover page | Recon gate | < 0.001% variance | `[Implemented]` |
| Bronze-to-silver holdings value | Recon gate | Exactly 0.000% variance | `[Implemented]` |
| Zero-value holdings identification | Recon gate | Informational surface | `[Implemented]` |
| Stale price detection | Recon gate | > 5 days stale → flagged | `[Implemented]` |
| Position NAV reconciliation | Recon gate | Sum of positions vs. declared NAV | `[Implemented]` |
| Rating coverage | Recon gate | ≥ 80% fixed-income rated | `[Implemented]` |
| Benchmark coverage | Recon gate | ≥ 95% constituents priced | `[Implemented]` |
| SCD integrity: no period overlap | Singular test | 0 rows with overlapping valid_from/valid_to | `[Implemented]` |
| SCD integrity: one current row | Singular test | 0 rows where count(is_current=true) > 1 per sec_id | `[Implemented]` |
| Source registration | sources.yml | All bronze tables registered | `[Implemented]` |
| Column-level tests | schema.yml | 192 tests across all layers | `[Implemented]` |

---

## 7. Governance Workflow

**For each pipeline run:**

```
1. Ingestion
   ├── edgar_client.py / ingest_seed_data.py execute
   ├── Bronze tables loaded (idempotent)
   └── Quarantine log reviewed (0 malformed records in v0.3)

2. dbt build
   ├── Bronze staging models built
   ├── Silver dimensions + facts built
   ├── Snapshots run (dbt snapshot)
   ├── Marts built
   └── Recon models built

3. dbt test
   ├── 192 schema + singular tests run
   ├── Any FAIL stops the pipeline
   └── All PASS → certified

4. Recon review
   ├── Data steward reviews recon_* model outputs
   ├── FAIL rows → issue triage → DECISIONS.md
   └── All PASS → marts available for consumption

5. Evidence preservation
   ├── Recon model rows are queryable for audit
   └── DECISIONS.md captures any tolerance decisions
```

**Answering an audit question: "Where does this number come from?"**

```
Claim: Wellington Management holds $571B in equities (Q4 2025)

Evidence chain:
1. Source: EDGAR accession 0000902219-26-000103 (filed 2026-02-17)
2. Bronze: bronze.raw_13f_holdings WHERE cik = '0000902219'
   → SUM(value) * 1000 = $571.4B
3. Recon gate 1: recon_filing_totals_reconciliation
   → PASS; variance vs. cover-page total = $0 (0.0000%)
4. Silver: fct_manager_holding WHERE manager_id = 'WELLINGTON_MGMT_GROUP'
   → SUM(value_usd) = $571.4B
5. Recon gate 2: recon_bronze_to_silver_reconciliation
   → PASS; variance = $0 (0.000%)
6. Dashboard: Wellington AUM displayed from fct_manager_holding
```

---

## 8. Implementation Workflow

**Adding a new data source to the lineage:**

1. Add source to `models/sources.yml`; add `loaded_at_field` and `freshness` blocks if the table has a TIMESTAMPTZ column (`_ingested_at` or equivalent). DATE columns are not compatible with dbt 1.11 source freshness; document the limitation if only a DATE column is available.
2. Create `models/bronze/stg_{source}.sql`
3. Add column tests and descriptions to `models/bronze/schema.yml`
4. Create or update silver model that consumes the source
5. Add reconciliation gate in `models/recon/` comparing source to silver totals
6. Create singular test in `tests/recon_{source}_no_failures.sql`
7. Update this document: add the new stream to the lineage map
8. Update `DATA_CONTRACT.md` with new grain and semantics

---

## 9. Operational Metrics

| Metric | Current Value |
|--------|-------------|
| Data streams with full lineage documented | 3 (13F, yfinance, synthetic) |
| Recon gates | 7 |
| Recon gates with blocking singular tests | 2 (13F only) |
| Recon PASS rate (13F filings) | 5/5 (100%) |
| Bronze-to-silver variance | 0.000% across all 5 managers |
| SCD lineage streams | 1 (dim_security) |
| Source tables registered in sources.yml | 8 (all bronze tables) |
| Source freshness gates active | 1 (`raw_13f_filings` via `_ingested_at` TIMESTAMPTZ; 120d warn / 180d error) |
| Source freshness gates designed (DATE columns) | 4 (`raw_positions`, `raw_prices`, `raw_benchmarks`, `raw_ratings` — need TIMESTAMPTZ column first) |
| Relationship (FK) tests | 14 across `fct_position_daily`, `fct_price_daily`, `fct_benchmark_return_daily`, `fct_manager_holding` |
| Governance scorecard KPIs | 8 (all implemented, live in `governance_scorecard` model) |

---

## 10. Workplace Application

This lineage model directly maps to investment operations requirements:

- **EDGAR filing reconciliation** mirrors the custodian reconciliation that fund administrators run: compare what was reported externally against what is in the internal position system
- **Bronze-to-silver zero-variance gate** is the equivalent of a system-to-system reconciliation between a portfolio management system (PMS) and a data warehouse — any ETL that changes a value must be explained and approved
- **Idempotent bronze loads** are the equivalent of a trade booking system that uses the trade ID as an idempotency key: re-submitting the same filing never creates duplicate records
- **SCD on dim_security** mirrors the security master audit trail that custodians and administrators maintain to show what attributes a security had on a given date — critical for historical position reporting and audit
- **Evidence chain** — the ability to trace from a dashboard number back to a raw source record — is what an operations team produces during a regulatory examination or investor due diligence request

---

## 11. Limitations

- **Lineage is documented, not automated.** There is no lineage graph tool (e.g., dbt docs graph, OpenLineage) generating this automatically. The dbt DAG provides automated model-level lineage within dbt; column-level lineage is manual documentation.
- **yfinance has no data contract.** Yahoo Finance API responses can change format without notice; the ingestion script has no schema validation layer.
- **Synthetic bond data has no external source.** Its lineage terminates at `ingest_seed_data.py`; there is no upstream source to reconcile against.
- **Single reporting period.** The 13F lineage covers Q4 2025 only; multi-period lineage is a v0.5 extension.

---

## 12. What This Does Not Claim

- This repo does not claim to have a production-grade lineage platform (e.g., OpenLineage, DataHub, Atlan).
- The lineage documented here covers the models in this repository only.
- Column-level lineage is manually maintained; it may lag behind code changes until this document is updated.
- Reconciliation tolerances are set for this demonstration data and should not be applied to production investment reporting without validation.

---

## 13. Extension Path

| Version | Extension | Status |
|---------|-----------|--------|
| v0.4 | `loaded_at_field` + freshness for `raw_13f_filings` using `_ingested_at` TIMESTAMPTZ | ✅ Completed |
| v0.4 | Relationship (FK) tests across all silver fact tables | ✅ Completed |
| v0.4 | Governance scorecard model (`governance_scorecard.sql`) | ✅ Completed |
| v0.5 | Add `_ingested_at TIMESTAMPTZ` to `raw_positions`, `raw_prices`, `raw_benchmarks`, `raw_ratings` to enable source freshness | Planned |
| v0.5 | Reconciliation CSV export (`reports/`) for audit evidence artifacts | Planned |
| v0.5 | Multi-quarter 13F lineage (add Q1–Q3 2025 filings) | Planned |
| v0.5 | dbt docs DAG published as static site | Planned |
| v0.5 | OpenLineage integration for automated column-level lineage | Planned |
| v0.5 | N-PORT lineage stream (fund-level holdings) | Planned |

---

## 14. Interview Talking Points

**On lineage as audit evidence:**
> "Lineage isn't just documentation — it's the answer to 'where does this number come from?' For every holding in the dashboard, I can trace back to the raw EDGAR XML, identify which accession number it came from, show the bronze-to-silver reconciliation, and explain any aggregation decisions. That chain of custody is what compliance and auditors actually need."

**On reconciliation gate design:**
> "I have two different tolerance levels for the 13F recon gates by design. The filing totals gate allows 0.001% because SEC XML reports in thousands of dollars — a $1,000 rounding difference on a $1B filing is a precision artifact, not an error. The bronze-to-silver gate allows exactly zero because the transformation is deterministic. Any non-zero variance there means the transformation code has a bug."

**On SCD and historical accuracy:**
> "Type 2 SCD on the security dimension means we can answer questions like 'what was GOOGL's sector classification on this date' even if it was reclassified later. That matters for historical backtest accuracy and for audit trails where you need to prove the data used in a past report matched the attributes the security had at that time."
