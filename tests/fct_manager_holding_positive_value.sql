-- Singular test: value_thousands_usd must not be negative.
-- Zero is permitted: small positions round to zero in thousands-USD units
-- (e.g. a $400 position = 0 thousands). These are valid SEC filings captured
-- in recon.recon_zero_value_holdings for visibility. Negative values only
-- indicate parsing corruption and must never reach silver.

select
    holding_id,
    manager_id,
    security_id,
    period_of_report,
    value_thousands_usd
from {{ ref('fct_manager_holding') }}
where value_thousands_usd < 0
