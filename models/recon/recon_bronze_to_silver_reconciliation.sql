-- Bronze-to-silver reconciliation: verifies that fct_manager_holding totals
-- match bronze.raw_13f_holdings totals at the manager+period level.
-- Grain: one row per (cik, period_of_report).
--
-- This gate catches transformation losses introduced between bronze and silver:
--   - Holdings dropped by the CUSIP→dim_security inner join (no dim_security match)
--   - Aggregation errors in fct_manager_holding SUM logic
--   - Incorrect value scaling (value_thousands_usd vs value_usd confusion)
--
-- All comparisons are in thousands-USD units to avoid the ×1000 scaling factor.
-- Status: PASS only if value variance is exactly zero. The silver transformation
-- is deterministic; any variance indicates a row was dropped or double-counted.
-- Row counts will legitimately differ (bronze: one row per discretion category;
-- silver: one row per manager-security-period after aggregation) — row count
-- difference is informational, not a failure signal.

with bronze_totals as (

    select
        h.cik,
        h.period_of_report,
        count(*)                      as bronze_row_count,
        sum(h.value_thousands_usd)    as bronze_sum_value_thousands_usd
    from {{ source('bronze', 'raw_13f_holdings') }} h
    group by h.cik, h.period_of_report

),

silver_totals as (

    select
        mgr.cik,
        f.period_of_report,
        count(*)                      as silver_row_count,
        sum(f.value_thousands_usd)    as silver_sum_value_thousands_usd
    from {{ ref('fct_manager_holding') }} f
    inner join {{ ref('dim_investment_manager') }} mgr
        on mgr.manager_id = f.manager_id
    group by mgr.cik, f.period_of_report

)

select
    b.cik,
    mgr.manager_name,
    b.period_of_report,

    b.bronze_row_count,
    coalesce(s.silver_row_count, 0)             as silver_row_count,

    b.bronze_sum_value_thousands_usd,
    coalesce(s.silver_sum_value_thousands_usd, 0) as silver_sum_value_thousands_usd,

    coalesce(s.silver_sum_value_thousands_usd, 0)
        - b.bronze_sum_value_thousands_usd        as value_variance_thousands_usd,

    round(
        (
            coalesce(s.silver_sum_value_thousands_usd, 0)
            - b.bronze_sum_value_thousands_usd
        )::numeric
        / nullif(b.bronze_sum_value_thousands_usd, 0)
        * 100,
        6
    )                                             as value_variance_pct,

    case
        when coalesce(s.silver_sum_value_thousands_usd, 0)
             = b.bronze_sum_value_thousands_usd
        then 'PASS'
        else 'FAIL'
    end                                           as status,

    current_timestamp                             as _generated_at

from bronze_totals b
left join silver_totals s
    on s.cik = b.cik
    and s.period_of_report = b.period_of_report
inner join {{ ref('dim_investment_manager') }} mgr
    on mgr.cik = b.cik
