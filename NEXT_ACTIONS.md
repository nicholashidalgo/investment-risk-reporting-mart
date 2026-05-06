# Next Actions

Listed by priority. One actionable item per line. When complete, move to "Done This Week" with date.

## Active

### Today (2026-05-06)

- [ ] Apply MEASURED_IMPACT.md draft to repo root
- [ ] Apply README.md top-section repositioning
- [ ] Untrack `logs/dbt.log` (owner runs: `git rm --cached logs/dbt.log`)
- [ ] Remove unused `dbt_project.yml` config path warning
- [ ] Manually identify and remove the unused dbt_project.yml config path (Claude Code could not isolate it safely — the `marts` key and `models/marts/` directory both exist; the warning appears to have been transient during initial project setup, but the root cause needs owner verification before the key is removed)
- [ ] LinkedIn headline + About rewrite (this evening)
- [ ] GitHub profile README rewrite (this evening)
- [ ] Identify 2-3 bridge role candidates (this evening)

### Tomorrow (2026-05-07)

- [ ] Run `dbt snapshot` then `dbt run --select dim_security_history dim_security_current` to materialize the new SCD models (owner action — no agent execution)
- [ ] Run `dbt test --select dim_security_history dim_security_current` to verify all 19 new tests pass
- [ ] Implement Type 2 SCD on `dim_issuer` (same dbt snapshot pattern as dim_security)
- [ ] Add 6-10 relationship tests (referential integrity)
- [ ] Add bronze layer tests (3-5 tests on staging views)
- [ ] Add GitHub Actions CI workflow (`.github/workflows/dbt.yml`)
- [ ] SEC 13F ingestion scaffold for one quarter, 5-10 managers (raw landing only)
- [ ] Generate `reports/dq_reconciliation_summary.csv` from real test outputs
- [ ] Tailor Beta-Investment resume to selected bridge role
- [ ] Submit one bridge role application before EOD Friday

### v0.2 (this week)

- [ ] Public SEC 13F ingestion to silver layer
- [ ] Reconciliation: raw 13F filing totals vs silver `fct_holdings`
- [ ] Update README to reflect public-data foundation

### v0.3 (next 2-4 weeks)

- [ ] N-PORT integration for fund-level holdings
- [ ] Risk metric layer (duration, credit quality distribution, sector concentration)
- [ ] Issuer mapping and identifier normalization

### v0.4 (60-90 days)

- [ ] Website case-study page at nicholashidalgo.com/investment-data-product
- [ ] Power BI build (alternative to static HTML)
- [ ] Benchmark-relative exposure marts

## Done This Week

- 2026-05-06: Local backup created (`../investment-risk-reporting-mart.backup-2026-05-06-1249/`)
- 2026-05-06: Tagged `pre-audit-2026-05-06`
- 2026-05-06: Repo audit completed (`docs/reviews/audit-2026-05-06.md`)
- 2026-05-06: Beta-Investment resume v0.1 drafted
- 2026-05-06: Specialist identity locked: "Governed Data Products for Financial & Risk Reporting"
- 2026-05-06: Type 2 SCD implemented on dim_security — snapshot + history table + current view + 19 tests
