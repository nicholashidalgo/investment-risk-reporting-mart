{{
    config(materialized='table')
}}

-- Investment manager dimension sourced from SEC 13F filings.
-- Grain: one row per CIK (natural key). Type 1 — latest-wins.
-- manager_type is static for v0.3; all 5 Boston-5 managers are institutional.
-- Type 2 SCD deferred to v0.4 (manager names are stable across quarters).

select
    {{ dbt_utils.generate_surrogate_key(['cik']) }}  as manager_id,
    cik,
    manager_name,
    'institutional_investment_manager'               as manager_type,
    current_timestamp                                as _ingested_at,
    'sec_edgar_13f'                                  as _source_system
from (
    select distinct
        cik,
        manager_name
    from {{ source('bronze', 'raw_13f_filings') }}
) managers
