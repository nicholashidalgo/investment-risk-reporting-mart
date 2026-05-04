-- Staging passthrough for bronze.raw_ratings. Author: Nicholas Hidalgo

select
    sec_id,
    rating_date,
    rating,
    agency
from {{ source('bronze', 'raw_ratings') }}
