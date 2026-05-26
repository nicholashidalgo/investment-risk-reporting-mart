{{
    config(materialized='table')
}}

-- Institutional manager holdings fact table.
-- Grain: one row per (manager_id, security_id, period_of_report).
--
-- Multi-row aggregation decision (v0.3):
-- A single manager can report the same CUSIP under multiple investment discretion
-- categories (SOLE, SHARED, DFND) in one filing, producing multiple bronze rows.
-- This model SUMS value and shares across categories into one grain row.
-- Voting authority columns are also summed. investment_discretion takes the
-- most granular value via max() (SOLE > SHARED > DFND alphabetically is not
-- meaningful, so we take max() as a stable tie-breaker and document the
-- limitation). See DECISIONS.md: "2026-05-07 — fct_manager_holding grain".
--
-- Securities with no dim_security match (CUSIP in bronze but not in silver)
-- are excluded. This can only occur if dim_security was built before the
-- 13F-sourced securities were loaded; running `dbt run -s dim_security` first
-- resolves it. See DECISIONS.md for the recommended run order.

with holdings as (

    select
        h.accession_no,
        h.cik,
        h.period_of_report,
        h.cusip,
        h.value_thousands_usd,
        h.ssh_prnamt,
        h.ssh_prnamt_type,
        h.investment_discretion,
        h.voting_authority_sole,
        h.voting_authority_shared,
        h.voting_authority_none,
        h.put_call
    from {{ source('bronze', 'raw_13f_holdings') }} h

),

-- Aggregate multiple discretion-category rows per (cik, cusip, period) into one
aggregated as (

    select
        accession_no,
        cik,
        period_of_report,
        cusip,
        sum(value_thousands_usd)                                      as value_thousands_usd,
        sum(case when ssh_prnamt_type = 'SH'  then ssh_prnamt end)   as shares,
        sum(case when ssh_prnamt_type = 'PRN' then ssh_prnamt end)   as principal_amount,
        max(investment_discretion)                                    as investment_discretion,
        sum(coalesce(voting_authority_sole,   0))                     as voting_authority_sole,
        sum(coalesce(voting_authority_shared, 0))                     as voting_authority_shared,
        sum(coalesce(voting_authority_none,   0))                     as voting_authority_none,
        -- put_call: null unless all rows for this grain agree; mixed puts/calls
        -- within the same CUSIP+period are kept distinct at bronze level only
        max(put_call)                                                 as put_call
    from holdings
    group by accession_no, cik, period_of_report, cusip

)

select
    {{ dbt_utils.generate_surrogate_key([
        'mgr.manager_id', 'sec.sec_id', 'a.period_of_report::text'
    ]) }}                                               as holding_id,

    mgr.manager_id,
    sec.sec_id                                          as security_id,
    a.period_of_report,

    a.value_thousands_usd,
    a.value_thousands_usd * 1000                        as value_usd,

    a.shares,
    a.principal_amount,

    a.investment_discretion,
    a.voting_authority_sole,
    a.voting_authority_shared,
    a.voting_authority_none,
    a.put_call,

    a.accession_no                                      as _filing_accession_no,
    current_timestamp                                   as _ingested_at,
    'sec_edgar_13f'                                     as _source_system

from aggregated a
inner join {{ ref('dim_investment_manager') }} mgr
    on mgr.cik = a.cik
inner join {{ ref('dim_security') }} sec
    on sec.cusip = a.cusip
