-- Current-state view over dim_security_history filtered to is_current = true.
-- Use this model for all fact-table joins that need the latest security attributes.
-- For historical or point-in-time queries, join dim_security_history on
-- valid_from <= snapshot_date AND (valid_to > snapshot_date OR valid_to IS NULL).

{{
    config(materialized='view')
}}

select
    security_key,
    sec_id,
    ticker,
    asset_class,
    sector,
    maturity,
    issue_date,
    rating,
    latest_rating_agency,
    latest_rating_date,
    valid_from,
    _ingested_at,
    _source_system
from {{ ref('dim_security_history') }}
where is_current = true
