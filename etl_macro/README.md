# etl_macro — FRED ingestion & regime classification

**Owns tables:** `economic_data`, `economic_conditions` (+ new rows in `economic_indicators` via PR to the seed)
**Reads:** FRED series FEDFUNDS, CPIAUCSL, GDP, GDPC1, UNRATE (CSV download or FRED API)
**Rules:** `schema/SCHEMA_CONTRACT.md` §3.2–3.4, §4.1

Deliverables:
1. `economic_data.csv` (indicator_id looked up by indicator_code, FRED dates unchanged, '.' rows dropped)
2. A regime classifier that turns monthly values into contiguous episodes (≥ 3 months) → `economic_conditions.csv`
3. `load_macro.sql`: `LOAD DATA LOCAL INFILE` statements

Done when `schema/03_validate_schema.sql` shows 0 FAIL for checks 6e–6h.
