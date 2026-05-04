CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.run_log (
    run_id          SERIAL       NOT NULL,
    run_timestamp   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    model_name      TEXT,
    row_count       INTEGER,
    drift_pct       NUMERIC(10,4),
    lag_days        INTEGER,
    sla_status      TEXT,
    checks_passed   BOOLEAN,
    failure_message TEXT,
    CONSTRAINT pk_run_log PRIMARY KEY (run_id)
);
