-- Security dimension: unified view of all securities from yfinance and SEC 13F.
-- Grain: one row per sec_id (natural key).
--
-- v0.3 extension: added cusip column and 13F-sourced securities.
-- Three populations:
--   1. yfinance equities/benchmarks — sec_id = ticker, cusip from seed lookup
--   2. yfinance synthetic bonds       — sec_id = BOND_NNN, cusip = null (no CUSIP exists)
--   3. 13F-only securities            — sec_id = '13F_' || cusip, cusip from filing
--
-- The CUSIP seed (seeds/yfinance_to_cusip.csv) maps the 13 real tickers to their
-- CUSIPs as confirmed from SEC 13F filing data. Synthetic bonds have no CUSIP.
--
-- asset_class derivation for 13F securities: the 13F Information Table does not
-- carry a standardized asset class field. We derive from title_of_class:
--   - contains 'COM' → 'Equity'
--   - contains 'SH' or 'ETF' → 'Equity'
--   - contains 'NOTE', 'BOND', 'DBT', 'DEB' → 'Fixed Income'
--   - otherwise → 'Equity'  (13F-HR holdings are predominantly equity)
-- This derivation is intentionally conservative; unknown cases default to Equity
-- because 13F-HR is primarily an equity holdings disclosure form.

with yfinance_securities as (

    select
        s.sec_id,
        s.ticker,
        c.cusip,
        case
            when s.sec_id in ('SPY', 'AGG') then 'Benchmark'
            else s.asset_class
        end                             as asset_class,
        s.sector,
        s.maturity,
        s.issue_date,
        s.rating,
        'yfinance'                      as _source_system
    from {{ ref('stg_security_master') }} s
    left join {{ ref('yfinance_to_cusip') }} c on c.ticker = s.ticker

),

-- Deduplicate 13F holdings to one row per CUSIP: take the most-reported name
-- and most common title_of_class. Exclude CUSIPs already covered by yfinance.
-- Two-step: count first, then pick the modal name per CUSIP with distinct on.
thirteenf_counted as (

    select
        cusip,
        name_of_issuer,
        title_of_class,
        count(*) as n
    from {{ source('bronze', 'raw_13f_holdings') }}
    where cusip not in (
        select cusip
        from {{ ref('yfinance_to_cusip') }}
        where cusip is not null
    )
    group by cusip, name_of_issuer, title_of_class

),

thirteenf_cusips as (

    select distinct on (cusip)
        cusip,
        name_of_issuer,
        title_of_class
    from thirteenf_counted
    order by cusip, n desc, name_of_issuer

),

thirteenf_securities as (

    select
        '13F_' || cusip                 as sec_id,
        null::text                      as ticker,
        cusip,
        -- asset_class derivation from title_of_class (see header comment)
        case
            when upper(title_of_class) similar to '%(NOTE|BOND|DBT|DEB|PREF|CONV)%'
                then 'Fixed Income'
            else 'Equity'
        end                             as asset_class,
        null::text                      as sector,
        null::date                      as maturity,
        null::date                      as issue_date,
        null::text                      as rating,
        'sec_13f'                       as _source_system
    from thirteenf_cusips

),

latest_rating as (

    select distinct on (sec_id)
        sec_id,
        rating       as latest_rating,
        agency       as latest_rating_agency,
        rating_date  as latest_rating_date
    from {{ ref('stg_ratings') }}
    order by sec_id, rating_date desc, agency

),

-- Union yfinance + 13F-only securities, then resolve latest credit rating
all_securities as (

    select * from yfinance_securities
    union all
    select * from thirteenf_securities

)

select
    s.sec_id,
    s.ticker,
    s.cusip,
    s.asset_class,
    s.sector,
    s.maturity,
    s.issue_date,
    coalesce(r.latest_rating, s.rating)  as rating,
    r.latest_rating_agency,
    r.latest_rating_date,
    current_timestamp                    as _ingested_at,
    s._source_system
from all_securities s
left join latest_rating r using (sec_id)
