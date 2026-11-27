# analytics_queries — views and final queries

**Owner:** Corey
**Reads:** all 8 tables in `stock_analysis` (load them with `schema/01` + `02` + `03` first)
**Rules:** `schema/SCHEMA_CONTRACT.md` §3 (join patterns), §4.4 (definitions), §5 (data caveats)

Deliverables:
1. `10_views.sql`, e.g.
   - `v_market_monthly_return`: cap-weighted market return per month
   - `v_monthly_macro`: one row per month with all 4 indicators side by side
   - extra metrics not stored in tables (industry volatility, win rate) as views, not new columns
2. `30_final_queries.sql`: the 5–6 graded queries (joins + subqueries), each with the question in English
   as a comment above it, plus the output.

Watch out: always join companies on `company_id` (tickers repeat); filter `monthly_return IS NOT NULL`;
283 micro-cap returns > +300% distort equal-weighted averages, so prefer cap weighting.
