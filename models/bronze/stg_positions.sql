-- Staging passthrough for bronze.raw_positions. Author: Nicholas Hidalgo

select
    portfolio_id,
    sec_id,
    position_date,
    market_value,
    par_value,
    weight
from {{ source('bronze', 'raw_positions') }}
