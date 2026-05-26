"""
EDGAR Submissions API client — Hour 1 of SEC 13F ingestion (v0.3).

Responsibilities:
  1. Fetch submissions JSON for each manager CIK from the EDGAR submissions API.
  2. Parse recent.filings to find 13F-HR filings with period_of_report == TARGET_PERIOD.
  3. Handle amendment preference: for a given (CIK, period_of_report), take the filing
     with the latest filed_date (covers 13F-HR/A amendments superseding originals).
  4. Return a list of filing metadata dicts.
  5. Cache the result to data/raw/sec_13f/_index/filing_metadata.json.

Does NOT write to the database. Does NOT fetch XML documents (that is Hour 2).

Usage:
    python scripts/sec_13f/edgar_client.py

Output:
    - Verification table printed to stdout
    - data/raw/sec_13f/_index/filing_metadata.json written to disk
"""

import json
import ssl
import time
import urllib.request
from datetime import date
from pathlib import Path

# macOS ships without the default CA bundle in some Python installs.
# The SEC EDGAR endpoints are public government servers; disabling cert
# verification is acceptable here (same as curl without --cacert).
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE

from managers import MANAGERS

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TARGET_PERIOD = "2025-12-31"
USER_AGENT = "Nicholas Hidalgo contact@nicholashidalgo.com"
SLEEP_BETWEEN_REQUESTS = 0.15  # SEC rate limit: 10 req/s; 0.15s gives ~6.7 req/s

SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik}.json"
EFTS_SEARCH_URL = "https://efts.sec.gov/LATEST/search-index?q=%22{accession_no}%22"
ARCHIVES_BASE = "https://www.sec.gov/Archives/edgar/data/{cik_int}/{accession_nodash}/{doc}"

REPO_ROOT = Path(__file__).resolve().parents[2]
INDEX_DIR = REPO_ROOT / "data" / "raw" / "sec_13f" / "_index"
METADATA_PATH = INDEX_DIR / "filing_metadata.json"


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _get_json(url: str, retries: int = 3) -> dict:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30, context=_SSL_CTX) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception:
            if attempt < retries - 1:
                time.sleep(1.0)
            else:
                raise


def _get_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30, context=_SSL_CTX) as resp:
        return resp.read().decode("utf-8")


# ---------------------------------------------------------------------------
# Submissions parsing
# ---------------------------------------------------------------------------

def _accession_no_with_dashes(raw: str) -> str:
    """Convert '0000093751-25-000123' or '000009375125000123' to dashed form."""
    raw = raw.replace("-", "")
    return f"{raw[:10]}-{raw[10:12]}-{raw[12:]}"


def _accession_nodash(accession_no: str) -> str:
    return accession_no.replace("-", "")


def fetch_13f_filings_for_cik(cik: str) -> tuple[str, list[dict]]:
    """
    Fetch the EDGAR submissions JSON for a CIK, return (entity_name, filings_list).

    filings_list entries:
        {cik, manager_name, accession_no, primary_doc, filed_date, period_of_report}

    Returns all 13F-HR / 13F-HR/A filings for the target period. Caller is responsible
    for selecting the preferred amendment (latest filed_date).
    """
    url = SUBMISSIONS_URL.format(cik=cik)
    data = _get_json(url)
    time.sleep(SLEEP_BETWEEN_REQUESTS)

    entity_name: str = data.get("name", "UNKNOWN")
    recent = data.get("filings", {}).get("recent", {})

    forms = recent.get("form", [])
    accessions = recent.get("accessionNumber", [])
    primary_docs = recent.get("primaryDocument", [])
    filed_dates = recent.get("filingDate", [])
    report_dates = recent.get("reportDate", [])

    hits = []
    for i, form in enumerate(forms):
        if form not in ("13F-HR", "13F-HR/A"):
            continue
        rdate = report_dates[i] if i < len(report_dates) else ""
        if rdate != TARGET_PERIOD:
            continue

        raw_accession = accessions[i] if i < len(accessions) else ""
        acc_dashed = _accession_no_with_dashes(raw_accession)
        primary_doc = primary_docs[i] if i < len(primary_docs) else ""
        filed_date = filed_dates[i] if i < len(filed_dates) else ""

        hits.append(
            {
                "cik": cik,
                "manager_name": entity_name,
                "accession_no": acc_dashed,
                "primary_doc": primary_doc,
                "filed_date": filed_date,
                "period_of_report": rdate,
                "form_type": form,
            }
        )

    return entity_name, hits


def discover_info_table_doc(accession_no: str) -> str | None:
    """
    Query the EDGAR full-text search index to find the Information Table document
    filename for a given accession number. Returns just the filename (no path),
    or None if not found.

    Each 13F-HR filing has exactly two documents: the cover (file_type='13F-HR')
    and the Information Table (file_type='INFORMATION TABLE'). The filename varies
    by filing agent (e.g. 'XML_Infotable.xml', '20260217_FMRLLC.xml', etc.).
    """
    url = EFTS_SEARCH_URL.format(accession_no=accession_no)
    try:
        data = _get_json(url)
        time.sleep(SLEEP_BETWEEN_REQUESTS)
        for hit in data.get("hits", {}).get("hits", []):
            src = hit.get("_source", {})
            if src.get("file_type") == "INFORMATION TABLE":
                doc_id = hit.get("_id", "")  # format: "accession_no:filename"
                if ":" in doc_id:
                    return doc_id.split(":", 1)[1]
    except Exception as exc:
        print(f"    WARNING: info table lookup failed for {accession_no}: {exc}")
    return None


def fetch_cover_page_summary(cik: str, accession_no: str) -> dict:
    """
    Fetch the cover page XML (primary_doc.xml) for a filing and parse the
    summaryPage block to extract tableEntryTotal and tableValueTotal.

    Returns a dict with keys: table_entry_total, table_value_total_thousands.
    Both may be None if the fetch or parse fails.
    """
    import xml.etree.ElementTree as ET

    cik_int = int(cik)
    acc_nodash = _accession_nodash(accession_no)
    url = ARCHIVES_BASE.format(cik_int=cik_int, accession_nodash=acc_nodash, doc="primary_doc.xml")
    result = {"table_entry_total": None, "table_value_total_thousands": None}
    try:
        xml_text = _get_text(url)
        time.sleep(SLEEP_BETWEEN_REQUESTS)
        root = ET.fromstring(xml_text)
        ns = {
            "n1": "http://www.sec.gov/edgar/thirteenffiler",
            "com": "http://www.sec.gov/edgar/common",
        }
        summary = root.find(".//n1:summaryPage", ns)
        if summary is None:
            summary = root.find(".//{http://www.sec.gov/edgar/thirteenffiler}summaryPage")
        if summary is not None:
            entry_el = summary.find(".//{http://www.sec.gov/edgar/thirteenffiler}tableEntryTotal")
            value_el = summary.find(".//{http://www.sec.gov/edgar/thirteenffiler}tableValueTotal")
            if entry_el is not None and entry_el.text:
                result["table_entry_total"] = int(entry_el.text.strip())
            if value_el is not None and value_el.text:
                result["table_value_total_thousands"] = int(value_el.text.strip())
    except Exception as exc:
        print(f"    WARNING: cover page fetch failed for {accession_no}: {exc}")
    return result


def _best_filing(hits: list[dict]) -> dict | None:
    """
    From a list of 13F-HR / 13F-HR/A hits for the same (CIK, period),
    return the one with the latest filed_date (amendment preference).
    """
    if not hits:
        return None
    return max(hits, key=lambda r: r["filed_date"])


# ---------------------------------------------------------------------------
# CIK verification
# ---------------------------------------------------------------------------

def verify_and_collect(managers: list[dict]) -> tuple[list[dict], list[dict]]:
    """
    For each manager, fetch submissions, verify entity name, find target filing.

    Returns:
        verification_rows — one row per manager with verification status
        filing_metadata   — one row per manager with the best matching filing
    """
    verification_rows = []
    filing_metadata = []

    for mgr in managers:
        cik = mgr["cik"]
        label = mgr["label"]
        expected = mgr.get("expected_name", "")

        print(f"  Fetching CIK {cik} ({label})...")
        entity_name, hits = fetch_13f_filings_for_cik(cik)

        name_match = expected.upper() in entity_name.upper() or entity_name.upper() in expected.upper()
        filing = _best_filing(hits)

        row = {
            "cik": cik,
            "label": label,
            "entity_name_from_api": entity_name,
            "name_match": "OK" if name_match else "MISMATCH",
            "filings_found": len(hits),
            "selected_accession": filing["accession_no"] if filing else "NONE",
            "selected_filed_date": filing["filed_date"] if filing else "NONE",
            "selected_form_type": filing["form_type"] if filing else "NONE",
        }
        verification_rows.append(row)

        if filing:
            meta = {k: v for k, v in filing.items() if k != "form_type"}

            # Discover the Information Table document filename
            info_doc = discover_info_table_doc(filing["accession_no"])
            meta["info_table_doc"] = info_doc
            if info_doc:
                cik_int = int(cik)
                acc_nodash = _accession_nodash(filing["accession_no"])
                meta["info_table_url"] = ARCHIVES_BASE.format(
                    cik_int=cik_int, accession_nodash=acc_nodash, doc=info_doc
                )
            else:
                meta["info_table_url"] = None

            # Fetch cover page summary for reconciliation reference values
            cover = fetch_cover_page_summary(cik, filing["accession_no"])
            meta.update(cover)

            filing_metadata.append(meta)
        else:
            # No filing found — check if a fallback CIK is configured
            fallback_cik = mgr.get("fallback_cik")
            if fallback_cik:
                print(f"    No filing at primary CIK {cik}; trying fallback {fallback_cik}...")
                fallback_entity, fallback_hits = fetch_13f_filings_for_cik(fallback_cik)
                fallback_filing = _best_filing(fallback_hits)
                if fallback_filing:
                    print(f"    Fallback CIK {fallback_cik} ({fallback_entity}) found filing.")
                    row["name_match"] += f" | FALLBACK HIT ({fallback_cik})"
                    row["selected_accession"] = fallback_filing["accession_no"]
                    row["selected_filed_date"] = fallback_filing["filed_date"]
                    row["selected_form_type"] = fallback_filing["form_type"]
                    row["filings_found"] = len(fallback_hits)
                    meta = {k: v for k, v in fallback_filing.items() if k != "form_type"}
                    meta["cik"] = fallback_cik
                    meta["manager_name"] = fallback_entity
                    info_doc = discover_info_table_doc(fallback_filing["accession_no"])
                    meta["info_table_doc"] = info_doc
                    if info_doc:
                        cik_int = int(fallback_cik)
                        acc_nodash = _accession_nodash(fallback_filing["accession_no"])
                        meta["info_table_url"] = ARCHIVES_BASE.format(
                            cik_int=cik_int, accession_nodash=acc_nodash, doc=info_doc
                        )
                    else:
                        meta["info_table_url"] = None
                    cover = fetch_cover_page_summary(fallback_cik, fallback_filing["accession_no"])
                    meta.update(cover)
                    filing_metadata.append(meta)
                else:
                    print(f"    Fallback CIK {fallback_cik} also had no filings for {TARGET_PERIOD}.")
            else:
                print(f"    WARNING: No 13F-HR filing found for CIK {cik} in period {TARGET_PERIOD}.")

    return verification_rows, filing_metadata


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

def print_verification_table(rows: list[dict], metadata: list[dict]) -> None:
    meta_by_cik = {m["cik"]: m for m in metadata}

    header = (
        f"{'CIK':<12} {'Label':<35} {'API Entity Name':<40} "
        f"{'Match':<8} {'Accession No':<25} {'Filed':>12} {'Info Table Doc':<35} {'Entries':>8} {'Value (000s USD)':>20}"
    )
    sep = "-" * len(header)
    print()
    print("EDGAR CIK VERIFICATION TABLE")
    print(sep)
    print(header)
    print(sep)
    for r in rows:
        m = meta_by_cik.get(r["cik"], {})
        info_doc = m.get("info_table_doc") or "NOT FOUND"
        entries = m.get("table_entry_total", "?")
        val = m.get("table_value_total_thousands", "?")
        val_fmt = f"{val:,}" if isinstance(val, int) else str(val)
        print(
            f"{r['cik']:<12} {r['label']:<35} {r['entity_name_from_api']:<40} "
            f"{r['name_match']:<8} {r['selected_accession']:<25} "
            f"{r['selected_filed_date']:>12} {info_doc:<35} {str(entries):>8} {val_fmt:>20}"
        )
    print(sep)
    print()


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

def cache_filing_metadata(filing_metadata: list[dict]) -> None:
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at": date.today().isoformat(),
        "target_period": TARGET_PERIOD,
        "filing_count": len(filing_metadata),
        "filings": filing_metadata,
    }
    METADATA_PATH.write_text(json.dumps(payload, indent=2))
    print(f"Filing metadata cached to: {METADATA_PATH}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> list[dict]:
    print(f"SEC 13F EDGAR client — target period: {TARGET_PERIOD}")
    print(f"Managers to fetch: {len(MANAGERS)}")
    print()

    verification_rows, filing_metadata = verify_and_collect(MANAGERS)

    print_verification_table(verification_rows, filing_metadata)
    cache_filing_metadata(filing_metadata)

    print(f"\nFilings ready for XML download: {len(filing_metadata)}")
    return filing_metadata


if __name__ == "__main__":
    main()
