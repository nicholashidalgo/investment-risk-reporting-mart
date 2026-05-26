# AI Readiness and Agentic Governance

> **Implementation Status Legend**
> `[Implemented]` — exists in this repo and is actively applied
> `[Designed]` — governance controls defined; not yet enforced programmatically
> `[Proposed]` — recommended approach; not yet designed

---

## 1. Purpose

This document defines how investment data in this repository could be safely exposed to AI-assisted workflows — including natural language querying, agentic data pipelines, anomaly detection, and automated reporting assistance — while maintaining the data governance controls required in an investment operations context.

It defines what data an AI agent is allowed to see, what actions it may take, what must require human approval, and how AI interactions are logged for audit purposes.

---

## 2. Business Use Case

Investment data teams increasingly face requests to use AI for:

- Natural language querying of portfolio holdings or risk metrics ("What's Wellington's largest tech position?")
- Automated anomaly detection in reconciliation outputs
- AI-assisted data quality triage ("Why did this recon gate fail?")
- Draft generation of investment commentary from portfolio data
- Agentic pipeline monitoring that pages an engineer when a quality gate fails

Each use case requires different levels of data access, different approval gates, and different audit requirements. This document defines the governance framework for those distinctions.

---

## 3. Data Sources

| Data Category | AI Accessibility | Rationale |
|--------------|-----------------|-----------|
| Marts layer (marts schema) | ✅ Allowed | Certified, aggregated; no PII; public data |
| Reconciliation outputs (recon schema) | ✅ Allowed (read-only) | Quality signal; no sensitive data |
| Silver facts and dimensions | ⚠️ Conditional | Grain-level data; require use-case review |
| Bronze staging (stg_* views) | ⚠️ Conditional | Requires data steward approval per use case |
| Raw bronze tables (bronze schema) | ❌ Restricted | Not for AI consumption without documented exception |
| dbt model SQL and schema.yml | ✅ Allowed | Code is not sensitive; needed for code assist |
| Pipeline credentials, profiles.yml | ❌ Never | Secrets must never be exposed to AI agents |

---

## 4. Operating Model

### AI Agent Roles

| Agent Role | Allowed Actions | Human Approval Required |
|-----------|----------------|------------------------|
| **Query assistant** | Read marts + recon; generate SQL; explain results | No (read-only, certified data) |
| **Code assist** | Read/suggest changes to SQL, schema.yml, scripts | Engineer review before commit |
| **Anomaly detector** | Read recon outputs; flag FAIL/WARN; draft triage notes | Steward reviews before action |
| **Pipeline agent** | Run dbt test; report results | Human initiates run; agent reports |
| **Report drafter** | Draft narrative from mart data; no calculations | Human reviews and edits before distribution |
| **Remediation agent** | Propose SQL fixes for data quality issues | Data engineer approves and applies |

### Hard Rules for All AI Agent Interactions (Implemented in AGENTS.md)

The following rules are documented in `AGENTS.md` and applied to all AI tool interactions in this repo:

1. **No git writes** — AI agents must not commit, push, create branches, or modify GitHub metadata
2. **No database writes** — AI agents must not run INSERT, UPDATE, DELETE, or DDL against any schema
3. **No credential access** — AI agents must never read or use connection strings, passwords, or API keys
4. **Honest metrics only** — AI agents must not claim production deployment, business outcomes, or verified ROI
5. **No fabrication** — AI agents must not invent data, test results, or schema documentation
6. **Label implementation status** — any documentation output must distinguish Implemented / Designed / Proposed

---

## 5. Architecture

```
 AI READINESS ARCHITECTURE — INVESTMENT DATA MART
 ──────────────────────────────────────────────────

 External AI Systems / Agents
 ─────────────────────────────
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │  Query       │  │  Code Assist │  │  Anomaly     │
  │  Assistant   │  │  (Claude CC) │  │  Detector    │
  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
         │                 │                 │
         ▼                 ▼                 ▼
 ┌──────────────────────────────────────────────────────┐
 │              AI ACCESS GOVERNANCE LAYER               │
 │  Semantic Allowlist  │  Restricted Field List          │
 │  SQL Safety Rules    │  Human Approval Gates           │
 │  Interaction Logging │  Evaluation Gates               │
 └──────────────────────────────────────────────────────┘
         │                 │                 │
         ▼                 ▼                 ▼
 ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐
 │  MARTS      │  │  RECON       │  │  CODE / DOCS     │
 │  (Allowed)  │  │  (Allowed    │  │  models/*.sql    │
 │  mart_*     │  │   read-only) │  │  schema.yml      │
 └─────────────┘  └──────────────┘  └──────────────────┘
         │
         ▼
 ┌─────────────────────────┐
 │  RESTRICTED LAYERS      │
 │  bronze.* (raw)         │
 │  credentials/profiles   │
 │  Requires documented    │
 │  exception + approval   │
 └─────────────────────────┘

 Interaction Logging → audit trail (designed)
 Human Approval Gate → required for: writes, external distribution, remediation
```

---

## 6. Data Controls

### 6.1 Semantic Allowlist

The following objects are approved for AI agent read access without additional approval:

| Object | Schema | Notes |
|--------|--------|-------|
| `mart_portfolio_exposure` | marts | Aggregated; no position-level detail |
| `mart_concentration_limits` | marts | Position weights; public securities |
| `mart_credit_exposure` | marts | Rating bucket aggregates |
| `mart_duration_summary` | marts | Single portfolio-level metric |
| `mart_var_parametric` | marts | Risk metric aggregate |
| `mart_tracking_error` | marts | Performance metric aggregate |
| `mart_scenario_impact` | marts | Scenario analysis aggregate |
| `governance_scorecard` | marts | 8 governance KPIs; no PII; derived from recon + mart outputs |
| `recon_filing_totals_reconciliation` | recon | PASS/FAIL status; no PII |
| `recon_bronze_to_silver_reconciliation` | recon | Variance metrics |
| `recon_stale_prices` | recon | Freshness flags |
| `recon_zero_value_holdings` | recon | Classification of anomalies |
| All `models/*.sql` | code | dbt model SQL |
| All `schema.yml` | code | Column descriptions and tests |
| All `docs/` | documentation | Architecture documentation |
| `certification_registry` (seed) | marts | Certification status per model; roles only, no PII |

### 6.2 Restricted Fields

The following fields require special consideration before AI agent access:

| Field | Location | Restriction | Reason |
|-------|---------|-------------|--------|
| `accession_no` | bronze.raw_13f_holdings | Read-only; do not use as insert key | Source identifier; immutable |
| `cik` | dim_investment_manager | Read-only display | Public regulatory ID; no modification |
| `holding_id` | fct_manager_holding | Do not regenerate | Surrogate key integrity |
| Connection strings | profiles.yml.template | NEVER expose | Security |
| Database passwords | Environment variables | NEVER expose | Security |
| API keys | Environment variables | NEVER expose | Security |

There is no PII in this repository. The data is derived entirely from public regulatory filings and public market data. However, institutional holdings data at position-level (pre-aggregation) should not be distributed to AI systems without a documented use case, because 13F holdings are sometimes filed with delayed public release.

### 6.3 SQL Safety Rules

For AI-generated SQL in this context:

```
ALLOWED:
  SELECT ... FROM marts.*
  SELECT ... FROM recon.*
  SELECT ... FROM silver.* (with steward approval per use case)
  WITH cte AS (SELECT ...) SELECT ...
  JOINs between allowed tables
  Aggregations and window functions on allowed tables

NEVER ALLOWED (block these patterns):
  INSERT INTO any schema
  UPDATE any table
  DELETE FROM any table
  DROP TABLE / DROP SCHEMA
  CREATE TABLE / ALTER TABLE
  TRUNCATE
  SET / GRANT / REVOKE
  Any query referencing bronze.raw_* tables (read by exception only)
  Any query joining to profiles.yml or credential stores
```

### 6.4 Human Approval Gates

| Action | Approval Required | Approver |
|--------|------------------|----------|
| Any write to database | Always | Data Engineer |
| Any dbt model change | Always | Data Engineer (code review) |
| External distribution of AI-generated analysis | Always | Data Owner |
| Lowering a quality threshold | Always | Data Owner |
| Adding a new object to the semantic allowlist | Always | Data Steward |
| Running pipeline agents in production | Always | Data Engineer |
| AI-generated commentary included in investor report | Always | Risk Officer + Data Owner |

### 6.5 Prompt and Output Logging

For production AI agent deployments `[Proposed]`:

```
Per interaction, log:
  - timestamp
  - agent_role (query_assistant, code_assist, anomaly_detector, etc.)
  - input_prompt (full text)
  - data_objects_accessed (list of tables/views queried)
  - output_text (full text)
  - human_reviewer (if applicable)
  - approval_status (auto_approved, pending, approved, rejected)
  - disposition (used_as_is, edited, rejected)
```

Logging rationale: investment data regulators (SEC, FCA) increasingly expect firms to maintain records of how AI tools interact with regulated data. An audit trail of AI interactions is part of the control environment.

### 6.6 Evaluation Gates

Before promoting an AI agent to a new use case `[Designed]`:

| Gate | Description |
|------|-------------|
| **Accuracy test** | Run 20 representative queries; verify outputs match SQL ground truth |
| **Boundary test** | Attempt to access restricted layers; confirm access is blocked |
| **Hallucination test** | Ask questions for which the data has no answer; confirm agent says "I don't know" rather than fabricating |
| **Injection test** | Attempt prompt injection via data values; confirm agent does not execute injected instructions |
| **Human review** | Data steward reviews 10% of outputs before promotion to new use case |

---

## 7. Governance Workflow

```
AI USE CASE ONBOARDING PROCESS [Designed]
──────────────────────────────────────────

  1. REQUEST
     └─► Engineer or analyst proposes AI use case
         Describes: data needed, action taken, distribution scope

  2. DATA STEWARD REVIEW
     └─► Checks: what data does the agent need?
         Any restricted fields? Any write actions?
         Adds objects to semantic allowlist (or denies access)

  3. EVALUATION
     └─► Accuracy, boundary, hallucination, injection tests
         Results documented

  4. DATA OWNER APPROVAL
     └─► For use cases involving external distribution or writes
         Sign-off required

  5. DEPLOYMENT
     └─► Agent deployed with logging enabled
         Interaction logs stored
         Regular audit review scheduled

  6. ONGOING
     └─► 10% of outputs reviewed monthly
         Any concerning outputs → incident report
         Annual re-evaluation of all active use cases
```

---

## 8. Implementation Workflow

For the current state of this repo (no production AI deployment):

1. **Semantic allowlist** — define which dbt models an AI agent may query (this document)
2. **AGENTS.md** — hard rules for AI tools used during development (implemented)
3. **Prompt design** — when using Claude Code for analysis, scope prompts to marts layer
4. **Output review** — any AI-generated analysis reviewed by engineer before inclusion in documentation
5. **No production claims** — AI-assisted documentation clearly states implementation status

For future production deployment:

1. Implement logging table in `recon` schema or external store
2. Define semantic layer (e.g., dbt Semantic Layer, or view-based access controls)
3. Implement database role for read-only AI agent access (marts + recon schemas only)
4. Integrate evaluation gates as part of agent onboarding checklist
5. Document each active use case in an AI Use Case Registry

---

## 9. Operational Metrics

| Metric | Current Value |
|--------|-------------|
| AI access rules documented | Yes (`AGENTS.md` + this document) |
| Semantic allowlist defined | Yes (8 marts including `governance_scorecard`, 4 recon views, `certification_registry` seed) |
| Restricted field list defined | Yes (this document) |
| SQL safety rules documented | Yes (this document) |
| Human approval gates defined | Yes (this document) |
| Interaction logging implemented | No (`[Designed]`) |
| Evaluation gates implemented | No (`[Designed]`) |
| Active AI agent use cases in production | 0 (development AI tool only) |

---

## 10. Workplace Application

This AI governance framework maps to real investment firm requirements:

- **Semantic allowlist** is the data governance equivalent of a role-based access control matrix — it defines what each agent type is permitted to see, following the principle of least privilege
- **SQL safety rules** prevent an AI agent from accidentally (or via prompt injection) modifying production data — the same concern that investment firms have when giving any system write access to their position systems
- **Human approval gates** reflect the "human-in-the-loop" requirement increasingly expected by investment regulators for AI-assisted workflows in regulated activities
- **Prompt and output logging** aligns with the SEC's 2023 guidance on AI in investment advisory processes, which expects firms to maintain records of how AI tools are used in client-facing activities
- **Evaluation gates** are the equivalent of model validation in quantitative finance — before a new model is used in production, it must be independently tested and approved

---

## 11. Limitations

- No AI agents are currently deployed in production in this repository.
- The governance framework described here is designed and documented; automated enforcement (role-based DB access, logging infrastructure) is not yet implemented.
- This framework is designed for investment data governance specifically; it should be adapted for any production deployment to reflect the firm's specific regulatory obligations and risk appetite.
- Prompt injection and adversarial testing guidance is based on current best practices as of 2025; the threat landscape evolves rapidly.

---

## 12. What This Does Not Claim

- This repo does not claim to have a production AI agent deployment.
- This repo does not claim that the governance framework described here is legally sufficient for any regulated investment activity.
- AGENTS.md hard rules apply to Claude Code development tool usage only; they do not constitute a production AI safety framework.
- No AI-generated content in this repo has been used in any investment decision, client communication, or regulatory filing.

---

## 13. Extension Path

| Version | Extension | Status |
|---------|-----------|--------|
| v0.4 | `governance_scorecard` model added to semantic allowlist | ✅ Completed |
| v0.4 | `certification_registry` seed added to allowlist | ✅ Completed |
| v0.5 | Database role for read-only AI agent access (marts + recon schemas) | Planned |
| v0.5 | AI Use Case Registry document | Planned |
| v0.5 | Interaction logging table in recon schema | Planned |
| v0.5 | Semantic layer definition (dbt Semantic Layer or view-based) | Planned |
| v0.5 | Evaluation gate checklist as runnable test suite | Planned |
| Future | NL query assistant scoped to certified marts | Future |
| Future | Anomaly detector for recon gate failures | Future |

---

## 14. Interview Talking Points

**On AI governance in investment data:**
> "The first question I ask about any AI use case in investment data is: what data does the agent need, and what actions can it take? In this repo, the answer is that AI development tools can read marts and recon outputs freely, can suggest code changes, but can never write to the database, commit to git, or access credentials. That's documented in AGENTS.md as hard rules, not guidelines."

**On semantic allowlist design:**
> "The allowlist principle is: AI agents should have access to the smallest dataset necessary for the task. For a query assistant answering portfolio questions, that's the marts layer — aggregated, certified, no raw detail. For a code assist tool, it's the SQL files and schema.yml. Raw bronze tables are never appropriate AI agent inputs without a documented exception, because you haven't validated the data yet."

**On the human approval gate principle:**
> "Every action with real-world consequences — a database write, an external distribution, a change to a quality threshold — requires a human to approve it. AI agents can prepare the action, draft the analysis, flag the anomaly, but they don't complete the action. That's the design principle. In investment operations, this aligns with the four-eyes principle that governs most material financial processes."
