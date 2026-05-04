-- Staging passthrough for bronze.raw_prices. Author: Nicholas Hidalgo

select
    sec_id,
    price_date,
    price,
    source
from {{ source('bronze', 'raw_prices') }}
