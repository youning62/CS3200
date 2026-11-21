# etl_stocks — CRSP daily → monthly

**Owns tables:** `companies`, `daily_stock_prices`, `monthly_stock_prices`
**Reads:** CRSP daily stock file (DSF) + header/names (SICCD, EXCHCD, SHRCD, TICKER, SHRCLS) from WRDS
**Rules:** `schema/SCHEMA_CONTRACT.md` §3.1, §4.2–4.5

Deliverables:
1. `companies.csv`, `daily_stock_prices.csv`, `monthly_stock_prices.csv`, with columns in exact table order
2. The script(s) that produce them (SIC → FF12 mapping, ticker standardization, ABS(PRC), monthly compounding)
3. `load_stocks.sql`: `LOAD DATA LOCAL INFILE` statements, in FK order

Done when `schema/03_validate_schema.sql` shows 0 FAIL for sections 5 and 6a/6b/6i/6j.
Raw CRSP extracts stay out of git (WRDS license).
