-- Staging passthrough for bronze.raw_security_master. Author: Nicholas Hidalgo

select
    sec_id,
    ticker,
    asset_class,
    sector,
    rating,
    maturity,
    issue_date
from {{ source('bronze', 'raw_security_master') }}
