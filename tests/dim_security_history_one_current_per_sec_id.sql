-- Singular test: Each sec_id must have exactly one row where is_current = true.
-- Returns rows that violate the invariant. dbt test passes when zero rows are returned.

select
    sec_id,
    count(*) as current_row_count
from {{ ref('dim_security_history') }}
where is_current = true
group by sec_id
having count(*) != 1
