# etl_stocks — CRSP monthly pull (~500 US companies)

**Owner:** Martin
**Owns tables:** `companies`, `monthly_stock_prices`
**Reads (WRDS):** CRSP Monthly Stock File (MSF), stock header/names (SICCD, EXCHCD, SHRCD, TICKER, SHRCLS),
S&P 500 constituents (`crsp.msp500list`), and optionally the daily index file (DSI) to count trading days.
**Rules:** `schema/SCHEMA_CONTRACT.md` §3.1, §4.2–4.5, §5

No daily data: `daily_stock_prices` was removed in schema v2.0.

Deliverables:
1. `companies.csv` with columns `ticker, permno, company_name, industry_id, exchange, active_status`
   (SICCD → Fama-French 12 via Ken French's Siccodes12; unmapped → 12 OTHER)
2. `monthly_stock_prices.csv` with columns `ticker, period_date, month_close_price, monthly_return, total_volume, trading_days`
   - `period_date` = first of month · `ABS(PRC)` · `RET` as a fraction · `VOL × 100` · drop rows with missing RET/PRC
3. The script(s) that build them, plus `load_stocks.sql` (`LOAD DATA LOCAL INFILE`, companies first)

Done when `schema/03_validate_schema.sql` shows 0 FAIL, checks 7h/7i/7j have no WARNs,
and section 8 shows ~500 tickers per month across 2000-01 → 2024-12.
Raw CRSP extracts stay out of git (WRDS license).
