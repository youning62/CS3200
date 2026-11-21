# etl_macro — FRED monthly pull & regime classification

**Owner:** Ryan
**Owns tables:** `economic_data`, `economic_conditions` (new series → PR to `schema/02_reference_data.sql`)
**Reads:** FRED series FEDFUNDS, CPIAUCSL, GDP, GDPC1, UNRATE (CSV download or FRED API)
**Rules:** `schema/SCHEMA_CONTRACT.md` §3.2–3.4, §4.1

Deliverables:
1. `economic_data.csv` with columns `indicator_id, period_date, value`, **one row per indicator per month**, 1999-01 → 2024-12
   - monthly series: FRED dates unchanged
   - GDP / GDPC1: each quarterly value repeated in all 3 months of its quarter
   - look up indicator_id by indicator_code; drop FRED '.' rows
2. A regime classifier (rules in contract §3.4: ≥ 3 consecutive months) → `economic_conditions.csv`
3. `load_macro.sql` (`LOAD DATA LOCAL INFILE`)

Done when `schema/03_validate_schema.sql` shows 0 FAIL on checks 7a–7c and 7f, and no WARN on 7g/7k.
