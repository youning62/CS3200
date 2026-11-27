# etl_macro — FRED macro data and conditions

**Owner:** Ryan
**Produces tables:** `economic_indicators`, `economic_data`, `economic_conditions`, `condition_industry_performance`
**Rules:** `schema/SCHEMA_CONTRACT.md` §3, §4.3–4.4

Current data: 4 indicators (FEDFUNDS, CPI YoY from CPIAUCSL, UNRATE, real GDP growth A191RL1Q225SBEA),
monthly 2015-01 → 2025-12; quarterly GDP growth repeated across each quarter's months;
12 conditions = Low/Moderate/High value ranges per indicator (min inclusive, max exclusive).
Oct 2025 CPI/UNRATE are absent (never published: 2025 government shutdown).

To do:
1. Commit the FRED download/transform script(s) here (CPI YoY calculation, quarterly repeat).
2. If thresholds change, update `economic_conditions` and rebuild `condition_industry_performance`.
   `schema/03_validate_schema.sql` check 6c must still PASS (each value in exactly one range).
