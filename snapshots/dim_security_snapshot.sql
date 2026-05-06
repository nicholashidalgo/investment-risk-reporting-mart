-- strategy: check — raw_security_master has no updated_at column; dbt compares all tracked attribute columns on each snapshot run to detect changes.

{% snapshot dim_security_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='sec_id',
        strategy='check',
        check_cols=['ticker', 'asset_class', 'sector', 'rating', 'maturity', 'issue_date']
    )
}}

select
    sec_id,
    ticker,
    asset_class,
    sector,
    rating,
    maturity,
    issue_date
from {{ source('bronze', 'raw_security_master') }}

{% endsnapshot %}
