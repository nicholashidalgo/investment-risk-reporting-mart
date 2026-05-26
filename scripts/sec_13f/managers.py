"""
Locked manager CIK registry for v0.3 SEC 13F ingestion.

CIKs are zero-padded to 10 digits as required by the EDGAR submissions API.
Expected entity names are used for verification only — the API entityName is
authoritative. If entityName does not match, the script logs a warning and
continues; it does not fail, because SEC sometimes records slight name variants.
"""

MANAGERS = [
    {
        "cik": "0000093751",
        "expected_name": "STATE STREET CORP",
        "label": "State Street Corp",
    },
    {
        "cik": "0000315066",
        "expected_name": "FMR LLC",
        "label": "Fidelity (FMR LLC)",
    },
    {
        "cik": "0000902219",
        "expected_name": "WELLINGTON MANAGEMENT CO LLP",
        "label": "Wellington Management Company LLP",
        "fallback_cik": "0000900092",
        "fallback_label": "Wellington Management Group LLP",
    },
    {
        "cik": "0000912938",
        "expected_name": "MASSACHUSETTS FINANCIAL SERVICES CO",
        "label": "MFS Investment Management",
        # Plan had 0000350797 (Mirror Merger Sub 2, LLC) — wrong CIK.
        # Correct CIK confirmed via EDGAR full-text search 2026-05-06.
    },
    {
        "cik": "0000312348",
        "expected_name": "LOOMIS SAYLES & CO L P",
        "label": "Loomis Sayles & Co LP",
        # Plan had 0001543160 (Benefit Street Partners LLC) — wrong CIK.
        # Correct CIK confirmed via EDGAR full-text search 2026-05-06.
    },
]
