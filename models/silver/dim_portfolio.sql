-- Portfolio dimension: one row per distinct portfolio_id. Author: Nicholas Hidalgo

select distinct
    portfolio_id
from {{ ref('stg_positions') }}
