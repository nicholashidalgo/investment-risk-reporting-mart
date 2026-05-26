"""
Bronze loader — Hour 3 of SEC 13F ingestion (v0.3).

Reads filing_metadata.json and all _parsed/*_holdings.json files.
Generates a single idempotent SQL script: sql/loads/bronze_13f_load.sql.

Idempotency strategy:
  - raw_13f_filings:  ON CONFLICT (accession_no) DO NOTHING
  - raw_13f_holdings: DELETE all holdings for the accession_no, then re-insert.
    This handles re-runs after partial failures without leaving partial data.
    The DELETE is wrapped in the same transaction as the INSERT block.

Does NOT connect to the database. Does NOT execute SQL.
Nicholas runs: psql -U nickhidalgo -d investment_risk -f sql/loads/bronze_13f_load.sql

Usage:
    python scripts/sec_13f/bronze_loader.py
"""

import json
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = REPO_ROOT / "data" / "raw" / "sec_13f"
METADATA_PATH = RAW_DIR / "_index" / "filing_metadata.json"
PARSED_DIR = RAW_DIR / "_parsed"
OUT_PATH = REPO_ROOT / "sql" / "loads" / "bronze_13f_load.sql"

# ---------------------------------------------------------------------------
# SQL helpers
# ---------------------------------------------------------------------------


def _sq(val) -> str:
    """Render a Python value as a SQL literal, single-quoted with escaping."""
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, (int, float)):
        return str(val)
    # String: escape single quotes by doubling them
    escaped = str(val).replace("'", "''")
    return f"'{escaped}'"


def _filing_insert(f: dict) -> str:
    """One INSERT ... ON CONFLICT DO NOTHING for a single filing row."""
    return (
        "INSERT INTO bronze.raw_13f_filings\n"
        "    (cik, manager_name, accession_no, period_of_report, filed_date,\n"
        "     primary_doc_url, reported_value_thousands_usd, entry_count)\n"
        "VALUES\n"
        f"    ({_sq(f['cik'])}, {_sq(f['manager_name'])}, {_sq(f['accession_no'])},\n"
        f"     {_sq(f['period_of_report'])}::date, {_sq(f['filed_date'])}::date,\n"
        f"     {_sq(f['info_table_url'])},\n"
        f"     {_sq(f['table_value_total_thousands'])}, {_sq(f['table_entry_total'])})\n"
        "ON CONFLICT (accession_no) DO NOTHING;"
    )


def _holdings_block(accession_no: str, holdings: list[dict]) -> str:
    """
    DELETE + batched INSERT for all holdings in one accession.

    Strategy: DELETE existing rows for this accession_no first, then insert all.
    This makes re-runs safe: no duplicates, no partial loads left over from a
    prior failed run. The whole block runs inside the outer BEGIN/COMMIT.
    """
    lines = [
        f"-- Holdings for {accession_no} ({len(holdings):,} rows)",
        f"DELETE FROM bronze.raw_13f_holdings WHERE accession_no = {_sq(accession_no)};",
    ]

    if not holdings:
        return "\n".join(lines)

    # Emit in batches of 500 to keep individual statements manageable
    BATCH = 500
    for batch_start in range(0, len(holdings), BATCH):
        batch = holdings[batch_start : batch_start + BATCH]
        rows = []
        for h in batch:
            rows.append(
                f"    ({_sq(h['accession_no'])}, {_sq(h['cik'])},\n"
                f"     {_sq(h['period_of_report'])}::date,\n"
                f"     {_sq(h['name_of_issuer'])}, {_sq(h['title_of_class'])},\n"
                f"     {_sq(h['cusip'])},\n"
                f"     {_sq(h['value_filed_thousands'])},\n"
                f"     {_sq(h['ssh_prnamt'])}, {_sq(h['ssh_prnamt_type'])},\n"
                f"     {_sq(h['investment_discretion'])},\n"
                f"     {_sq(h['voting_authority_sole'])},\n"
                f"     {_sq(h['voting_authority_shared'])},\n"
                f"     {_sq(h['voting_authority_none'])},\n"
                f"     {_sq(h['put_call'])}, {_sq(h['other_manager'])})"
            )

        lines.append(
            "INSERT INTO bronze.raw_13f_holdings\n"
            "    (accession_no, cik, period_of_report,\n"
            "     name_of_issuer, title_of_class, cusip,\n"
            "     value_thousands_usd,\n"
            "     ssh_prnamt, ssh_prnamt_type,\n"
            "     investment_discretion,\n"
            "     voting_authority_sole, voting_authority_shared, voting_authority_none,\n"
            "     put_call, other_manager)\n"
            "VALUES\n"
            + ",\n".join(rows)
            + ";"
        )

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def build_load_sql() -> None:
    metadata = json.loads(METADATA_PATH.read_text())
    filings = metadata["filings"]

    # Load all parsed holdings files, keyed by accession_no
    parsed: dict[str, list[dict]] = {}
    total_holdings = 0
    for path in sorted(PARSED_DIR.glob("*_holdings.json")):
        doc = json.loads(path.read_text())
        acc = doc["accession_no"]
        parsed[acc] = doc["holdings"]
        total_holdings += len(doc["holdings"])

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    lines: list[str] = [
        "-- =============================================================================",
        "-- SEC 13F Bronze Load Script",
        "-- Generated by: scripts/sec_13f/bronze_loader.py",
        f"-- Generated at: {generated_at}",
        f"-- Filings:      {len(filings)}",
        f"-- Holdings:     {total_holdings:,}",
        "-- Target DB:    investment_risk (local PostgreSQL)",
        "-- Run as:       psql -U nickhidalgo -d investment_risk -f sql/loads/bronze_13f_load.sql",
        "-- Idempotent:   YES — safe to re-run. Holdings are DELETE+INSERT per accession.",
        "-- =============================================================================",
        "",
        "\\set ON_ERROR_STOP on",
        "",
        "BEGIN;",
        "",
        "-- ---------------------------------------------------------------------------",
        "-- Section 1: raw_13f_filings (5 rows, ON CONFLICT DO NOTHING)",
        "-- ---------------------------------------------------------------------------",
        "",
    ]

    for f in filings:
        lines.append(_filing_insert(f))
        lines.append("")

    lines += [
        "-- ---------------------------------------------------------------------------",
        f"-- Section 2: raw_13f_holdings ({total_holdings:,} rows, DELETE+INSERT per filing)",
        "-- ---------------------------------------------------------------------------",
        "",
    ]

    for f in filings:
        acc = f["accession_no"]
        holdings = parsed.get(acc, [])
        lines.append(_holdings_block(acc, holdings))
        lines.append("")

    lines += [
        "COMMIT;",
        "",
        "-- ---------------------------------------------------------------------------",
        "-- Quick row-count sanity check (informational, not a hard assertion)",
        "-- ---------------------------------------------------------------------------",
        "",
        "SELECT 'raw_13f_filings' AS table_name, COUNT(*) AS row_count",
        "  FROM bronze.raw_13f_filings",
        " WHERE _source_system = 'sec_edgar_13f'",
        "UNION ALL",
        "SELECT 'raw_13f_holdings', COUNT(*)",
        "  FROM bronze.raw_13f_holdings",
        " WHERE _source_system = 'sec_edgar_13f';",
        "",
    ]

    sql_text = "\n".join(lines)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(sql_text, encoding="utf-8")

    size_kb = OUT_PATH.stat().st_size / 1024
    print(f"Load SQL written to: {OUT_PATH}")
    print(f"  Filings rows:  {len(filings)}")
    print(f"  Holdings rows: {total_holdings:,}")
    print(f"  File size:     {size_kb:,.1f} KB")


if __name__ == "__main__":
    build_load_sql()
