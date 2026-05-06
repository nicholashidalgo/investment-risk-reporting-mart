-- Type 2 SCD history for dim_security. Selects from dbt snapshot and resolves the latest credit
-- rating from stg_ratings for each version row. Use this model for point-in-time and historical queries.
-- For current-state joins use dim_security_current instead.

{{
    config(materialized='table')
}}

with snapshot as (
    select * from {{ ref('dim_security_snapshot') }}
),

latest_rating as (
    select distinct on (sec_id)
        sec_id,
        rating       as latest_rating,
        agency       as latest_rating_agency,
        rating_date  as latest_rating_date
    from {{ ref('stg_ratings') }}
    order by sec_id, rating_date desc, agency
)

select
    {{ dbt_utils.generate_surrogate_key(['s.sec_id', 's.dbt_valid_from::text']) }}
                                                as security_key,
    s.sec_id,
    s.ticker,
    case
        when s.sec_id in ('SPY', 'AGG') then 'Benchmark'
        else s.asset_class
    end                                         as asset_class,
    s.sector,
    s.maturity,
    s.issue_date,
    coalesce(r.latest_rating, s.rating)         as rating,
    r.latest_rating_agency,
    r.latest_rating_date,
    s.dbt_valid_from                            as valid_from,
    s.dbt_valid_to                              as valid_to,
    (s.dbt_valid_to is null)                    as is_current,
    s.dbt_scd_id                                as scd_id,
    current_timestamp                           as _ingested_at,
    'dbt_snapshot'                              as _source_system
from snapshot s
left join latest_rating r using (sec_id)
