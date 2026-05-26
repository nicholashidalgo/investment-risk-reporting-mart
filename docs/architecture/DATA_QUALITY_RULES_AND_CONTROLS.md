# Data Quality Rules and Controls

> **Implementation Status Legend**
> `[Implemented]` — exists in this repo, tested, verified
> `[Designed]` — logic defined, not yet executed
> `[Proposed]` — recommended approach, not yet designed

---

## 1. Purpose

This document defines the data quality rules and controls applied to investment reference data, holdings data, pricing data, and reconciliation outputs in this repository. Each rule is categorized by quality dimension, mapped to the affected models, assigned a severity, and labeled with its implementation status.

The goal is to make the control environment legible to data stewards, analysts, auditors, and engineers — and to provide a reference for extending quality coverage as the data product grows.

---

## 2. Business Use Case

Data quality failures in investment data have direct operational consequences:

- **Incorrect holdings** can cause compliance breaches (concentration limits, regulatory thresholds)
- **Stale prices** produce incorrect NAV and risk metrics
- **Missing ratings** cause credit exposure to be underreported
- **Reconciliation breaks** between a manager's filed totals and internal records trigger regulatory scrutiny
- **Duplicate positions** overstate exposure and distort analytics

These rules implement the categories of controls that an investment operations or data governance team would apply before certifying data for reporting.

---

## 3. Data Sources

Quality rules are applied across all layers:

| Layer | Schema | Primary Sources |
|-------|--------|----------------|
| Bronze staging | `bronze_dbt` | SEC EDGAR 13F-HR XML, yfinance prices, synthetic bonds |
| Silver dimensions | `silver` | Conformed from bronze; Type 2 SCD on dim_security |
| Silver facts | `silver` | fct_position_daily, fct_price_daily, fct_manager_holding |
| Marts | `marts` | Pre-aggregated risk analytics |
| Recon | `recon` | Reconciliation gate outputs |

---

## 4. Operating Model

Data quality rules are enforced through three mechanisms:

1. **dbt schema tests** — declarative tests in `schema.yml` files; run as part of `dbt build`; blocking on failure
2. **Singular tests** — custom SQL in `tests/`; assert zero rows returned; blocking on failure
3. **Reconciliation models** — SQL models in `models/recon/`; produce PASS/FAIL/WARN rows; paired with singular tests that block if any FAIL exists

All 192 tests are configured at `severity: error` (blocking). There are no warn-only tests in this repo.

---

## 5. Architecture

```
 DATA QUALITY ENFORCEMENT ARCHITECTURE
 ──────────────────────────────────────
 
 schema.yml (declarative)      tests/ (singular)         models/recon/
 ─────────────────────────     ─────────────────         ─────────────
 not_null                       fct_manager_holding_      recon_filing_totals_
 unique                          positive_shares.sql        reconciliation
 accepted_values                fct_manager_holding_      recon_bronze_to_silver_
 expression_is_true              positive_value.sql         reconciliation
 relationships [Implemented]    recon_*_no_failures.sql   recon_zero_value_holdings
                                dim_security_history_*    recon_stale_prices
                                  (SCD integrity)         recon_position_to_nav
                                                          recon_benchmark_coverage
                                                          recon_rating_coverage
 
 ALL TESTS RUN IN: dbt build --select +mart_* +recon_* (or dbt test)
 RESULT: 192/192 PASS (227/227 total in dbt build) as of 2026-05-26
```

---

## 6. Data Controls

### 6.1 Completeness

*No required field should be null in a certified record.*

| Rule ID | Rule Description | Model(s) | Implementation | Status |
|---------|-----------------|----------|---------------|--------|
| CMP-001 | `sec_id` must not be null | `stg_security_master`, `dim_security`, `fct_position_daily` | `not_null` test | `[Implemented]` |
| CMP-002 | `holding_id` must not be null | `fct_manager_holding` | `not_null` test | `[Implemented]` |
| CMP-003 | `manager_id` must not be null | `fct_manager_holding`, `dim_investment_manager` | `not_null` test | `[Implemented]` |
| CMP-004 | `price_date` must not be null | `fct_price_daily`, `stg_prices` | `not_null` test | `[Implemented]` |
| CMP-005 | `period_of_report` must not be null | `fct_manager_holding` | `not_null` test | `[Implemented]` |
| CMP-006 | `asset_class` must not be null | `dim_security`, `fct_position_daily` | `not_null` test | `[Implemented]` |
| CMP-007 | `cusip` populated for 13F-sourced securities | `dim_security` | `not_null` test (CUSIP-joined rows only) | `[Designed]` |
| CMP-008 | `sector` populated for equity securities | `dim_security` | Partial — yfinance provides; 13F defaults to 'Unknown' | `[Designed]` |

### 6.2 Uniqueness

*No primary key or business key should appear more than once.*

| Rule ID | Rule Description | Model(s) | Implementation | Status |
|---------|-----------------|----------|---------------|--------|
| UNQ-001 | `sec_id` is unique per security | `dim_security` | `unique` test | `[Implemented]` |
| UNQ-002 | `holding_id` (MD5 surrogate) is unique | `fct_manager_holding` | `unique` test | `[Implemented]` |
| UNQ-003 | `(portfolio_id, sec_id, date)` is unique per day | `fct_position_daily` | `unique` test on composite | `[Implemented]` |
| UNQ-004 | `(sec_id, price_date)` is unique per day | `fct_price_daily` | `unique` test on composite | `[Implemented]` |
| UNQ-005 | `cik` is unique per manager | `dim_investment_manager` | `unique` test | `[Implemented]` |
| UNQ-006 | `(manager_id, security_id, period_of_report)` is unique | `fct_manager_holding` | `unique` test on composite | `[Implemented]` |
| UNQ-007 | One `is_current = true` row per `sec_id` in history | `dim_security_history` | Singular test | `[Implemented]` |

### 6.3 Referential Integrity

*Foreign keys must resolve to valid parent records.*

| Rule ID | Rule Description | Model(s) | Implementation | Status |
|---------|-----------------|----------|---------------|--------|
| REF-001 | `security_id` in fct_manager_holding must exist in dim_security | `fct_manager_holding` | Inner join (enforced at query time) + `relationships` test | `[Implemented]` |
| REF-002 | `manager_id` in fct_manager_holding must exist in dim_investment_manager | `fct_manager_holding` | `relationships` test | `[Implemented]` |
| REF-003 | `portfolio_id` in fct_position_daily must exist in dim_portfolio | `fct_position_daily` | `relationships` test | `[Implemented]` |
| REF-004 | `sec_id` in fct_position_daily must exist in dim_security | `fct_position_daily` | `relationships` test | `[Implemented]` |
| REF-005 | `benchmark_id` in fct_benchmark_return_daily must exist in dim_benchmark | `fct_benchmark_return_daily` | `relationships` test | `[Implemented]` |
| REF-006 | `position_date` in fct_position_daily must exist in dim_date | `fct_position_daily` | `relationships` test | `[Implemented]` |
| REF-007 | `price_date` in fct_price_daily must exist in dim_date | `fct_price_daily` | `relationships` test | `[Implemented]` |
| REF-008 | `benchmark_date` in fct_benchmark_return_daily must exist in dim_date | `fct_benchmark_return_daily` | `relationships` test | `[Implemented]` |

### 6.4 Freshness

*Data should not be stale beyond defined tolerances.*

| Rule ID | Rule Description | Model(s) | Implementation | Status |
|---------|-----------------|----------|---------------|--------|
| FRS-001 | Price records should not be older than 5 business days | `recon_stale_prices` | Recon gate; produces WARN rows | `[Implemented]` |
| FRS-002 | Source data freshness check via dbt source freshness — raw_13f_filings | `sources.yml` | `loaded_at_field` (_ingested_at TIMESTAMPTZ) + `freshness` block (120d warn / 180d error) | `[Implemented]` |
| FRS-002b | Source data freshness for raw_positions, raw_prices, raw_benchmarks, raw_ratings | `sources.yml` | `[Designed]` — these tables have only DATE columns; dbt 1.11 requires TIMESTAMP-compatible loaded_at_field; scheduled for v0.5 | `[Designed]` |
| FRS-003 | 13F filing date freshness | `sources.yml` (raw_13f_filings) | Covered by source freshness on raw_13f_filings (120d warn / 180d error threshold) | `[Implemented]` |

```sql
-- FRS-001: Implemented in models/recon/recon_stale_prices.sql
-- Finds prices where max(price_date) lags current date by > tolerance
SELECT
    sec_id,
    max(price_date) AS last_price_date,
    current_date - max(price_date) AS days_stale,
    CASE
        WHEN current_date - max(price_date) > 5 THEN 'STALE'
        ELSE 'CURRENT'
    END AS freshness_status
FROM silver.fct_price_daily
GROUP BY sec_id
```

### 6.5 Price Reasonability

*Price values should fall within plausible bounds.*

| Rule ID | Rule Description | Model(s) | Implementation | Status |
|---------|-----------------|----------|---------------|--------|
| PRC-001 | `close_price` must be > 0 for equity securities | `fct_price_daily` | `expression_is_true` test | `[Implemented]` |
| PRC-002 | `close_price` for bonds must be between 0.01 and 200 (price per 100 par) | `fct_price_daily` | `expression_is_true` test | `[Designed]` |
| PRC-003 | Daily price return must not exceed ±50% (outlier detection) | `fct_price_daily` | Analytical check in mart | `[Proposed]` |
| PRC-004 | `value_thousands_usd` in 13F holdings must not be negative | `fct_manager_holding` | Singular test | `[Implemented]` |

```sql
-- PRC-003: Proposed — daily return outlier detection
-- Add to mart_price_analytics (v0.5 candidate)
SELECT
    sec_id,
    price_date,
    close_price,
    LAG(close_price) OVER (PARTITION BY sec_id ORDER BY price_date) AS prev_close,
    (close_price - LAG(close_price) OVER (PARTITION BY sec_id ORDER BY price_date))
      / NULLIF(LAG(close_price) OVER (PARTITION BY sec_id ORDER BY price_date), 0)
      AS daily_return_pct
FROM silver.fct_price_daily
WHERE ABS(daily_return_pct) > 0.50
```

### 6.6 Holdings Reconciliation

*Transformed holdings totals must match source totals within defined tolerances.*

| Rule ID | Rule Description | Model(s) | Tolerance | Status |
|---------|-----------------|----------|-----------|--------|
| REC-001 | Silver holding value sum = bronze holding value sum per (cik, period) | `recon_bronze_to_silver_reconciliation` | Exactly 0.000% | `[Implemented]` |
| REC-002 | Bronze filing total = SEC cover-page reported total per accession_no | `recon_filing_totals_reconciliation` | < 0.001% | `[Implemented]` |
| REC-003 | Holdings with value=0 or shares=0 are surfaced as informational | `recon_zero_value_holdings` | Informational; not a failure | `[Implemented]` |
| REC-004 | Portfolio NAV sum of positions reconciles to declared NAV | `recon_position_to_nav` | Tolerance configurable | `[Implemented]` |
| REC-005 | Benchmark coverage ≥ 95% of constituents with prices | `recon_benchmark_coverage` | ≥ 95% | `[Implemented]` |
| REC-006 | Rating coverage ≥ 80% of fixed-income holdings | `recon_rating_coverage` | ≥ 80% | `[Implemented]` |

```sql
-- REC-001: Implemented in models/recon/recon_bronze_to_silver_reconciliation.sql
-- Any non-zero variance is a blocking failure
SELECT
    b.cik,
    b.period_of_report,
    b.bronze_total_value,
    s.silver_total_value,
    s.silver_total_value - b.bronze_total_value AS variance_usd,
    CASE
        WHEN ABS(s.silver_total_value - b.bronze_total_value) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM bronze_totals b
JOIN silver_totals s
  ON b.cik = s.cik
 AND b.period_of_report = s.period_of_report
```

### 6.7 Stale Records

*Records that have not been updated within expected windows should be flagged.*

| Rule ID | Rule Description | Model(s) | Status |
|---------|-----------------|----------|--------|
| STL-001 | Prices not updated in > 5 business days | `recon_stale_prices` | `[Implemented]` |
| STL-002 | Security master not updated in > 30 days | Future recon gate | `[Proposed]` |
| STL-003 | 13F holdings older than 90 days from period_of_report | Informational flag | `[Proposed]` |

### 6.8 Outlier Detection

*Statistical outliers in key metrics should be surfaced for review.*

| Rule ID | Rule Description | Model(s) | Status |
|---------|-----------------|----------|--------|
| OUT-001 | VaR exceeds 10% of NAV (1-day, 99% confidence) | `mart_var_parametric` | Manual review | `[Proposed]` |
| OUT-002 | Concentration limit breach: position > 5% of portfolio NAV | `mart_concentration_limits` | `breach_flag` column | `[Implemented]` |
| OUT-003 | Manager holding value > 3 standard deviations from peer mean | `fct_manager_holding` | Statistical gate | `[Proposed]` |

### 6.9 Reporting Readiness

*Before data is certified for reporting, all gates must pass.*

| Rule ID | Rule Description | Model(s) | Status |
|---------|-----------------|----------|--------|
| RPT-001 | All dbt tests pass (0 failures) | Entire pipeline | `[Implemented]` |
| RPT-002 | All recon gates return PASS | `recon_*` models | `[Implemented]` |
| RPT-003 | No FAIL rows in recon_filing_totals | Singular test | `[Implemented]` |
| RPT-004 | No FAIL rows in recon_bronze_to_silver | Singular test | `[Implemented]` |
| RPT-005 | Metadata completeness ≥ threshold | schema.yml | `[Designed]` |
| RPT-006 | Lineage documented for all certified models | docs/architecture | `[Implemented]` |

---

## 7. Governance Workflow

```
dbt build
    │
    ├─► schema.yml tests (not_null, unique, accepted_values, expression_is_true, relationships)
    │       All 192 must PASS
    │
    ├─► Singular tests (tests/)
    │       positive_shares, positive_value
    │       recon_*_no_failures → blocks if any FAIL in recon outputs
    │       dim_security_history SCD integrity
    │
    └─► PASS → Marts available for certified consumption
        FAIL → Build stops; engineer reviews failure message;
               DECISIONS.md updated with triage notes
```

**Note:** The `governance_scorecard` model (models/marts/governance/governance_scorecard.sql) now surfaces warehouse-queryable versions of KPI-01 through KPI-08. This provides a single queryable view of all major quality signals without manually querying each recon model.

**Escalation path on test failure:**
1. Engineer identifies failing test and model
2. Root cause: source data issue, transformation bug, or tolerance exceeded
3. If source data: document in DECISIONS.md; escalate to data steward
4. If transformation: fix SQL, re-run dbt build
5. If tolerance: review with data owner before adjusting threshold
6. Resolution documented; build re-run to confirm pass

---

## 8. Implementation Workflow

Adding a new data quality rule:

1. **Identify** the quality dimension (completeness, uniqueness, freshness, etc.)
2. **Choose** the correct enforcement mechanism:
   - Declarative → add to `schema.yml` under the model and column
   - Custom logic → create `tests/{rule_name}.sql` (returns 0 rows on PASS)
   - Aggregate check → add column or model to `models/recon/`
3. **Set severity** to `error` unless there is a documented reason for `warn`
4. **Assign** a rule ID and add to this document with status
5. **Run** `dbt test --select {model_name}` to verify
6. **Update** `GOVERNANCE_SCORECARD_MODEL.md` if the rule affects a KPI

---

## 9. Operational Metrics

| Metric | Current Value |
|--------|-------------|
| Total quality rules defined | 45 (this document; added REF-006, REF-007, REF-008) |
| Rules implemented | 34 |
| Rules designed (not yet executed) | 7 |
| Rules proposed (not yet designed) | 4 |
| Test pass rate | 100% (227/227) |
| Recon PASS rate (13F filings) | 100% (5/5) |
| Bronze-to-silver variance | 0.000% |
| Zero-value holdings flagged | 18 rows (informational) |

---

## 10. Workplace Application

These control categories map directly to investment data quality programs at asset managers, fund administrators, and custodians:

- **Completeness and uniqueness** — equivalent to security master data controls that prevent duplicate ISINs or missing CUSIPs from entering downstream systems
- **Referential integrity** — equivalent to position master checks that ensure every position has a valid security and fund reference
- **Freshness** — equivalent to the T+0 or T+1 price validation that operations teams run before NAV calculation
- **Price reasonability** — equivalent to automated "price challenge" workflows that flag returns outside tolerance bands before prices are applied to positions
- **Holdings reconciliation** — equivalent to the back-office break management process, where any variance between custodian and internal records must be resolved before reporting
- **Reporting readiness gates** — equivalent to the sign-off checklist that a fund controller completes before releasing a NAV or investor report

---

## 11. Limitations

- Price reasonability rules (PRC-002, PRC-003) apply to synthetic bond data only; yfinance prices are not validated against an independent source.
- Referential integrity tests (REF-002 through REF-008) are now active as explicit dbt `relationships` tests; integrity is enforced both via inner joins in Silver models and via declarative tests.
- No real-time or near-real-time quality monitoring. All checks are batch, run per pipeline execution.
- Tolerance thresholds (e.g., 0.001% for filing totals) are set based on SEC data precision. They are not validated against production fund reconciliation standards.

---

## 12. What This Does Not Claim

- This repo does not claim that these quality rules are sufficient for production fund operations.
- This repo does not claim that yfinance prices have been validated against a secondary pricing source.
- Synthetic bond data quality rules test structure only; they have no real-world pricing validity.
- No third-party audit of these controls has been performed.

---

## 13. Extension Path

| Version | Extension |
|---------|-----------|
| v0.4 | FK relationship tests (REF-002 through REF-005) | **Completed** — plus REF-006, REF-007, REF-008 added |
| v0.4 | dbt source freshness (FRS-002) | **Partially completed** — raw_13f_filings implemented; date-type sources (raw_positions, raw_prices, raw_benchmarks, raw_ratings) require TIMESTAMP column and remain v0.5 |
| v0.4 | Filing date freshness gate (FRS-003) | **Completed** — covered by source freshness on raw_13f_filings |
| v0.5 | Source freshness for date-type tables (raw_positions, raw_prices, raw_benchmarks, raw_ratings) | Requires TIMESTAMP-compatible loaded_at_field column |
| v0.5 | Price outlier detection mart (PRC-003) |
| v0.5 | Manager outlier detection (OUT-003) |
| v0.5 | Automated reporting readiness scorecard (RPT-005) |

---

## 14. Interview Talking Points

**On building quality rules:**
> "I categorize quality rules by dimension — completeness, uniqueness, referential integrity, freshness, reasonability, reconciliation, and reporting readiness. Each one has a different enforcement mechanism: declarative schema tests for column-level rules, singular SQL tests for business logic, and reconciliation models for aggregate controls. The hierarchy matters: completeness and uniqueness must pass before reconciliation even runs."

**On reconciliation tolerance design:**
> "The bronze-to-silver gate is set to exact zero variance because the transformation is deterministic — if the transformation changes a value, that's a bug, not a rounding difference. The filing totals gate allows 0.001% because that's the precision of the SEC's own XML format, which reports in thousands of dollars. Choosing the right tolerance requires understanding the source system's precision, not just picking a number."

**On test severity:**
> "Everything is severity error in this repo — no warn-only tests. In a production environment you might use warn for informational signals like zero-value holdings, but I want to develop the habit of treating data quality as binary: the build either passes or it doesn't. The zero-value holdings case is handled as a separate informational recon model rather than a warning on a test."
