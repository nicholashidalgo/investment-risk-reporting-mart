-- Surfaces holdings where value_thousands_usd = 0 OR shares = 0.
-- These are valid SEC filings, not data errors:
--   - value rounds to zero when a position is < $500 (filed in thousands)
--   - shares round to zero for fractional-share positions
-- Used for transparency and auditability; does not block pipeline.

select
    mgr.manager_name,
    h.security_id,
    s.cusip,
    h.value_thousands_usd,
    h.shares,
    h.principal_amount,
    case
        when h.value_thousands_usd = 0 and h.shares = 0
            then 'fully_rounded_to_zero'
        when h.shares = 0 and h.value_thousands_usd > 0
            then 'fractional_shares_rounded'
        when h.value_thousands_usd = 0 and coalesce(h.shares, 0) > 0
            then 'value_rounded_to_zero'
        else 'other'
    end                         as anomaly_type
from {{ ref('fct_manager_holding') }} h
inner join {{ ref('dim_investment_manager') }} mgr
    on mgr.manager_id = h.manager_id
inner join {{ ref('dim_security') }} s
    on s.sec_id = h.security_id
where h.value_thousands_usd = 0
   or h.shares = 0
