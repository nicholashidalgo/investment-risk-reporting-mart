-- Portfolio exposure summary: asset class, sector breakdown, and top-10 concentration at latest position date. Author: Nicholas Hidalgo

with latest_date as (
    select portfolio_id, max(position_date) as position_date
    from {{ ref('fct_position_daily') }}
    group by portfolio_id
),

positions as (
    select f.*
    from {{ ref('fct_position_daily') }} f
    inner join latest_date ld
        on f.portfolio_id = ld.portfolio_id
       and f.position_date = ld.position_date
),

nav as (
    select portfolio_id, position_date, sum(market_value) as total_nav
    from positions
    group by portfolio_id, position_date
),

asset_class_breakdown as (
    select
        p.portfolio_id,
        p.position_date,
        p.asset_class,
        sum(p.market_value)                                    as asset_class_mv,
        sum(p.market_value) / n.total_nav * 100                as asset_class_pct
    from positions p
    inner join nav n using (portfolio_id, position_date)
    group by p.portfolio_id, p.position_date, p.asset_class, n.total_nav
),

sector_breakdown as (
    select
        p.portfolio_id,
        p.position_date,
        p.sector,
        sum(p.market_value)                                    as sector_mv,
        sum(p.market_value) / n.total_nav * 100                as sector_pct
    from positions p
    inner join nav n using (portfolio_id, position_date)
    group by p.portfolio_id, p.position_date, p.sector, n.total_nav
),

top10 as (
    select
        p.portfolio_id,
        p.position_date,
        sum(p.market_value) as top10_mv
    from (
        select
            portfolio_id,
            position_date,
            market_value,
            row_number() over (
                partition by portfolio_id, position_date
                order by market_value desc
            ) as rnk
        from positions
    ) p
    where p.rnk <= 10
    group by p.portfolio_id, p.position_date
),

final as (
    select
        n.portfolio_id,
        n.position_date,
        n.total_nav,
        t.top10_mv,
        t.top10_mv / n.total_nav * 100                         as top10_concentration_pct,
        (
            select json_agg(
                json_build_object(
                    'asset_class', asset_class,
                    'mv', asset_class_mv,
                    'pct', round(asset_class_pct::numeric, 4)
                ) order by asset_class_mv desc
            )
            from asset_class_breakdown ab
            where ab.portfolio_id = n.portfolio_id
              and ab.position_date = n.position_date
        )                                                       as asset_class_breakdown,
        (
            select json_agg(
                json_build_object(
                    'sector', sector,
                    'mv', sector_mv,
                    'pct', round(sector_pct::numeric, 4)
                ) order by sector_mv desc
            )
            from sector_breakdown sb
            where sb.portfolio_id = n.portfolio_id
              and sb.position_date = n.position_date
        )                                                       as sector_breakdown
    from nav n
    inner join top10 t using (portfolio_id, position_date)
)

select * from final
