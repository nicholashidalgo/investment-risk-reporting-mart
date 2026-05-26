-- Filing-level reconciliation: SEC cover-page reported totals vs bronze holdings sum.
-- Grain: one row per (cik, accession_no, period_of_report).
--
-- The silver fact table (fct_manager_holding) cannot be used as the sum source
-- because its aggregation collapses multiple discretion-category bronze rows into
-- one grain row, losing the accession_no link. The authoritative sum must come
-- from bronze.raw_13f_holdings directly, which preserves accession_no on every row.
--
-- Status threshold: PASS if abs(variance_pct) < 0.001% (~$1,000 per $1B filed).
-- This is stricter than the plan spec (0.1%) to reflect that all 5 filings
-- reconciled to exact match or single-unit rounding in the Hour 2 parse check.

with filing_reported as (

    select
        cik,
        manager_name,
        accession_no,
        period_of_report,
        reported_value_thousands_usd
    from {{ source('bronze', 'raw_13f_filings') }}

),

bronze_sums as (

    select
        accession_no,
        sum(value_thousands_usd) as bronze_sum_value_thousands_usd,
        count(*)                 as bronze_row_count
    from {{ source('bronze', 'raw_13f_holdings') }}
    group by accession_no

)

select
    f.cik,
    f.manager_name,
    f.accession_no,
    f.period_of_report,
    f.reported_value_thousands_usd,
    coalesce(b.bronze_sum_value_thousands_usd, 0)        as silver_sum_value_thousands_usd,
    coalesce(b.bronze_row_count, 0)                      as bronze_holding_row_count,

    coalesce(b.bronze_sum_value_thousands_usd, 0)
        - f.reported_value_thousands_usd                 as variance_thousands_usd,

    round(
        (
            coalesce(b.bronze_sum_value_thousands_usd, 0)
            - f.reported_value_thousands_usd
        )::numeric
        / nullif(f.reported_value_thousands_usd, 0)
        * 100,
        6
    )                                                    as variance_pct,

    case
        when abs(
            round(
                (
                    coalesce(b.bronze_sum_value_thousands_usd, 0)
                    - f.reported_value_thousands_usd
                )::numeric
                / nullif(f.reported_value_thousands_usd, 0)
                * 100,
                6
            )
        ) < 0.001
        then 'PASS'
        else 'FAIL'
    end                                                  as status,

    current_timestamp                                    as _generated_at

from filing_reported f
left join bronze_sums b using (accession_no)
