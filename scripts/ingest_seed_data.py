# Bronze-layer seed ingestion: pulls market data, synthesizes bonds/positions, loads all bronze tables and ops.run_log
# Author: Nicholas Hidalgo

import os
import sys
import datetime
import traceback

import numpy as np
import pandas as pd
import psycopg2
import psycopg2.extras
import yfinance as yf

DATABASE_URL = os.environ["DATABASE_URL"]

EQUITY_TICKERS = ["AAPL", "MSFT", "GOOGL", "JPM", "XOM", "JNJ", "PG", "KO", "NVDA", "V", "MA"]
BENCHMARK_TICKERS = ["SPY", "AGG"]
ALL_TICKERS = EQUITY_TICKERS + BENCHMARK_TICKERS

PORTFOLIOS = {
    "PORT_CORE": {"target_nav": 100_000_000, "profile": "equity-heavy"},
    "PORT_FLEX": {"target_nav":  50_000_000, "profile": "mixed"},
}

BOND_RATINGS = ["AAA", "AA", "A", "BBB", "BB"]
BOND_RATING_WEIGHTS = [0.10, 0.20, 0.35, 0.25, 0.10]

STRESS_SCENARIOS = [
    ("STRESS_EQUITY_10",  "equity",        -10.00),
    ("STRESS_EQUITY_20",  "equity",        -20.00),
    ("STRESS_RATES_100",  "interest_rate", +100.00),
    ("STRESS_RATES_200",  "interest_rate", +200.00),
    ("STRESS_CREDIT_100", "credit_spread", +100.00),
]

RATING_AGENCIES = ["Moody's", "S&P", "Fitch"]


def fetch_prices(end_date: datetime.date) -> pd.DataFrame:
    start_date = end_date - datetime.timedelta(days=365)
    raw = yf.download(
        ALL_TICKERS,
        start=start_date.isoformat(),
        end=end_date.isoformat(),
        auto_adjust=True,
        progress=False,
    )
    close = raw["Close"] if isinstance(raw.columns, pd.MultiIndex) else raw
    close = close.dropna(how="all")
    records = []
    for dt, row in close.iterrows():
        price_date = dt.date() if hasattr(dt, "date") else dt
        for ticker in ALL_TICKERS:
            if ticker in row.index and not pd.isna(row[ticker]):
                records.append({
                    "sec_id":     ticker,
                    "price_date": price_date,
                    "price":      round(float(row[ticker]), 6),
                    "source":     "yfinance",
                })
    return pd.DataFrame(records)


def build_bond_security_master(n: int = 10) -> pd.DataFrame:
    rng = np.random.default_rng(42)
    today = datetime.date.today()
    records = []
    sectors = ["Financials", "Energy", "Healthcare", "Technology", "Consumer Staples",
               "Industrials", "Utilities", "Real Estate", "Materials", "Communication"]
    ratings = rng.choice(BOND_RATINGS, size=n, p=BOND_RATING_WEIGHTS)
    for i in range(n):
        issue_years_ago = rng.integers(1, 6)
        maturity_years  = rng.integers(2, 11)
        issue_dt   = today - datetime.timedelta(days=int(issue_years_ago * 365))
        maturity_dt = today + datetime.timedelta(days=int(maturity_years * 365))
        bond_id = f"BOND_{i+1:03d}"
        records.append({
            "sec_id":      bond_id,
            "ticker":      bond_id,
            "asset_class": "Fixed Income",
            "sector":      sectors[i % len(sectors)],
            "rating":      ratings[i],
            "maturity":    maturity_dt,
            "issue_date":  issue_dt,
        })
    return pd.DataFrame(records)


def build_equity_security_master(tickers: list[str]) -> pd.DataFrame:
    sector_map = {
        "SPY":   ("Benchmark", "Broad Market",     None),
        "AGG":   ("Benchmark", "Broad Market",     None),
        "AAPL":  ("Equity",    "Technology",       None),
        "MSFT":  ("Equity",    "Technology",       None),
        "GOOGL": ("Equity",    "Technology",       None),
        "NVDA":  ("Equity",    "Technology",       None),
        "JPM":   ("Equity",    "Financials",       None),
        "V":     ("Equity",    "Financials",       None),
        "MA":    ("Equity",    "Financials",       None),
        "XOM":   ("Equity",    "Energy",           None),
        "JNJ":   ("Equity",    "Healthcare",       None),
        "PG":    ("Equity",    "Consumer Staples", None),
        "KO":    ("Equity",    "Consumer Staples", None),
    }
    records = []
    for t in tickers:
        ac, sector, _ = sector_map.get(t, ("Equity", "Unknown", None))
        records.append({
            "sec_id":      t,
            "ticker":      t,
            "asset_class": ac,
            "sector":      sector,
            "rating":      "NR",
            "maturity":    None,
            "issue_date":  None,
        })
    return pd.DataFrame(records)


def build_bond_prices(bond_ids: list[str], price_dates: list[datetime.date]) -> pd.DataFrame:
    rng = np.random.default_rng(99)
    records = []
    for bond_id in bond_ids:
        base_price = rng.uniform(88.0, 103.0)
        vol = rng.uniform(0.001, 0.003)
        prices = base_price + np.cumsum(rng.normal(0, vol, len(price_dates)))
        prices = np.clip(prices, 50.0, 115.0)
        for dt, px in zip(price_dates, prices):
            records.append({
                "sec_id":     bond_id,
                "price_date": dt,
                "price":      round(float(px), 6),
                "source":     "synthetic",
            })
    return pd.DataFrame(records)


def _capped_weights(rng, n: int, alloc: float, cap: float) -> np.ndarray:
    """Generate n random weights summing to alloc with no weight exceeding cap.

    Algorithm: freeze positions at cap permanently, redistribute excess only across
    positions that have never been frozen. Mathematically guaranteed to terminate.
    """
    if alloc > n * cap:
        raise ValueError(f"infeasible: alloc={alloc} > n*cap={n * cap}")

    weights = rng.uniform(0.005, 1.0, size=n)
    weights = weights / weights.sum()  # normalize to sum to 1.0 in sleeve space

    sleeve_cap = cap / alloc  # cap in sleeve-normalized space

    frozen = set()  # indices permanently capped

    for _ in range(100):
        violators = [i for i in range(n) if i not in frozen and weights[i] > sleeve_cap]
        if not violators:
            break

        excess = 0.0
        for i in violators:
            excess += weights[i] - sleeve_cap
            weights[i] = sleeve_cap
            frozen.add(i)

        non_frozen = [i for i in range(n) if i not in frozen]
        if not non_frozen:
            raise RuntimeError("_capped_weights: all positions frozen at cap, cannot redistribute")

        non_frozen_total = sum(weights[i] for i in non_frozen)
        for i in non_frozen:
            weights[i] += excess * (weights[i] / non_frozen_total)
    else:
        raise RuntimeError(f"_capped_weights: did not converge after 100 iterations (cap={cap}, alloc={alloc}, n={n})")

    weights = weights * alloc  # scale to actual alloc

    assert (weights <= cap + 1e-9).all(), f"cap violation after convergence: max={weights.max()}, cap={cap}"
    assert abs(weights.sum() - alloc) < 1e-9, f"sum violation: sum={weights.sum()}, alloc={alloc}"

    return weights


def build_positions(
    equity_prices: pd.DataFrame,
    bond_prices: pd.DataFrame,
    bond_master: pd.DataFrame,
) -> pd.DataFrame:
    rng = np.random.default_rng(7)
    latest_date = equity_prices["price_date"].max()
    eq_latest = equity_prices[equity_prices["price_date"] == latest_date].copy()
    eq_latest = eq_latest[eq_latest["sec_id"].isin(EQUITY_TICKERS)].set_index("sec_id")

    bond_latest = bond_prices[bond_prices["price_date"] == latest_date].copy().set_index("sec_id")

    records = []

    for port_id, meta in PORTFOLIOS.items():
        nav = meta["target_nav"]
        profile = meta["profile"]

        if profile == "equity-heavy":
            eq_alloc  = 0.70
            bond_alloc = 0.30
        else:
            eq_alloc  = 0.70
            bond_alloc = 0.30

        eq_tickers = EQUITY_TICKERS
        eq_weights = _capped_weights(rng, len(eq_tickers), eq_alloc, cap=0.08)

        bond_ids = bond_master["sec_id"].tolist()
        bond_weights = _capped_weights(rng, len(bond_ids), bond_alloc, cap=0.06)

        for ticker, w in zip(eq_tickers, eq_weights):
            mv = nav * w
            records.append({
                "portfolio_id":  port_id,
                "sec_id":        ticker,
                "position_date": latest_date,
                "market_value":  round(mv, 4),
                "par_value":     round(mv, 4),
                "weight":        round(float(w), 6),
            })

        for bond_id, w in zip(bond_ids, bond_weights):
            px = float(bond_latest.loc[bond_id, "price"]) if bond_id in bond_latest.index else 100.0
            mv = nav * w
            par = mv * (100.0 / px)
            records.append({
                "portfolio_id":  port_id,
                "sec_id":        bond_id,
                "position_date": latest_date,
                "market_value":  round(mv, 4),
                "par_value":     round(par, 4),
                "weight":        round(float(w), 6),
            })

    return pd.DataFrame(records)


def build_benchmarks(price_df: pd.DataFrame) -> pd.DataFrame:
    spy = price_df[price_df["sec_id"] == "SPY"].sort_values("price_date").copy()
    agg = price_df[price_df["sec_id"] == "AGG"].sort_values("price_date").copy()

    records = []
    for df, bm_id in [(spy, "BENCH_SPY"), (agg, "BENCH_AGG")]:
        df = df.set_index("price_date")["price"]
        daily_ret = df.pct_change().dropna()
        for dt, r in daily_ret.items():
            records.append({
                "benchmark_id":   bm_id,
                "benchmark_date": dt,
                "return":         round(float(r), 8),
            })
    return pd.DataFrame(records)


def build_ratings(bond_master: pd.DataFrame, price_dates: list[datetime.date]) -> pd.DataFrame:
    rng = np.random.default_rng(55)
    records = []
    sample_dates = sorted(price_dates)[-4:]
    for _, row in bond_master.iterrows():
        base_rating = row["rating"]
        for agency in RATING_AGENCIES:
            for dt in sample_dates:
                records.append({
                    "sec_id":      row["sec_id"],
                    "rating_date": dt,
                    "rating":      base_rating,
                    "agency":      agency,
                })
    return pd.DataFrame(records)


def upsert_rows(cur, table: str, df: pd.DataFrame, conflict_cols: list[str]) -> int:
    if df.empty:
        return 0
    cols = list(df.columns)
    placeholders = ", ".join(["%s"] * len(cols))
    col_names = ", ".join(cols)
    conflict = ", ".join(conflict_cols)
    update_set = ", ".join(
        f"{c} = EXCLUDED.{c}" for c in cols if c not in conflict_cols
    )
    if update_set:
        on_conflict = f"ON CONFLICT ({conflict}) DO UPDATE SET {update_set}"
    else:
        on_conflict = f"ON CONFLICT ({conflict}) DO NOTHING"

    sql = f"INSERT INTO {table} ({col_names}) VALUES ({placeholders}) {on_conflict}"
    rows = [tuple(r) for r in df.itertuples(index=False, name=None)]
    psycopg2.extras.execute_batch(cur, sql, rows, page_size=500)
    return len(rows)


def main():
    today = datetime.date.today()
    start_ts = datetime.datetime.utcnow()
    total_rows = 0
    failure_msg = None
    checks_passed = True

    try:
        print("Fetching equity/ETF prices from yfinance...")
        eq_prices = fetch_prices(today)
        print(f"  Fetched {len(eq_prices)} equity/ETF price rows")

        price_dates = sorted(eq_prices["price_date"].unique())

        print("Building security master...")
        bond_master = build_bond_security_master(10)
        eq_master   = build_equity_security_master(ALL_TICKERS)
        security_master = pd.concat([eq_master, bond_master], ignore_index=True)

        print("Building bond prices...")
        bond_prices = build_bond_prices(bond_master["sec_id"].tolist(), price_dates)

        all_prices = pd.concat([eq_prices, bond_prices], ignore_index=True)

        print("Building positions...")
        positions = build_positions(eq_prices, bond_prices, bond_master)

        print("Building benchmarks...")
        benchmarks = build_benchmarks(eq_prices)

        print("Building ratings...")
        ratings = build_ratings(bond_master, price_dates)

        stress_df = pd.DataFrame(STRESS_SCENARIOS, columns=["scenario_id", "factor", "shock_pct"])

        print("Connecting to database...")
        conn = psycopg2.connect(DATABASE_URL)
        conn.autocommit = False
        cur = conn.cursor()

        print("Inserting security master...")
        n = upsert_rows(cur, "bronze.raw_security_master", security_master,
                        ["sec_id"])
        total_rows += n
        print(f"  {n} rows")

        print("Inserting prices...")
        n = upsert_rows(cur, "bronze.raw_prices", all_prices,
                        ["sec_id", "price_date"])
        total_rows += n
        print(f"  {n} rows")

        print("Inserting positions...")
        n = upsert_rows(cur, "bronze.raw_positions", positions,
                        ["portfolio_id", "sec_id", "position_date"])
        total_rows += n
        print(f"  {n} rows")

        print("Inserting benchmarks...")
        n = upsert_rows(cur, "bronze.raw_benchmarks", benchmarks,
                        ["benchmark_id", "benchmark_date"])
        total_rows += n
        print(f"  {n} rows")

        print("Inserting ratings...")
        n = upsert_rows(cur, "bronze.raw_ratings", ratings,
                        ["sec_id", "rating_date", "agency"])
        total_rows += n
        print(f"  {n} rows")

        print("Inserting stress scenarios...")
        n = upsert_rows(cur, "bronze.raw_stress_scenarios", stress_df,
                        ["scenario_id", "factor"])
        total_rows += n
        print(f"  {n} rows")

        lag_days = (today - price_dates[-1]).days if price_dates else None

        cur.execute(
            """
            INSERT INTO ops.run_log
                (run_timestamp, model_name, row_count, drift_pct, lag_days, sla_status, checks_passed, failure_message)
            VALUES
                (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                start_ts,
                "ingest_seed_data",
                total_rows,
                None,
                lag_days,
                "OK" if lag_days is not None and lag_days <= 3 else "WARN",
                checks_passed,
                None,
            ),
        )

        conn.commit()
        cur.close()
        conn.close()
        print(f"\nDone. {total_rows} total rows inserted across all bronze tables.")

    except Exception as exc:
        failure_msg = str(exc)
        checks_passed = False
        traceback.print_exc()
        try:
            conn2 = psycopg2.connect(DATABASE_URL)
            conn2.autocommit = True
            c2 = conn2.cursor()
            c2.execute(
                """
                INSERT INTO ops.run_log
                    (run_timestamp, model_name, row_count, drift_pct, lag_days, sla_status, checks_passed, failure_message)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (start_ts, "ingest_seed_data", total_rows, None, None, "FAIL", False, failure_msg[:2000]),
            )
            c2.close()
            conn2.close()
        except Exception:
            pass
        sys.exit(1)


if __name__ == "__main__":
    main()
