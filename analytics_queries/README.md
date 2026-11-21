# analytics_queries — cross-domain views, derived tables, final queries

**Owns tables:** `industry_monthly_returns`, `condition_industry_performance`, `annual_economic_summary`
**Reads:** everything else (built with `INSERT … SELECT`, never hand-entered)
**Rules:** `schema/SCHEMA_CONTRACT.md` §3.3, §4.6

Deliverables:
1. `10_views.sql`: e.g. `v_market_monthly_return`, `v_monthly_macro` (one row per month with all indicators aligned)
2. `20_build_derived_tables.sql`: populates the 3 derived tables (re-runnable: DELETE then INSERT … SELECT)
3. `30_final_queries.sql`: the 5–6 graded queries (joins + subqueries, English question in a comment above each)

Develop against `schema/02_mock_seed.sql` now. Re-run on real data once ETL lands.
Done when `schema/03_validate_schema.sql` checks 6c/6d PASS with 0 placeholder WARNs.
