-- Synthetic modified duration by maturity bucket (0-2y=1.5, 2-5y=3.5, 5-10y=6.5, 10y+=12.0); portfolio-weighted average duration for fixed income positions. Author: Nicholas Hidalgo

with latest_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('fct_position_daily') }}
    group by portfolio_id
),

fi_positions as (
    select
        f.portfolio_id,
        f.sec_id,
        f.position_date,
        f.market_value,
        f.weight,
        s.maturity
    from {{ ref('fct_position_daily') }} f
    inner join latest_date ld
        on f.portfolio_id = ld.portfolio_id
       and f.position_date = ld.position_date
    inner join {{ ref('dim_security') }} s using (sec_id)
    where f.asset_class = 'Fixed Income'
),

with_duration as (
    select
        portfolio_id,
        sec_id,
        position_date,
        market_value,
        maturity,
        case
            when maturity is null                                  then 3.5
            when maturity <= current_date + interval '2 years'    then 1.5
            when maturity <= current_date + interval '5 years'    then 3.5
            when maturity <= current_date + interval '10 years'   then 6.5
            else 12.0
        end                                                        as synthetic_duration
    from fi_positions
),

fi_nav as (
    select portfolio_id, position_date, sum(market_value) as fi_nav
    from with_duration
    group by portfolio_id, position_date
),

weighted as (
    select
        w.portfolio_id,
        w.position_date,
        sum(w.market_value * w.synthetic_duration)
            / nullif(n.fi_nav, 0)                                  as weighted_avg_duration,
        n.fi_nav
    from with_duration w
    inner join fi_nav n using (portfolio_id, position_date)
    group by w.portfolio_id, w.position_date, n.fi_nav
)

select
    portfolio_id,
    position_date,
    fi_nav,
    round(weighted_avg_duration::numeric, 4)                       as weighted_avg_duration
from weighted
