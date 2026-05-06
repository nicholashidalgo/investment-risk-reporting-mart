# SEC 13F Ingestion Plan

**Status:** Decisions locked 2026-05-06 — ready for execution  
**Target version:** v0.3  
**Planned execution:** 2026-05-07  
**Author:** Nicholas Hidalgo

---

## Goal

This work replaces synthetic portfolio positions in the investment-risk-reporting-mart with real institutional holdings data from SEC Form 13F filings, ingested as a new bronze source layer. Holdings are conformed into existing silver dimensions where possible (dim_security via CUSIP lookup) and exposed through a new silver fact table (fct_manager_holding) that feeds existing risk marts. The result upgrades the project from a synthetic-data demonstration to a pipeline grounded in public regulatory data, enabling honest claims about source-to-curated reconciliation against a real filing authority. This covers 5 institutional managers, 1 reporting quarter, and produces two new reconciliation gates measuring filing-total accuracy and transformation completeness.

---

## Source Decision

### Quarter

**LOCKED: Q4 2025 (period_of_report = 2025-12-31, filed Q1 2026).** Most recent fully-filed quarter as of 2026-05-06.

---

### Managers

**LOCKED: Boston-area institutional managers (v0.3 scope):**

| Manager | CIK | Style |
|---|---|---|
| State Street Corp | 0000093751 | Index manager |
| Fidelity (FMR LLC) | 0000315066 | Active mutual funds |
| Wellington Management Company LLP | 0000902219 | Active institutional |
| MFS Investment Management | 0000350797 | Active mutual funds |
| Loomis Sayles & Co LP | 0001543160 | Fixed income leaning |

Rationale: All 5 are Boston-headquartered. Hiring managers at LMI, MFS, Wellington, Putnam, Eaton Vance, and other Boston buy-side firms will recognize peer firms in the dataset. Mix of investment styles ensures portfolio variety in the data shape.

**Note for tomorrow:** Wellington files under multiple CIKs. The 0000902219 above is Wellington Management Company LLP (operating company, has substantive holdings). Verify this is the correct CIK during ingestion.

---

### Data Endpoint

SEC EDGAR EDGAR provides two access paths:

**Submissions API** — per-CIK filing index:
```
https://data.sec.gov/submissions/CIK{10-digit-zero-padded-cik}.json
```
Returns all filings for a CIK. Filter for `formType == "13F-HR"` and the target `reportDate`.

**Filing document URL** — primary document for a given accession number:
```
https://www.sec.gov/Archives/edgar/data/{cik}/{accession_no_no_dashes}/{primary_doc}
```
The primary document for a 13F-HR is the Information Table XML (typically named `informationtable.xml` or similar; the index lists all documents).

**SEC rate limit:** 10 requests per second per IP. Plan for a 0.15-second sleep between requests.

**User-Agent header:** Required by SEC EDGAR policy. Requests without it are rate-limited or rejected.

**LOCKED:** `Nicholas Hidalgo contact@nicholashidalgo.com`

This is a real, monitored email address required by SEC for API access. SEC may contact this address if API requests cause server issues. Standard practice. This is sent in HTTP headers only, not stored in the repo.

---

## Parser Approach

### Option 1: XML Information Table (recommended)

13F-HR filings include a structured XML document — the "Information Table" — as a separate attachment within the filing. It contains one element per holding with these fields:

| XML Field | Description | Notes |
|---|---|---|
| `nameOfIssuer` | Issuer name as filed | Not standardized; requires normalization |
| `titleOfClass` | Security class description | e.g., "COM" for common stock |
| `cusip` | 9-character CUSIP | Primary join key to dim_security |
| `value` | Market value | **In thousands of USD** — multiply × 1000 for value_usd |
| `sshPrnamt` | Shares or principal amount | |
| `sshPrnamtType` | SH (shares) or PRN (principal) | |
| `putCall` | Put or Call if option | Null for most equity holdings |
| `investmentDiscretion` | SOLE, SHARED, or OTHER | |
| `otherManager` | Other manager number if shared | |
| `votingAuthority` | Sole/shared/none vote counts | |

Parse via `xml.etree.ElementTree` (stdlib) or `lxml` (faster, handles malformed XML better).

### Option 2: EDGAR Flat File Extracts (alternative)

SEC publishes quarterly 13F summary datasets as `.tsv` files covering all filers for a quarter. Simpler to bulk-load but less granular — no control over which managers are included without post-load filtering.

**Recommendation: Option 1.** Per-filing XML parsing gives precise control, supports incremental manager additions, and produces clean normalized records. Flat files are useful for full-market analysis but exceed v0.3 scope.

**LOCKED: XML per-filing with raw XML cached to disk.**

Implementation requirements:
1. Use SEC EDGAR submissions API to discover 13F-HR filings per CIK
2. Filter to filings where period_of_report = 2025-12-31
3. Fetch each filing's XML Information Table document via the SEC Archives URL pattern
4. Cache raw XML to `data/raw/sec_13f/{cik}/{accession_no}.xml` before parsing (allows re-parsing without re-fetching)
5. Parse XML using Python `xml.etree.ElementTree` or `lxml`
6. Output structured records ready for bronze.raw_13f_holdings ingestion

Rationale: Builds production-style EDGAR API client and Information Table parser. Filing-level traceability (every holding ties to specific accession number). Resume defensibility: "Built EDGAR submissions API client and Information Table XML parser for filing-level holdings ingestion."

Rate limiting: SEC enforces 10 requests per second per IP. Use 0.15-second sleep between requests. Estimated total fetch time for 5 managers: 5–10 minutes.

---

## Schema Design

### New Bronze Tables

**`bronze.raw_13f_filings`** — one row per filing  
Grain: `(cik, accession_no)`

| Column | Type | Description |
|---|---|---|
| cik | TEXT NOT NULL | SEC CIK, zero-padded to 10 digits |
| accession_no | TEXT NOT NULL | Accession number (dashes included, e.g. 0001067983-25-000123) |
| period_of_report | DATE NOT NULL | Reporting period end date |
| filed_at | DATE | Filing date |
| manager_name | TEXT | Filer name as reported |
| total_table_value | NUMERIC | Total value reported on cover page (thousands USD) |
| table_entry_count | INTEGER | Row count in Information Table |
| _ingested_at | TIMESTAMP | Pipeline run timestamp |

---

**`bronze.raw_13f_holdings`** — one row per holding  
Grain: `(accession_no, cusip, ssh_prnamt_type, put_call)`

| Column | Type | Description |
|---|---|---|
| cik | TEXT NOT NULL | SEC CIK |
| accession_no | TEXT NOT NULL | Accession number |
| period_of_report | DATE NOT NULL | Reporting period (denormalized from filing) |
| name_of_issuer | TEXT | Issuer name as filed |
| title_of_class | TEXT | Security class description |
| cusip | TEXT | 9-character CUSIP |
| value | NUMERIC NOT NULL | Market value in **thousands** of USD (raw from filing) |
| shares | NUMERIC | Shares or principal amount |
| share_type | TEXT | SH or PRN |
| put_call | TEXT | Put, Call, or NULL |
| investment_discretion | TEXT | SOLE, SHARED, or OTHER |
| other_manager | TEXT | Other manager number if applicable |
| _ingested_at | TIMESTAMP | Pipeline run timestamp |

---

### New Silver Dimensions

**`silver.dim_investment_manager`** — one row per manager  
Grain: `manager_id` (surrogate), `cik` (natural key)

| Column | Description |
|---|---|
| manager_key | Surrogate key (generate_surrogate_key on cik) |
| cik | SEC CIK, zero-padded to 10 digits |
| manager_name | Normalized manager name |
| manager_type | institutional, hedge_fund, index, active (owner-assigned) |
| _ingested_at | Model run timestamp |
| _source_system | 'sec_13f' |

Type 2 SCD deferred to v0.4. For v0.3 this is a Type 1 (latest-wins) dimension — manager names and classifications are stable.

---

### Silver Dimension to Extend

**`silver.dim_security` / `dim_security_history`** — add CUSIP column

13F holdings are CUSIP-keyed. Existing dim_security is ticker-keyed. A join strategy is required.

**LOCKED: Extend dim_security with new entries from 13F filings.**

Implementation:
1. Add `cusip` column to `dim_security` (and `dim_security_history` via snapshot replay)
2. For each 13F holding's CUSIP, look up existing dim_security entry by CUSIP
3. If found: link the holding to that security's `sec_id`
4. If not found: create new dim_security entry with:
   - `sec_id`: generated surrogate (pattern: `13F_{cusip}` or sequential)
   - `name`: `nameOfIssuer` from 13F filing
   - `asset_class`: derive from `titleOfClass` when possible, else `'Unknown'`
   - `cusip`: from filing
   - `_source_system`: `'sec_13f'`
   - `_ingested_at`: current_timestamp

Rationale: Conformed dimension pattern. One source of truth for each security regardless of source system. Standard data warehouse approach. Avoids dimension fragmentation.

Note: Existing dim_security entries (from yfinance) will need CUSIP backfill. Tomorrow's work includes a one-time CUSIP enrichment for the 23 existing securities.

---

### New Silver Fact

**`silver.fct_manager_holding`** — one row per (manager, security, reporting period)  
Grain: `(manager_key, security_key, reporting_period)`  
Materialization: table

| Column | Description |
|---|---|
| holding_id | Surrogate key (generate_surrogate_key on manager_key + security_key + reporting_period) |
| manager_key | FK to dim_investment_manager.manager_key |
| security_key | FK to dim_security_current.security_key |
| reporting_period | Period of report date |
| value_usd | value × 1000 (converted from thousands to USD) |
| shares | Raw share/principal amount |
| share_type | SH or PRN |
| put_call | Put, Call, or NULL |
| _filing_accession_no | Source filing accession number |
| _ingested_at | Model run timestamp |
| _source_system | 'sec_13f' |

---

## Reconciliation Approach

Two new reconciliation gates, following the existing `recon` schema pattern:

**`recon.recon_13f_filing_totals`** — filing-level reconciliation  
Reconciles: `SUM(bronze.raw_13f_holdings.value)` per accession_no vs `bronze.raw_13f_filings.total_table_value`  
Surfaces: XML parsing errors, truncated ingestion, row drops  
Status logic: PASS if variance ≤ 0.1%, WARN if ≤ 1%, FAIL otherwise

**`recon.recon_13f_source_to_curated`** — source-to-silver reconciliation  
Reconciles: `SUM(silver.fct_manager_holding.value_usd / 1000)` per (cik, reporting_period) vs `SUM(bronze.raw_13f_holdings.value)` per (cik, period_of_report)  
Surfaces: transformation drops, duplications, incorrect value scaling  
Status logic: PASS if variance = 0, FAIL otherwise (value conversion is exact — no tolerance acceptable)

Both gates write output as tables to the `recon` schema, matching the four existing reconciliation model patterns.

---

## Test Coverage Plan

### Bronze layer (new)

| Test | Target |
|---|---|
| not_null on cik, accession_no, period_of_report | raw_13f_filings |
| unique_combination_of_columns on (cik, accession_no) | raw_13f_filings |
| not_null on cik, accession_no, cusip, value, shares | raw_13f_holdings |
| unique_combination_of_columns on (accession_no, cusip, share_type, put_call) | raw_13f_holdings |
| expression_is_true: value > 0 | raw_13f_holdings |

### Silver layer (new)

| Test | Target |
|---|---|
| unique + not_null on manager_key | dim_investment_manager |
| unique + not_null on cik | dim_investment_manager |
| unique + not_null on holding_id | fct_manager_holding |
| not_null on manager_key, security_key, reporting_period, value_usd | fct_manager_holding |
| relationships: manager_key → dim_investment_manager | fct_manager_holding |
| relationships: security_key → dim_security_current | fct_manager_holding |
| expression_is_true: value_usd > 0 | fct_manager_holding |
| Custom singular: no (manager, security, period) duplicates | fct_manager_holding |

**Estimated new tests:** 15–18 blocking tests added in v0.3.  
**Projected total after v0.3:** 142–145 tests.

---

## Effort Estimate

| Phase | Hours | Notes |
|---|---:|---|
| EDGAR fetch script | 1.0 | Submissions API client, 13F filing index per CIK, document URL resolution |
| XML parser | 1.5 | Information Table extraction, error handling, quarantine for bad CUSIPs |
| Bronze DDL + ingest script | 1.0 | Two tables, idempotent upserts, run_log entry |
| Silver dim_investment_manager | 0.5 | Conform manager records from filings |
| Silver dim_security CUSIP extension | 1.0 | Lookup / create logic for securities not in dim_security |
| Silver fct_manager_holding | 1.0 | Standard fact model, value scaling, FK joins |
| Reconciliation models (2 gates) | 1.0 | Following existing recon/ pattern |
| Test coverage | 0.5 | schema.yml entries + singular test files |
| Documentation updates | 0.5 | DATA_CONTRACT, METHODOLOGY, README, MEASURED_IMPACT |
| Verification (owner-run) | 0.5 | dbt snapshot, dbt run, dbt test |
| **Total** | **8.5** | Realistic for a focused full-day block |

---

## Risk Areas

**1. CUSIP-to-security mapping**  
13F holdings reference securities by CUSIP. Existing dim_security uses ticker keys. If Option A (extend dim_security) is chosen, care is needed to avoid corrupting existing rows. Mitigation: add CUSIP as a nullable column with `_source_system` tracing; never modify existing rows.

**2. Missing or non-standard CUSIPs**  
Some 13F filings include holdings with blank, invalid, or non-standard CUSIPs (private placements, restricted securities, certain ETFs). Plan: log to a `bronze.raw_13f_holdings_quarantine` table with a reason column. Do not block ingestion for valid holdings.

**3. Dollar value scaling (off-by-1000 risk)**  
13F values are filed in thousands of USD. Bronze stores the raw filed value; silver multiplies by 1000 to produce `value_usd`. This conversion must be explicit in DATA_CONTRACT.md and tested via `expression_is_true: value_usd = value_raw * 1000` on a sample row. A missed conversion would make portfolio values appear 1000× smaller than actual.

**4. Filing volume**  
5 managers × Q4 2025 ≈ 1,000–5,000 holdings total. Well within PostgreSQL's capacity for this project size. Wellington and Fidelity are likely the largest (potentially 2,000–4,000 holdings each). No performance concern expected.

**5. SEC rate limiting**  
SEC enforces 10 requests per second per IP. Sleep 0.15 seconds between requests. For 5 managers with ~3–5 HTTP calls each, total fetch time is under 10 minutes.

**6. Amendment filings**  
Some managers file 13F-HR/A (amendments). The ingestion script should prefer the most recent amendment over the original filing for a given (CIK, reporting period). Filter: take the filing with the latest `filed_at` for each (CIK, period_of_report).

---

## Rollback Plan

Before starting tomorrow's execution block:

```bash
git tag pre-13f-ingestion-2026-05-07
```

If execution fails partway through:

| Failure point | Rollback action |
|---|---|
| Bronze DDL or ingest fails | Drop bronze.raw_13f_filings and raw_13f_holdings; no silver impact |
| Silver dim_investment_manager fails | Drop silver.dim_investment_manager; no fact table yet |
| Silver fct_manager_holding fails | Drop silver.fct_manager_holding; no impact on existing models |
| dim_security CUSIP extension fails | Revert the specific migration; existing dim_security rows unaffected if nullable column add is idempotent |
| Full failure | `git checkout pre-13f-ingestion-2026-05-07` and drop all new tables |

The existing pipeline (bronze → silver → marts → recon for synthetic data) is not touched by this work. Risk is additive, not modifying.

---

## Tomorrow's Critical Path

Execute in this order to minimize rework if a step fails:

1. [x] ~~Resolve owner decisions~~ — all 5 decisions locked 2026-05-06
2. [ ] Tag `pre-13f-ingestion-2026-05-07`
3. [ ] Add DDL for bronze.raw_13f_filings and raw_13f_holdings (`scripts/03_ddl_13f.sql`)
4. [ ] Implement EDGAR fetch script (`scripts/fetch_13f_filings.py`)
5. [ ] Validate: fetch 1 filing (State Street, Q4 2025) and inspect raw XML
6. [ ] Implement XML parser and bronze ingest function
7. [ ] Run bronze ingest for State Street only; verify row counts
8. [ ] Build silver.dim_investment_manager
9. [ ] Build silver.fct_manager_holding (initial pass — skip CUSIP join, use NULL security_key)
10. [ ] Verify silver row counts and value totals
11. [ ] Implement dim_security CUSIP extension (add column, populate from holdings)
12. [ ] Re-run fct_manager_holding with CUSIP join active
13. [ ] Add reconciliation models (recon_13f_filing_totals, recon_13f_source_to_curated)
14. [ ] Add schema.yml tests
15. [ ] Run full pipeline for all 5 managers
16. [ ] Run dbt test; verify 0 failures
17. [ ] Update DATA_CONTRACT.md, METHODOLOGY.md, MEASURED_IMPACT.md, PROJECT_STATUS.md

---

## Owner Decisions to Resolve Before Tomorrow

All 5 decisions resolved 2026-05-06 17:00 ET. See locked values inline above.

- [x] **Quarter:** LOCKED — Q4 2025 (period_of_report = 2025-12-31)
- [x] **Manager list:** LOCKED — Boston-5: State Street, Fidelity, Wellington, MFS, Loomis Sayles
- [x] **CUSIP strategy:** LOCKED — Extend dim_security (Option A); new entries with `_source_system = 'sec_13f'`
- [x] **User-Agent string:** LOCKED — `Nicholas Hidalgo contact@nicholashidalgo.com`
- [x] **Parser approach:** LOCKED — XML per-filing, cached to `data/raw/sec_13f/{cik}/{accession_no}.xml`
