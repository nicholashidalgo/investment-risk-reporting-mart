-- Staging passthrough for bronze.raw_benchmarks. Author: Nicholas Hidalgo

select
    benchmark_id,
    benchmark_date,
    return
from {{ source('bronze', 'raw_benchmarks') }}
