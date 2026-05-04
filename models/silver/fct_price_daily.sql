-- Daily price fact: grain sec_id x price_date. Author: Nicholas Hidalgo

select
    p.sec_id,
    p.price_date,
    p.price,
    p.source,
    s.asset_class,
    s.sector,
    d.year,
    d.quarter,
    d.month
from {{ ref('stg_prices') }} p
left join {{ ref('dim_security') }} s using (sec_id)
left join {{ ref('dim_date') }}     d on d.date_day = p.price_date
