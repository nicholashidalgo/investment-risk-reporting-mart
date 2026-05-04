-- Stress scenario impact: equity shock hits Equity positions, rate shock hits Fixed Income via duration, credit shock hits BBB+ Fixed Income. Author: Nicholas Hidalgo

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

duration as (
    select portfolio_id, position_date, weighted_avg_duration
    from {{ ref('mart_duration_summary') }}
),

nav as (
    select portfolio_id, position_date, sum(market_value) as total_nav
    from positions
    group by portfolio_id, position_date
),

equity_mv as (
    select portfolio_id, position_date, sum(market_value) as eq_mv
    from positions
    where asset_class = 'Equity'
    group by portfolio_id, position_date
),

fi_mv as (
    select portfolio_id, position_date, sum(market_value) as fi_mv
    from positions
    where asset_class = 'Fixed Income'
    group by portfolio_id, position_date
),

bbb_plus_mv as (
    select portfolio_id, position_date, sum(market_value) as bbb_plus_mv
    from positions
    where asset_class = 'Fixed Income'
      and rating in ('AAA', 'AA', 'A', 'BBB')
    group by portfolio_id, position_date
),

scenarios as (
    select scenario_id, factor, shock_pct
    from {{ ref('stg_stress_scenarios') }}
),

crossed as (
    select
        n.portfolio_id,
        n.position_date,
        n.total_nav,
        s.scenario_id,
        s.factor,
        s.shock_pct,
        coalesce(e.eq_mv,  0)              as eq_mv,
        coalesce(f.fi_mv,  0)              as fi_mv,
        coalesce(b.bbb_plus_mv, 0)         as bbb_plus_mv,
        coalesce(d.weighted_avg_duration, 0) as duration
    from nav n
    cross join scenarios s
    left join equity_mv   e using (portfolio_id, position_date)
    left join fi_mv       f using (portfolio_id, position_date)
    left join bbb_plus_mv b using (portfolio_id, position_date)
    left join duration    d using (portfolio_id, position_date)
),

impact as (
    select
        portfolio_id,
        position_date,
        scenario_id,
        factor,
        shock_pct,
        total_nav,
        case
            when factor = 'equity' then
                eq_mv * (shock_pct / 100.0)
            when factor = 'interest_rate' then
                -- price change = -duration * (shock_bps/10000) * fi_mv
                -duration * (shock_pct / 10000.0) * fi_mv
            when factor = 'credit_spread' then
                -- price change = -duration * (spread_bps/10000) * bbb+_mv
                -duration * (shock_pct / 10000.0) * bbb_plus_mv
            else 0
        end                                as mv_change_usd
    from crossed
)

select
    portfolio_id,
    position_date,
    scenario_id,
    factor,
    shock_pct,
    round(mv_change_usd::numeric, 2)                            as mv_change_usd,
    round((mv_change_usd / nullif(total_nav, 0) * 100)::numeric, 4) as mv_change_pct
from impact
