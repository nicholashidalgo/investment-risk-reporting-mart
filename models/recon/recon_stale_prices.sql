-- Detects stale prices per security; PASS<=3 business days, WARN=4-5, FAIL>5. Author: Nicholas Hidalgo

with last_price as (
    select sec_id, max(price_date) as last_price_date
    from {{ ref('stg_prices') }}
    group by sec_id
),

today as (
    select current_date as ref_date
)

select
    lp.sec_id,
    sm.ticker,
    lp.last_price_date,
    (t.ref_date - lp.last_price_date)                               as days_since,
    case
        when (t.ref_date - lp.last_price_date) <= 3 then 'PASS'
        when (t.ref_date - lp.last_price_date) <= 5 then 'WARN'
        else 'FAIL'
    end                                                             as status
from last_price lp
cross join today t
inner join {{ ref('stg_security_master') }} sm using (sec_id)
