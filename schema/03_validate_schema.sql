-- =============================================================================
-- 03_validate_schema.sql
-- Verifies structure (tables, PKs, FKs, indexes, CHECKs), referential
-- integrity, and the data-alignment rules in SCHEMA_CONTRACT.md.
--
-- Safe to run any time: read-only except for a TEMPORARY results table.
-- Run after 01 (structure checks) and again after every data load.
--
--   mysql -u <user> -p < schema/03_validate_schema.sql
--
-- Output: one row per check -> section | check_name | status | detail
--   status = PASS / FAIL / WARN.  Any FAIL must be fixed before merging data.
-- =============================================================================

USE stock_macro_db;

DROP TEMPORARY TABLE IF EXISTS validation_results;
CREATE TEMPORARY TABLE validation_results (
    check_no    INT AUTO_INCREMENT PRIMARY KEY,
    section     VARCHAR(30)  NOT NULL,
    check_name  VARCHAR(120) NOT NULL,
    status      ENUM('PASS', 'FAIL', 'WARN') NOT NULL,
    detail      VARCHAR(1000) NULL
);

-- =============================================================================
-- SECTION 1: Tables exist
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
    UNION ALL SELECT 'daily_stock_prices'
    UNION ALL SELECT 'monthly_stock_prices'
    UNION ALL SELECT 'economic_indicators'
    UNION ALL SELECT 'economic_data'
    UNION ALL SELECT 'economic_conditions'
    UNION ALL SELECT 'industry_monthly_returns'
    UNION ALL SELECT 'condition_industry_performance'
    UNION ALL SELECT 'annual_economic_summary'
) e
LEFT JOIN information_schema.TABLES t
       ON t.TABLE_SCHEMA = DATABASE() AND t.TABLE_NAME = e.tbl;

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '1. Tables', 'Exactly 10 base tables in schema',
       IF(COUNT(*) = 10, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' base tables found')
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE';

-- =============================================================================
-- SECTION 2: Primary keys (expected column list per table)
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '2. Primary keys',
       CONCAT('PK on ', e.tbl, ' = (', e.pk_cols, ')'),
       IF(a.actual_cols = e.pk_cols, 'PASS', 'FAIL'),
       CONCAT('actual: (', COALESCE(a.actual_cols, 'NONE'), ')')
FROM (
          SELECT 'industries' AS tbl,                    'industry_id' AS pk_cols
    UNION ALL SELECT 'companies',                        'ticker'
    UNION ALL SELECT 'daily_stock_prices',               'ticker,trade_date'
    UNION ALL SELECT 'monthly_stock_prices',             'ticker,period_date'
    UNION ALL SELECT 'economic_indicators',              'indicator_id'
    UNION ALL SELECT 'economic_data',                    'indicator_id,observation_date'
    UNION ALL SELECT 'economic_conditions',              'condition_id'
    UNION ALL SELECT 'industry_monthly_returns',         'industry_id,period_date'
    UNION ALL SELECT 'condition_industry_performance',   'condition_id,industry_id'
    UNION ALL SELECT 'annual_economic_summary',          'year'
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
    UNION ALL SELECT 'daily_stock_prices',             'ticker',       'companies',           'ticker'
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

-- Ticker columns must share charset/collation or FKs/joins break or get slow.
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '3. Foreign keys', 'All ticker columns use ascii / ascii_bin',
       IF(SUM(CHARACTER_SET_NAME <> 'ascii' OR COLLATION_NAME <> 'ascii_bin') = 0, 'PASS', 'FAIL'),
       GROUP_CONCAT(CONCAT(TABLE_NAME, ':', COLLATION_NAME) SEPARATOR '; ')
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'ticker';

-- =============================================================================
-- SECTION 4: Secondary / unique indexes
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '4. Indexes',
       CONCAT('Index ', e.tbl, '.', e.idx, ' (', e.cols, ')'),
       IF(a.actual_cols = e.cols, 'PASS', 'FAIL'),
       CONCAT('actual: (', COALESCE(a.actual_cols, 'NONE'), ')',
              IF(a.non_unique = 0, ' UNIQUE', ''))
FROM (
          SELECT 'industries' AS tbl, 'uq_industries_name' AS idx, 'industry_name' AS cols
    UNION ALL SELECT 'industries',                     'uq_industries_sector_code',     'sector_code'
    UNION ALL SELECT 'companies',                      'uq_companies_permno',           'permno'
    UNION ALL SELECT 'companies',                      'idx_companies_industry',        'industry_id'
    UNION ALL SELECT 'daily_stock_prices',             'idx_daily_trade_date',          'trade_date'
    UNION ALL SELECT 'monthly_stock_prices',           'idx_monthly_period_date',       'period_date'
    UNION ALL SELECT 'economic_indicators',            'uq_indicators_code',            'indicator_code'
    UNION ALL SELECT 'economic_data',                  'idx_econdata_observation_date', 'observation_date'
    UNION ALL SELECT 'economic_conditions',            'uq_conditions_name_start',      'condition_name,start_date'
    UNION ALL SELECT 'economic_conditions',            'idx_conditions_dates',          'start_date,end_date'
    UNION ALL SELECT 'economic_conditions',            'idx_conditions_category',       'condition_category'
    UNION ALL SELECT 'industry_monthly_returns',       'idx_imr_period_date',           'period_date'
    UNION ALL SELECT 'condition_industry_performance', 'idx_cip_industry',              'industry_id'
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
SELECT '4. Indexes', 'CHECK constraints present and enforced',
       IF(COUNT(*) >= 25 AND SUM(ENFORCED = 'NO') = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' CHECK constraints (expected 25), ', SUM(ENFORCED = 'NO'),
              ' not enforced; server ', VERSION())
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_TYPE = 'CHECK';

-- =============================================================================
-- SECTION 5: Referential integrity (orphans). Should always be 0 while FKs are
-- on, but catches rows bulk-loaded with FOREIGN_KEY_CHECKS = 0.
-- =============================================================================
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '5. Orphans', o.chk, IF(o.n = 0, 'PASS', 'FAIL'), CONCAT(o.n, ' orphan rows')
FROM (
    SELECT 'companies -> industries' AS chk, COUNT(*) AS n
      FROM companies c LEFT JOIN industries i ON i.industry_id = c.industry_id
     WHERE i.industry_id IS NULL
    UNION ALL
    SELECT 'daily_stock_prices -> companies', COUNT(*)
      FROM daily_stock_prices d LEFT JOIN companies c ON c.ticker = d.ticker
     WHERE c.ticker IS NULL
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
-- SECTION 6: Data alignment (SCHEMA_CONTRACT.md rules)
-- =============================================================================

-- 6a. Every monthly row with daily data behind it must match the daily rows.
--     (Months with no daily rows, e.g. mock Dec 2023 / Feb 2024, are skipped.)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'monthly_stock_prices matches daily_stock_prices aggregation',
       IF(SUM(bad) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' ticker-months compared, ', COALESCE(SUM(bad), 0), ' mismatched',
              COALESCE(CONCAT(' e.g. ', MIN(IF(bad = 1, CONCAT(ticker, ' ', period_date), NULL))), ''))
FROM (
    SELECT m.ticker, m.period_date,
           (   m.trading_days      <> agg.n_days
            OR m.total_volume      <> agg.sum_vol
            OR m.month_open_price  <> agg.first_close
            OR m.month_close_price <> agg.last_close
            OR ABS(m.monthly_return - agg.comp_ret) > 0.0001) AS bad
    FROM monthly_stock_prices m
    JOIN (
        SELECT d.ticker,
               DATE_FORMAT(d.trade_date, '%Y-%m-01')                AS period_date,
               COUNT(*)                                              AS n_days,
               SUM(d.volume)                                         AS sum_vol,
               EXP(SUM(LN(1 + d.daily_return))) - 1                  AS comp_ret,
               MIN(CASE WHEN d.trade_date = b.first_day THEN d.close_price END) AS first_close,
               MIN(CASE WHEN d.trade_date = b.last_day  THEN d.close_price END) AS last_close
        FROM daily_stock_prices d
        JOIN (SELECT ticker, DATE_FORMAT(trade_date, '%Y-%m-01') AS p,
                     MIN(trade_date) AS first_day, MAX(trade_date) AS last_day
              FROM daily_stock_prices
              GROUP BY ticker, DATE_FORMAT(trade_date, '%Y-%m-01')) b
          ON b.ticker = d.ticker AND b.p = DATE_FORMAT(d.trade_date, '%Y-%m-01')
        GROUP BY d.ticker, DATE_FORMAT(d.trade_date, '%Y-%m-01')
    ) agg ON agg.ticker = m.ticker AND agg.period_date = m.period_date
) x;

-- 6b. Daily rows with NULL daily_return (cannot be compounded into monthly_return)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'daily_stock_prices.daily_return populated',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' daily rows with NULL daily_return')
FROM daily_stock_prices WHERE daily_return IS NULL;

-- 6c. industry_monthly_returns equals recomputation from monthly_stock_prices
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'industry_monthly_returns matches monthly_stock_prices',
       IF(SUM(bad) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' industry-months compared, ', COALESCE(SUM(bad), 0), ' mismatched')
FROM (
    SELECT (   r.stock_count <> calc.n
            OR ABS(r.avg_monthly_return - calc.avg_ret) > 0.000001
            OR NOT (r.volatility <=> calc.vol
                    OR ABS(r.volatility - calc.vol) <= 0.000001)) AS bad
    FROM industry_monthly_returns r
    LEFT JOIN (
        SELECT c.industry_id, m.period_date, COUNT(*) AS n,
               AVG(m.monthly_return) AS avg_ret,
               IF(COUNT(*) >= 2, STDDEV_SAMP(m.monthly_return), NULL) AS vol
        FROM monthly_stock_prices m
        JOIN companies c ON c.ticker = m.ticker
        GROUP BY c.industry_id, m.period_date
    ) calc ON calc.industry_id = r.industry_id AND calc.period_date = r.period_date
) x;

-- 6d. condition_industry_performance matches recomputation, for every
--     (condition, industry) pair that has industry_monthly_returns rows
--     inside the episode. Pairs with no source months are reported as WARN.
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'condition_industry_performance matches recomputation',
       IF(SUM(calc.n IS NOT NULL AND (
                 p.sample_months <> calc.n
              OR ABS(p.avg_monthly_return - calc.avg_ret) > 0.000005
              OR ABS(p.win_rate_pct - calc.win_pct) > 0.01
              OR ABS(p.excess_return_vs_market - calc.excess) > 0.000005)) = 0,
          'PASS', 'FAIL'),
       CONCAT(SUM(calc.n IS NOT NULL), ' pairs recomputed, ',
              SUM(calc.n IS NULL), ' pairs have no source months (placeholders)')
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

INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'condition_industry_performance rows without source months',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' rows cannot be verified (expected with mock placeholders; must be 0 on real data)')
FROM condition_industry_performance p
WHERE NOT EXISTS (
    SELECT 1 FROM economic_conditions ec
    JOIN industry_monthly_returns r
      ON r.period_date BETWEEN ec.start_date AND COALESCE(ec.end_date, '9999-12-01')
    WHERE ec.condition_id = p.condition_id AND r.industry_id = p.industry_id);

-- 6e. Episodes of the SAME condition must not overlap in time
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'No overlapping episodes of the same condition_name',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' overlapping pairs',
              COALESCE(CONCAT(' e.g. ids ', MIN(CONCAT(a.condition_id, '&', b.condition_id))), ''))
FROM economic_conditions a
JOIN economic_conditions b
  ON a.condition_name = b.condition_name
 AND a.condition_id < b.condition_id
 AND a.start_date <= COALESCE(b.end_date, '9999-12-01')
 AND b.start_date <= COALESCE(a.end_date, '9999-12-01');

-- 6f. Quarterly indicators must be dated on quarter starts (Jan/Apr/Jul/Oct)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'Quarterly FRED series dated on quarter-start months',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' quarterly observations not in Jan/Apr/Jul/Oct')
FROM economic_data d
JOIN economic_indicators i ON i.indicator_id = d.indicator_id
WHERE i.frequency = 'Q' AND MONTH(d.observation_date) NOT IN (1, 4, 7, 10);

-- 6g. Annual indicators must be dated January 1
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'Annual FRED series dated on January 1',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' annual observations not on YYYY-01-01')
FROM economic_data d
JOIN economic_indicators i ON i.indicator_id = d.indicator_id
WHERE i.frequency = 'A' AND MONTH(d.observation_date) <> 1;

-- 6h. Required FRED series are registered
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'Core FRED series registered (FEDFUNDS, CPIAUCSL, GDP, UNRATE)',
       IF(COUNT(*) = 4, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), '/4 present')
FROM economic_indicators
WHERE indicator_code IN ('FEDFUNDS', 'CPIAUCSL', 'GDP', 'UNRATE');

-- 6i. Companies with no price data at all (fine for delisted placeholders)
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'Every company has monthly price data',
       IF(COUNT(*) = 0, 'PASS', 'WARN'),
       CONCAT(COUNT(*), ' companies with no monthly rows',
              COALESCE(CONCAT(': ', GROUP_CONCAT(c.ticker ORDER BY c.ticker SEPARATOR ', ')), ''))
FROM companies c
WHERE NOT EXISTS (SELECT 1 FROM monthly_stock_prices m WHERE m.ticker = c.ticker);

-- 6j. Gaps: a ticker's monthly series should have no missing months between
--     its first and last month.
INSERT INTO validation_results (section, check_name, status, detail)
SELECT '6. Alignment', 'No gaps inside each ticker''s monthly series',
       IF(SUM(expected_months <> actual_months) = 0, 'PASS', 'WARN'),
       CONCAT(COALESCE(SUM(expected_months <> actual_months), 0), ' tickers with gaps')
FROM (
    SELECT ticker,
           PERIOD_DIFF(DATE_FORMAT(MAX(period_date), '%Y%m'),
                       DATE_FORMAT(MIN(period_date), '%Y%m')) + 1 AS expected_months,
           COUNT(*) AS actual_months
    FROM monthly_stock_prices
    GROUP BY ticker
) g;

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
ORDER BY FIELD(status, 'FAIL', 'WARN', 'PASS');
