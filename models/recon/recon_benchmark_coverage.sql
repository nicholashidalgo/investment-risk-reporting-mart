-- Checks that every benchmark constituent has a price on the latest benchmark date; PASS=100%, WARN=95-99%, FAIL<95%. Author: Nicholas Hidalgo

with benchmark_map as (
    select 'BENCH_SPY' as benchmark_id, array['SPY']                                                     as constituents
    union all
    select 'BENCH_AGG',                  array['AGG']
),

latest_bench_date as (
    select benchmark_id, max(benchmark_date) as benchmark_date
    from {{ ref('stg_benchmarks') }}
    group by benchmark_id
),

expected as (
    select
        bm.benchmark_id,
        ld.benchmark_date,
        unnest(bm.constituents)             as sec_id,
        array_length(bm.constituents, 1)    as expected_constituents
    from benchmark_map bm
    inner join latest_bench_date ld using (benchmark_id)
),

priced as (
    select e.benchmark_id, e.benchmark_date, e.expected_constituents,
           count(p.sec_id)                  as priced_constituents
    from expected e
    left join {{ ref('stg_prices') }} p
        on p.sec_id = e.sec_id
       and p.price_date = e.benchmark_date
    group by e.benchmark_id, e.benchmark_date, e.expected_constituents
)

select
    benchmark_id,
    benchmark_date,
    expected_constituents,
    priced_constituents::int                                        as priced_constituents,
    round(
        priced_constituents::numeric / nullif(expected_constituents, 0) * 100,
        4
    )                                                               as coverage_pct,
    case
        when priced_constituents >= expected_constituents          then 'PASS'
        when priced_constituents::numeric / nullif(expected_constituents, 0) >= 0.95
                                                                   then 'WARN'
        else 'FAIL'
    end                                                             as status
from priced
