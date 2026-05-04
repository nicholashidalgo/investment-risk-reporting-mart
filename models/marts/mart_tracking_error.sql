-- Ex-post tracking error using current position weights held constant across full price history (static-weight approximation); PORT_CORE->BENCH_SPY, PORT_FLEX->BENCH_AGG. Author: Nicholas Hidalgo

with benchmark_map as (
    select 'PORT_CORE' as portfolio_id, 'BENCH_SPY' as benchmark_id
    union all
    select 'PORT_FLEX',                 'BENCH_AGG'
),

latest_pos_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('fct_position_daily') }}
    group by portfolio_id
),

current_weights as (
    select f.portfolio_id, f.sec_id, f.weight
    from {{ ref('fct_position_daily') }} f
    inner join latest_pos_date ld
        on f.portfolio_id = ld.portfolio_id
       and f.position_date = ld.position_date
),

security_daily_returns as (
    select
        sec_id,
        price_date,
        (price - lag(price) over (partition by sec_id order by price_date))
            / nullif(lag(price) over (partition by sec_id order by price_date), 0) as daily_return
    from {{ ref('fct_price_daily') }}
),

portfolio_daily_returns as (
    select
        cw.portfolio_id,
        sdr.price_date,
        sum(cw.weight * sdr.daily_return) as port_return
    from current_weights cw
    inner join security_daily_returns sdr using (sec_id)
    where sdr.daily_return is not null
    group by cw.portfolio_id, sdr.price_date
),

benchmark_returns as (
    select benchmark_id, benchmark_date, return as bench_return
    from {{ ref('fct_benchmark_return_daily') }}
),

active_returns as (
    select
        pdr.portfolio_id,
        bm.benchmark_id,
        pdr.price_date,
        pdr.port_return - br.bench_return as active_return
    from portfolio_daily_returns pdr
    inner join benchmark_map bm using (portfolio_id)
    inner join benchmark_returns br
        on br.benchmark_id = bm.benchmark_id
       and br.benchmark_date = pdr.price_date
),

max_date as (
    select max(price_date) as anchor_date from {{ ref('fct_price_daily') }}
)

select
    ar.portfolio_id,
    ar.benchmark_id,
    round(
        (stddev(case when ar.price_date > md.anchor_date - interval '30 days'
                     then ar.active_return end) * sqrt(252))::numeric, 6
    )                                                                   as te_30d,
    round(
        (stddev(case when ar.price_date > md.anchor_date - interval '60 days'
                     then ar.active_return end) * sqrt(252))::numeric, 6
    )                                                                   as te_60d,
    round(
        (stddev(ar.active_return) * sqrt(252))::numeric, 6
    )                                                                   as te_90d
from active_returns ar
cross join max_date md
where ar.price_date > md.anchor_date - interval '90 days'
group by ar.portfolio_id, ar.benchmark_id
