-- =============================================================================
-- 03_validate_schema.sql   (schema v2.0: 8 monthly tables)
-- Verifies structure (tables, PKs, FKs, indexes, CHECKs), reference data,
-- referential integrity, and the data-alignment rules in SCHEMA_CONTRACT.md.
--
-- Safe to run any time: read-only except for a TEMPORARY results table.
-- Works on an EMPTY database: data checks pass trivially when there are no
-- rows; nothing fails just because a table hasn't been loaded yet.
--
--   mysql -u <user> -p < schema/03_validate_schema.sql
--
-- Output: one row per check -> section | check_name | status | detail
--   PASS / FAIL / WARN / INFO.   Any FAIL must be fixed before sharing data.
-- =============================================================================

USE stock_macro_db;

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

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '1. Tables', 'Removed v1.0 tables are gone (daily_stock_prices, annual_economic_summary)',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       COALESCE(CONCAT('still present: ', GROUP_CONCAT(TABLE_NAME)), 'none present')
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('daily_stock_prices', 'annual_economic_summary');

-- =============================================================================
-- SECTION 2: Primary keys (expected column list per table)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '2. Primary keys',
       CONCAT('PK on ', e.tbl, ' = (', e.pk_cols, ')'),
       IF(a.actual_cols <=> e.pk_cols, 'PASS', 'FAIL'),
       CONCAT('actual: (', COALESCE(a.actual_cols, 'NONE'), ')')
FROM (
              SELECT 'industries' AS tbl,                  'industry_id' AS pk_cols
    UNION ALL SELECT 'companies',                          'ticker'
    UNION ALL SELECT 'monthly_stock_prices',               'ticker,period_date'
    UNION ALL SELECT 'economic_indicators',                'indicator_id'
    UNION ALL SELECT 'economic_data',                      'indicator_id,period_date'
    UNION ALL SELECT 'economic_conditions',                'condition_id'
    UNION ALL SELECT 'industry_monthly_returns',           'industry_id,period_date'
    UNION ALL SELECT 'condition_industry_performance',     'condition_id,industry_id'
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
    UNION ALL SELECT 'monthly_stock_prices',           'ticker',       'companies',           'ticker'
    UNION ALL SELECT 'economic_data',                  'indicator_id', 'economic_indicators', 'indicator_id'
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

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '3. Foreign keys', 'All ticker columns use ascii / ascii_bin',
       IF(COUNT(*) = 2 AND SUM(CHARACTER_SET_NAME <> 'ascii' OR COLLATION_NAME <> 'ascii_bin') = 0,
          'PASS', 'FAIL'),
       GROUP_CONCAT(CONCAT(TABLE_NAME, ':', COLLATION_NAME) SEPARATOR '; ')
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'ticker';

-- =============================================================================
-- SECTION 4: Secondary / unique indexes and CHECK constraints
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '4. Indexes & CHECKs',
       CONCAT('Index ', e.tbl, '.', e.idx, ' (', e.cols, ')'),
       IF(a.actual_cols <=> e.cols, 'PASS', 'FAIL'),
       CONCAT('actual: (', COALESCE(a.actual_cols, 'NONE'), ')',
              IF(a.non_unique = 0, ' UNIQUE', ''))
FROM (
              SELECT 'industries' AS tbl, 'uq_industries_name' AS idx, 'industry_name' AS cols
    UNION ALL SELECT 'industries',                     'uq_industries_sector_code', 'sector_code'
    UNION ALL SELECT 'companies',                      'uq_companies_permno',       'permno'
    UNION ALL SELECT 'companies',                      'idx_companies_industry',    'industry_id'
    UNION ALL SELECT 'monthly_stock_prices',           'idx_monthly_period_date',   'period_date'
    UNION ALL SELECT 'economic_indicators',            'uq_indicators_code',        'indicator_code'
    UNION ALL SELECT 'economic_data',                  'idx_econdata_period_date',  'period_date'
    UNION ALL SELECT 'economic_conditions',            'uq_conditions_name_start',  'condition_name,start_date'
    UNION ALL SELECT 'economic_conditions',            'idx_conditions_dates',      'start_date,end_date'
    UNION ALL SELECT 'economic_conditions',            'idx_conditions_category',   'condition_category'
    UNION ALL SELECT 'industry_monthly_returns',       'idx_imr_period_date',       'period_date'
    UNION ALL SELECT 'condition_industry_performance', 'idx_cip_industry',          'industry_id'
) e
LEFT JOIN (
    SELECT TABLE_NAME, INDEX_NAME, MIN(NON_UNIQUE) AS non_unique,
           GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',') AS actual_cols
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
    GROUP BY TABLE_NAME, INDEX_NAME
) a ON a.TABLE_NAME = e.tbl AND a.INDEX_NAME = e.idx;

-- CHECK constraints present and ENFORCED (needs MySQL 8.0.16+)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '4. Indexes & CHECKs', 'CHECK constraints present and enforced',
       IF(COUNT(*) >= 19 AND COALESCE(SUM(ENFORCED = 'NO'), 0) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' CHECK constraints (expected 19), ',
              COALESCE(SUM(ENFORCED = 'NO'), 0), ' not enforced; server ', VERSION())
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_TYPE = 'CHECK';

-- =============================================================================
-- SECTION 5: Reference data (from 02_reference_data.sql)
--   Empty = WARN (not loaded yet). Present but wrong = FAIL.
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '5. Reference data', 'industries = 12 Fama-French industries with fixed IDs',
       CASE WHEN (SELECT COUNT(*) FROM industries) = 0 THEN 'WARN'
            WHEN SUM(i.industry_id IS NOT NULL) = 12
             AND (SELECT COUNT(*) FROM industries) = 12 THEN 'PASS'
            ELSE 'FAIL' END,
       CASE WHEN (SELECT COUNT(*) FROM industries) = 0
            THEN 'empty - run 02_reference_data.sql before loading companies'
            ELSE CONCAT(SUM(i.industry_id IS NOT NULL), '/12 expected (id, code) pairs found; ',
                        (SELECT COUNT(*) FROM industries), ' rows total') END
FROM (
              SELECT 1 AS id, 'NODUR' AS code UNION ALL SELECT 2, 'DURBL'
    UNION ALL SELECT 3, 'MANUF' UNION ALL SELECT 4, 'ENRGY' UNION ALL SELECT 5, 'CHEMS'
    UNION ALL SELECT 6, 'BUSEQ' UNION ALL SELECT 7, 'TELCM' UNION ALL SELECT 8, 'UTILS'
    UNION ALL SELECT 9, 'SHOPS' UNION ALL SELECT 10, 'HLTH' UNION ALL SELECT 11, 'MONEY'
    UNION ALL SELECT 12, 'OTHER'
) e
LEFT JOIN industries i ON i.industry_id = e.id AND i.sector_code = e.code;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '5. Reference data', 'Core FRED series registered with fixed IDs',
       CASE WHEN (SELECT COUNT(*) FROM economic_indicators) = 0 THEN 'WARN'
            WHEN SUM(i.indicator_id IS NOT NULL) = 5 THEN 'PASS'
            ELSE 'FAIL' END,
       CASE WHEN (SELECT COUNT(*) FROM economic_indicators) = 0
            THEN 'empty - run 02_reference_data.sql before loading economic_data'
            ELSE CONCAT(SUM(i.indicator_id IS NOT NULL),
                        '/5 of FEDFUNDS, CPIAUCSL, GDP, GDPC1, UNRATE at expected IDs') END
FROM (
              SELECT 1 AS id, 'FEDFUNDS' AS code UNION ALL SELECT 2, 'CPIAUCSL'
    UNION ALL SELECT 3, 'GDP' UNION ALL SELECT 4, 'GDPC1' UNION ALL SELECT 5, 'UNRATE'
) e
LEFT JOIN economic_indicators i ON i.indicator_id = e.id AND i.indicator_code = e.code;

-- =============================================================================
-- SECTION 6: Referential integrity (orphans). Always 0 while FKs are on, but
-- catches rows bulk-loaded with FOREIGN_KEY_CHECKS = 0.
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Orphans', o.chk, IF(o.n = 0, 'PASS', 'FAIL'), CONCAT(o.n, ' orphan rows')
FROM (
    SELECT 'companies -> industries' AS chk, COUNT(*) AS n
      FROM companies c LEFT JOIN industries i ON i.industry_id = c.industry_id
     WHERE i.industry_id IS NULL
    UNION ALL
    SELECT 'monthly_stock_prices -> companies', COUNT(*)
      FROM monthly_stock_prices m LEFT JOIN companies c ON c.ticker = m.ticker
     WHERE c.ticker IS NULL
    UNION ALL
    SELECT 'economic_data -> economic_indicators', COUNT(*)
      FROM economic_data d LEFT JOIN economic_indicators i ON i.indicator_id = d.indicator_id
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
-- SECTION 7: Data alignment (SCHEMA_CONTRACT.md rules)
-- Every check below passes trivially on empty tables.
-- =============================================================================

-- 7a. Every month that has stock data has a value for EVERY indicator,
--     so stock-to-macro joins never silently drop months.
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'Every stock month has a value for every FRED indicator',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' missing (month, indicator) pairs',
              COALESCE(CONCAT(' e.g. ', MIN(CONCAT(sm.period_date, ' ', i.indicator_code))), ''))
FROM (SELECT DISTINCT period_date FROM monthly_stock_prices) sm
CROSS JOIN economic_indicators i
LEFT JOIN economic_data d
       ON d.indicator_id = i.indicator_id AND d.period_date = sm.period_date
WHERE d.indicator_id IS NULL;

-- 7b. No missing months inside each indicator's series
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'No gaps inside each indicator''s monthly series',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' indicators with gaps',
              COALESCE(CONCAT(': ', GROUP_CONCAT(code SEPARATOR ', ')), ''))
FROM (
    SELECT i.indicator_code AS code
    FROM economic_data d
    JOIN economic_indicators i ON i.indicator_id = d.indicator_id
    GROUP BY i.indicator_code
    HAVING COUNT(*) <> PERIOD_DIFF(DATE_FORMAT(MAX(d.period_date), '%Y%m'),
                                   DATE_FORMAT(MIN(d.period_date), '%Y%m')) + 1
) g;

-- 7c. QUARTER_REPEAT series: all 3 months of a quarter present and identical
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'Quarterly series repeat one value across all 3 months of each quarter',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' bad (indicator, quarter) groups',
              COALESCE(CONCAT(' e.g. ', MIN(CONCAT(code, ' ', yr, 'Q', qtr))), ''))
FROM (
    SELECT i.indicator_code AS code, YEAR(d.period_date) AS yr, QUARTER(d.period_date) AS qtr
    FROM economic_data d
    JOIN economic_indicators i ON i.indicator_id = d.indicator_id
    WHERE i.monthly_alignment = 'QUARTER_REPEAT'
    GROUP BY i.indicator_code, YEAR(d.period_date), QUARTER(d.period_date)
    HAVING COUNT(*) <> 3 OR COUNT(DISTINCT d.value) <> 1
) q;

-- 7d. industry_monthly_returns equals recomputation from monthly_stock_prices
--     (checks both directions: wrong values AND industry-months never built)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'industry_monthly_returns matches monthly_stock_prices',
       IF((SELECT COUNT(*) FROM industry_monthly_returns) = 0
          OR COALESCE(SUM(bad), 0) = 0, 'PASS', 'FAIL'),
       IF((SELECT COUNT(*) FROM industry_monthly_returns) = 0,
          'not built yet (0 rows) - skipped',
          CONCAT(COUNT(*), ' industry-months compared, ', COALESCE(SUM(bad), 0), ' mismatched or missing'))
FROM (
    SELECT (   r.industry_id IS NULL
            OR r.stock_count <> calc.n
            OR ABS(r.avg_monthly_return - calc.avg_ret) > 0.000001
            OR NOT (r.volatility <=> calc.vol
                    OR ABS(r.volatility - calc.vol) <= 0.000001)) AS bad
    FROM (
        SELECT c.industry_id, m.period_date, COUNT(*) AS n,
               AVG(m.monthly_return) AS avg_ret,
               IF(COUNT(*) >= 2, STDDEV_SAMP(m.monthly_return), NULL) AS vol
        FROM monthly_stock_prices m
        JOIN companies c ON c.ticker = m.ticker
        GROUP BY c.industry_id, m.period_date
    ) calc
    LEFT JOIN industry_monthly_returns r
           ON r.industry_id = calc.industry_id AND r.period_date = calc.period_date
) x;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'No industry_monthly_returns rows without underlying stock rows',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' stale rows')
FROM industry_monthly_returns r
WHERE NOT EXISTS (
    SELECT 1 FROM monthly_stock_prices m JOIN companies c ON c.ticker = m.ticker
    WHERE c.industry_id = r.industry_id AND m.period_date = r.period_date);

-- 7e. condition_industry_performance equals recomputation from
--     industry_monthly_returns over each episode's months
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'condition_industry_performance matches recomputation',
       IF(COALESCE(SUM(calc.n IS NULL OR
                 p.sample_months <> calc.n
              OR ABS(p.avg_monthly_return - calc.avg_ret) > 0.000005
              OR ABS(p.win_rate_pct - calc.win_pct) > 0.01
              OR ABS(p.excess_return_vs_market - calc.excess) > 0.000005), 0) = 0,
          'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' rows compared, ',
              COALESCE(SUM(calc.n IS NULL), 0), ' have no source months')
FROM condition_industry_performance p
LEFT JOIN (
    SELECT ec.condition_id, r.industry_id,
           COUNT(*)                                     AS n,
           AVG(r.avg_monthly_return)                    AS avg_ret,
           100 * AVG(r.avg_monthly_return > 0)          AS win_pct,
           AVG(r.avg_monthly_return) - AVG(mk.mkt_ret)  AS excess
    FROM economic_conditions ec
    JOIN industry_monthly_returns r
      ON r.period_date BETWEEN ec.start_date AND COALESCE(ec.end_date, '9999-12-01')
    JOIN (SELECT period_date, AVG(monthly_return) AS mkt_ret
          FROM monthly_stock_prices GROUP BY period_date) mk
      ON mk.period_date = r.period_date
    GROUP BY ec.condition_id, r.industry_id
) calc ON calc.condition_id = p.condition_id AND calc.industry_id = p.industry_id;

-- 7f. Episodes of the SAME condition must not overlap in time
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'No overlapping episodes of the same condition_name',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' overlapping pairs',
              COALESCE(CONCAT(' e.g. ids ', MIN(CONCAT(a.condition_id, '&', b.condition_id))), ''))
FROM economic_conditions a
JOIN economic_conditions b
  ON a.condition_name = b.condition_name
 AND a.condition_id < b.condition_id
 AND a.start_date <= COALESCE(b.end_date, '9999-12-01')
 AND b.start_date <= COALESCE(a.end_date, '9999-12-01');

-- 7g. Episodes should fall inside the months we actually have macro data for
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'Condition episodes lie within economic_data coverage',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' episodes start before or end after the macro data range')
FROM economic_conditions ec
CROSS JOIN (SELECT MIN(period_date) AS lo, MAX(period_date) AS hi FROM economic_data) r
WHERE r.lo IS NOT NULL
  AND (ec.start_date < r.lo OR COALESCE(ec.end_date, r.hi) > r.hi);

-- 7h. Companies with no monthly rows (likely a ticker mismatch in ETL)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'Every company has monthly price data',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' companies with no monthly rows',
              COALESCE(CONCAT(': ', SUBSTRING(GROUP_CONCAT(c.ticker ORDER BY c.ticker SEPARATOR ', '), 1, 200)), ''))
FROM companies c
WHERE NOT EXISTS (SELECT 1 FROM monthly_stock_prices m WHERE m.ticker = c.ticker);

-- 7i. Gaps inside each ticker's monthly series
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'No gaps inside each ticker''s monthly series',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' tickers with gaps',
              COALESCE(CONCAT(': ', SUBSTRING(GROUP_CONCAT(ticker SEPARATOR ', '), 1, 200)), ''))
FROM (
    SELECT ticker
    FROM monthly_stock_prices
    GROUP BY ticker
    HAVING COUNT(*) <> PERIOD_DIFF(DATE_FORMAT(MAX(period_date), '%Y%m'),
                                   DATE_FORMAT(MIN(period_date), '%Y%m')) + 1
) g;

-- 7j. Implausible monthly returns (> +300%) usually mean a unit error
--     (e.g. percent loaded as fraction)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'No implausible monthly returns (> +300%)',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' rows with monthly_return > 3.0',
              COALESCE(CONCAT(' e.g. ', MIN(CONCAT(ticker, ' ', period_date))), ''))
FROM monthly_stock_prices
WHERE monthly_return > 3.0;

-- 7k. Rates stored in percent, not fractions (FEDFUNDS 0.05 instead of 5.00 = unit error)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '7. Alignment', 'Percent-unit FRED series look like percents (max > 1)',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' percent series whose max value is <= 1',
              COALESCE(CONCAT(': ', GROUP_CONCAT(code)), ''))
FROM (
    SELECT i.indicator_code AS code
    FROM economic_data d
    JOIN economic_indicators i ON i.indicator_id = d.indicator_id
    WHERE i.units = 'Percent'
    GROUP BY i.indicator_code
    HAVING MAX(d.value) <= 1
) p;

-- =============================================================================
-- SECTION 8: Load status (informational only)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '8. Load status', CONCAT('Rows in ', t.tbl), 'INFO', CONCAT(t.n, ' rows')
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
SELECT '8. Load status', 'Stock universe and date range', 'INFO',
       CONCAT(COUNT(DISTINCT ticker), ' tickers (target ~500), ',
              COUNT(DISTINCT period_date), ' months, ',
              COALESCE(CONCAT(MIN(period_date), ' to ', MAX(period_date)), 'no data'),
              ', ', COALESCE(SUM(trading_days IS NULL), 0), ' rows with NULL trading_days')
FROM monthly_stock_prices;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '8. Load status', 'Macro date range', 'INFO',
       COALESCE(CONCAT(MIN(period_date), ' to ', MAX(period_date)), 'no data')
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
