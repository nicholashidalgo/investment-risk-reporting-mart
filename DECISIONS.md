# Decision Log

Decisions are dated, written in past tense, and never deleted. If a decision is reversed, append the reversal as a new entry with rationale.

## 2026-05-06 — Reposition repo as governed investment data product

**Context:** Repo currently reads as a synthetic risk-reporting demo. Recruiter market signal is generalist analytics, not specialist data product owner.

**Decision:** Reposition as "Governed Investment Data Product for Risk Reporting." Public regulatory data (SEC 13F) becomes the target source layer. Synthetic data retained only for seeded defect testing. README, MEASURED_IMPACT.md, and downstream documents will reflect this identity.

**Trade-off accepted:** Some existing language ("Type 2 effective dating," "production-style") overclaims relative to current build. Either the build catches up (v0.2 work this week) or the language is softened. Catching up is preferred.

## 2026-05-06 — Adopt minimum-deny Claude Code permission model

**Context:** Repo-level `.claude/settings.local.json` configured for high throughput. Allows all reads, writes, and bash commands except destructive categories.

**Decision:** Deny list scoped to: all git writes (owner-only by standing rule), `sudo`, `psql`, `dropdb`, `dropuser`. Everything else auto-runs.

**Trade-off accepted:** Faster sessions, fewer prompts. Risk mitigated by: working tree always cleanable via `git restore` and `git clean`, plus pre-session full directory backup.

## 2026-05-06 — One tool owns the working tree at a time

**Context:** Codex and Claude Code can both edit files but do not coordinate.

**Decision:** Codex inspects and reviews only — markdown output to `docs/reviews/`. Claude Code is the writer. Phase-based handoffs via `HANDOFF.md`. Never run both tools concurrently on the same repo.

## 2026-05-06 — Type 2 SCD pattern: dbt snapshot

**Context:** Repo claimed Type 2 effective dating in resume bullets but had no SCD implementation. Closing the gap on dim_security first as the highest-value claim.

**Decision:** Use dbt snapshot for SCD capture. Strategy: check (no updated_at column exists on bronze.raw_security_master; dbt compares all six attribute columns on each snapshot run). Surface via dim_security_history (table) and dim_security_current (view). Idiomatic dbt pattern, well-documented, recognized by reviewers.

**Trade-off accepted:** Requires running `dbt snapshot` command separately from `dbt build`. Acceptable because owner-controlled execution is the standing rule. Also: the history model joins stg_ratings for rating resolution — this means the rating column in history reflects the latest agency rating at model run time, not the rating that was active at dbt_valid_from. This is a known simplification documented in METHODOLOGY.md.

## 2026-05-07 — fct_manager_holding grain: sum across discretion categories

**Context:** A single manager can report the same CUSIP under multiple `investmentDiscretion` categories (SOLE, SHARED, DFND) in one 13F filing, producing multiple rows in `bronze.raw_13f_holdings` for the same `(cik, cusip, period_of_report)` triple. Two options:
- (a) Sum: aggregate to one row per `(manager_id, security_id, period_of_report)`, summing value, shares, and voting authority.
- (b) Preserve: keep all bronze rows with discretion as an additional grain dimension.

**Decision:** Option (a) — sum at the silver fact level.

**Rationale:** The intended consumers of `fct_manager_holding` are risk analytics and reconciliation models that need total exposure per manager-security-period. The distinction between SOLE/SHARED/DFND discretion categories matters for governance reporting (which we are not building in v0.3) but not for exposure aggregation. Preserving the split would require either a composite grain key or a separate discretion dimension, both of which add joins and complicate all downstream consumers. The reconciliation gate (`recon_13f_source_to_curated`) operates on total value per manager, so option (a) is the natural join surface.

**Limitation documented:** `investment_discretion` in `fct_manager_holding` takes `max()` over the contributing bronze rows. This is a stable tie-breaker but does not indicate which discretion category held the largest position. Raw bronze rows preserve the full breakdown for any future governance reporting need.

**Trade-off accepted:** Cannot reconstruct discretion-split totals from silver alone. Bronze is the authoritative source for that detail.

---

## 2026-05-07 — dim_security v0.1→v0.2 schema evolution: add cusip column

**Context:** `dim_security` was ticker-keyed; SEC 13F holdings are CUSIP-keyed. To join holdings to the security dimension, CUSIP must be a first-class column.

**Decision:** Add `cusip` column to `dim_security`. Backfill the 13 real yfinance tickers (equities + benchmarks) via a dbt seed (`seeds/yfinance_to_cusip.csv`). Synthetic bonds (`BOND_NNN`) carry `cusip = NULL` — no real CUSIP exists for synthesized securities. 13F-only securities get `sec_id = '13F_' || cusip` as their natural key.

**Run order required after this change:**
1. `dbt seed` — load `yfinance_to_cusip.csv` to `bronze.yfinance_to_cusip`
2. `dbt run -s dim_security` — rebuild with cusip column and 13F securities
3. `dbt snapshot` — capture schema evolution in `dim_security_snapshot`
4. `dbt run -s dim_security_history dim_security_current` — rebuild SCD models
5. `dbt run -s fct_manager_holding` — build fact table with CUSIP joins live

**Snapshot note:** `dim_security_snapshot` reads `bronze.raw_security_master`, which contains only yfinance equities and synthetic bonds — not 13F-sourced securities. This means `dim_security_history` and `dim_security_current` cover only the original 23 securities. 13F-only securities are available in `dim_security` but have no SCD history rows. This is acceptable for v0.3: institutional holdings fact joins use `dim_security` directly (not `dim_security_current`), and SCD history for 13F securities is a v0.4 scope item. Adding `cusip` to the snapshot's `check_cols` is also a v0.4 candidate.

**Trade-off accepted:** Synthetic bonds permanently have NULL CUSIP. They cannot be linked to 13F holdings. This is correct — synthetic bonds are not real securities and will not appear in any institutional 13F filing.

---

## 2026-05-07 — fct_manager_holding accepts zero-value and zero-share holdings

**Context:** After loading Q4 2025 13F data, the original positive-value singular test (`value_thousands_usd <= 0`) and positive-shares test (`shares <= 0`) produced failures. Investigation confirmed these are valid SEC filings: positions < $500 round to zero in thousands-USD units; fractional share positions round to zero integer shares.

**Decision:** Relax singular tests from `<= 0` to `< 0` (reject only negative values, which remain an unambiguous parsing error). Zero-value and zero-share holdings are routed to `recon.recon_zero_value_holdings` for governance visibility.

**Trade-off accepted:** Zero-value holdings count as zero contribution to AUM totals. They are real positions below the reporting precision threshold, not errors. Keeping them in the fact table preserves complete manager-security coverage for governance queries.

---

## 2026-05-07 — Wellington 13F filed under holding company CIK, not operating company

**Context:** The ingestion plan locked CIK `0000902219` as Wellington Management Company LLP (operating company). The EDGAR submissions API returned entity name `WELLINGTON MANAGEMENT GROUP LLP` — the holding company, not the operating entity.

**Decision:** Retain CIK `0000902219`. The 7,580 holdings and $570B reported AUM confirm this is the substantive filing. The name mismatch is a holding-company vs. operating-company EDGAR registration variant, not an incorrect CIK. Fallback CIK `0000900092` was not needed.

**Trade-off accepted:** `manager_name` in `dim_investment_manager` reflects the EDGAR-registered name (`WELLINGTON MANAGEMENT GROUP LLP`), not the operating entity name. This is the authoritative source value.

---

## 2026-05-07 — recon_bronze_to_silver requires exact zero variance

**Context:** The bronze-to-silver reconciliation gate (`recon_bronze_to_silver_reconciliation`) was designed to catch holdings dropped by the CUSIP→dim_security inner join or value scaling errors. Two tolerance options: (a) same 0.001% tolerance as filing-totals gate, or (b) exact zero.

**Decision:** Exact zero (`variance = 0`). The bronze-to-silver transformation is purely deterministic SQL arithmetic — there is no rounding between source and target at this step. Any non-zero variance means a row was dropped (CUSIP with no dim_security match) or duplicated. The `status = 'FAIL'` singular test enforces this.

**Trade-off accepted:** If a CUSIP appears in bronze but not in dim_security (e.g., dim_security was not rebuilt before fct_manager_holding), this gate will FAIL, which is the correct behavior — it surfaces the dependency ordering violation.

---

---

## 2026-05-26 — v0.4: Source freshness scoped to TIMESTAMPTZ columns only

**Context:** dbt source freshness requires a TIMESTAMP-compatible `loaded_at_field`. Five candidate sources — `raw_security_master`, `raw_prices`, `raw_ratings`, `raw_benchmarks`, and `raw_13f_filings` — were evaluated. Four use DATE columns (`position_date`, `price_date`, `rating_date`, `filed_date`) which dbt 1.11 rejects for freshness monitoring with: `"Expected a timestamp value when querying field 'last_modified' of table None but received value of type 'date' instead"`.

**Decision:** Implement source freshness only on `raw_13f_filings` using the existing `_ingested_at TIMESTAMPTZ DEFAULT now()` column (present in `sql/ddl/bronze_13f.sql`). Thresholds: warn_after 120 days, error_after 180 days. The four DATE-column sources are documented as `[Designed]` — requiring a `_ingested_at TIMESTAMPTZ` column addition as a v0.5 DDL migration before freshness can be activated.

**Alternative considered:** Cast DATE to TIMESTAMP in the freshness query via a dbt macro override. Rejected because it is a non-standard dbt pattern, fragile across dbt version upgrades, and the governance overhead is not justified when the `recon_stale_prices` model already monitors price freshness at the recon layer.

**Trade-off accepted:** Source freshness is currently partial — only 13F filing freshness is monitored at the source layer. Price, position, rating, and benchmark freshness is monitored via the `recon_stale_prices` reconciliation model instead.

---

## 2026-05-26 — v0.4: FK relationship tests added to all silver fact tables

**Context:** v0.3 had relationship tests on `fct_manager_holding` (manager_id→dim_investment_manager, security_id→dim_security) but not on the three portfolio-analytics fact tables. This created an asymmetry — the 13F fact was better tested than the core portfolio facts.

**Decision:** Add `relationships` tests to all three remaining fact tables:
- `fct_position_daily`: portfolio_id→dim_portfolio, security_id→dim_security, date_id→dim_date (3 tests)
- `fct_price_daily`: security_id→dim_security, date_id→dim_date (2 tests)
- `fct_benchmark_return_daily`: benchmark_id→dim_benchmark, date_id→dim_date (2 tests)

Total relationship tests: 14 across all silver fact tables (7 existing + 7 new).

**Trade-off accepted:** `fct_manager_holding` already had 2 relationship tests. `fct_manager_holding` references `dim_investment_manager` (manager_id) and `dim_security` (security_id) — these were preserved. No relationship test exists for `period_of_report` because this column is a DATE value, not a foreign key to a date dimension (13F holdings facts do not join to `dim_date`). This is documented as a design difference between the portfolio analytics layer and the regulatory reporting layer.

---

## 2026-05-26 — v0.4: Governance scorecard honest output policy

**Context:** The `governance_scorecard` model computes KPI-08 (Composite Readiness) as READY/REVIEW/BLOCKED based on the other 7 KPIs. At first run, KPI-08 showed BLOCKED because: (1) KPI-03 (price freshness) was RED — yfinance prices are ~25 days stale because there is no scheduled intraday refresh; (2) KPI-07 (concentration limits) was RED — 22/42 synthetic portfolio positions exceed the 5% single-security limit, which is by design (the synthetic portfolio tests the limit rule).

**Decision:** Do not modify the scorecard to suppress or soften these RED outputs. KPI-08 BLOCKED is the correct, honest signal. The scorecard is working as intended: it surfaces real data quality conditions, not a rubber-stamp result.

**Rationale:** An investment operations scorecard that shows READY when data is stale is worse than no scorecard. The purpose of the governance model is to require human action when thresholds are breached. Suppressing the RED outputs would defeat the purpose and misrepresent the portfolio data quality.

**Documentation:** The `GOVERNANCE_SCORECARD_MODEL.md` architecture document explicitly notes that KPI-08 BLOCKED is intentional and explains the two contributing conditions.

**Trade-off accepted:** The scorecard will remain BLOCKED in any environment where: (a) yfinance prices have not been refreshed within 25 days, or (b) the synthetic portfolio positions are loaded as-is. This is acceptable because this is a development repo, not production. In production, BLOCKED would require engineering action before the scorecard could be used for certified reporting.

---

## Reserved for v0.5 decisions

- Source freshness DDL migration: add `_ingested_at TIMESTAMPTZ DEFAULT now()` to raw_security_master, raw_prices, raw_ratings, raw_benchmarks
- Database role for read-only AI agent access
- SCD type for `dim_issuer` (same dbt snapshot pattern as dim_security)
- SCD type for `dim_investment_manager` (manager names/types can change)
- Add `cusip` to `dim_security_snapshot` check_cols
- CI scope (parse, build, test, all three)
