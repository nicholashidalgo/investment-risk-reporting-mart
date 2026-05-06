-- Singular test: Two history versions of the same sec_id must not have overlapping valid_from/valid_to ranges.
-- NULL valid_to means "still current" and is treated as far-future for range comparison.
-- Returns rows that violate the invariant. Test passes when zero rows are returned.

select
    a.sec_id,
    a.scd_id as version_a_scd_id,
    a.valid_from as version_a_start,
    a.valid_to as version_a_end,
    b.scd_id as version_b_scd_id,
    b.valid_from as version_b_start,
    b.valid_to as version_b_end
from {{ ref('dim_security_history') }} a
join {{ ref('dim_security_history') }} b
    on a.sec_id = b.sec_id
    and a.scd_id < b.scd_id
where a.valid_from < coalesce(b.valid_to, '9999-12-31'::timestamp)
  and coalesce(a.valid_to, '9999-12-31'::timestamp) > b.valid_from
