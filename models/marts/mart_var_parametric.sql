-- Parametric variance-covariance VaR (zero-correlation assumption); 1-day 95% and 99% VaR per portfolio at latest position date. Author: Nicholas Hidalgo

with latest_pos_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('fct_position_daily') }}
    group by portfolio_id
),

positions as (
    select f.portfolio_id, f.sec_id, f.position_date, f.market_value
    from {{ ref('fct_position_daily') }} f
    inner join latest_pos_date ld
        on f.portfolio_id = ld.portfolio_id
       and f.position_date = ld.position_date
),

nav as (
    select portfolio_id, position_date, sum(market_value) as total_nav
    from positions
    group by portfolio_id, position_date
),

log_returns as (
    select
        sec_id,
        price_date,
        ln(price / nullif(
            lag(price) over (partition by sec_id order by price_date), 0
        ))                                                          as log_return
    from {{ ref('fct_price_daily') }}
),

security_vol as (
    select
        sec_id,
        stddev(log_return)                                          as daily_vol
    from log_returns
    where log_return is not null
    group by sec_id
),

position_var_components as (
    select
        p.portfolio_id,
        p.position_date,
        p.sec_id,
        p.market_value,
        coalesce(v.daily_vol, 0.01)                                 as daily_vol,
        power(p.market_value * coalesce(v.daily_vol, 0.01), 2)      as variance_contribution
    from positions p
    left join security_vol v using (sec_id)
),

portfolio_sigma as (
    select
        portfolio_id,
        position_date,
        sqrt(sum(variance_contribution)) / n.total_nav               as sigma_daily
    from position_var_components
    inner join nav n using (portfolio_id, position_date)
    group by portfolio_id, position_date, n.total_nav
)

select
    ps.portfolio_id,
    ps.position_date,
    n.total_nav                                                      as nav,
    round(ps.sigma_daily::numeric,     8)                           as sigma_daily,
    round((1.645 * ps.sigma_daily * n.total_nav)::numeric, 2)       as var_95_1d,
    round((2.326 * ps.sigma_daily * n.total_nav)::numeric, 2)       as var_99_1d
from portfolio_sigma ps
inner join nav n using (portfolio_id, position_date)
