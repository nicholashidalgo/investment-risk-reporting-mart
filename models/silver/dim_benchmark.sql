-- Benchmark dimension: one row per distinct benchmark_id. Author: Nicholas Hidalgo

select distinct
    benchmark_id
from {{ ref('stg_benchmarks') }}
