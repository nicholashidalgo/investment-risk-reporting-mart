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

## Reserved for v0.2 decisions

- SCD type for `dim_issuer` (same dbt snapshot pattern as dim_security)
- SEC 13F filing scope (which quarters, how many managers)
- Relationship test coverage scope
- CI scope (parse, build, test, all three)
