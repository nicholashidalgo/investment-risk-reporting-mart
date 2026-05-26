# Governance Scorecard Model

> **Implementation Status Legend**
> `[Implemented]` — KPI is calculable from current repo artifacts
> `[Designed]` — KPI defined; reporting surface not yet built
> `[Proposed]` — KPI recommended; definition not yet finalized

---

## 1. Purpose

This document defines the data governance scorecard for the Investment Risk Reporting Mart — the set of health KPIs used to assess whether investment data is trustworthy, complete, current, and ready for reporting.

The scorecard aggregates signals from testing, reconciliation, metadata, lineage, and certification into a structured view that different stakeholders can use to make decisions: a data steward triaging quality issues, an analyst deciding whether to trust a number, a risk officer certifying data for distribution, or an executive reviewing data operations.

**Implementation status (v0.4):** The governance scorecard is now implemented as a live dbt model at `models/marts/governance/governance_scorecard.sql`. All 8 KPIs are queryable from the warehouse. The SQL described in earlier versions of this document as "designed" is now active and tested.

---

## 2. Business Use Case

Investment data governance fails silently. A stale price, a missing rating, or a reconciliation break may not produce an error — it just produces a wrong number in a report. A governance scorecard makes the health of the data product visible before those wrong numbers reach a portfolio manager, a regulator, or an investor.

Specific use cases:
- **Pre-report certification**: run scorecard before releasing any investor-facing or regulatory report
- **Daily operations monitoring**: identify quality degradation before it accumulates
- **Stewardship accountability**: track trend in metadata coverage and test pass rate over time
- **Executive review**: one-page summary of data reliability for leadership reporting on data operations

---

## 3. Data Sources

All scorecard KPIs derive from artifacts already in this repo:

| KPI Category | Source |
|-------------|--------|
| Test pass rate | dbt test results (192 tests; 227/227 in full dbt build) |
| Freshness status | `recon_stale_prices` |
| Reconciliation status | `recon_filing_totals_reconciliation`, `recon_bronze_to_silver_reconciliation` |
| Missing metadata | schema.yml description coverage |
| Lineage coverage | `models/sources.yml` + this document |
| Certified model count | Manual certification status (designed) |
| Reporting readiness | Composite: tests + recon + freshness |

---

## 4. Operating Model

### Who Uses the Scorecard

| Role | Use Case | Frequency | Decision Made |
|------|---------|-----------|---------------|
| **Data Steward** | Identify open quality issues; prioritize remediation | Per pipeline run | Which issues to triage; whether to block reporting |
| **Data Analyst** | Verify data is trustworthy before publishing analysis | Before sharing | Whether to proceed with analysis or wait for remediation |
| **Risk Officer / Data Owner** | Certify data for distribution; sign off reporting period | Per reporting period | Release or hold reporting |
| **Executive / Head of Data** | Review data operations health; track trend | Monthly | Resource allocation; escalation |

### Governance Cadence

| Activity | Frequency | Owner |
|----------|-----------|-------|
| Scorecard refresh | Per dbt build | Data Engineer |
| Scorecard review | Per build + before any report release | Data Steward |
| Trend review | Monthly | Data Owner |
| KPI threshold review | Quarterly | Data Owner + Risk Officer |

---

## 5. Architecture

```
 GOVERNANCE SCORECARD — COMPUTATION MODEL
 ─────────────────────────────────────────
 
 INPUT SIGNALS                    KPI CATEGORIES          SCORECARD OUTPUT
 ──────────────                   ──────────────          ────────────────
 
 dbt test results ─────────────► Test Pass Rate          ┌──────────────────┐
 (192 tests)                                              │  OVERALL HEALTH  │
                                                          │  ● / ◐ / ○       │
 recon_stale_prices ──────────► Freshness Status         │                  │
                                                          │  per category:   │
 recon_filing_totals                                      │  QUALITY GATES   │
 recon_bronze_to_silver ──────► Reconciliation Status    │  FRESHNESS       │
 recon_position_to_nav                                    │  RECONCILIATION  │
 (all 7 gates)                                            │  METADATA        │
                                                          │  LINEAGE         │
 schema.yml descriptions ─────► Metadata Completeness   │  CERTIFICATION   │
 (column coverage %)                                      └──────────────────┘
 
 sources.yml + docs/ ─────────► Lineage Coverage
 
 Certification sign-off ──────► Certified Model Count
 (designed)
 
 Composite formula ───────────► Reporting Readiness
 (tests ∩ recon ∩ freshness)

 
 CURRENT REPORTING SURFACE: governance_scorecard model (models/marts/governance/governance_scorecard.sql)
 IMPLEMENTED: All 8 KPIs queryable from warehouse as of v0.4
 PROPOSED SURFACE: Executive dashboard section (v0.5 candidate)
```

---

## 6. Data Controls

The scorecard itself is a control — it surfaces whether other controls are passing.

| Control | Purpose | Status |
|---------|---------|--------|
| Scorecard blocks reporting if any KPI is RED | Prevents certified distribution of degraded data | `[Designed]` |
| Scorecard history preserved for audit | Evidence of control environment over time | `[Proposed]` |
| KPI threshold changes require data owner approval | Prevents threshold gaming | `[Proposed]` |

---

## 7. KPI Definitions and Current Values

---

### KPI-01 — Reconciliation Status (13F Filing Totals)

| Attribute | Value |
|-----------|-------|
| **Definition** | Whether all 13F filing totals reconciliation gates return PASS |
| **Source model** | `recon_filing_totals_reconciliation` |
| **Live output** | 5/5 PASS, GREEN |
| **Threshold** | GREEN: All PASS; YELLOW: Any WARN; RED: Any FAIL |
| **Rationale** | A FAIL means the holdings data in the mart does not match the authoritative regulatory filing — no distribution should occur |
| **Status** | `[Implemented]` — derived from recon_filing_totals_reconciliation |

---

### KPI-02 — Reconciliation Status (Bronze-to-Silver)

| Attribute | Value |
|-----------|-------|
| **Definition** | Whether bronze-to-silver transformation produces zero variance per (cik, period) |
| **Source model** | `recon_bronze_to_silver_reconciliation` |
| **Live output** | 5/5 PASS, GREEN |
| **Threshold** | GREEN: All PASS (0.000% variance); RED: Any FAIL |
| **Rationale** | Any non-zero variance in a deterministic transformation is a bug — this gate enforces exact reproducibility |
| **Status** | `[Implemented]` — derived from recon_bronze_to_silver_reconciliation |

---

### KPI-03 — Freshness Status

| Attribute | Value |
|-----------|-------|
| **Definition** | Days since the latest price record in fct_price_daily; whether any active securities have stale prices |
| **Source model** | `fct_price_daily` (via governance_scorecard) |
| **Live output** | 25 days since latest price, RED (yfinance data approximately 25 days stale at scorecard generation) |
| **Threshold** | GREEN: ≤ 5 days stale; YELLOW: 6–15 days; RED: > 15 days |
| **Rationale** | Stale prices propagate to incorrect NAV, VaR, and concentration calculations |
| **Status** | `[Implemented]` — derived from fct_price_daily |

---

### KPI-04 — Holdings Volume

| Attribute | Value |
|-----------|-------|
| **Definition** | Count of active institutional managers and total holdings rows in fct_manager_holding |
| **Source model** | `fct_manager_holding` |
| **Live output** | 5 managers, 13,191 holdings, GREEN |
| **Threshold** | GREEN: Manager count ≥ 1; holdings count > 0 |
| **Rationale** | A drop in manager or holdings count is an early signal of ingestion failure |
| **Status** | `[Implemented]` — derived from fct_manager_holding |

---

### KPI-05 — Security Coverage

| Attribute | Value |
|-----------|-------|
| **Definition** | Total distinct securities in dim_security |
| **Source model** | `dim_security` |
| **Live output** | 5,994 securities, GREEN |
| **Threshold** | GREEN: Count > 0; significant drop flags ingestion issue |
| **Rationale** | Security master is the reference for all downstream joins; coverage collapse indicates data loss |
| **Status** | `[Implemented]` — derived from dim_security |

---

### KPI-06 — Zero-Value Holdings

| Attribute | Value |
|-----------|-------|
| **Definition** | Count of holdings with market value = 0 or shares = 0 (informational, not a blocker) |
| **Source model** | `recon_zero_value_holdings` |
| **Live output** | 18 zero-value holdings, INFO |
| **Threshold** | INFO: Count surfaced for review; not a blocking failure unless count increases unexpectedly |
| **Rationale** | Zero-value holdings may indicate rounding, position exits, or data entry issues; surfaced for steward review |
| **Status** | `[Implemented]` — derived from recon_zero_value_holdings |

---

### KPI-07 — Concentration Breaches

| Attribute | Value |
|-----------|-------|
| **Definition** | Count of positions exceeding the 5% NAV concentration limit |
| **Source model** | `mart_concentration_limits` |
| **Live output** | 22/42 positions exceed 5% NAV, RED (synthetic portfolio — expected for demo data) |
| **Threshold** | GREEN: 0 breaches; YELLOW: 1–5; RED: > 5 |
| **Rationale** | Concentration limit breaches require risk officer review before reporting |
| **Status** | `[Implemented]` — derived from mart_concentration_limits |

---

### KPI-08 — Reporting Readiness

| Attribute | Value |
|-----------|-------|
| **Definition** | Composite gate: READY only if all blocking conditions are clear (recon PASS, no stale prices within tolerance, no concentration breaches above threshold) |
| **Formula** | Composite of KPI-01 through KPI-07 blocking conditions |
| **Live output** | BLOCKED / RED |
| **Threshold** | READY or BLOCKED (binary) |
| **Rationale** | This gate replaces a manual pre-report checklist; BLOCKED status must be triaged before data is distributed |
| **Status** | `[Implemented]` — implemented as composite logic in governance_scorecard.sql |

> **On the BLOCKED status:** The BLOCKED status for KPI-08 reflects honest data state: yfinance prices were last ingested approximately 25 days before scorecard generation (KPI-03 RED), and the synthetic portfolio has many positions exceeding the 5% concentration limit by design (KPI-07 RED). This demonstrates that the scorecard correctly surfaces real governance conditions rather than returning a false READY status. In a production context, these would be triaged: stale prices remediated by re-running yfinance ingestion; concentration breaches reviewed by the risk officer against the portfolio's actual limit structure.

---

## 8. Governance Workflow

### Steward Review (Per Build)

The governance scorecard is now a live dbt model: `models/marts/governance/governance_scorecard.sql`. After each `dbt build`, query `marts.governance_scorecard` directly to review all 8 KPIs.

```
dbt build completes
    │
    ├─► Query marts.governance_scorecard
    │       KPI-01 (13F recon): GREEN? → YES: continue | NO: triage
    │       KPI-02 (bronze-silver): GREEN? → YES: continue | NO: triage
    │       KPI-03 (freshness): status? → if RED, check days_stale; escalate
    │       KPI-04 (holdings volume): plausible? → review count changes
    │       KPI-05 (security coverage): plausible? → review count changes
    │       KPI-06 (zero-value): new records? → review classification
    │       KPI-07 (concentration): breach count? → route to risk officer
    │       KPI-08 (readiness): READY or BLOCKED?
    │
    └─► KPI-08 = READY → Reporting Readiness confirmed
        KPI-08 = BLOCKED → Do not distribute; triage blocking KPIs first
```

### Analyst Decision Flow

```
Before publishing any analysis:
    │
    ├─► Was the last dbt build successful? (192/192 passing)
    │       YES: proceed | NO: wait for resolution
    │
    ├─► Query marts.governance_scorecard — is KPI-08 = READY?
    │       YES: proceed | NO: note which KPIs are blocking; wait
    │
    └─► Use certified marts only (marts schema)
        Do not query bronze or staging layers directly
```

### Data Owner Certification (Per Reporting Period)

```
Before releasing reports to external stakeholders:
    │
    ├─► Request scorecard from data steward
    │       All KPIs GREEN?
    │
    ├─► Review DECISIONS.md for any open issues
    │       Any unresolved tolerance decisions?
    │
    ├─► Sign off: "I certify that the data in marts schema as of [date]
    │    has passed all quality gates and is approved for distribution"
    │
    └─► Document sign-off (PDF, email, ticket, or future workflow tool)
```

### Executive Review (Monthly)

Scorecard items for monthly reporting:

| Item | What It Means |
|------|--------------|
| Test pass rate trend | Is data quality improving or degrading? |
| Recon FAIL count (month) | How many reconciliation breaks occurred? |
| Average time-to-resolution | How quickly are quality issues resolved? |
| Metadata coverage % | Is the data product becoming more governable? |
| New data sources added | Is the platform growing? |
| Certified models this period | Are we keeping up with certification? |

---

## 9. Scorecard Model (Implemented)

The governance scorecard SQL is now live at `models/marts/governance/governance_scorecard.sql`. The model is built as part of `dbt build` and is queryable from the `marts` schema.

The implemented model computes all 8 KPIs in a single query, including:
- KPI-01 and KPI-02: counts of FAIL rows from recon models
- KPI-03: days since latest price in fct_price_daily
- KPI-04: manager count and holdings row count from fct_manager_holding
- KPI-05: distinct security count from dim_security
- KPI-06: zero-value holding count from recon_zero_value_holdings
- KPI-07: concentration breach count from mart_concentration_limits
- KPI-08: composite READY/BLOCKED status derived from all blocking conditions

For the SQL definition, see: `models/marts/governance/governance_scorecard.sql`

---

## 10. Operational Metrics

| KPI | Live Output | Status |
|-----|-------------|--------|
| KPI-01: 13F Filing Totals Recon | 5/5 PASS, GREEN | `[Implemented]` |
| KPI-02: Bronze-to-Silver Recon | 5/5 PASS, GREEN | `[Implemented]` |
| KPI-03: Freshness Status | 25 days since latest price, RED | `[Implemented]` |
| KPI-04: Holdings Volume | 5 managers, 13,191 holdings, GREEN | `[Implemented]` |
| KPI-05: Security Coverage | 5,994 securities, GREEN | `[Implemented]` |
| KPI-06: Zero-Value Holdings | 18 zero-value holdings, INFO | `[Implemented]` |
| KPI-07: Concentration Breaches | 22/42 positions exceed 5% NAV, RED | `[Implemented]` |
| KPI-08: Reporting Readiness | BLOCKED / RED | `[Implemented]` |

---

## 11. Workplace Application

This scorecard model maps to investment data operations practices:

- **Reporting readiness gate** is the equivalent of the daily NAV certification checklist that a fund controller completes before releasing NAV to prime brokers or investors — except automated
- **Recon status KPI** is the investment operations equivalent of a "break report" — the 10-minute summary of what is reconciled and what is not at the start of each operations day
- **Metadata completeness** is the equivalent of a security master audit — are all the fields your risk system needs populated correctly for every security you hold?
- **Certified model count** is the equivalent of a data governance council's model certification registry — what data products have been formally approved for production use
- **Executive review section** maps to the monthly data quality review that a Chief Data Officer or Head of Operations presents to a fund's operations committee

---

## 12. Limitations

- All 8 KPIs are now implemented as a queryable dbt model (governance_scorecard.sql). Point-in-time health is visible from the warehouse.
- The scorecard has no historical trending — it reflects the most recent build only, not trend over time. Historical trend table is a v0.5 item.
- KPI-03 (Freshness) will show RED whenever yfinance prices are not re-ingested before running dbt build. This is the honest state, not a defect in the scorecard.
- KPI-07 (Concentration Breaches) reflects the synthetic portfolio structure, which has many positions exceeding 5% NAV by design. In a production context, thresholds would be set with the risk officer based on the portfolio's actual limit structure.
- Scorecard thresholds are illustrative and based on this repo's structure; production thresholds should be set with operations stakeholders.

---

## 13. What This Does Not Claim

- This scorecard does not replace a production data observability platform.
- KPI thresholds are illustrative; they are not validated against industry standards for investment reporting.
- "Reporting Readiness = READY" in this repo means this demonstration data product has passed its own quality gates — not that it is suitable for regulatory reporting or investor distribution.

---

## 14. Extension Path

| Version | Extension |
|---------|-----------|
| v0.4 | Governance scorecard view | **Completed** — implemented as models/marts/governance/governance_scorecard.sql |
| v0.4 | Certification sign-off record table | **Completed** — implemented as seeds/governance/certification_registry.csv |
| v0.4 | Metadata completeness count query against schema.yml | Deferred to v0.5 |
| v0.5 | Scorecard section in dashboard |
| v0.5 | Historical scorecard trend table (one row per build) |
| v0.5 | Automated reporting readiness email/alert |
| v0.5 | Source freshness for date-type tables (raw_positions, raw_prices, raw_benchmarks, raw_ratings) |

---

## 15. Interview Talking Points

**On scorecard design:**
> "I designed the scorecard around eight KPIs covering the dimensions that actually matter in investment data: test quality, freshness, reconciliation, metadata completeness, lineage coverage, certification, and composite readiness. The key insight is that 'all tests pass' is necessary but not sufficient — you also need freshness, recon status, and a human sign-off for reporting certification."

**On the reporting readiness gate:**
> "The composite reporting readiness flag replaces a manual checklist. Instead of an analyst asking five different questions before trusting the data, the scorecard answers them all in one view. In fund operations, this is the equivalent of a pre-NAV release checklist — except the checklist runs itself."

**On different stakeholder views:**
> "Different roles need different views of the same scorecard. A data steward needs the full KPI list with triage notes. An analyst needs a binary 'trust this or wait.' A data owner needs trend and certification status. An executive needs a one-paragraph summary. The same underlying data surfaces differently depending on the decision being made."
