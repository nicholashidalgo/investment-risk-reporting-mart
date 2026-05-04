-- Staging passthrough for bronze.raw_stress_scenarios. Author: Nicholas Hidalgo

select
    scenario_id,
    factor,
    shock_pct
from {{ source('bronze', 'raw_stress_scenarios') }}
