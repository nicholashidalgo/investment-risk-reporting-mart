-- DDL for SEC 13F bronze landing tables
-- Part of v0.3 SEC 13F ingestion
-- Run once against: psql -U nickhidalgo -d investment_risk -f sql/ddl/bronze_13f.sql
--
-- These tables are additive — they do not touch any existing bronze tables.
-- Safe to re-run: all objects use IF NOT EXISTS / CREATE INDEX IF NOT EXISTS.

-- ---------------------------------------------------------------------------
-- raw_13f_filings
-- Grain: one row per 13F-HR filing (accession_no is the natural primary key)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bronze.raw_13f_filings (
    cik                            TEXT        NOT NULL,
    manager_name                   TEXT        NOT NULL,
    accession_no                   TEXT        NOT NULL,
    period_of_report               DATE        NOT NULL,
    filed_date                     DATE        NOT NULL,
    primary_doc_url                TEXT        NOT NULL,
    reported_value_thousands_usd   BIGINT      NOT NULL,
    entry_count                    INTEGER     NOT NULL,
    _ingested_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    _source_system                 TEXT        NOT NULL DEFAULT 'sec_edgar_13f',

    CONSTRAINT pk_raw_13f_filings PRIMARY KEY (accession_no)
);

COMMENT ON TABLE bronze.raw_13f_filings IS
    'One row per SEC 13F-HR filing. Grain: accession_no. '
    'reported_value_thousands_usd is the tableValueTotal from the cover page XML '
    '(same unit as value_thousands_usd in raw_13f_holdings). '
    'Used as the reconciliation reference in recon.recon_13f_filing_totals.';

COMMENT ON COLUMN bronze.raw_13f_filings.reported_value_thousands_usd IS
    'tableValueTotal from the 13F cover page XML, in thousands of USD. '
    'Must equal SUM(raw_13f_holdings.value_thousands_usd) for the same accession_no.';

-- ---------------------------------------------------------------------------
-- raw_13f_holdings
-- Grain: one row per holding entry in the Information Table XML
-- Natural grain per the SEC schema: (accession_no, cusip, ssh_prnamt_type, put_call)
-- A surrogate holding_id is added for simple FK references from silver.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bronze.raw_13f_holdings (
    holding_id              BIGSERIAL   NOT NULL,
    accession_no            TEXT        NOT NULL,
    cik                     TEXT        NOT NULL,
    period_of_report        DATE        NOT NULL,
    name_of_issuer          TEXT        NOT NULL,
    title_of_class          TEXT        NOT NULL,
    cusip                   TEXT        NOT NULL,
    value_thousands_usd     BIGINT      NOT NULL,
    ssh_prnamt              BIGINT      NOT NULL,
    ssh_prnamt_type         TEXT        NOT NULL,
    investment_discretion   TEXT,
    voting_authority_sole   BIGINT,
    voting_authority_shared BIGINT,
    voting_authority_none   BIGINT,
    put_call                TEXT,
    other_manager           TEXT,
    _ingested_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    _source_system          TEXT        NOT NULL DEFAULT 'sec_edgar_13f',

    CONSTRAINT pk_raw_13f_holdings      PRIMARY KEY (holding_id),
    CONSTRAINT fk_raw_13f_holdings_filing
        FOREIGN KEY (accession_no) REFERENCES bronze.raw_13f_filings (accession_no)
);

COMMENT ON TABLE bronze.raw_13f_holdings IS
    'One row per holding line in a 13F-HR Information Table XML. '
    'value_thousands_usd is the raw filed value (in thousands of USD). '
    'Multiply by 1000 to get value_usd for the silver fact table. '
    'Natural grain: (accession_no, cusip, ssh_prnamt_type, put_call). '
    'holding_id is a surrogate for silver FK references only.';

COMMENT ON COLUMN bronze.raw_13f_holdings.value_thousands_usd IS
    'Market value as filed in the Information Table XML, in thousands of USD. '
    'Do NOT use this column directly in value calculations — multiply by 1000 '
    'to get value_usd. This unit is preserved from the raw filing to support '
    'exact reconciliation against reported_value_thousands_usd in raw_13f_filings.';

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS ix_raw_13f_holdings_cusip
    ON bronze.raw_13f_holdings (cusip);

CREATE INDEX IF NOT EXISTS ix_raw_13f_holdings_cik_period
    ON bronze.raw_13f_holdings (cik, period_of_report);

CREATE INDEX IF NOT EXISTS ix_raw_13f_holdings_accession_no
    ON bronze.raw_13f_holdings (accession_no);
