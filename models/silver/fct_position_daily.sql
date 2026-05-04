-- Daily position fact: grain portfolio_id x sec_id x position_date. Author: Nicholas Hidalgo

select
    p.portfolio_id,
    p.sec_id,
    p.position_date,
    p.market_value,
    p.par_value,
    p.weight,
    s.asset_class,
    s.sector,
    s.rating,
    d.year,
    d.quarter,
    d.month
from {{ ref('stg_positions') }} p
left join {{ ref('dim_security') }} s using (sec_id)
left join {{ ref('dim_date') }}     d on d.date_day = p.position_date
