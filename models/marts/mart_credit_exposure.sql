-- Credit exposure by rating bucket for fixed income positions at latest position date. Author: Nicholas Hidalgo

with latest_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('fct_position_daily') }}
    group by portfolio_id
),

fi_positions as (
    select f.*
    from {{ ref('fct_position_daily') }} f
    inner join latest_date ld
        on f.portfolio_id = ld.portfolio_id
       and f.position_date = ld.position_date
    where f.asset_class = 'Fixed Income'
),

total_nav as (
    select p.portfolio_id, p.position_date, sum(p.market_value) as total_nav
    from {{ ref('fct_position_daily') }} p
    inner join latest_date ld
        on p.portfolio_id = ld.portfolio_id
       and p.position_date = ld.position_date
    group by p.portfolio_id, p.position_date
),

total_fi as (
    select portfolio_id, position_date, sum(market_value) as total_fi_mv
    from fi_positions
    group by portfolio_id, position_date
),

bucketed as (
    select
        portfolio_id,
        position_date,
        case
            when rating in ('AAA', 'AA')  then 'AAA-AA'
            when rating = 'A'             then 'A'
            when rating = 'BBB'           then 'BBB'
            when rating = 'BB'            then 'BB'
            when rating in ('B')          then 'B'
            when rating in ('CCC', 'CC', 'C', 'D') then 'CCC and below'
            else 'NR'
        end                              as rating_bucket,
        sum(market_value)                as market_value
    from fi_positions
    group by portfolio_id, position_date,
        case
            when rating in ('AAA', 'AA')  then 'AAA-AA'
            when rating = 'A'             then 'A'
            when rating = 'BBB'           then 'BBB'
            when rating = 'BB'            then 'BB'
            when rating in ('B')          then 'B'
            when rating in ('CCC', 'CC', 'C', 'D') then 'CCC and below'
            else 'NR'
        end
)

select
    b.portfolio_id,
    b.position_date,
    b.rating_bucket,
    b.market_value,
    round(b.market_value / nullif(f.total_fi_mv, 0) * 100, 4)  as pct_of_fixed_income,
    round(b.market_value / nullif(n.total_nav,   0) * 100, 4)  as pct_of_total_nav
from bucketed b
inner join total_fi f using (portfolio_id, position_date)
inner join total_nav n using (portfolio_id, position_date)
