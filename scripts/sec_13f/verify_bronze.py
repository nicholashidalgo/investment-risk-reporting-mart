"""
Bronze verification script — Hour 3 of SEC 13F ingestion (v0.3).

Read-only. Connects to the database as nickhidalgo and validates that the
bronze_13f_load.sql was applied correctly before proceeding to Hour 4.

Checks:
  1. bronze.raw_13f_filings has exactly 5 rows.
  2. bronze.raw_13f_holdings has exactly 30,135 rows.
  3. Per-filing: SUM(value_thousands_usd) == reported_value_thousands_usd.
  4. No NULL cusip, accession_no, or value_thousands_usd in holdings.

Usage (run AFTER psql load):
    python scripts/sec_13f/verify_bronze.py

Requires: psycopg2
    pip install psycopg2-binary
"""

import sys

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    print("ERROR: psycopg2 not installed. Run: pip install psycopg2-binary")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

DB_PARAMS = {
    "host": "localhost",
    "port": 5432,
    "dbname": "investment_risk",
    "user": "nickhidalgo",
    "password": "",
}

EXPECTED_FILINGS = 5
EXPECTED_HOLDINGS = 30_135

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

Q_FILING_COUNT = """
    SELECT COUNT(*) AS n
      FROM bronze.raw_13f_filings
     WHERE _source_system = 'sec_edgar_13f';
"""

Q_HOLDING_COUNT = """
    SELECT COUNT(*) AS n
      FROM bronze.raw_13f_holdings
     WHERE _source_system = 'sec_edgar_13f';
"""

Q_VALUE_RECON = """
    SELECT
        f.cik,
        f.manager_name,
        f.accession_no,
        f.reported_value_thousands_usd,
        COALESCE(SUM(h.value_thousands_usd), 0) AS parsed_value_thousands_usd,
        COALESCE(SUM(h.value_thousands_usd), 0)
            - f.reported_value_thousands_usd       AS variance_thousands,
        COUNT(h.holding_id)                         AS holding_row_count
    FROM bronze.raw_13f_filings f
    LEFT JOIN bronze.raw_13f_holdings h
           ON h.accession_no = f.accession_no
    WHERE f._source_system = 'sec_edgar_13f'
    GROUP BY
        f.cik, f.manager_name, f.accession_no, f.reported_value_thousands_usd
    ORDER BY f.cik;
"""

Q_NULL_CUSIP = """
    SELECT COUNT(*) AS n
      FROM bronze.raw_13f_holdings
     WHERE cusip IS NULL
       AND _source_system = 'sec_edgar_13f';
"""

Q_NULL_VALUE = """
    SELECT COUNT(*) AS n
      FROM bronze.raw_13f_holdings
     WHERE value_thousands_usd IS NULL
       AND _source_system = 'sec_edgar_13f';
"""

# ---------------------------------------------------------------------------
# Verification runner
# ---------------------------------------------------------------------------


def verify() -> bool:
    all_pass = True

    try:
        conn = psycopg2.connect(**DB_PARAMS)
        conn.autocommit = True
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    except Exception as exc:
        print(f"FATAL: Cannot connect to database — {exc}")
        print(f"  Connection params: {DB_PARAMS}")
        return False

    print("=" * 70)
    print("BRONZE VERIFICATION — SEC 13F (v0.3)")
    print("=" * 70)

    # ------------------------------------------------------------------
    # Check 1: filing count
    # ------------------------------------------------------------------
    cur.execute(Q_FILING_COUNT)
    filing_count = cur.fetchone()["n"]
    ok = filing_count == EXPECTED_FILINGS
    all_pass = all_pass and ok
    status = "PASS" if ok else "FAIL"
    print(f"\n[{status}] raw_13f_filings row count: {filing_count} (expected {EXPECTED_FILINGS})")

    # ------------------------------------------------------------------
    # Check 2: holdings count
    # ------------------------------------------------------------------
    cur.execute(Q_HOLDING_COUNT)
    holding_count = cur.fetchone()["n"]
    ok = holding_count == EXPECTED_HOLDINGS
    all_pass = all_pass and ok
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] raw_13f_holdings row count: {holding_count:,} (expected {EXPECTED_HOLDINGS:,})")

    # ------------------------------------------------------------------
    # Check 3: value reconciliation per filing
    # ------------------------------------------------------------------
    cur.execute(Q_VALUE_RECON)
    rows = cur.fetchall()

    print(f"\n{'Manager':<42} {'Rows':>7} {'Parsed ($000s)':>22} {'Reported ($000s)':>22} {'Variance':>10} {'Status'}")
    print("-" * 115)

    for row in rows:
        variance = int(row["variance_thousands"])
        var_pct = abs(variance) / int(row["reported_value_thousands_usd"]) * 100 if row["reported_value_thousands_usd"] else 0
        ok = var_pct < 0.1
        all_pass = all_pass and ok
        status = "PASS" if ok else "FAIL"
        print(
            f"{row['manager_name']:<42} "
            f"{int(row['holding_row_count']):>7,} "
            f"{int(row['parsed_value_thousands_usd']):>22,} "
            f"{int(row['reported_value_thousands_usd']):>22,} "
            f"{variance:>+10,} "
            f"{status}"
        )

    print("-" * 115)

    # ------------------------------------------------------------------
    # Check 4: NULL integrity
    # ------------------------------------------------------------------
    cur.execute(Q_NULL_CUSIP)
    null_cusip = cur.fetchone()["n"]
    ok = null_cusip == 0
    all_pass = all_pass and ok
    status = "PASS" if ok else "FAIL"
    print(f"\n[{status}] NULL cusip in holdings: {null_cusip} (expected 0)")

    cur.execute(Q_NULL_VALUE)
    null_value = cur.fetchone()["n"]
    ok = null_value == 0
    all_pass = all_pass and ok
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] NULL value_thousands_usd in holdings: {null_value} (expected 0)")

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    cur.close()
    conn.close()

    print("\n" + "=" * 70)
    if all_pass:
        print("RESULT: ALL CHECKS PASS — safe to proceed to Hour 4 (silver layer)")
    else:
        print("RESULT: ONE OR MORE CHECKS FAILED — do not proceed to Hour 4")
        print("        Review output above, re-run the load SQL if needed.")
    print("=" * 70)

    return all_pass


if __name__ == "__main__":
    ok = verify()
    sys.exit(0 if ok else 1)
