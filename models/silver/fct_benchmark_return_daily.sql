-- Daily benchmark return fact: grain benchmark_id x benchmark_date. Author: Nicholas Hidalgo

select
    b.benchmark_id,
    b.benchmark_date,
    b.return,
    d.year,
    d.quarter,
    d.month
from {{ ref('stg_benchmarks') }} b
left join {{ ref('dim_date') }} d on d.date_day = b.benchmark_date
