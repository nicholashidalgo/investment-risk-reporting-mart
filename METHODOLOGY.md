# Methodology

> Production-pattern, not production-grade. Built to demonstrate domain vocabulary, governance discipline, and lineage thinking applied to investment risk reporting. Not built to manage real money.

---

## 1. Parametric VaR

**Implementation**
Value-at-Risk is computed using the parametric variance-covariance method. Daily log returns are calculated for each security from `fct_price_daily`. Per-security daily volatility (σᵢ) is the standard deviation of those log returns over the full available history (~252 trading days).

Portfolio volatility is computed under a **zero-correlation assumption**: positions are treated as independent, so portfolio variance is the sum of position-level variances weighted by market value squared.

```
portfolio_σ = sqrt( Σ (wᵢ × σᵢ)² ) / NAV
VaR_95 = 1.645 × portfolio_σ × NAV
VaR_99 = 2.326 × portfolio_σ × NAV
```

**Limitations**
- Zero correlation suppresses portfolio sigma materially. Real equity portfolios have high cross-asset correlations (ρ > 0.6 in stress periods), which would increase true portfolio VaR significantly.
- Single time horizon (1-day). Regulatory capital models typically require 10-day horizons.
- Normal distribution assumption understates tail risk. Equity returns exhibit fat tails (kurtosis > 3), meaning true 99% VaR is higher than the Gaussian estimate.
- Volatility is computed over a static lookback window. In stress regimes, volatility clusters and historical estimates lag realized risk.

**Production-grade equivalent**
Full historical covariance matrix estimated via exponential weighting (EWMA, λ=0.94). Monte Carlo simulation or historical simulation using 500+ scenarios. Fat-tailed distributions (Student-t, cornish-fisher expansion). Multi-day horizons with square-root-of-time scaling or overlapping returns.

---

## 2. Tracking Error

**Implementation**
Ex-post realized tracking error is computed using **static current weights** applied backward across all available price history. For each price date, a portfolio return is synthesized as the sum of current position weights multiplied by that day's security return. Active return is the difference between the synthesized portfolio return and the mapped benchmark daily return.

```
port_return(t) = Σ wᵢ × (pᵢ(t) - pᵢ(t-1)) / pᵢ(t-1)
active_return(t) = port_return(t) - benchmark_return(t)
TE = stddev(active_return) × sqrt(252)
```

Benchmark mapping: `PORT_CORE → BENCH_SPY`, `PORT_FLEX → BENCH_AGG`.

Trailing windows: 30, 60, and 90 calendar days from the most recent price date.

**Limitations**
- Static weight assumption treats the current portfolio as if it had been held for the entire lookback period. Real portfolios rebalance, generating different historical return profiles.
- Ex-post TE measures what happened, not what is likely to happen. Ex-ante TE from a factor model is the relevant forward-looking risk metric.
- Benchmark selection is simplified (single index). Blended benchmarks (e.g., 70% SPY / 30% AGG) are more appropriate for multi-asset portfolios.
- Short lookback windows (30 days = ~21 trading days) produce high estimation noise in the standard deviation.

**Production-grade equivalent**
Ex-ante TE from a commercial multi-factor risk model (Barra, Axioma, Northfield). Time-varying weights using daily or weekly position snapshots. Custom blended benchmark aligned to investment mandate. Decomposition into systematic vs idiosyncratic TE contributions.

---

## 3. Stress Scenarios

**Implementation**
Five single-factor scenarios defined in `bronze.raw_stress_scenarios`. Shocks are applied linearly to the relevant exposure subset:

| Scenario | Factor | Shock | Applied To |
|---|---|---|---|
| STRESS_EQUITY_10 | equity | −10% | All Equity MV |
| STRESS_EQUITY_20 | equity | −20% | All Equity MV |
| STRESS_RATES_100 | interest_rate | +100bp | Fixed Income MV via duration |
| STRESS_RATES_200 | interest_rate | +200bp | Fixed Income MV via duration |
| STRESS_CREDIT_100 | credit_spread | +100bp | BBB+ Fixed Income MV via duration |

Rate and credit spread impact use the duration approximation:
```
ΔP = −D × (Δy / 10000) × MV
```
where D is the portfolio-weighted average modified duration from `mart_duration_summary`.

**Limitations**
- Single-factor shocks ignore cross-asset correlation. A rate shock in reality depresses equity valuations via discount rate effects and affects credit spreads simultaneously.
- Linear price approximation ignores convexity. For large parallel shifts (>200bp), convexity correction is material.
- No historical event calibration. The 2008 GFC saw equities −50%, rates −200bp, and credit spreads +600bp simultaneously.
- Credit shock applied only to BBB+ rated bonds. In practice, all credit instruments widen in a credit event, with high-yield (BB and below) widening more than investment grade.

**Production-grade equivalent**
Multi-factor scenarios with correlated shocks across equity, rates, FX, and credit. Historical event replay (2008 GFC, 2011 Euro sovereign crisis, 2020 COVID, 2022 rate shock). Non-linear pricing via full repricing of fixed income instruments. Reverse stress testing to identify portfolio vulnerabilities.

---

## 4. Duration

**Implementation**
Synthetic modified duration is assigned to each fixed income position by maturity bucket:

| Maturity Bucket | Synthetic Duration |
|---|---|
| 0–2 years | 1.5 years |
| 2–5 years | 3.5 years |
| 5–10 years | 6.5 years |
| 10+ years | 12.0 years |

Portfolio-weighted average duration is computed as:
```
D_portfolio = Σ (MVᵢ / MV_total_FI) × Dᵢ
```

**Limitations**
- Bucket midpoints are rough approximations. Actual modified duration depends on coupon rate, yield, and cash flow schedule.
- No convexity adjustment. For large yield moves, duration understates the price change for bonds with positive convexity.
- All positions within a bucket receive identical duration regardless of coupon structure (zero-coupon bonds, high-coupon bonds, and floaters all differ materially).
- Single portfolio-weighted average ignores key rate exposures across the yield curve (2y, 5y, 10y, 30y).

**Production-grade equivalent**
Macaulay and modified duration computed analytically from discounted cash flows using a market yield curve. Key rate durations (KRD) for each tenor bucket. Duration times spread (DTS) for credit positioning. Full repricing across yield curve scenarios.

---

## 5. Concentration Limits

**Implementation**
Two thresholds apply at the portfolio level:

| Threshold | Value | Where enforced |
|---|---|---|
| Hard synthesis cap — equity | 8% per position | `_capped_weights()` in `ingest_seed_data.py` (asserts at runtime) |
| Hard synthesis cap — fixed income | 6% per position | `_capped_weights()` in `ingest_seed_data.py` (asserts at runtime) |
| Soft watch threshold | 5% per position | `mart_concentration_limits.sql` — `breach_flag = TRUE` |

The 5% watch threshold is intentionally set below the 8% synthesis cap to surface positions trending toward the limit before they reach it. This mirrors a risk escalation framework where positions between 5–8% trigger review without requiring mandatory reduction.

**Limitations**
- Single-dimension limit (weight by market value). No sector, country, currency, or counterparty concentration monitoring.
- No look-through for ETF positions (SPY/AGG treated as single-name exposure, not constituent-level).
- Static NAV denominator. Intraday mark-to-market moves are not reflected until next position snapshot.
- No netting of correlated exposures (e.g., two technology names at 4% each are not flagged together despite 8% combined technology exposure).

**Production-grade equivalent**
Tiered limit framework: single-name (by issuer, not ticker), sector, industry, country, currency, counterparty, and liquidity buckets. Issuer look-through for funds. Real-time monitoring vs end-of-day batch. Regulatory 10% single-issuer UCITS limits for regulated funds.

---

## 6. Private Credit (Synthetic Bonds)

**Implementation**
Ten synthetic corporate bond positions (`BOND_001` through `BOND_010`) are generated with:
- Ratings drawn from a realistic distribution: AAA (10%), AA (20%), A (35%), BBB (25%), BB (10%)
- Sectors assigned round-robin across 10 GICS sectors
- Maturities drawn uniformly from 2–10 years forward
- Prices initialized near par (88–103) with a low-volatility random walk (σ ≈ 0.1–0.3% daily)
- Ratings confirmed by all three agencies (Moody's, S&P, Fitch) at four sample dates

**Limitations**
- Prices do not reflect credit spread dynamics, market liquidity, or bid-ask spreads.
- Ratings are static across the full history. Real ratings are reviewed quarterly and can gap-down in stress.
- No OAS (option-adjusted spread) or Z-spread available for relative value analysis.
- Synthetic valuations would not be accepted by a fund administrator or prime broker.

**Production-grade equivalent**
Real position-level data from portfolio management system. Manager-supplied mark-to-market or model-based NAV (Level 2/3 fair value hierarchy). Bloomberg BVAL or TRACE pricing for traded bonds. Third-party administrator sign-off for NAV validation.

---

## 7. Data Sources

| Data | Source | Coverage | Notes |
|---|---|---|---|
| Equity prices | yfinance (Yahoo Finance API) | 1 year trailing daily OHLCV | Real market data, auto-adjusted for splits/dividends |
| Equity benchmark (SPY) | yfinance | 1 year trailing | SPDR S&P 500 ETF Trust |
| Fixed income benchmark (AGG) | yfinance | 1 year trailing | iShares Core US Aggregate Bond ETF |
| Corporate bond prices | Synthetic random walk | Matches equity price history dates | Not real market data |
| Credit ratings | Synthetic assignment | 4 sample dates × 3 agencies | Reflects realistic distribution, not real issuer ratings |
| Portfolio positions | Synthetic weight generation | Single snapshot (latest date) | Capped at 8% equity / 6% bond per position |
| Stress scenarios | Manually defined | 5 scenarios | Illustrative magnitudes, not regulatory calibrated |

---

## 8. Honest Summary

This project is **production-pattern, not production-grade**. It is built to demonstrate:
- Domain vocabulary fluency (VaR, tracking error, duration, credit exposure, recon gates)
- Governance discipline (data contracts, methodology documentation, dbt tests, schema checks)
- Lineage thinking (bronze → silver → marts → recon → dashboard, with clear dependencies)
- Engineering craft (idempotent ingestion, dbt best practices, parameterized risk mart SQL)

It is **not** built to:
- Manage real money
- Meet any regulatory capital or reporting standard (UCITS, AIFMD, SEC, Basel)
- Replace a commercial risk system (Bloomberg PORT, Aladdin, Axioma, FactSet)
- Handle real-time pricing, corporate actions, or multi-currency accounting

The synthetic bond data, zero-correlation VaR, and static-weight tracking error are known and documented simplifications, not oversights. The goal is to show how a production risk reporting system is structured, not to build one with real data and real stakes.
