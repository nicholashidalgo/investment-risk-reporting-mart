# Business Glossary and Metadata Model

> **Implementation Status Legend**
> `[Implemented]` — defined in schema.yml and/or DATA_CONTRACT.md; enforced by tests
> `[Designed]` — definition agreed upon; not yet in schema.yml
> `[Proposed]` — recommended for inclusion; not yet defined

---

## 1. Purpose

This document defines the authoritative business terms used in the Investment Risk Reporting Mart. It serves as the single source of truth for how key concepts are defined, who owns them, how they are measured, and what downstream systems consume them.

A business glossary reduces ambiguity between engineers, analysts, risk officers, and compliance stakeholders. When a term like "market value" or "holding" has different interpretations across teams, reports disagree — this document prevents that.

---

## 2. Business Use Case

Governed investment data requires consistent terminology across:

- Portfolio management (position sizing, exposure limits)
- Risk management (VaR, tracking error, duration, concentration)
- Operations (reconciliation, NAV certification, regulatory filing)
- Compliance (13F reporting, concentration thresholds, regulatory definitions)
- Data engineering (model grain, join logic, test conditions)

Terms in this glossary are referenced in `DATA_CONTRACT.md`, `schema.yml` descriptions, dbt model documentation, and the reconciliation controls in `models/recon/`.

---

## 3. Data Sources

Terms are derived from and mapped to:

| Source | Reference |
|--------|-----------|
| SEC EDGAR 13F-HR XML schema | `data/raw/sec_13f/` |
| Yahoo Finance API | `scripts/ingest_seed_data.py` |
| dbt model grain definitions | `models/*/schema.yml` |
| DATA_CONTRACT.md | `DATA_CONTRACT.md` |
| METHODOLOGY.md | `METHODOLOGY.md` |

---

## 4. Operating Model

### Term Ownership

| Role | Responsibility |
|------|---------------|
| **Data Steward** | Defines terms; maintains this document; resolves ambiguity disputes |
| **Data Owner** | Approves changes to certified terms (marked with ⭐) |
| **Data Engineer** | Implements terms in schema.yml; flags mismatches |
| **Risk Officer** | Owns risk metric definitions (VaR, duration, tracking error) |

### Change Process

1. Propose new or revised term via PR comment or stewardship issue
2. Data steward drafts definition and submits to this document
3. Data owner approves changes to certified terms
4. Data engineer updates `schema.yml` descriptions to match
5. `dbt docs generate` regenerates catalog with updated descriptions

---

## 5. Architecture

Glossary terms are implemented across the following artifacts:

```
Business Glossary (this document)
    │
    ├─► schema.yml descriptions (column-level)
    │       models/bronze/schema.yml
    │       models/silver/schema.yml
    │       models/marts/schema.yml (planned v0.4)
    │
    ├─► DATA_CONTRACT.md (grain and semantics per model)
    │
    ├─► dbt docs catalog (generated from schema.yml)
    │
    └─► Reconciliation model logic (recon_* use these definitions)
```

---

## 6. Data Controls

| Control | Description | Status |
|---------|-------------|--------|
| All model PKs described in schema.yml | Ensures grain is documented | `[Implemented]` |
| accepted_values tests enforce allowed term values | e.g., asset_class ∈ {Equity, Fixed Income, Benchmark} | `[Implemented]` |
| New terms must be added here before being used in model logic | Process control | `[Proposed]` |

---

## 7. Glossary — Core Investment Terms

---

### Security ⭐

| Attribute | Value |
|-----------|-------|
| **Definition** | A financial instrument that is tradeable or reportable. In this repo, securities include publicly-traded equities, fixed-income instruments (bonds), and benchmark indices. |
| **Primary Key** | `sec_id` (internal surrogate; format: ticker for equities, BOND_NNN for synthetic bonds, 13F-sourced securities inherit CUSIP as a secondary key) |
| **Secondary Key** | `cusip` (9-character CUSIP identifier; populated for yfinance equities via seed map; populated for 13F securities from EDGAR XML) |
| **Owner** | Data Steward |
| **Source** | `dim_security` (silver layer) |
| **Grain** | 1 row per security, current attributes only |
| **History** | `dim_security_history` — Type 2 SCD; tracks ticker, asset_class, sector, rating, maturity, issue_date |
| **Allowed Values** | `asset_class` ∈ {Equity, Fixed Income, Benchmark} |
| **Downstream Usage** | All facts join to dim_security; `fct_manager_holding` joins on CUSIP |
| **Status** | `[Implemented]` |

---

### Issuer

| Attribute | Value |
|-----------|-------|
| **Definition** | The legal entity that issued a security. For equities, this is the public company (e.g., Apple Inc. for AAPL). For bonds, this is the borrower. |
| **Note** | This repo does not have a `dim_issuer` table. Issuer information is embedded in `dim_security.ticker` (equities) and in SEC EDGAR filings. A normalized issuer dimension with LEI cross-referencing is a v0.5 candidate. |
| **Downstream Usage** | Would support issuer-level concentration and credit exposure |
| **Status** | `[Proposed]` (v0.5) |

---

### Holding ⭐

| Attribute | Value |
|-----------|-------|
| **Definition** | A reported position of a specific security held by a specific investment manager, as of a specific reporting period. Sourced from SEC 13F-HR regulatory filings. |
| **Primary Key** | `holding_id` — MD5 hash of (manager_id \|\| security_id \|\| period_of_report) |
| **Grain** | 1 row per (manager, security, reporting period) — multiple discretion categories from the 13F XML are summed into one silver row |
| **Grain Decision** | Summing discretion categories is documented in DECISIONS.md (2026-05-07). Bronze rows are authoritative for split detail. |
| **Owner** | Data Steward |
| **Source** | `fct_manager_holding` (silver layer); sourced from `bronze.raw_13f_holdings` |
| **Key Measures** | `value_thousands_usd` (as reported on 13F), `shares`, `principal_amount` (bonds) |
| **Allowed Values** | `value_thousands_usd` ≥ 0 (negative values rejected by singular test); `shares` ≥ 0 |
| **Downstream Usage** | Manager exposure analysis; sector and security concentration; trend analysis (v0.5) |
| **Status** | `[Implemented]` |

---

### Market Value

| Attribute | Value |
|-----------|-------|
| **Definition** | The current monetary value of a position, calculated as shares × price (for equities) or reported directly (for 13F holdings where value_thousands_usd is the filed market value). |
| **In 13F context** | `value_thousands_usd` × 1,000 = reported market value in USD. This is the value reported on Schedule 13F by the institution; it reflects the institution's own valuation as of period-end, not independently verified. |
| **In position context** | `market_value_usd` in `fct_position_daily` = `shares * close_price` using yfinance prices |
| **Precision** | 13F values are in thousands of dollars (SEC format). Amounts below $500 may appear as $0 due to rounding. |
| **Owner** | Risk Officer |
| **Status** | `[Implemented]` |

---

### Sector

| Attribute | Value |
|-----------|-------|
| **Definition** | The industry classification of the issuing company. In this repo, sector labels are sourced from Yahoo Finance for equities and default to 'Unknown' for 13F-only securities (no independent sector lookup is performed). |
| **Allowed Values** | Technology, Financial Services, Energy, Consumer Staples, Healthcare, Unknown (for 13F securities without yfinance data) |
| **Grain** | Attribute of `dim_security`; applies at security level |
| **Limitation** | 13F holdings are classified by CUSIP but not enriched with sector unless the CUSIP appears in the yfinance universe. Sector coverage for 13F securities is partial. |
| **Owner** | Data Steward |
| **Status** | `[Implemented]` (for yfinance universe); `[Designed]` (for full 13F universe) |

---

### Price Date

| Attribute | Value |
|-----------|-------|
| **Definition** | The calendar date for which a closing price observation is recorded. Prices are as-of end-of-day closing prices from Yahoo Finance. |
| **Column** | `price_date` in `fct_price_daily` |
| **Grain** | 1 row per (sec_id, price_date) |
| **Freshness SLA** | Must not exceed 5 business days stale (enforced by `recon_stale_prices`) |
| **Limitation** | Prices are sourced from Yahoo Finance and are not independently verified. Not suitable for NAV calculation or regulatory reporting. |
| **Status** | `[Implemented]` |

---

### Treasury Rate

| Attribute | Value |
|-----------|-------|
| **Definition** | The yield on U.S. Treasury securities, used as a risk-free rate benchmark in fixed-income analytics (duration, spread calculations). |
| **Current Status** | Not implemented in this repo. The synthetic bond data includes a fixed yield assumption in `METHODOLOGY.md` but does not source live Treasury rates. |
| **Reference** | FRED (Federal Reserve Economic Data) provides daily Treasury yields via public API. Integration is a v0.5 candidate. |
| **Status** | `[Proposed]` (v0.5) |

---

### Reporting Period

| Attribute | Value |
|-----------|-------|
| **Definition** | The quarter-end date for which a regulatory filing or performance report covers positions. For 13F filings, this is the last calendar day of a calendar quarter (e.g., 2025-12-31 for Q4 2025). |
| **Column** | `period_of_report` in `fct_manager_holding`, `dim_investment_manager` |
| **Allowed Values** | Must be a valid quarter-end date: March 31, June 30, September 30, or December 31 |
| **Current Coverage** | Q4 2025 (2025-12-31) only |
| **Status** | `[Implemented]` |

---

### Source System

| Attribute | Value |
|-----------|-------|
| **Definition** | The originating system or data provider from which a record was ingested. Used to trace lineage and apply appropriate quality tolerances. |
| **Values in this repo** | `sec_edgar` (13F filings), `yfinance` (equity prices), `synthetic` (deterministic RNG bonds) |
| **Column** | `data_source` in `dim_security`; `source_system` convention in bronze models |
| **Owner** | Data Engineer |
| **Status** | `[Implemented]` (`dim_security.data_source`); `[Designed]` (not yet propagated to all bronze models) |

---

### Certified Metric

| Attribute | Value |
|-----------|-------|
| **Definition** | A calculated metric in the marts layer that has passed all quality gates, reconciliation checks, and data owner review, and is approved for reporting or stakeholder distribution. |
| **Current Status** | "Certified" in this repo means all 192 dbt tests pass and all recon gates return PASS. Certification status per model is tracked in `seeds/governance/certification_registry.csv`. A formal automated sign-off workflow is `[Designed]` for v0.5. |
| **Downstream Usage** | Only certified metrics should appear in the dashboard or be shared with external stakeholders |
| **Related model** | `governance_scorecard` (KPI-08: Reporting Readiness) surfaces the composite certification gate |
| **Status** | `[Implemented]` (registry and scorecard gate); formal automated workflow `[Designed]` |

---

### Reconciliation Status

| Attribute | Value |
|-----------|-------|
| **Definition** | The outcome of a reconciliation check comparing two sources of the same data. |
| **Allowed Values** | `PASS` — variance within defined tolerance; `FAIL` — variance exceeds tolerance or is unexpected; `WARN` — informational flag (e.g., zero-value holdings); `PENDING` — check not yet run |
| **Column** | `status` in all `recon_*` models |
| **Tolerance by Gate** | `recon_bronze_to_silver`: 0.000%; `recon_filing_totals`: < 0.001%; `recon_stale_prices`: PASS if ≤ 5 days stale |
| **Status** | `[Implemented]` |

---

### Investment Manager

| Attribute | Value |
|-----------|-------|
| **Definition** | An institutional investment adviser that files a Form 13F with the SEC, disclosing equity and equity-equivalent holdings above the $100M discretionary AUM threshold. |
| **Primary Key** | `manager_id` (internal surrogate); `cik` (SEC Central Index Key — permanent, public identifier) |
| **Grain** | 1 row per manager (Type 1 — latest attributes win) |
| **Current Coverage** | 5 managers: State Street Corp, FMR LLC (Fidelity), Wellington Management Group, MFS Investment Management, Loomis Sayles |
| **Source** | `dim_investment_manager` (silver); sourced from `bronze.raw_13f_holdings` EDGAR metadata |
| **Status** | `[Implemented]` |

---

### Portfolio

| Attribute | Value |
|-----------|-------|
| **Definition** | A named collection of positions managed to a specific investment strategy or mandate. In this repo, portfolios are synthetic constructs (PORT_CORE, PORT_FLEX) that hold yfinance equity and synthetic bond positions. |
| **Primary Key** | `portfolio_id` |
| **Note** | Portfolio data is synthetic. These do not represent real investment mandates, NAVs, or client accounts. |
| **Status** | `[Implemented]` (as synthetic structure) |

---

### NAV (Net Asset Value)

| Attribute | Value |
|-----------|-------|
| **Definition** | The total value of a portfolio's assets minus liabilities, typically expressed in USD. For this repo, NAV is approximated as the sum of `market_value_usd` across all positions, without netting liabilities (not a production NAV calculation). |
| **Column** | `total_nav_usd` in `mart_portfolio_exposure` |
| **Limitation** | Uses yfinance prices, which are not validated. Does not include cash, derivatives, liabilities, or fund fees. |
| **Status** | `[Implemented]` (as approximation) |

---

### Concentration Limit

| Attribute | Value |
|-----------|-------|
| **Definition** | A rule that restricts any single position from exceeding a defined percentage of portfolio NAV. A breach occurs when a position's weight exceeds the limit. |
| **Current Rule** | 5% of portfolio NAV per security |
| **Column** | `breach_flag`, `breach_amount_over_5pct` in `mart_concentration_limits` |
| **Note** | The 5% threshold is illustrative. Real concentration limits depend on fund mandate, regulatory requirements, and investment guidelines. |
| **Status** | `[Implemented]` |

---

### VaR (Value at Risk)

| Attribute | Value |
|-----------|-------|
| **Definition** | The maximum expected loss over a defined horizon at a given confidence level. In this repo: parametric 1-day VaR at 95% and 99% confidence, assuming zero cross-asset correlation and normal return distribution. |
| **Columns** | `var_95_1d`, `var_99_1d` in `mart_var_parametric` |
| **Limitations** | Parametric method; zero-correlation assumption understates risk in stress events; normal distribution assumption underweights fat tails. See METHODOLOGY.md for full limitations. |
| **Owner** | Risk Officer |
| **Status** | `[Implemented]` (with documented limitations) |

---

### Tracking Error

| Attribute | Value |
|-----------|-------|
| **Definition** | The annualized standard deviation of the difference between portfolio returns and benchmark returns over a lookback window. |
| **Columns** | `te_30d`, `te_60d`, `te_90d` in `mart_tracking_error` |
| **Method** | Ex-post (realized), annualized by multiplying daily standard deviation by √252 |
| **Status** | `[Implemented]` |

---

### Duration

| Attribute | Value |
|-----------|-------|
| **Definition** | Modified duration: the price sensitivity of a fixed-income security to a 1% change in yield, expressed in years. Portfolio modified duration is the market-value-weighted average across all fixed-income holdings. |
| **Column** | `weighted_avg_modified_duration` in `mart_duration_summary` |
| **Note** | Duration values for synthetic bonds are calculated from synthetic cash flows. Not applicable to real fixed-income portfolios. |
| **Status** | `[Implemented]` (on synthetic bonds only) |

---

### Accession Number

| Attribute | Value |
|-----------|-------|
| **Definition** | The SEC EDGAR unique identifier for a specific regulatory filing submission. Format: `{CIK}-{YY}-{NNNNNN}`. Immutable once assigned by EDGAR. |
| **Column** | `accession_no` in `bronze.raw_13f_holdings`, `recon_filing_totals_reconciliation` |
| **Usage** | Idempotency key for bronze loads; joins filing metadata to holdings; reconciliation identifier |
| **Status** | `[Implemented]` |

---

### CIK (Central Index Key)

| Attribute | Value |
|-----------|-------|
| **Definition** | The permanent SEC identifier assigned to a reporting entity. Used to look up all filings by a given institution on EDGAR. |
| **Column** | `cik` in `dim_investment_manager`, `bronze.raw_13f_holdings` |
| **Example Values** | 0000093751 (State Street), 0000315066 (FMR LLC), 0000902219 (Wellington Management) |
| **Status** | `[Implemented]` |

---

### CUSIP

| Attribute | Value |
|-----------|-------|
| **Definition** | A 9-character alphanumeric identifier assigned by CUSIP Global Services to North American securities. The primary key for securities in 13F filings. |
| **Column** | `cusip` in `dim_security`, `bronze.raw_13f_holdings` |
| **Source** | Populated for yfinance equities via `seeds/yfinance_to_cusip.csv`; populated for 13F securities from EDGAR XML |
| **Join Usage** | `fct_manager_holding` joins `dim_security` on CUSIP |
| **Status** | `[Implemented]` |

---

### Governance Scorecard

| Attribute | Value |
|-----------|-------|
| **Definition** | A dbt model that computes 8 governance health KPIs from warehouse tables, providing a single queryable view of data quality, freshness, reconciliation, and reporting readiness. One row per KPI. |
| **Primary Key** | `kpi_id` (KPI-01 through KPI-08) |
| **Grain** | 1 row per KPI |
| **Owner** | Data Steward |
| **Source** | `models/marts/governance/governance_scorecard.sql` |
| **Severity values** | `GREEN` (healthy), `YELLOW` (review recommended), `RED` (blocked), `INFO` (informational) |
| **KPI-08** | Composite Reporting Readiness — `READY`, `REVIEW`, or `BLOCKED` based on all blocking gates |
| **Downstream Usage** | Pre-report certification check; steward triage; data owner sign-off gate |
| **Status** | `[Implemented]` |

---

## 8. Governance Workflow

1. **New term** identified by engineer or analyst during model development
2. **Draft definition** written following the attribute table format above
3. **Data Steward** reviews for consistency with existing terms and source system semantics
4. **Data Owner** approves terms marked ⭐ (certified metric terms)
5. **Engineer** adds `description:` in schema.yml matching the glossary definition
6. **Glossary** updated with implementation status
7. **DATA_CONTRACT.md** updated if grain or semantic changes

---

## 9. Implementation Workflow

To add a new term:

```
1. Add a section in this document following the attribute table format
2. Include: Definition, Primary Key (if applicable), Grain, Owner, Source,
   Allowed Values, Downstream Usage, Implementation Status
3. Add corresponding description: in schema.yml for the column
4. Run: dbt docs generate
5. Verify the description appears in the dbt catalog
```

---

## 10. Operational Metrics

| Metric | Current Value |
|--------|-------------|
| Terms defined in this glossary | 23 (added Governance Scorecard term) |
| Terms with schema.yml mapping | ~18 |
| Terms with accepted_values tests | 7 (asset_class, investment_discretion, _source_system, manager_type, status, kpi_category, severity) |
| Terms marked [Proposed] (not yet designed) | 3 (Issuer, Treasury Rate are the main candidates) |

---

## 11. Workplace Application

A business glossary is required in investment data governance because:

- **Operations vs. Finance**: "market value" means the filed value on a 13F to compliance, the NAV to fund accounting, and shares × price to analytics — without a glossary, these produce different numbers
- **Grain ambiguity**: whether "holding" means one row per CUSIP or one row per CUSIP × discretion-category changes every downstream query; this repo made that decision explicit in DECISIONS.md
- **Audit readiness**: regulators and internal auditors will ask "how do you define X?" — a glossary with implementation status is the evidence
- **Onboarding**: new engineers and analysts can understand the data model by reading this document before touching the SQL

---

## 12. Limitations

- This glossary covers only the terms actively used in this repo. It is not an exhaustive investment industry glossary.
- Sector and industry classifications are from Yahoo Finance and may differ from GICS, ICB, or other standard classification systems.
- VaR, duration, and tracking error definitions use simplified methodologies suitable for demonstration; not suitable for regulatory risk reporting.
- CUSIP population is partial: yfinance equities are mapped via seed file; 13F-only securities inherit CUSIP from EDGAR XML but have no independent validation.

---

## 13. What This Does Not Claim

- This glossary does not constitute a legal or regulatory definition of any investment term.
- Definitions are specific to this data model; they should not be applied to other systems without validation.
- The terms defined here do not represent a complete data dictionary for any production investment platform.

---

## 14. Extension Path

| Version | Extension | Status |
|---------|-----------|--------|
| v0.4 | Add `relationships:` dbt tests for FK terms (portfolio_id, sec_id, benchmark_id, position_date, price_date) | ✅ Completed — 14 relationship tests added |
| v0.4 | `accepted_values` tests for `_source_system`, `manager_type`, `investment_discretion` | ✅ Completed |
| v0.4 | Governance Scorecard term added to glossary | ✅ Completed |
| v0.4 | Certification Registry seed (`certification_registry.csv`) | ✅ Completed |
| v0.5 | Add `_ingested_at TIMESTAMPTZ` to raw tables for source freshness coverage | Planned |
| v0.5 | Treasury Rate term with FRED integration | Planned |
| v0.5 | Issuer term with dim_issuer (LEI, FIGI) | Planned |
| v0.5 | Benchmark Constituent term with weights | Planned |

---

## 15. Interview Talking Points

**On business glossary value:**
> "Without a glossary, 'holding' means different things to different teams. On a 13F, a manager reports one row per security per discretion category — so a single position might have three rows. For risk analytics, you want one row per position. We made that grain decision explicit in DECISIONS.md and defined it here so anyone joining or maintaining the model understands exactly what they're working with."

**On metadata and schema.yml:**
> "Descriptions in schema.yml aren't just documentation — they're the source of truth for the dbt docs catalog and for any downstream tool that reads column metadata. When I write `description: 'Market value in thousands of USD, as reported on SEC Form 13F. May be zero for positions below $500 due to filing precision.'`, that's the glossary definition implemented in code."

**On CUSIP as a join key:**
> "The 13F pipeline joins to dim_security on CUSIP rather than ticker because CUSIPs are stable across name changes, mergers, and ticker reassignments. That's a real investment data architecture decision — you never join positions to securities on ticker if you have a CUSIP, because tickers are reused and reassigned over time."
