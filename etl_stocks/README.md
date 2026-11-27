# etl_stocks — CRSP monthly stock data

**Owner:** Martin
**Produces tables:** `companies`, `monthly_stock_prices` (plus `industries`, `industry_monthly_returns`)
**Rules:** `schema/SCHEMA_CONTRACT.md` §3, §4.1–4.4

The current data is in `Dump20261126.sql` (team drive, NOT git): all CRSP common stocks,
2015-01 → 2025-12, 8,833 companies / 663,899 monthly rows.

To do:
1. Commit the extraction/cleaning script(s) that produced the dump here (no data files). This is needed
   for the "how AI/code was used" write-up and to make the data reproducible.
2. Document in this README how the 11 sectors were assigned (source field and mapping).
3. If you re-export: keep the same tables/columns, then run
   `schema/02_load_data.sh` + `schema/03_validate_schema.sql` (0 FAIL required).
