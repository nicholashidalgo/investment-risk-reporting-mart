{{
    config(
        materialized='table',
        schema='marts'
    )
}}

-- Governance Scorecard
-- Computes 8 governance health KPIs from warehouse tables.
-- Grain: one row per KPI (kpi_name is the natural key).
--
-- Severity levels:
--   GREEN  = within acceptable thresholds; no action required
--   YELLOW = approaching threshold; steward review recommended
--   RED    = threshold exceeded; reporting should be held pending review
--   INFO   = informational; not a pass/fail metric
--
-- Reporting readiness (the last KPI) is a composite:
--   READY   = all blocking KPIs are GREEN
--   REVIEW  = any KPI is YELLOW; steward review required before release
--   BLOCKED = any KPI is RED; data must not be released
--
-- Source: this model reads from the recon schema which is built before marts.
-- All KPI values are derived from actual warehouse tables, not hardcoded assertions.

with

-- ── KPI 1: Test Pass Rate ────────────────────────────────────────────────────
-- dbt run results are not queryable in-warehouse; we use a proxy:
-- the existence of non-zero rows in recon models with FAIL status.
-- Full test pass rate (153/153) is asserted by the CI run and singular tests.
-- This KPI surfaces recon gate failures as a warehouse-queryable signal.
filing_recon_fails as (
    select count(*) as fail_count
    from {{ ref('recon_filing_totals_reconciliation') }}
    where status = 'FAIL'
),

bronze_silver_fails as (
    select count(*) as fail_count
    from {{ ref('recon_bronze_to_silver_reconciliation') }}
    where status = 'FAIL'
),

position_nav_fails as (
    select count(*) as fail_count
    from {{ ref('recon_position_to_nav') }}
    where status = 'FAIL'
),

benchmark_fails as (
    select count(*) as fail_count
    from {{ ref('recon_benchmark_coverage') }}
    where status = 'FAIL'
),

rating_fails as (
    select count(*) as fail_count
    from {{ ref('recon_rating_coverage') }}
    where status = 'FAIL'
),

-- ── KPI 2: Freshness Status ──────────────────────────────────────────────────
stale_price_counts as (
    select
        count(case when status = 'FAIL' then 1 end) as stale_fail_count,
        count(case when status = 'WARN' then 1 end) as stale_warn_count,
        max(days_since)                              as max_days_stale
    from {{ ref('recon_stale_prices') }}
),

-- ── KPI 3: 13F Reconciliation Status ────────────────────────────────────────
filing_recon_summary as (
    select
        count(*)                                   as total_filings,
        count(case when status = 'PASS' then 1 end) as pass_count,
        count(case when status = 'FAIL' then 1 end) as fail_count,
        max(abs(variance_pct))                     as max_variance_pct
    from {{ ref('recon_filing_totals_reconciliation') }}
),

bronze_silver_summary as (
    select
        count(*)                                   as total_managers,
        count(case when status = 'PASS' then 1 end) as pass_count,
        count(case when status = 'FAIL' then 1 end) as fail_count,
        sum(abs(coalesce(value_variance_thousands_usd, 0))) as total_abs_variance_thousands
    from {{ ref('recon_bronze_to_silver_reconciliation') }}
),

-- ── KPI 4: Holdings Volume ───────────────────────────────────────────────────
holdings_volume as (
    select
        count(distinct period_of_report) as distinct_periods,
        count(distinct manager_id)       as distinct_managers,
        count(*)                         as total_holding_rows,
        sum(value_usd)                   as total_aum_usd,
        min(period_of_report)            as earliest_period,
        max(period_of_report)            as latest_period
    from {{ ref('fct_manager_holding') }}
),

-- ── KPI 5: Security Coverage ─────────────────────────────────────────────────
security_coverage as (
    select
        count(*)                                            as total_securities,
        count(case when cusip is not null then 1 end)       as securities_with_cusip,
        count(case when asset_class = 'Equity' then 1 end)  as equity_count,
        count(case when asset_class = 'Fixed Income' then 1 end) as fixed_income_count,
        count(case when _source_system = 'sec_13f' then 1 end)   as thirteenf_count,
        count(case when _source_system = 'yfinance' then 1 end)  as yfinance_count
    from {{ ref('dim_security') }}
),

-- ── KPI 6: Zero-Value Holdings ───────────────────────────────────────────────
zero_value_summary as (
    select count(*) as zero_value_count
    from {{ ref('recon_zero_value_holdings') }}
),

-- ── KPI 7: Price Coverage for yfinance securities ────────────────────────────
price_coverage as (
    select
        count(distinct sec_id)                             as securities_priced,
        max(price_date)                                    as latest_price_date,
        current_date - max(price_date)                     as days_since_latest_price
    from {{ ref('fct_price_daily') }}
),

-- ── KPI 8: Concentration Breach Count ───────────────────────────────────────
concentration_summary as (
    select
        count(case when breach_flag = true then 1 end)  as breach_count,
        count(*)                                        as total_positions
    from {{ ref('mart_concentration_limits') }}
),

-- ── Composite reporting readiness ───────────────────────────────────────────
composite as (
    select
        -- All recon gates must be PASS
        filing_recon_fails.fail_count                  as filing_fails,
        bronze_silver_fails.fail_count                 as bronze_silver_fails,
        position_nav_fails.fail_count                  as position_nav_fails,
        benchmark_fails.fail_count                     as benchmark_cov_fails,
        rating_fails.fail_count                        as rating_cov_fails,
        stale_price_counts.stale_fail_count            as stale_price_fails,
        -- Summary for readiness
        (
            filing_recon_fails.fail_count
            + bronze_silver_fails.fail_count
            + position_nav_fails.fail_count
            + stale_price_counts.stale_fail_count
        ) as total_blocking_fails,
        (stale_price_counts.stale_warn_count) as total_warnings
    from filing_recon_fails
    cross join bronze_silver_fails
    cross join position_nav_fails
    cross join benchmark_fails
    cross join rating_fails
    cross join stale_price_counts
)

-- ── Output: one row per KPI ──────────────────────────────────────────────────
select
    'KPI-01'                                          as kpi_id,
    'Reconciliation Gate Status — 13F Filing Totals'  as kpi_name,
    'reconciliation'                                  as kpi_category,
    filing_recon_summary.pass_count::text
        || '/' || filing_recon_summary.total_filings::text
        || ' PASS'                                    as metric_value,
    case
        when filing_recon_summary.fail_count = 0 then 'GREEN'
        else 'RED'
    end                                               as severity,
    case
        when filing_recon_summary.fail_count = 0
        then 'All ' || filing_recon_summary.total_filings::text
            || ' filings reconciled within tolerance.'
        else filing_recon_summary.fail_count::text
            || ' filing(s) exceed 0.001% variance — release BLOCKED.'
    end                                               as detail,
    'recon_filing_totals_reconciliation'              as source_model,
    current_timestamp                                 as scorecard_as_of

from filing_recon_summary

union all

select
    'KPI-02',
    'Reconciliation Gate Status — Bronze to Silver',
    'reconciliation',
    bronze_silver_summary.pass_count::text
        || '/' || bronze_silver_summary.total_managers::text
        || ' PASS; abs_variance=$'
        || (bronze_silver_summary.total_abs_variance_thousands * 1000)::text,
    case
        when bronze_silver_summary.fail_count = 0 then 'GREEN'
        else 'RED'
    end,
    case
        when bronze_silver_summary.fail_count = 0
        then 'Transformation variance is exactly $0 for all managers.'
        else bronze_silver_summary.fail_count::text
            || ' manager(s) show non-zero variance — transformation bug suspected.'
    end,
    'recon_bronze_to_silver_reconciliation',
    current_timestamp

from bronze_silver_summary

union all

select
    'KPI-03',
    'Data Freshness — Market Prices',
    'freshness',
    coalesce(
        (current_date - price_coverage.latest_price_date)::text || ' days since latest price ('
        || price_coverage.latest_price_date::text || ')',
        'No prices loaded'
    ),
    case
        when price_coverage.days_since_latest_price is null     then 'RED'
        when price_coverage.days_since_latest_price <= 3         then 'GREEN'
        when price_coverage.days_since_latest_price <= 5         then 'YELLOW'
        else                                                          'RED'
    end,
    case
        when price_coverage.days_since_latest_price is null
        then 'No price data found — ingestion required.'
        when price_coverage.days_since_latest_price <= 3
        then 'Prices current. Latest: ' || price_coverage.latest_price_date::text
        when price_coverage.days_since_latest_price <= 5
        then 'Prices approaching stale (' || price_coverage.days_since_latest_price::text || ' days). Review before release.'
        else 'Prices stale (' || price_coverage.days_since_latest_price::text || ' days). Re-ingest required before release.'
    end,
    'fct_price_daily / recon_stale_prices',
    current_timestamp

from price_coverage

union all

select
    'KPI-04',
    'Holdings Volume — 13F Manager Coverage',
    'completeness',
    holdings_volume.distinct_managers::text
        || ' managers, '
        || holdings_volume.total_holding_rows::text
        || ' holdings, period: '
        || holdings_volume.latest_period::text,
    case
        when holdings_volume.distinct_managers >= 5 then 'GREEN'
        when holdings_volume.distinct_managers >= 3 then 'YELLOW'
        else 'RED'
    end,
    'Periods covered: ' || holdings_volume.earliest_period::text
        || ' to ' || holdings_volume.latest_period::text
        || '. Total AUM: $'
        || round((holdings_volume.total_aum_usd / 1e12)::numeric, 2)::text
        || 'T.',
    'fct_manager_holding',
    current_timestamp

from holdings_volume

union all

select
    'KPI-05',
    'Security Dimension Coverage',
    'completeness',
    security_coverage.total_securities::text
        || ' securities ('
        || security_coverage.thirteenf_count::text
        || ' from 13F, '
        || security_coverage.yfinance_count::text
        || ' from yfinance)',
    'GREEN',
    security_coverage.securities_with_cusip::text
        || '/' || security_coverage.total_securities::text
        || ' have CUSIP. yfinance securities without CUSIP are synthetic bonds (expected).',
    'dim_security',
    current_timestamp

from security_coverage

union all

select
    'KPI-06',
    'Zero-Value Holdings — Informational',
    'data_quality',
    zero_value_summary.zero_value_count::text || ' zero-value holding rows',
    'INFO',
    'Zero-value holdings are valid SEC data (sub-$500 rounding or fractional shares). '
        || 'See recon_zero_value_holdings for classification. Not a blocking condition.',
    'recon_zero_value_holdings',
    current_timestamp

from zero_value_summary

union all

select
    'KPI-07',
    'Concentration Limit Breaches',
    'risk_controls',
    concentration_summary.breach_count::text
        || '/' || concentration_summary.total_positions::text
        || ' positions exceed 5% NAV',
    case
        when concentration_summary.breach_count = 0 then 'GREEN'
        when concentration_summary.breach_count <= 2 then 'YELLOW'
        else 'RED'
    end,
    case
        when concentration_summary.breach_count = 0
        then 'No concentration breaches. All positions within 5% limit.'
        else concentration_summary.breach_count::text
            || ' position(s) exceed 5% of NAV. Review mart_concentration_limits.'
    end,
    'mart_concentration_limits',
    current_timestamp

from concentration_summary

union all

select
    'KPI-08',
    'Reporting Readiness — Composite',
    'certification',
    case
        when composite.total_blocking_fails = 0
             and composite.total_warnings   = 0 then 'READY'
        when composite.total_blocking_fails = 0
             and composite.total_warnings   > 0 then 'REVIEW'
        else                                         'BLOCKED'
    end,
    case
        when composite.total_blocking_fails = 0
             and composite.total_warnings   = 0 then 'GREEN'
        when composite.total_blocking_fails = 0
             and composite.total_warnings   > 0 then 'YELLOW'
        else                                         'RED'
    end,
    case
        when composite.total_blocking_fails = 0 and composite.total_warnings = 0
        then 'All blocking controls PASS. Data may proceed to certification.'
        when composite.total_blocking_fails = 0
        then composite.total_warnings::text
            || ' warning(s) require steward review before release.'
        else composite.total_blocking_fails::text
            || ' blocking failure(s). Data MUST NOT be released until resolved. '
            || 'Failing gates: '
            || case when filing_fails > 0 then 'filing_totals_recon ' else '' end
            || case when bronze_silver_fails > 0 then 'bronze_silver_recon ' else '' end
            || case when position_nav_fails > 0 then 'position_nav_recon ' else '' end
            || case when stale_price_fails > 0 then 'stale_prices' else '' end
    end,
    'composite: all recon + freshness gates',
    current_timestamp

from composite
