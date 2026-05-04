-- Concentration limit monitor: flags any position exceeding 5% of NAV at latest position date. Author: Nicholas Hidalgo

with latest_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('fct_position_daily') }}
    group by portfolio_id
),

positions as (
    select f.*
    from {{ ref('fct_position_daily') }} f
    inner join latest_date ld
        on f.portfolio_id = ld.portfolio_id
       and f.position_date = ld.position_date
),

nav as (
    select portfolio_id, position_date, sum(market_value) as total_nav
    from positions
    group by portfolio_id, position_date
),

with_pct as (
    select
        p.portfolio_id,
        p.position_date,
        p.sec_id,
        s.ticker,
        p.market_value,
        p.weight,
        round((p.market_value / nullif(n.total_nav, 0) * 100)::numeric, 4) as weight_pct
    from positions p
    inner join nav n using (portfolio_id, position_date)
    inner join {{ ref('dim_security') }} s using (sec_id)
)

select
    portfolio_id,
    position_date,
    sec_id,
    ticker,
    weight_pct,
    weight_pct > 5.0                                            as breach_flag,
    greatest(round((weight_pct - 5.0)::numeric, 4), 0)         as breach_amount_over_5pct
from with_pct
