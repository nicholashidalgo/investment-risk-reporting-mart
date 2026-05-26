"""
XML Information Table parser — Hour 2 of SEC 13F ingestion (v0.3).

Responsibilities:
  1. Read filing_metadata.json (produced by edgar_client.py in Hour 1).
  2. For each filing, fetch the Information Table XML via its info_table_url.
  3. Cache raw XML to data/raw/sec_13f/{cik}/{accession_no}.xml.
  4. Parse each XML into structured holding records.
  5. Quarantine records with missing CUSIP (do not fail the run).
  6. Log and skip malformed records (missing value or shares).
  7. Write parsed output to data/raw/sec_13f/_parsed/{accession_no}_holdings.json.
  8. Print a value reconciliation table comparing parsed sums to filing-reported totals.

Does NOT write to the database. Does NOT commit. Does NOT run git commands.

Usage:
    python scripts/sec_13f/xml_parser.py
"""

import json
import ssl
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

USER_AGENT = "Nicholas Hidalgo contact@nicholashidalgo.com"
SLEEP_BETWEEN_FETCHES = 0.15

REPO_ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = REPO_ROOT / "data" / "raw" / "sec_13f"
INDEX_DIR = RAW_DIR / "_index"
METADATA_PATH = INDEX_DIR / "filing_metadata.json"
PARSED_DIR = RAW_DIR / "_parsed"
QUARANTINE_DIR = RAW_DIR / "_quarantine"

# SEC 13F Information Table XML namespaces vary by filing.
# Modern filings use the n2 namespace; some older ones use no namespace at all.
# We try both. The namespace URIs we've observed in the wild:
_NS_CANDIDATES = [
    "http://www.sec.gov/edgar/document/thirteenf/informationtable",
    "",  # no namespace
]

# ---------------------------------------------------------------------------
# SSL context
# ---------------------------------------------------------------------------

_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------


def _fetch_url(url: str, retries: int = 3) -> bytes:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=60, context=_SSL_CTX) as resp:
                return resp.read()
        except Exception as exc:
            if attempt < retries - 1:
                print(f"    Retry {attempt + 1}: {exc}")
                time.sleep(1.0)
            else:
                raise


# ---------------------------------------------------------------------------
# XML namespace helpers
# ---------------------------------------------------------------------------


def _find_all_entries(root: ET.Element) -> list[ET.Element]:
    """
    Return all <infoTable> elements regardless of namespace prefix.

    The SEC uses two patterns in 13F filings:
      - Namespaced: <n2:infoTable xmlns:n2="http://www.sec.gov/edgar/...">
      - Bare:       <infoTable>

    We try the namespaced form first, then fall back to a namespace-agnostic
    local-name scan so we never miss entries due to a namespace variant we
    haven't seen before.
    """
    for ns_uri in _NS_CANDIDATES:
        if ns_uri:
            tag = f"{{{ns_uri}}}infoTable"
        else:
            tag = "infoTable"
        entries = root.findall(f".//{tag}")
        if entries:
            return entries

    # Fallback: match on local name only (handles any namespace variant)
    return [el for el in root.iter() if el.tag.split("}")[-1] == "infoTable"]


def _local(tag: str) -> str:
    """Strip namespace URI prefix from an XML tag, returning the local name."""
    return tag.split("}")[-1] if "}" in tag else tag


def _text(entry: ET.Element, local_name: str) -> str | None:
    """
    Extract text from a direct child element by local name, ignoring namespace.
    Returns stripped string or None if element absent or empty.
    """
    for child in entry:
        if _local(child.tag) == local_name:
            return (child.text or "").strip() or None
    return None


def _nested_text(entry: ET.Element, parent_local: str, child_local: str) -> str | None:
    """
    Extract text from a grandchild: entry → parent_local → child_local.

    Handles SEC 13F patterns like:
      <shrsOrPrnAmt><sshPrnamt>…</sshPrnamt></shrsOrPrnAmt>
      <votingAuthority><Sole>…</Sole></votingAuthority>
    """
    for child in entry:
        if _local(child.tag) == parent_local:
            for grandchild in child:
                if _local(grandchild.tag) == child_local:
                    return (grandchild.text or "").strip() or None
    return None


# ---------------------------------------------------------------------------
# Per-entry parsing
# ---------------------------------------------------------------------------


def _parse_entry(
    entry: ET.Element,
    cik: str,
    accession_no: str,
    period_of_report: str,
) -> dict | None:
    """
    Parse one <infoTable> element into a holding record dict.

    Returns None if the record is missing a required field (value or shares),
    indicating it should be skipped as malformed.
    """
    name_of_issuer = _text(entry, "nameOfIssuer")
    title_of_class = _text(entry, "titleOfClass")
    cusip = _text(entry, "cusip")
    value_raw = _text(entry, "value")
    # sshPrnamt and sshPrnamtType live inside <shrsOrPrnAmt> in modern 13F filings
    ssh_prnamt = _nested_text(entry, "shrsOrPrnAmt", "sshPrnamt")
    ssh_prnamt_type = _nested_text(entry, "shrsOrPrnAmt", "sshPrnamtType")
    put_call = _text(entry, "putCall")
    investment_discretion = _text(entry, "investmentDiscretion")
    other_manager = _text(entry, "otherManager")

    # Voting authority lives in a nested block <votingAuthority><Sole>...</Sole>...
    voting_sole = _nested_text(entry, "votingAuthority", "Sole")
    voting_shared = _nested_text(entry, "votingAuthority", "Shared")
    voting_none = _nested_text(entry, "votingAuthority", "None")

    # Required: value and shares — if either is absent or non-numeric, skip
    try:
        value_thousands = int(value_raw) if value_raw is not None else None
    except (ValueError, TypeError):
        value_thousands = None

    try:
        shares = int(ssh_prnamt) if ssh_prnamt is not None else None
    except (ValueError, TypeError):
        shares = None

    if value_thousands is None or shares is None:
        return None  # malformed — caller logs and skips

    return {
        "cik": cik,
        "accession_no": accession_no,
        "period_of_report": period_of_report,
        "name_of_issuer": name_of_issuer,
        "title_of_class": title_of_class,
        "cusip": cusip,
        # value is filed in thousands of USD; multiply by 1000 for value_usd
        "value_usd": value_thousands * 1000,
        "value_filed_thousands": value_thousands,
        "ssh_prnamt": shares,
        "ssh_prnamt_type": ssh_prnamt_type,
        "put_call": put_call,
        "investment_discretion": investment_discretion,
        "other_manager": other_manager,
        "voting_authority_sole": int(voting_sole) if voting_sole else None,
        "voting_authority_shared": int(voting_shared) if voting_shared else None,
        "voting_authority_none": int(voting_none) if voting_none else None,
    }


# ---------------------------------------------------------------------------
# Per-filing parse
# ---------------------------------------------------------------------------


def parse_filing(filing: dict) -> dict:
    """
    Fetch, cache, and parse one filing's Information Table XML.

    Returns a result dict:
        {
            accession_no, manager_name, cik,
            parsed_count, quarantine_count, malformed_count,
            value_usd_sum,           # sum of value_usd from parsed records
            reported_value_thousands, # from filing metadata cover page
            holdings: [...],          # clean records
        }
    """
    cik = filing["cik"]
    accession_no = filing["accession_no"]
    manager_name = filing["manager_name"]
    period_of_report = filing["period_of_report"]
    info_table_url = filing["info_table_url"]
    reported_value_thousands = filing.get("table_value_total_thousands")

    print(f"\n  [{manager_name}] CIK {cik}")
    print(f"    URL: {info_table_url}")

    # ---- Cache dir ----
    cik_dir = RAW_DIR / cik
    cik_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cik_dir / f"{accession_no}.xml"

    # ---- Fetch or load from cache ----
    if cache_path.exists():
        print(f"    Cache hit: {cache_path.name}")
        xml_bytes = cache_path.read_bytes()
    else:
        print(f"    Fetching XML...")
        xml_bytes = _fetch_url(info_table_url)
        cache_path.write_bytes(xml_bytes)
        print(f"    Cached {len(xml_bytes):,} bytes → {cache_path}")
        time.sleep(SLEEP_BETWEEN_FETCHES)

    # ---- Parse ----
    xml_text = xml_bytes.decode("utf-8", errors="replace")
    root = ET.fromstring(xml_text)
    entries = _find_all_entries(root)
    print(f"    Found {len(entries):,} <infoTable> entries in XML")

    holdings = []
    quarantine = []
    malformed_count = 0

    for entry in entries:
        record = _parse_entry(entry, cik, accession_no, period_of_report)

        if record is None:
            malformed_count += 1
            continue

        if not record["cusip"]:
            quarantine.append(record)
            continue

        holdings.append(record)

    # ---- Write quarantine ----
    if quarantine:
        QUARANTINE_DIR.mkdir(parents=True, exist_ok=True)
        qpath = QUARANTINE_DIR / f"{accession_no}_missing_cusip.json"
        qpath.write_text(json.dumps(quarantine, indent=2))
        print(f"    Quarantined {len(quarantine)} missing-CUSIP records → {qpath.name}")

    if malformed_count:
        print(f"    Skipped {malformed_count} malformed records (missing value or shares)")

    # ---- Value sum ----
    value_usd_sum = sum(r["value_usd"] for r in holdings)
    value_usd_sum_with_quarantine = value_usd_sum + sum(r["value_usd"] for r in quarantine)
    # filed_thousands for recon against cover page tableValueTotal (same unit)
    value_filed_thousands_sum = sum(r["value_filed_thousands"] for r in holdings)
    value_filed_thousands_with_quarantine = value_filed_thousands_sum + sum(
        r["value_filed_thousands"] for r in quarantine
    )

    # ---- Write parsed output ----
    PARSED_DIR.mkdir(parents=True, exist_ok=True)
    out_path = PARSED_DIR / f"{accession_no}_holdings.json"
    out_path.write_text(
        json.dumps(
            {
                "accession_no": accession_no,
                "cik": cik,
                "manager_name": manager_name,
                "period_of_report": period_of_report,
                "parsed_count": len(holdings),
                "quarantine_count": len(quarantine),
                "malformed_count": malformed_count,
                "value_usd_sum": value_usd_sum,
                "holdings": holdings,
            },
            indent=2,
        )
    )
    print(f"    Wrote {len(holdings):,} clean holdings → {out_path.name}")

    return {
        "accession_no": accession_no,
        "cik": cik,
        "manager_name": manager_name,
        "parsed_count": len(holdings),
        "quarantine_count": len(quarantine),
        "malformed_count": malformed_count,
        "value_usd_sum": value_usd_sum,
        "value_usd_sum_with_quarantine": value_usd_sum_with_quarantine,
        "value_filed_thousands_with_quarantine": value_filed_thousands_with_quarantine,
        "reported_value_thousands": reported_value_thousands,
        "holdings": holdings,
    }


# ---------------------------------------------------------------------------
# Reconciliation table
# ---------------------------------------------------------------------------


def print_recon_table(results: list[dict]) -> None:
    col = 120
    print()
    print("VALUE RECONCILIATION: parsed sum vs filing-reported total (values in thousands USD)")
    print("-" * col)
    print(
        f"{'Manager':<42} {'Parsed':>8} {'Quar':>6} "
        f"{'Parsed Sum ($000s)':>22} {'Reported ($000s)':>22} {'Variance':>10} {'Status':<8}"
    )
    print("-" * col)

    total_parsed = 0
    total_quarantine = 0
    total_malformed = 0

    for r in results:
        parsed = r["parsed_count"]
        qcount = r["quarantine_count"]
        # Compare at the thousands-USD level (same unit as tableValueTotal)
        val_sum_thousands = r["value_filed_thousands_with_quarantine"]
        reported_thousands = r["reported_value_thousands"]

        if reported_thousands is not None and reported_thousands > 0:
            variance_pct = abs(val_sum_thousands - reported_thousands) / reported_thousands * 100
            status = "PASS" if variance_pct < 0.1 else ("WARN" if variance_pct < 1.0 else "FAIL")
            var_str = f"{variance_pct:.4f}%"
        else:
            status = "NO REF"
            var_str = "N/A"

        reported_str = f"{reported_thousands:,}" if reported_thousands is not None else "N/A"
        print(
            f"{r['manager_name']:<42} {parsed:>8,} {qcount:>6,} "
            f"{val_sum_thousands:>22,} {reported_str:>22} {var_str:>10} {status:<8}"
        )

        total_parsed += parsed
        total_quarantine += qcount
        total_malformed += r["malformed_count"]

    print("-" * col)
    print(
        f"{'TOTAL':<42} {total_parsed:>8,} {total_quarantine:>6,}"
    )
    print()
    print(f"  Expected total records: ~30,135")
    print(f"  Parsed clean:           {total_parsed:,}")
    print(f"  Quarantined (no CUSIP): {total_quarantine:,}")
    print(f"  Malformed (skipped):    {total_malformed:,}")
    print(f"  Total processed:        {total_parsed + total_quarantine + total_malformed:,}")
    print()


# ---------------------------------------------------------------------------
# Sample records
# ---------------------------------------------------------------------------


def print_sample_records(results: list[dict]) -> None:
    print("SAMPLE HOLDING RECORD (first clean record per manager)")
    print("-" * 80)
    for r in results:
        holdings = r["holdings"]
        if not holdings:
            print(f"  [{r['manager_name']}]: no clean holdings")
            continue
        sample = holdings[0]
        print(f"  Manager:     {r['manager_name']}")
        print(f"  CIK:         {sample['cik']}")
        print(f"  Accession:   {sample['accession_no']}")
        print(f"  Issuer:      {sample['name_of_issuer']}")
        print(f"  Class:       {sample['title_of_class']}")
        print(f"  CUSIP:       {sample['cusip']}")
        print(f"  Value USD:   {sample['value_usd']:,}")
        print(f"  Shares:      {sample['ssh_prnamt']:,}  ({sample['ssh_prnamt_type']})")
        print(f"  Discretion:  {sample['investment_discretion']}")
        print(f"  Put/Call:    {sample['put_call']}")
        print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> list[dict]:
    metadata = json.loads(METADATA_PATH.read_text())
    filings = metadata["filings"]

    print(f"SEC 13F XML parser — {len(filings)} filings to process")
    print(f"Target period: {metadata['target_period']}")

    results = []
    for filing in filings:
        result = parse_filing(filing)
        results.append(result)

    print_recon_table(results)
    print_sample_records(results)

    return results


if __name__ == "__main__":
    main()
