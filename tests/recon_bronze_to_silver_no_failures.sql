-- Singular test: recon_bronze_to_silver_reconciliation must have zero FAIL rows.
-- Any FAIL means the silver fct_manager_holding value sum diverged from the
-- bronze raw_13f_holdings sum for the same (cik, period_of_report).
-- The transformation is deterministic; variance = 0 is the only acceptable result.
-- A FAIL indicates holdings were dropped by the CUSIP→dim_security inner join
-- (i.e., CUSIPs present in bronze that have no matching entry in dim_security).

select
    cik,
    manager_name,
    period_of_report,
    bronze_row_count,
    silver_row_count,
    bronze_sum_value_thousands_usd,
    silver_sum_value_thousands_usd,
    value_variance_thousands_usd,
    value_variance_pct,
    status
from {{ ref('recon_bronze_to_silver_reconciliation') }}
where status = 'FAIL'
