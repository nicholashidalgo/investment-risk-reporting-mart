-- Security dimension: one row per sec_id with latest rating joined. Author: Nicholas Hidalgo

with latest_rating as (
    select distinct on (sec_id)
        sec_id,
        rating       as latest_rating,
        agency       as latest_rating_agency,
        rating_date  as latest_rating_date
    from {{ ref('stg_ratings') }}
    order by sec_id, rating_date desc, agency
)

select
    s.sec_id,
    s.ticker,
    case
        when s.sec_id in ('SPY', 'AGG') then 'Benchmark'
        else s.asset_class
    end                                  as asset_class,
    s.sector,
    s.maturity,
    s.issue_date,
    coalesce(r.latest_rating, s.rating)  as rating,
    r.latest_rating_agency,
    r.latest_rating_date
from {{ ref('stg_security_master') }} s
left join latest_rating r using (sec_id)
