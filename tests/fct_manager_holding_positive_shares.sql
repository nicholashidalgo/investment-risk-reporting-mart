-- Singular test: when shares is not null, it must not be negative.
-- Zero is permitted: fractional share positions can round to zero integer shares
-- while still carrying a non-zero value. These are valid SEC filings captured
-- in recon.recon_zero_value_holdings for visibility. Negative share counts
-- only indicate corrupt data and must never reach silver.

select
    holding_id,
    manager_id,
    security_id,
    period_of_report,
    shares
from {{ ref('fct_manager_holding') }}
where shares is not null
  and shares < 0
