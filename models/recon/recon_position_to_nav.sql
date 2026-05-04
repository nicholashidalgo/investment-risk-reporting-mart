-- Reconciles sum of position market values to declared NAV targets; PASS within 0.1%, FAIL otherwise. Author: Nicholas Hidalgo

with declared_nav as (
    select 'PORT_CORE' as portfolio_id, 100000000.0 as declared_nav
    union all
    select 'PORT_FLEX',                  50000000.0
),

latest_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('stg_positions') }}
    group by portfolio_id
),

summed as (
    select p.portfolio_id, p.position_date, sum(p.market_value) as sum_mv
    from {{ ref('stg_positions') }} p
    inner join latest_date ld using (portfolio_id)
    where p.position_date = ld.position_date
    group by p.portfolio_id, p.position_date
)

select
    s.portfolio_id,
    s.position_date,
    round(s.sum_mv::numeric, 2)                                     as sum_mv,
    d.declared_nav,
    round(
        abs(s.sum_mv - d.declared_nav) / nullif(d.declared_nav, 0) * 100,
        4
    )                                                               as variance_pct,
    case
        when abs(s.sum_mv - d.declared_nav) / nullif(d.declared_nav, 0) <= 0.001
        then 'PASS'
        else 'FAIL'
    end                                                             as status
from summed s
inner join declared_nav d using (portfolio_id)
