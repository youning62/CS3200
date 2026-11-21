# analytics_queries — cross-domain views, derived tables, final queries

**Owner:** Corey
**Owns tables:** `industry_monthly_returns`, `condition_industry_performance`
**Reads:** everything else (built with `INSERT … SELECT`, never hand-entered)
**Rules:** `schema/SCHEMA_CONTRACT.md` §3.3, §4.6

Deliverables:
1. `10_views.sql`, e.g.
   - `v_market_monthly_return`: equal-weighted market return per month
   - `v_monthly_macro`: one row per month with FEDFUNDS, CPI YoY, real GDP growth, UNRATE side by side
   - `v_annual_summary`: yearly averages (replaces the dropped annual_economic_summary table)
2. `20_build_derived_tables.sql`: fills the 2 derived tables (re-runnable: DELETE, then INSERT … SELECT)
3. `30_final_queries.sql`: the 5–6 graded queries (joins + subqueries, English question in a comment above each)

There is no mock data. Until ETL lands, write the SQL against the empty schema (it parses and runs, returning 0 rows),
or load a small real extract locally (don't commit it).
Done when `schema/03_validate_schema.sql` checks 7d/7e PASS on the real data.
