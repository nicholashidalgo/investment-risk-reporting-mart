# Project Status

**Last updated:** 2026-05-06 (afternoon — SCD verification complete, 127/127 tests passing)
**Owner:** Nicholas Hidalgo
**Current state:** v0.1.0 (tagged), pushed to GitHub on origin/main

## Current Build

| Layer | Count | Status |
|---|---:|---|
| Bronze staging views | 6 | Built, no tests |
| Silver dimensions | 6 | Built, tested (incl. dim_security_history, dim_security_current) |
| Silver facts | 3 | Built, tested |
| Risk marts (gold) | 7 | Built, tested |
| Reconciliation gates | 4 | Built, output to `recon` schema |
| dbt snapshots | 1 | dim_security_snapshot (strategy: check) |
| Total dbt models | 26 | All compiling |
| Total dbt tests | 127 | All blocking, 127 of 127 passing as of 2026-05-06 |

## What Exists

- 26 dbt models across 4 layers (bronze, silver, marts, recon) + 1 snapshot
- 127 blocking dbt tests, 127 of 127 passing as of 2026-05-06 (108 baseline + 19 new SCD tests including 2 custom singular tests for SCD invariants)
- 4 reconciliation models writing to `recon` schema (position-to-NAV, benchmark coverage, stale prices, rating coverage)
- Static HTML dashboard with Chart.js (`dashboard/index.html`, all 7 marts and 4 recon gates rendered)
- Real yfinance equity prices ingested via `scripts/ingest_seed_data.py`
- Synthetic bond prices, ratings, and positions (deterministic RNG seeds)
- README, DATA_CONTRACT, METHODOLOGY, CHANGELOG documentation
- **Type 2 SCD on dim_security** via dbt snapshot (`snapshots/dim_security_snapshot.sql`, strategy: check)
- **dim_security_history** — table with valid_from/valid_to/is_current/scd_id per security version
- **dim_security_current** — view filtered to is_current = true; intended join target for fact tables

## What Does Not Exist

- Type 2 SCD on dim_issuer (planned for v0.2)
- Relationship/foreign-key tests (planned for v0.2)
- Tests on bronze staging views (planned for v0.2)
- Public regulatory data source (SEC 13F ingestion planned for v0.3)
- GitHub Actions CI (planned for v0.2)
- MEASURED_IMPACT.md formal artifact (drafted today)
- Reconciliation summary CSV (planned for v0.2)
- Website case-study page (planned for v0.4)

## Known Issues

- `logs/dbt.log` is tracked but ignored by current `.gitignore`. Needs `git rm --cached` before next commit.
- One unused `dbt_project.yml` config path warns on every run. Cleanup pending.
- README and DATA_CONTRACT predate the specialist repositioning and need updates to align with current identity.

## Repo Health

- Tag: `v0.1.0`, `pre-audit-2026-05-06`
- Branch: `main`, up to date with `origin/main`
- Working tree: clean as of audit (2026-05-06)
- Local backup: `../investment-risk-reporting-mart.backup-2026-05-06-1249/`
