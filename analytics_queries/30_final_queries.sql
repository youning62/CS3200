-- =============================================================================
-- 30_final_queries.sql
-- CS3200 Project: Analyzing Stock Market Performance Across Different
--                 Macroeconomic Environments
-- Database: stock_analysis (schema v3.0). Data: CRSP monthly + FRED, 2015-01 to 2025-12.
--
-- Conventions used below (see schema/SCHEMA_CONTRACT.md):
--   * A month is "in" a condition when the indicator's value that month is
--     >= min_value (if set) and < max_value (if set).
--   * Returns are fractions; queries multiply by 100 only for display (%).
--   * Industry returns are market-cap weighted (industry_monthly_returns).
-- =============================================================================

USE stock_analysis;


-- -----------------------------------------------------------------------------
-- Query 1
-- Question: How do average monthly returns compare across all 11 industries
--           during Low Interest Rate months versus High Interest Rate months?
--
-- Approach: a derived table tags every month with its interest-rate condition
-- (range join from economic_data to economic_conditions). It is joined to the
-- monthly cap-weighted industry returns, and conditional aggregation puts the
-- Low and High averages side by side. RANK() orders industries by how much
-- better (or worse) they did when rates were high.
-- -----------------------------------------------------------------------------
SELECT
    i.industry_name,
    ROUND(100 * AVG(CASE WHEN rate_months.condition_name = 'Low Interest Rates'
                         THEN r.avg_return END), 3)                      AS low_rate_avg_pct,
    ROUND(100 * AVG(CASE WHEN rate_months.condition_name = 'High Interest Rates'
                         THEN r.avg_return END), 3)                      AS high_rate_avg_pct,
    ROUND(100 * (AVG(CASE WHEN rate_months.condition_name = 'High Interest Rates'
                          THEN r.avg_return END)
               - AVG(CASE WHEN rate_months.condition_name = 'Low Interest Rates'
                          THEN r.avg_return END)), 3)                    AS high_minus_low_pct,
    SUM(rate_months.condition_name = 'Low Interest Rates')               AS low_rate_months,
    SUM(rate_months.condition_name = 'High Interest Rates')              AS high_rate_months,
    RANK() OVER (ORDER BY AVG(CASE WHEN rate_months.condition_name = 'High Interest Rates'
                                   THEN r.avg_return END)
                        - AVG(CASE WHEN rate_months.condition_name = 'Low Interest Rates'
                                   THEN r.avg_return END) DESC)          AS rank_high_vs_low
FROM industry_monthly_returns r
JOIN industries i ON i.industry_id = r.industry_id
JOIN (
    -- every month whose Fed funds rate puts it in the Low or High condition
    SELECT d.month, ec.condition_name
    FROM economic_data d
    JOIN economic_conditions ec
      ON ec.indicator_id = d.indicator_id
     AND (ec.min_value IS NULL OR d.value >= ec.min_value)
     AND (ec.max_value IS NULL OR d.value <  ec.max_value)
    WHERE ec.condition_name IN ('Low Interest Rates', 'High Interest Rates')
) AS rate_months ON rate_months.month = r.month
GROUP BY i.industry_id, i.industry_name
ORDER BY rank_high_vs_low;


-- -----------------------------------------------------------------------------
-- Query 2
-- Question: During High Interest Rate months, which 3 companies in each
--           industry had the highest average monthly returns?
--
-- Approach: average each company's monthly return over the High Interest Rate
-- months only, then rank companies within their industry with ROW_NUMBER()
-- and keep the top 3.
--
-- Eligibility filters (without them, the top 3 in every industry is a
-- micro-cap with one freak +1,000% month; see SCHEMA_CONTRACT.md §5):
--   * the company has a return in at least 30 of the High Interest Rate
--     months (out of 39), so the average covers most of the period;
--   * its average start-of-month market cap during those months is at least
--     $1 billion (start_market_cap is in USD thousands, so 1,000,000).
-- Note: an arithmetic mean can still be driven by a few huge months (e.g. a
-- stock that jumps several hundred percent once). Industry labels come from
-- the data's sector mapping (e.g. some crypto-mining and quantum-computing
-- firms are classified as Financials).
-- -----------------------------------------------------------------------------
SELECT
    ranked.industry_name,
    ranked.industry_rank,
    ranked.ticker,
    ranked.company_name,
    ROUND(100 * ranked.avg_monthly_return, 3)    AS avg_monthly_return_pct,
    ranked.months_with_data,
    ROUND(ranked.avg_market_cap / 1000000, 1)    AS avg_market_cap_billions
FROM (
    SELECT
        i.industry_name,
        c.ticker,
        c.company_name,
        AVG(m.monthly_return)   AS avg_monthly_return,
        COUNT(*)                AS months_with_data,
        AVG(m.start_market_cap) AS avg_market_cap,
        ROW_NUMBER() OVER (PARTITION BY i.industry_id
                           ORDER BY AVG(m.monthly_return) DESC) AS industry_rank
    FROM monthly_stock_prices m
    JOIN companies  c ON c.company_id  = m.company_id
    JOIN industries i ON i.industry_id = c.industry_id
    WHERE m.monthly_return IS NOT NULL
      AND m.month IN (
          -- months when the Fed funds rate was in the High Interest Rates range
          SELECT d.month
          FROM economic_data d
          JOIN economic_conditions ec
            ON ec.indicator_id = d.indicator_id
           AND (ec.min_value IS NULL OR d.value >= ec.min_value)
           AND (ec.max_value IS NULL OR d.value <  ec.max_value)
          WHERE ec.condition_name = 'High Interest Rates'
      )
    GROUP BY i.industry_id, i.industry_name, c.company_id, c.ticker, c.company_name
    HAVING COUNT(*) >= 30
       AND AVG(m.start_market_cap) >= 1000000
) AS ranked
WHERE ranked.industry_rank <= 3
ORDER BY ranked.industry_name, ranked.industry_rank;


-- -----------------------------------------------------------------------------
-- Query 3
-- Question: How do industry returns compare between High Unemployment and
--           Low Unemployment periods?
--
-- Approach: self-join the condition_industry_performance summary table, once
-- for the High Unemployment rows and once for the Low Unemployment rows, so
-- each industry gets one row with both periods side by side. Besides the raw
-- return, the excess return over the market shows whether an industry beat
-- the overall market in each period. Scalar subqueries look up the two
-- condition IDs by name; a second query below gives the market's own average
-- return in each period for reference.
-- Interpretation caveat: all 13 High Unemployment months (UNRATE >= 6%) are
-- 2020-04 to 2021-04, the COVID crash recovery, so the high returns reflect
-- the rebound rather than "high unemployment" in general.
-- Note: Oct 2025 unemployment was never published (US government shutdown),
-- so that month is in neither group.
-- -----------------------------------------------------------------------------
SELECT
    i.industry_name,
    ROUND(100 * lo.avg_return, 3)                         AS low_unemp_avg_pct,
    ROUND(100 * hi.avg_return, 3)                         AS high_unemp_avg_pct,
    ROUND(100 * (hi.avg_return - lo.avg_return), 3)       AS high_minus_low_pct,
    ROUND(100 * lo.avg_excess_return, 3)                  AS low_unemp_excess_pct,
    ROUND(100 * hi.avg_excess_return, 3)                  AS high_unemp_excess_pct,
    CASE
        WHEN hi.avg_excess_return > 0 AND lo.avg_excess_return > 0 THEN 'Beat market in both'
        WHEN hi.avg_excess_return > 0                              THEN 'Beat market only in high unemployment'
        WHEN lo.avg_excess_return > 0                              THEN 'Beat market only in low unemployment'
        ELSE 'Lagged market in both'
    END                                                   AS vs_market,
    lo.num_months                                         AS low_unemp_months,
    hi.num_months                                         AS high_unemp_months
FROM industries i
JOIN condition_industry_performance lo
  ON lo.industry_id = i.industry_id
 AND lo.condition_id = (SELECT condition_id FROM economic_conditions
                        WHERE condition_name = 'Low Unemployment')
JOIN condition_industry_performance hi
  ON hi.industry_id = i.industry_id
 AND hi.condition_id = (SELECT condition_id FROM economic_conditions
                        WHERE condition_name = 'High Unemployment')
ORDER BY high_minus_low_pct DESC;

-- Market reference for Query 3: the cap-weighted market's average monthly
-- return in each unemployment condition (all stocks, same months).
SELECT
    ec.condition_name,
    COUNT(*)                          AS months,
    ROUND(100 * AVG(mkt.market_return), 3) AS market_avg_pct
FROM economic_conditions ec
JOIN economic_data d
  ON d.indicator_id = ec.indicator_id
 AND (ec.min_value IS NULL OR d.value >= ec.min_value)
 AND (ec.max_value IS NULL OR d.value <  ec.max_value)
JOIN (
    SELECT month,
           SUM(monthly_return * start_market_cap) / SUM(start_market_cap) AS market_return
    FROM monthly_stock_prices
    WHERE monthly_return IS NOT NULL AND start_market_cap IS NOT NULL
    GROUP BY month
) AS mkt ON mkt.month = d.month
WHERE ec.condition_name IN ('Low Unemployment', 'High Unemployment')
GROUP BY ec.condition_id, ec.condition_name
ORDER BY ec.condition_id;
