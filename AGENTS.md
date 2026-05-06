# Agent Operating Rules

This repository is a governed investment data product. Any agent (Claude Code, Codex, automated tools) operating on this repo must follow these rules.

## Identity

This repo demonstrates a governed data product operating model applied to investment holdings, risk reporting, and reconciliation. It is not a production buy-side system. It is portfolio-grade evidence of how the owner (Nicholas Hidalgo) approaches investment data products: contracts, grain, quality gates, reconciliation, SLA controls, and reporting readiness.

## Hard Rules

1. **No git writes by agents.** `git add`, `git commit`, `git push`, `git tag`, `git rebase`, `git reset`, and related commands are reserved for the human owner. Agents never run them. Prompts written for agents never include them.

2. **No database writes by agents.** Agents do not run `psql` write commands, `dropdb`, `dropuser`, `createdb`, `createuser`, or pipeline execution (`dbt run`, `dbt build`, `dbt test`, `dbt seed`, `dbt snapshot`). The owner runs these manually with eyes on the screen.

3. **Honest metrics only.** No claim in any document, README, or commit is allowed unless backed by an artifact in the repo: a test, a query result, a reconciliation output, a log line. Estimated, simulated, or projected metrics must be labeled clearly as such or omitted.

4. **No production claims.** This repo does not claim production buy-side adoption, assets under management coverage, business cost savings, analyst time saved, or investment decision impact. The product demonstrates technical controls and reporting readiness, not market deployment.

5. **One tool owns the working tree at a time.** Codex and Claude Code do not edit the same files concurrently. Phase-based handoffs only.

6. **Synthetic data is for seeded defect testing only.** Public regulatory data (SEC, FRED, Treasury, ETF issuer disclosures) is the preferred source. Synthetic data is acceptable as starting seed for proof-of-shape work but must be replaced or supplemented with public data before the project leaves portfolio-evidence status.

## Operating Cadence

- Every meaningful work session updates `PROJECT_STATUS.md`, `DECISIONS.md`, and `NEXT_ACTIONS.md`.
- Phase transitions update `HANDOFF.md` so the next session (or next tool) starts with no re-explanation.
- Codex output is read-only markdown. Claude Code is the writer. The owner is the committer.

## Forbidden Files in Tracked History

These files must never be committed:
- `resume_translation.md`
- `interview_talk_track.md`
- `cover_letter_*.md`
- `*.env`, `.env.*`
- Any file containing personal credentials, PATs, database passwords, or local file paths

## When in Doubt

Stop. Update `HANDOFF.md`. Surface the question. Wait for owner direction.
