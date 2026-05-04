CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE IF NOT EXISTS bronze.raw_security_master (
    sec_id       TEXT        NOT NULL,
    ticker       TEXT,
    asset_class  TEXT,
    sector       TEXT,
    rating       TEXT,
    maturity     DATE,
    issue_date   DATE,
    CONSTRAINT pk_raw_security_master PRIMARY KEY (sec_id)
);

CREATE TABLE IF NOT EXISTS bronze.raw_positions (
    portfolio_id   TEXT           NOT NULL,
    sec_id         TEXT           NOT NULL,
    position_date  DATE           NOT NULL,
    market_value   NUMERIC(18,4),
    par_value      NUMERIC(18,4),
    weight         NUMERIC(10,6),
    CONSTRAINT pk_raw_positions PRIMARY KEY (portfolio_id, sec_id, position_date)
);

CREATE TABLE IF NOT EXISTS bronze.raw_prices (
    sec_id      TEXT           NOT NULL,
    price_date  DATE           NOT NULL,
    price       NUMERIC(18,6),
    source      TEXT,
    CONSTRAINT pk_raw_prices PRIMARY KEY (sec_id, price_date)
);

CREATE TABLE IF NOT EXISTS bronze.raw_benchmarks (
    benchmark_id    TEXT           NOT NULL,
    benchmark_date  DATE           NOT NULL,
    return          NUMERIC(14,8),
    CONSTRAINT pk_raw_benchmarks PRIMARY KEY (benchmark_id, benchmark_date)
);

CREATE TABLE IF NOT EXISTS bronze.raw_ratings (
    sec_id       TEXT  NOT NULL,
    rating_date  DATE  NOT NULL,
    rating       TEXT,
    agency       TEXT  NOT NULL,
    CONSTRAINT pk_raw_ratings PRIMARY KEY (sec_id, rating_date, agency)
);

CREATE TABLE IF NOT EXISTS bronze.raw_stress_scenarios (
    scenario_id  TEXT           NOT NULL,
    factor       TEXT           NOT NULL,
    shock_pct    NUMERIC(10,4),
    CONSTRAINT pk_raw_stress_scenarios PRIMARY KEY (scenario_id, factor)
);
