# Investment Data Operating Model

> **Implementation Status Legend**
> `[Implemented]` — process is defined and followed in this repo
> `[Designed]` — process defined; tooling or automation not yet built
> `[Proposed]` — recommended process; not yet designed

---

## 1. Purpose

This document describes the operating model for recurring investment data production in the Investment Risk Reporting Mart. It defines the end-to-end workflow from source data intake through ingestion, validation, issue triage, remediation, certification, reporting release, and executive review.

An operating model transforms a data pipeline into a repeatable, auditable process. This document makes that process explicit so that any qualified data engineer, steward, or operations professional could run the pipeline, diagnose a failure, and escalate appropriately.

---

## 2. Business Use Case

Investment data production must be repeatable because:

- Regulatory filings (13F, N-PORT) are submitted on fixed schedules and require consistent data processes
- Portfolio managers need consistent data refresh so they can trust the numbers they act on
- Auditors and compliance review data processes, not just data outputs
- Operational errors in investment data (wrong prices, missing positions, incorrect classifications) have direct business and regulatory consequences

This operating model documents what happens at each stage of the data production lifecycle and who is responsible.

---

## 3. Data Sources

| Source | Ingestion Trigger | Cadence | Owner |
|--------|------------------|---------|-------|
| SEC EDGAR 13F-HR | Quarterly, after filing deadline | Within 45 days of quarter-end | Data Engineer |
| Yahoo Finance prices | Daily (per yfinance availability) | Daily (T or T+1) | Data Engineer |
| Synthetic bond/position data | On demand (development/test only) | Per pipeline run | Data Engineer |

---

## 4. Operating Model

### Roles

| Role | Responsibilities |
|------|----------------|
| **Data Engineer** | Source registration, ingestion scripts, dbt model development, test authoring, pipeline execution, issue remediation |
| **Data Steward** | Business term ownership, quality rule definitions, recon gate review, metadata completeness, issue escalation |
| **Data Owner** | Reporting certification sign-off, threshold approval, escalation authority, executive reporting |
| **Risk Officer** | Methodology validation (VaR, duration, tracking error), mart output review |
| **Analyst / Consumer** | Mart consumption, anomaly escalation, ad hoc queries against certified layer |

### Governance Cadence Summary

| Cadence | Activities | Owner |
|---------|-----------|-------|
| Per pipeline run | Ingestion, dbt build, all 192 tests, recon gate review | Data Engineer |
| Per 13F filing cycle (quarterly) | New filing ingestion, extended recon review, manager universe update | Data Engineer + Steward |
| Weekly | Open issue review, DECISIONS.md update, backlog triage | Data Steward |
| Monthly | Scorecard trend review, metadata coverage audit, CI/CD health | Data Owner |
| Quarterly | SLA and tolerance review, operating model update, new source evaluation | Data Owner + Risk Officer |

---

## 5. Architecture — Pipeline Stages

```
╔════════════════════════════════════════════════════════════════════════════════╗
║               INVESTMENT DATA OPERATING MODEL — PIPELINE STAGES                ║
╚════════════════════════════════════════════════════════════════════════════════╝

 STAGE 1: INTAKE          STAGE 2: INGESTION        STAGE 3: VALIDATION
 ─────────────────         ──────────────────         ───────────────────
 Source identified         Python pipeline runs       dbt build + test
 sources.yml updated       Idempotent bronze load     192 blocking tests
 DATA_CONTRACT.md          Quarantine log reviewed    recon gates execute
  updated                  Load counts verified        All must PASS
 Owner assigned            ↓ to bronze schema         ↓
 ↓                                                    ↓ (if FAIL: STAGE 5)

 STAGE 4: CERTIFICATION    STAGE 5: TRIAGE            STAGE 6: REMEDIATION
 ───────────────────────   ───────────────             ─────────────────────
 All tests PASS            Failing test identified     SQL fix or source
 All recon PASS            Root cause analysis:        re-ingestion
 Steward reviews            source issue?              DECISIONS.md updated
  recon outputs             transform bug?             Re-run dbt build
 Data owner signs off       tolerance exceeded?        Re-verify
 ↓                         Escalation path: →          ↓ back to STAGE 3
                            Data Owner if
                            tolerance change

 STAGE 7: REPORTING        STAGE 8: EXECUTIVE
 RELEASE                    REVIEW
 ──────────────────         ───────────────────
 Marts certified            Monthly scorecard
 Dashboard updated          Trend analysis
 Analysts notified          Resource decisions
 Evidence preserved          New source evaluation
 (recon rows, logs)         Operating model update
```

---

## 6. Detailed Stage Descriptions

---

### Stage 1: Intake

**Trigger:** New data source identified, new reporting period available, or scheduled refresh.

**Activities:**

| Activity | Owner | Output |
|----------|-------|--------|
| Register source in `models/sources.yml` | Data Engineer | source block with name, description, loaded_at_field |
| Document grain and semantics in `DATA_CONTRACT.md` | Data Engineer + Steward | Updated schema entry |
| Assign data owner | Data Steward | Owner named in schema.yml `meta:` |
| Define quality SLAs | Data Steward | Freshness tolerance, recon tolerance |
| Add lineage entry in `LINEAGE_AND_RECONCILIATION_MODEL.md` | Data Engineer | Updated stream documentation |

**For SEC 13F specifically:**
- Confirm filing is available on EDGAR (accession number verified)
- Verify period_of_report matches expected quarter-end
- Check for amended filings (13F-HR/A) and determine if superseding

**Exit criteria:** Source registered, owner assigned, SLAs documented.

---

### Stage 2: Ingestion

**Trigger:** Stage 1 complete; pipeline execution initiated.

**Activities:**

| Activity | Tool | Output |
|----------|------|--------|
| Fetch source data | `edgar_client.py` or `ingest_seed_data.py` | Raw JSON/XML cached in `data/raw/` |
| Parse source format | `xml_parser.py` (13F) | Validated Python objects |
| Load to bronze (idempotent) | `bronze_loader.py` | SQL INSERT script; bronze tables populated |
| Verify bronze load | `verify_bronze.py` | Row counts, value totals vs. expected |

**Idempotency pattern:**
```
DELETE FROM bronze.raw_13f_holdings WHERE accession_no = '{target}'
INSERT INTO bronze.raw_13f_holdings ...  (all rows for this accession)
```
This ensures re-running the pipeline produces identical results — no duplicates, no partial loads.

**Quarantine log:** Any malformed records (XML parse errors, type mismatches) are counted and logged. In v0.3, 0 quarantined records across all 5 filings.

**Exit criteria:** Bronze row count matches expected; quarantine count = 0 or documented.

---

### Stage 3: Validation

**Trigger:** Bronze load complete; `dbt build` initiated.

**Activities:**

| Activity | Tool | Output |
|----------|------|--------|
| Build all models (bronze → silver → marts → recon) | `dbt build` | Compiled and executed SQL |
| Run all 192 schema tests | `dbt test` | PASS / FAIL per test |
| Run all singular tests | `dbt test` | PASS / FAIL per test |
| Review recon gate outputs | Query `recon.*` | PASS / FAIL / WARN per gate |

**Current test inventory (192 total):**
- `not_null`: ~49 tests
- `unique`: ~24 tests
- `accepted_values`: ~21 tests (added manager_type, _source_system, investment_discretion)
- `expression_is_true`: ~49 tests (added range/expression tests on market_value, weight, price columns)
- `relationships`: 14 tests (fct_position_daily, fct_price_daily, fct_benchmark_return_daily, fct_manager_holding)
- Singular custom tests: 6
- SCD integrity tests: 2
- Source freshness: 1 (raw_13f_filings)

**Exit criteria:** `dbt build` exits 0; all 192 tests PASS (227/227 total in dbt build including seeds/snapshots); all recon gates PASS.

**On failure:** Proceed to Stage 5 (Triage).

---

### Stage 4: Certification

**Trigger:** Stage 3 complete with all PASS.

**Activities:**

| Activity | Owner | Output |
|----------|-------|--------|
| Review recon gate outputs (summary) | Data Steward | Confirmed PASS status |
| Check zero-value holdings (informational) | Data Steward | New anomalies? Document in DECISIONS.md |
| Verify mart outputs are plausible | Risk Officer | Spot-check VaR, concentration, AUM totals |
| Data owner sign-off | Data Owner | Certification record (designed: future sign-off table) |

**Certification checklist (current: manual + governance_scorecard):**
```
☐ dbt build: 0 failures (227/227 PASS)
☐ recon_filing_totals_reconciliation: all PASS
☐ recon_bronze_to_silver_reconciliation: all PASS (0.000% variance)
☐ recon_stale_prices: 0 STALE
☐ New zero-value holdings reviewed and classified
☐ Mart spot-check: AUM totals plausible vs. known manager sizes
☐ Governance scorecard (marts.governance_scorecard) reviewed — KPI-08 must not be BLOCKED
☐ Data owner notified / sign-off received (certification_registry.csv updated)
```

**Exit criteria:** Checklist complete; data owner sign-off obtained.

---

### Stage 5: Issue Triage

**Trigger:** Any test FAIL or recon gate FAIL during Stage 3.

**Triage categories:**

| Category | Description | Resolution Path |
|----------|-------------|-----------------|
| Source data issue | Bronze records malformed, missing, or out-of-range | Investigate source; re-ingest; document quarantine |
| Transformation bug | Silver or mart model produces incorrect output | Fix SQL; re-run dbt build |
| Tolerance exceeded | Recon variance is above defined threshold | Investigate root cause; document in DECISIONS.md; escalate to Data Owner before adjusting threshold |
| Schema change | Source system column renamed, added, or removed | Update staging model and schema.yml; re-run |
| Dependency ordering | Bronze load incomplete when silver runs | Re-run in correct order; add CI dependency |

**Escalation path:**
```
Data Engineer → identifies failure
    │
    ├─► Root cause: transform bug → Engineer fixes; no escalation needed
    │
    ├─► Root cause: source issue → Engineer documents; Steward notified
    │
    ├─► Root cause: tolerance change needed → Steward + Data Owner required
    │       Never change a threshold without Data Owner approval
    │
    └─► Root cause: unknown → Steward + Engineer joint investigation
        Document in DECISIONS.md; do not release data until resolved
```

**Documentation requirement:** Every triage case resulting in a DECISIONS.md entry.

---

### Stage 6: Remediation

**Trigger:** Stage 5 complete; root cause identified.

**Activities:**

| Activity | Owner | Output |
|----------|-------|--------|
| Apply fix (SQL, ingestion script, or source correction) | Data Engineer | Updated model or re-ingested bronze |
| Re-run `dbt build` | Data Engineer | New test results |
| Verify recon gates return PASS | Data Steward | Confirmed PASS |
| Update DECISIONS.md with resolution | Data Steward | Decision log entry |

**Closed loop requirement:** Remediation is not complete until Stage 3 validation passes cleanly with no exceptions.

---

### Stage 7: Reporting Release

**Trigger:** Stage 4 certification complete.

**Activities:**

| Activity | Owner | Output |
|----------|------|--------|
| Confirm dashboard reads from certified marts | Data Engineer | Dashboard displays current data |
| Notify consuming analysts | Data Steward | Distribution notification |
| Preserve recon evidence | Data Engineer | recon_* rows queryable; DECISIONS.md updated |
| Archive data (future: reports/ CSV export) | Data Engineer | Designed for v0.4 |

**Exit criteria:** Consumers notified; evidence preserved; no pending issues.

---

### Stage 8: Executive Review

**Cadence:** Monthly

**Agenda:**

| Item | Owner | Data Source |
|------|-------|------------|
| Governance scorecard summary | Data Steward | recon_* models, test counts |
| Open quality issues | Data Steward | DECISIONS.md |
| New data source candidates | Data Engineer | NEXT_ACTIONS.md |
| SLA and threshold review | Data Owner | DECISIONS.md history |
| Operating model updates needed | Data Owner | This document |

**Outputs:**
- Updated DECISIONS.md (if any threshold changes approved)
- Updated NEXT_ACTIONS.md (if new sources or capabilities prioritized)
- Updated PROJECT_STATUS.md (current build state)

---

## 7. Governance Workflow — Decision Log

All governance decisions are documented in `DECISIONS.md` following this format:

```markdown
### [YYYY-MM-DD] Title of Decision

**Context:** What situation prompted this decision?
**Decision:** What was decided?
**Rationale:** Why was this the right choice?
**Trade-offs:** What is sacrificed by this decision?
**Owner:** Who approved this decision?
```

Current decision log entries (v0.3):
1. Reposition as governed investment data product (2026-05-06)
2. Type 2 SCD via dbt snapshot (2026-05-06)
3. fct_manager_holding grain: sum discretion categories (2026-05-07)
4. Zero-value holdings accepted (< 0 only rejected) (2026-05-07)
5. dim_security extended with CUSIP + 13F securities (2026-05-07)
6. recon_bronze_to_silver exact zero tolerance (2026-05-07)

---

## 8. Implementation Workflow

For setting up this operating model in a new environment:

1. **Configure PostgreSQL** per `profiles/profiles.yml.template`
2. **Install dependencies**: `pip install -r requirements.txt`; `dbt deps`
3. **Run initial ingestion**: `python scripts/ingest_seed_data.py`; `python scripts/sec_13f/edgar_client.py` (then xml_parser.py, bronze_loader.py)
4. **Build dbt**: `dbt seed; dbt snapshot; dbt build`
5. **Verify**: `python scripts/sec_13f/verify_bronze.py`; review recon_* models
6. **Baseline**: confirm 192/192 tests pass (227/227 in full dbt build); all recon gates PASS

For recurring execution (after initial setup):
1. Re-run ingestion scripts for new data period
2. `dbt snapshot; dbt build`
3. Review recon gates
4. Update DECISIONS.md if any issues
5. Certify and release

---

## 9. Operational Metrics

| Metric | Current Value |
|--------|-------------|
| Pipeline stages documented | 8 |
| Tests per pipeline run | 192 |
| Test pass rate | 100% (227/227 in dbt build) |
| Recon gates | 7 |
| Average recon PASS rate | 100% (v0.4) |
| Governance scorecard KPIs | 8 (all implemented) |
| Decision log entries | 6 |
| Data sources in production | 3 (EDGAR, yfinance, synthetic) |
| Managers covered | 5 (Q4 2025) |
| Holdings ingested | 30,135 |
| Quarantined records | 0 |
| Open quality issues | 0 (v0.4) |

---

## 10. Workplace Application

This operating model maps directly to investment operations practice:

- **Stage 1 (Intake)** mirrors the onboarding process for a new data feed at a fund administrator: you register the source, document its SLA, assign a data owner, and define what good data looks like before you accept the first file
- **Idempotent bronze loads** are the equivalent of a reconciled trade booking: re-submitting the same trade doesn't create a duplicate; re-loading the same filing doesn't create duplicate holdings
- **Stage 5 (Triage)** is the investment operations break management process: when a reconciliation gate fails, you don't release data — you investigate, classify the break, and escalate if needed
- **Data owner sign-off (Stage 4)** is the equivalent of the NAV controller's sign-off before a fund NAV is released to prime brokers: a named person certifies that the process was followed and the data is accurate
- **DECISIONS.md** is the equivalent of an investment operations incident log: it captures what decisions were made, why, and who approved them — the audit trail that compliance reviewers ask for

---

## 11. Limitations

- This operating model is designed for a single-engineer data product. Production investment data operations teams have dedicated operations staff, SLA-monitored feeds, and automated escalation tooling.
- The certification workflow (Stage 4) is currently manual and checklist-based. Automation is designed for v0.4.
- No real-time monitoring. All validation is batch, per pipeline execution.
- The 13F ingestion cadence (quarterly) means this operating model does not cover daily position reconciliation against a custodian — the most operationally intensive part of investment data management.
- Synthetic bond and position data have no external source to reconcile against; Stage 3 validates internal consistency only.

---

## 12. What This Does Not Claim

- This operating model does not claim to represent a complete investment operations function.
- It does not claim that these processes are sufficient for regulatory reporting, fund administration, or investor-facing distribution without additional controls.
- The cadences described (daily, weekly, monthly, quarterly) are designed recommendations; actual cadences in this repo are driven by manual pipeline execution.
- No SLA was breached or met in a production context; all metrics are from a development data product.

---

## 13. Extension Path

| Version | Extension |
|---------|-----------|
| v0.4 | Automated certification view (governance_scorecard) | **Completed** — implemented as models/marts/governance/governance_scorecard.sql |
| v0.4 | Certification sign-off record table | **Completed** — implemented as seeds/governance/certification_registry.csv |
| v0.5 | GitHub Actions CI: `dbt build` on PR |
| v0.4 | Reconciliation CSV export for each pipeline run |
| v0.4 | Decision log template enforcement |
| v0.5 | Multi-quarter ingestion (4 quarters of 13F data) |
| v0.5 | Automated reporting readiness notification |
| v0.5 | Additional managers (extended EDGAR universe) |

---

## 14. Interview Talking Points

**On the end-to-end operating model:**
> "I think about investment data production as eight stages: intake, ingestion, validation, certification, triage, remediation, reporting release, and executive review. Most data pipelines only automate stages 2 and 3. The governance value comes from formalizing stages 1, 4, 5, 6, and 7 — the human-in-the-loop stages where someone has to make a decision and document it."

**On idempotency:**
> "Idempotency is a non-negotiable design principle for financial data ingestion. Re-running a pipeline should produce identical results. For SEC 13F data, that means deleting existing rows for a given accession number before inserting — so whether you run the pipeline once or ten times, you get the same result. This eliminates the entire class of 'duplicate position' bugs."

**On the triage and escalation model:**
> "When a reconciliation gate fails, the rule is: don't release data, and don't change the threshold without approval. Those two rules prevent the most common governance failure modes — releasing bad data under time pressure, and quietly expanding tolerances to make failures disappear. Every threshold change has to be documented in the decisions log with a reason and an approver."

**On certification:**
> "Certification is distinct from testing. Tests pass or fail automatically — that's the machine's job. Certification is a human saying 'I've reviewed the outputs, I understand any anomalies, and I approve this data for distribution.' In investment operations, that's a named person signing off before a report goes to a portfolio manager or investor. The governance structure has to make that sign-off explicit, not assumed."
