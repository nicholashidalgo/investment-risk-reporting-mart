-- Date spine covering full range of position and price dates. Author: Nicholas Hidalgo

with date_bounds as (
    select
        least(
            min(position_date),
            (select min(price_date) from {{ ref('stg_prices') }})
        ) as min_date,
        greatest(
            max(position_date),
            (select max(price_date) from {{ ref('stg_prices') }})
        ) as max_date
    from {{ ref('stg_positions') }}
),

spine as (
    select
        generate_series(min_date, max_date, interval '1 day')::date as date_day
    from date_bounds
)

select
    date_day,
    extract(year  from date_day)::int                          as year,
    extract(quarter from date_day)::int                        as quarter,
    extract(month from date_day)::int                          as month,
    extract(week  from date_day)::int                          as week_of_year,
    extract(dow   from date_day)::int                          as day_of_week,
    to_char(date_day, 'Month')                                 as month_name,
    case when extract(dow from date_day) in (0, 6) then true
         else false end                                        as is_weekend
from spine
