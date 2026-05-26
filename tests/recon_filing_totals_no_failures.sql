-- Singular test: recon_filing_totals_reconciliation must have zero FAIL rows.
-- Any FAIL means the bronze holdings sum diverged from the SEC cover-page
-- reported total by >= 0.001%, indicating a parsing or ingestion error.
-- All 5 Q4 2025 filings reconciled to exact match (Wellington: $1,000 rounding)
-- during the Hour 2 parse check; any future FAIL is a regression.

select
    cik,
    manager_name,
    accession_no,
    period_of_report,
    reported_value_thousands_usd,
    silver_sum_value_thousands_usd,
    variance_thousands_usd,
    variance_pct,
    status
from {{ ref('recon_filing_totals_reconciliation') }}
where status = 'FAIL'
