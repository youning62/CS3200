-- =============================================================================
-- 03_validate_schema.sql   (schema v3.0: 8 tables, matches the real-data dump)
-- Verifies structure (tables, PKs, FKs, indexes, CHECKs), referential
-- integrity, and the data rules in SCHEMA_CONTRACT.md, including a full
-- recomputation of both derived tables.
--
-- Safe to run any time: read-only except for a TEMPORARY results table.
-- Works on an EMPTY database too (data checks pass trivially).
--
--   mysql -u <user> -p < schema/03_validate_schema.sql
--
-- Output: one row per check -> section | check_name | status | detail
--   PASS / FAIL / WARN / INFO.   Any FAIL must be fixed before sharing data.
--   WARNs are known data characteristics; see SCHEMA_CONTRACT.md §5.
-- =============================================================================

USE stock_analysis;

DROP TEMPORARY TABLE IF EXISTS validation_results;
CREATE TEMPORARY TABLE validation_results (
    check_no    INT AUTO_INCREMENT PRIMARY KEY,
    section     VARCHAR(30)  NOT NULL,
    check_name  VARCHAR(120) NOT NULL,
    status      ENUM('PASS', 'FAIL', 'WARN', 'INFO') NOT NULL,
    detail      VARCHAR(1000) NULL
);

-- =============================================================================
-- SECTION 1: Tables
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '1. Tables',
       CONCAT('Table exists: ', e.tbl),
       IF(t.TABLE_NAME IS NULL, 'FAIL', 'PASS'),
       IF(t.TABLE_NAME IS NULL, 'Missing - re-run 01_create_tables.sql',
          CONCAT('engine=', t.ENGINE))
FROM (
              SELECT 'industries' AS tbl
    UNION ALL SELECT 'companies'
    UNION ALL SELECT 'monthly_stock_prices'
    UNION ALL SELECT 'economic_indicators'
    UNION ALL SELECT 'economic_data'
    UNION ALL SELECT 'economic_conditions'
    UNION ALL SELECT 'industry_monthly_returns'
    UNION ALL SELECT 'condition_industry_performance'
) e
LEFT JOIN information_schema.TABLES t
       ON t.TABLE_SCHEMA = DATABASE() AND t.TABLE_NAME = e.tbl;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '1. Tables', 'Exactly 8 base tables in schema',
       IF(COUNT(*) = 8, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' base tables found')
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE';

-- =============================================================================
-- SECTION 2: Primary keys
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '2. Primary keys',
       CONCAT('PK on ', e.tbl, ' = (', e.pk_cols, ')'),
       IF(a.actual_cols <=> e.pk_cols, 'PASS', 'FAIL'),
       CONCAT('actual: (', COALESCE(a.actual_cols, 'NONE'), ')')
FROM (
              SELECT 'industries' AS tbl,              'industry_id' AS pk_cols
    UNION ALL SELECT 'companies',                      'company_id'
    UNION ALL SELECT 'monthly_stock_prices',           'company_id,month'
    UNION ALL SELECT 'economic_indicators',            'indicator_id'
    UNION ALL SELECT 'economic_data',                  'indicator_id,month'
    UNION ALL SELECT 'economic_conditions',            'condition_id'
    UNION ALL SELECT 'industry_monthly_returns',       'industry_id,month'
    UNION ALL SELECT 'condition_industry_performance', 'condition_id,industry_id'
) e
LEFT JOIN (
    SELECT TABLE_NAME,
           GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',') AS actual_cols
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND INDEX_NAME = 'PRIMARY'
    GROUP BY TABLE_NAME
) a ON a.TABLE_NAME = e.tbl;

-- =============================================================================
-- SECTION 3: Foreign keys (child.col -> parent.col)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '3. Foreign keys',
       CONCAT('FK ', e.child, '.', e.child_col, ' -> ', e.parent, '.', e.parent_col),
       IF(k.CONSTRAINT_NAME IS NULL, 'FAIL', 'PASS'),
       COALESCE(CONCAT(k.CONSTRAINT_NAME, ' (ON DELETE ', r.DELETE_RULE,
                       ', ON UPDATE ', r.UPDATE_RULE, ')'), 'missing')
FROM (
              SELECT 'companies' AS child, 'industry_id' AS child_col, 'industries' AS parent, 'industry_id' AS parent_col
    UNION ALL SELECT 'monthly_stock_prices',           'company_id',   'companies',           'company_id'
    UNION ALL SELECT 'economic_data',                  'indicator_id', 'economic_indicators', 'indicator_id'
    UNION ALL SELECT 'economic_conditions',            'indicator_id', 'economic_indicators', 'indicator_id'
    UNION ALL SELECT 'industry_monthly_returns',       'industry_id',  'industries',          'industry_id'
    UNION ALL SELECT 'condition_industry_performance', 'condition_id', 'economic_conditions', 'condition_id'
    UNION ALL SELECT 'condition_industry_performance', 'industry_id',  'industries',          'industry_id'
) e
LEFT JOIN information_schema.KEY_COLUMN_USAGE k
       ON k.TABLE_SCHEMA = DATABASE()
      AND k.TABLE_NAME = e.child AND k.COLUMN_NAME = e.child_col
      AND k.REFERENCED_TABLE_NAME = e.parent AND k.REFERENCED_COLUMN_NAME = e.parent_col
LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS r
       ON r.CONSTRAINT_SCHEMA = k.TABLE_SCHEMA AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME;

-- =============================================================================
-- SECTION 4: Secondary / unique indexes and CHECK constraints
--   (CHECK count = 14: fails if the dump's own DDL replaced ours, e.g. after
--    loading the dump with `mysql < dump.sql` instead of 02_load_data.sh)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '4. Indexes & CHECKs',
       CONCAT('Index ', e.tbl, '.', e.idx, ' (', e.cols, ')'),
       IF(a.actual_cols <=> e.cols, 'PASS', 'FAIL'),
       CONCAT('actual: (', COALESCE(a.actual_cols, 'NONE'), ')',
              IF(a.non_unique = 0, ' UNIQUE', ''))
FROM (
              SELECT 'industries' AS tbl, 'industry_name' AS idx, 'industry_name' AS cols
    UNION ALL SELECT 'companies',                      'industry_id',          'industry_id'
    UNION ALL SELECT 'companies',                      'idx_companies_ticker', 'ticker'
    UNION ALL SELECT 'monthly_stock_prices',           'month',                'month'
    UNION ALL SELECT 'economic_indicators',            'indicator_name',       'indicator_name'
    UNION ALL SELECT 'economic_data',                  'idx_econdata_month',   'month'
    UNION ALL SELECT 'economic_conditions',            'condition_name',       'condition_name'
    UNION ALL SELECT 'economic_conditions',            'indicator_id',         'indicator_id'
    UNION ALL SELECT 'industry_monthly_returns',       'idx_imr_month',        'month'
    UNION ALL SELECT 'condition_industry_performance', 'industry_id',          'industry_id'
) e
LEFT JOIN (
    SELECT TABLE_NAME, INDEX_NAME, MIN(NON_UNIQUE) AS non_unique,
           GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',') AS actual_cols
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
    GROUP BY TABLE_NAME, INDEX_NAME
) a ON a.TABLE_NAME = e.tbl AND a.INDEX_NAME = e.idx;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '4. Indexes & CHECKs', 'CHECK constraints present and enforced',
       IF(COUNT(*) >= 14 AND COALESCE(SUM(ENFORCED = 'NO'), 0) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' CHECK constraints (expected 14), ',
              COALESCE(SUM(ENFORCED = 'NO'), 0), ' not enforced; server ', VERSION(),
              IF(COUNT(*) = 0, ' - did you load the dump with mysql < dump.sql? Use 02_load_data.sh', ''))
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_TYPE = 'CHECK';

-- =============================================================================
-- SECTION 5: Referential integrity (orphans). 02_load_data.sh loads with
-- FOREIGN_KEY_CHECKS = 0, so this section is what proves the FKs hold.
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '5. Orphans', o.chk, IF(o.n = 0, 'PASS', 'FAIL'), CONCAT(o.n, ' orphan rows')
FROM (
    SELECT 'companies -> industries' AS chk, COUNT(*) AS n
      FROM companies c LEFT JOIN industries i ON i.industry_id = c.industry_id
     WHERE i.industry_id IS NULL
    UNION ALL
    SELECT 'monthly_stock_prices -> companies', COUNT(*)
      FROM monthly_stock_prices m LEFT JOIN companies c ON c.company_id = m.company_id
     WHERE c.company_id IS NULL
    UNION ALL
    SELECT 'economic_data -> economic_indicators', COUNT(*)
      FROM economic_data d LEFT JOIN economic_indicators i ON i.indicator_id = d.indicator_id
     WHERE i.indicator_id IS NULL
    UNION ALL
    SELECT 'economic_conditions -> economic_indicators', COUNT(*)
      FROM economic_conditions ec LEFT JOIN economic_indicators i ON i.indicator_id = ec.indicator_id
     WHERE i.indicator_id IS NULL
    UNION ALL
    SELECT 'industry_monthly_returns -> industries', COUNT(*)
      FROM industry_monthly_returns r LEFT JOIN industries i ON i.industry_id = r.industry_id
     WHERE i.industry_id IS NULL
    UNION ALL
    SELECT 'condition_industry_performance -> economic_conditions', COUNT(*)
      FROM condition_industry_performance p
      LEFT JOIN economic_conditions c ON c.condition_id = p.condition_id
     WHERE c.condition_id IS NULL
    UNION ALL
    SELECT 'condition_industry_performance -> industries', COUNT(*)
      FROM condition_industry_performance p LEFT JOIN industries i ON i.industry_id = p.industry_id
     WHERE i.industry_id IS NULL
) o;

-- =============================================================================
-- SECTION 6: Macro data and conditions
-- =============================================================================

-- 6a. Every stock month has a value for every indicator.
--     WARN, not FAIL: Oct 2025 CPI/UNRATE were never published (2025 US
--     government shutdown), so those months are legitimately missing.
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Macro & conditions', 'Every stock month has a value for every indicator',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' missing (month, indicator) pairs',
              COALESCE(CONCAT(': ', SUBSTRING(GROUP_CONCAT(CONCAT(sm.month, ' ', i.indicator_name)
                                        ORDER BY sm.month SEPARATOR '; '), 1, 300)), ''))
FROM (SELECT DISTINCT month FROM monthly_stock_prices) sm
CROSS JOIN economic_indicators i
LEFT JOIN economic_data d ON d.indicator_id = i.indicator_id AND d.month = sm.month
WHERE d.indicator_id IS NULL;

-- 6b. Quarterly series repeat one value across all 3 months of each quarter
--     (identified by the word 'quarterly' in economic_indicators.unit)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Macro & conditions', 'Quarterly series repeat one value across each quarter''s months',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' quarters with differing values',
              COALESCE(CONCAT(' e.g. ', MIN(CONCAT(name, ' ', yr, 'Q', qtr))), ''))
FROM (
    SELECT i.indicator_name AS name, YEAR(d.month) AS yr, QUARTER(d.month) AS qtr
    FROM economic_data d
    JOIN economic_indicators i ON i.indicator_id = d.indicator_id
    WHERE i.unit LIKE '%quarterly%'
    GROUP BY i.indicator_name, YEAR(d.month), QUARTER(d.month)
    HAVING COUNT(DISTINCT d.value) <> 1
) q;

-- 6c. Each indicator's condition ranges cover every value exactly once
--     (no month falls in 0 or 2+ conditions of the same indicator)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Macro & conditions', 'Every macro value falls in exactly one condition of its indicator',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' (indicator, month) values matched by 0 or 2+ conditions',
              COALESCE(CONCAT(' e.g. ', MIN(CONCAT(x.indicator_id, ' ', x.month, ' n=', x.n))), ''))
FROM (
    SELECT d.indicator_id, d.month, COUNT(ec.condition_id) AS n
    FROM economic_data d
    JOIN (SELECT DISTINCT indicator_id FROM economic_conditions) has_cond
      ON has_cond.indicator_id = d.indicator_id
    LEFT JOIN economic_conditions ec
      ON ec.indicator_id = d.indicator_id
     AND (ec.min_value IS NULL OR d.value >= ec.min_value)
     AND (ec.max_value IS NULL OR d.value <  ec.max_value)
    GROUP BY d.indicator_id, d.month
    HAVING COUNT(ec.condition_id) <> 1
) x;

-- 6d. Percent series look like percents (catches 0.05 loaded instead of 5.00)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Macro & conditions', 'Percent series look like percents (max |value| > 1)',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' percent indicators whose values are all within +/-1',
              COALESCE(CONCAT(': ', GROUP_CONCAT(name)), ''))
FROM (
    SELECT i.indicator_name AS name
    FROM economic_data d
    JOIN economic_indicators i ON i.indicator_id = d.indicator_id
    WHERE i.unit LIKE 'Percent%'
    GROUP BY i.indicator_name
    HAVING MAX(ABS(d.value)) <= 1
) p;

-- =============================================================================
-- SECTION 7: Derived tables recomputed from source
-- =============================================================================

-- 7a. industry_monthly_returns = cap-weighted recomputation (both directions)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Derived tables', 'industry_monthly_returns matches cap-weighted recomputation',
       IF(COALESCE(SUM(bad), 0) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' industry-months compared, ', COALESCE(SUM(bad), 0),
              ' mismatched or missing (tolerance 0.0001)')
FROM (
    SELECT (   r.industry_id IS NULL
            OR r.num_companies <> calc.n
            OR ABS(r.avg_return - calc.cw_ret) > 0.0001) AS bad
    FROM (
        SELECT c.industry_id, m.month, COUNT(*) AS n,
               SUM(m.monthly_return * m.start_market_cap) / SUM(m.start_market_cap) AS cw_ret
        FROM monthly_stock_prices m
        JOIN companies c ON c.company_id = m.company_id
        WHERE m.monthly_return IS NOT NULL AND m.start_market_cap IS NOT NULL
        GROUP BY c.industry_id, m.month
    ) calc
    LEFT JOIN industry_monthly_returns r
           ON r.industry_id = calc.industry_id AND r.month = calc.month
) x;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Derived tables', 'No industry_monthly_returns rows without underlying stock rows',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' stale rows')
FROM industry_monthly_returns r
WHERE NOT EXISTS (
    SELECT 1 FROM monthly_stock_prices m JOIN companies c ON c.company_id = m.company_id
    WHERE c.industry_id = r.industry_id AND m.month = r.month
      AND m.monthly_return IS NOT NULL AND m.start_market_cap IS NOT NULL);

-- 7b. condition_industry_performance = recomputation over the months where
--     each condition held (min inclusive, max exclusive), both directions
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Derived tables', 'condition_industry_performance matches recomputation',
       IF(COALESCE(SUM(bad), 0) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' (condition, industry) pairs compared, ', COALESCE(SUM(bad), 0),
              ' mismatched or missing (tolerance 0.00001)')
FROM (
    SELECT (   p.condition_id IS NULL
            OR p.num_months <> calc.n
            OR ABS(p.avg_return - calc.avg_ret) > 0.00001
            OR ABS(p.avg_excess_return - calc.avg_excess) > 0.00001) AS bad
    FROM (
        SELECT ec.condition_id, r.industry_id, COUNT(*) AS n,
               AVG(r.avg_return) AS avg_ret,
               AVG(r.avg_return - mk.mkt_ret) AS avg_excess
        FROM economic_conditions ec
        JOIN economic_data d
          ON d.indicator_id = ec.indicator_id
         AND (ec.min_value IS NULL OR d.value >= ec.min_value)
         AND (ec.max_value IS NULL OR d.value <  ec.max_value)
        JOIN industry_monthly_returns r ON r.month = d.month
        JOIN (SELECT month,
                     SUM(monthly_return * start_market_cap) / SUM(start_market_cap) AS mkt_ret
              FROM monthly_stock_prices
              WHERE monthly_return IS NOT NULL AND start_market_cap IS NOT NULL
              GROUP BY month) mk ON mk.month = d.month
        GROUP BY ec.condition_id, r.industry_id
    ) calc
    LEFT JOIN condition_industry_performance p
           ON p.condition_id = calc.condition_id AND p.industry_id = calc.industry_id
) x;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Derived tables', 'condition_industry_performance has no extra rows',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' rows with no qualifying months')
FROM condition_industry_performance p
JOIN economic_conditions ec ON ec.condition_id = p.condition_id
WHERE NOT EXISTS (
    SELECT 1 FROM economic_data d
    JOIN industry_monthly_returns r ON r.month = d.month AND r.industry_id = p.industry_id
    WHERE d.indicator_id = ec.indicator_id
      AND (ec.min_value IS NULL OR d.value >= ec.min_value)
      AND (ec.max_value IS NULL OR d.value <  ec.max_value));

-- =============================================================================
-- SECTION 8: Stock data quality (WARN = known characteristic, see contract §5)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '8. Stock data quality', 'Rows with no price, return or market cap at all',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' empty rows (excluded from every weighted calculation)')
FROM monthly_stock_prices
WHERE close_price IS NULL AND monthly_return IS NULL AND start_market_cap IS NULL;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '8. Stock data quality', 'Extreme monthly returns (> +300%)',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' rows; max ', COALESCE(MAX(monthly_return), 0),
              ' (mostly micro-caps; cap weighting limits their effect)')
FROM monthly_stock_prices
WHERE monthly_return > 3.0;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '8. Stock data quality', 'Companies without a ticker',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' companies with NULL ticker (identify them by company_id/company_name)')
FROM companies
WHERE ticker IS NULL;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '8. Stock data quality', 'Companies with no monthly rows',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' companies')
FROM companies c
WHERE NOT EXISTS (SELECT 1 FROM monthly_stock_prices m WHERE m.company_id = c.company_id);

-- =============================================================================
-- SECTION 9: Load status (informational only)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '9. Load status', CONCAT('Rows in ', t.tbl), 'INFO', CONCAT(t.n, ' rows')
FROM (
              SELECT 'industries' AS tbl, COUNT(*) AS n FROM industries
    UNION ALL SELECT 'companies', COUNT(*) FROM companies
    UNION ALL SELECT 'monthly_stock_prices', COUNT(*) FROM monthly_stock_prices
    UNION ALL SELECT 'economic_indicators', COUNT(*) FROM economic_indicators
    UNION ALL SELECT 'economic_data', COUNT(*) FROM economic_data
    UNION ALL SELECT 'economic_conditions', COUNT(*) FROM economic_conditions
    UNION ALL SELECT 'industry_monthly_returns', COUNT(*) FROM industry_monthly_returns
    UNION ALL SELECT 'condition_industry_performance', COUNT(*) FROM condition_industry_performance
) t;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '9. Load status', 'Stock universe and date range', 'INFO',
       CONCAT(COUNT(DISTINCT company_id), ' companies, ', COUNT(DISTINCT month), ' months, ',
              COALESCE(CONCAT(MIN(month), ' to ', MAX(month)), 'no data'))
FROM monthly_stock_prices;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '9. Load status', 'Macro date range', 'INFO',
       COALESCE(CONCAT(MIN(month), ' to ', MAX(month)), 'no data')
FROM economic_data;

-- =============================================================================
-- REPORT
-- =============================================================================
SELECT ROW_NUMBER() OVER (ORDER BY check_no) AS check_no,
       section, check_name, status, detail
FROM validation_results
ORDER BY check_no;

SELECT status, COUNT(*) AS checks
FROM validation_results
GROUP BY status
ORDER BY FIELD(status, 'FAIL', 'WARN', 'PASS', 'INFO');
