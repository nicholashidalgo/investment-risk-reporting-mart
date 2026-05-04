-- Checks every fixed income security has at least one rating record; PASS=covered, FAIL=missing. Author: Nicholas Hidalgo

with fi_securities as (
    select sec_id, ticker
    from {{ ref('stg_security_master') }}
    where asset_class = 'Fixed Income'
),

rated as (
    select distinct sec_id
    from {{ ref('stg_ratings') }}
)

select
    f.sec_id,
    f.ticker,
    (r.sec_id is not null)                                          as has_rating,
    case when r.sec_id is not null then 'PASS' else 'FAIL' end      as status
from fi_securities f
left join rated r using (sec_id)
