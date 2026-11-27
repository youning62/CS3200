-- =============================================================================
-- 01_create_tables.sql
-- CS3200 Project: Analyzing Stock Market Performance Across Different
--                 Macroeconomic Environments
-- Team: Martin Villa, Youning Zheng, Ryan Marshall, Corey Rattray
--
-- Target: MySQL 8.0.16+ (CHECK constraints are enforced from 8.0.16 onward)
-- Schema version: 3.0 (matches the real-data dump, Dump20261126.sql)
--
-- !! WARNING: this script DROPS and recreates all tables. Running it on a
-- !! loaded database deletes all data. Back up first (mysqldump) if needed.
--
-- Column names, types and ORDER match the team's real-data dump exactly,
-- because the dump's INSERT statements have no column lists. Do not add,
-- remove or reorder columns without re-exporting the data.
-- v3.0 adds, on top of the dump's own DDL: CHECK constraints, secondary
-- indexes, NOT NULL where the data is always present, and explicit FK actions.
--
-- Conventions (full detail in schema/SCHEMA_CONTRACT.md):
--   * Every table is MONTHLY. Every `month` column is a DATE on the first day
--     of the month (YYYY-MM-01), enforced with CHECK (DAY(month) = 1).
--   * Returns are DECIMAL FRACTIONS (0.05 = +5%).
--   * Macro values and condition thresholds are PERCENT POINTS (5.33 = 5.33%).
--   * Companies are keyed on CRSP PERMNO (company_id), because CRSP reuses
--     tickers across companies over time.
--
-- Table build order (parents before children):
--   industries -> companies -> monthly_stock_prices
--   economic_indicators -> economic_data, economic_conditions
--   industry_monthly_returns, condition_industry_performance
-- =============================================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS stock_analysis
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE stock_analysis;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS
    condition_industry_performance,
    industry_monthly_returns,
    economic_conditions,
    economic_data,
    economic_indicators,
    monthly_stock_prices,
    companies,
    industries;
SET FOREIGN_KEY_CHECKS = 1;


-- -----------------------------------------------------------------------------
-- 1. industries
--    11 sector categories. IDs are fixed by the data load (1 = Technology ...
--    11 = Utilities); see SCHEMA_CONTRACT.md §4.3.
-- -----------------------------------------------------------------------------
CREATE TABLE industries (
    industry_id    INT          NOT NULL AUTO_INCREMENT,
    industry_name  VARCHAR(40)  NOT NULL,

    PRIMARY KEY (industry_id),
    UNIQUE KEY industry_name (industry_name)
) ENGINE = InnoDB
  COMMENT = 'Sector categories (11)';


-- -----------------------------------------------------------------------------
-- 2. companies
--    One row per CRSP security. company_id = CRSP PERMNO (stable over time).
--    ticker is informational only: it can be NULL and is NOT unique, because
--    CRSP reassigns tickers to different companies over the years.
-- -----------------------------------------------------------------------------
CREATE TABLE companies (
    company_id    INT           NOT NULL COMMENT 'CRSP permanent security ID',
    ticker        VARCHAR(10)   NULL,
    company_name  VARCHAR(120)  NOT NULL,
    industry_id   INT           NOT NULL,

    PRIMARY KEY (company_id),
    KEY industry_id (industry_id),
    KEY idx_companies_ticker (ticker),

    CONSTRAINT companies_ibfk_1
        FOREIGN KEY (industry_id) REFERENCES industries (industry_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_companies_permno_positive CHECK (company_id > 0),
    -- Uppercase letters/digits, optional '.' share-class suffix (e.g. BRK.B)
    CONSTRAINT chk_companies_ticker_format
        CHECK (ticker IS NULL OR REGEXP_LIKE(ticker, '^[A-Z0-9]{1,8}([.][A-Z])?$', 'c'))
) ENGINE = InnoDB
  COMMENT = 'CRSP securities, keyed on PERMNO';


-- -----------------------------------------------------------------------------
-- 3. monthly_stock_prices
--    CRSP monthly stock data. One row per company per month.
--    PK (company_id, month) = clustered index -> fast "one stock over time".
--    Secondary index on month                -> fast "all stocks in month X".
--    Value columns are NULLable: CRSP has months with no price/return
--    (e.g. a stock's first month). Weighted calculations skip those rows.
-- -----------------------------------------------------------------------------
CREATE TABLE monthly_stock_prices (
    company_id        INT            NOT NULL,
    month             DATE           NOT NULL COMMENT 'first day of the month',
    close_price       DECIMAL(14,6)  NULL,
    monthly_return    DECIMAL(12,6)  NULL COMMENT 'total return incl. dividends, 0.05 = 5%',
    start_market_cap  DECIMAL(18,2)  NULL COMMENT 'USD thousands at the previous month-end; return weight',

    PRIMARY KEY (company_id, month),
    KEY month (month),

    CONSTRAINT monthly_stock_prices_ibfk_1
        FOREIGN KEY (company_id) REFERENCES companies (company_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_msp_first_of_month   CHECK (DAY(month) = 1),
    CONSTRAINT chk_msp_price_positive   CHECK (close_price IS NULL OR close_price > 0),
    CONSTRAINT chk_msp_return_floor     CHECK (monthly_return IS NULL OR monthly_return >= -1),
    CONSTRAINT chk_msp_mktcap_positive  CHECK (start_market_cap IS NULL OR start_market_cap > 0)
) ENGINE = InnoDB
  COMMENT = 'CRSP monthly prices, returns and start-of-month market cap';


-- -----------------------------------------------------------------------------
-- 4. economic_indicators
--    The 4 macro measures. `unit` records the unit AND the source FRED series.
-- -----------------------------------------------------------------------------
CREATE TABLE economic_indicators (
    indicator_id    INT          NOT NULL AUTO_INCREMENT,
    indicator_name  VARCHAR(40)  NOT NULL,
    unit            VARCHAR(60)  NOT NULL,

    PRIMARY KEY (indicator_id),
    UNIQUE KEY indicator_name (indicator_name)
) ENGINE = InnoDB
  COMMENT = 'Macro indicators and their FRED source series';


-- -----------------------------------------------------------------------------
-- 5. economic_data
--    One value per indicator per month. Quarterly real GDP growth repeats
--    the quarter's value in each of its three months.
-- -----------------------------------------------------------------------------
CREATE TABLE economic_data (
    indicator_id  INT            NOT NULL,
    month         DATE           NOT NULL COMMENT 'first day of the month',
    value         DECIMAL(10,4)  NOT NULL,

    PRIMARY KEY (indicator_id, month),
    KEY idx_econdata_month (month),

    CONSTRAINT economic_data_ibfk_1
        FOREIGN KEY (indicator_id) REFERENCES economic_indicators (indicator_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_econdata_first_of_month CHECK (DAY(month) = 1)
) ENGINE = InnoDB
  COMMENT = 'Monthly macro values (percent points)';


-- -----------------------------------------------------------------------------
-- 6. economic_conditions
--    A condition is a VALUE RANGE on one indicator. A month is in the
--    condition when   (min_value IS NULL OR value >= min_value)
--                 AND (max_value IS NULL OR value <  max_value)
--    i.e. min inclusive, max exclusive. The 3 ranges per indicator
--    (Low / Moderate / High) cover the whole number line with no overlap.
-- -----------------------------------------------------------------------------
CREATE TABLE economic_conditions (
    condition_id    INT            NOT NULL AUTO_INCREMENT,
    condition_name  VARCHAR(40)    NOT NULL,
    indicator_id    INT            NOT NULL,
    min_value       DECIMAL(10,4)  NULL COMMENT 'inclusive; NULL = no lower bound',
    max_value       DECIMAL(10,4)  NULL COMMENT 'exclusive; NULL = no upper bound',

    PRIMARY KEY (condition_id),
    UNIQUE KEY condition_name (condition_name),
    KEY indicator_id (indicator_id),

    CONSTRAINT economic_conditions_ibfk_1
        FOREIGN KEY (indicator_id) REFERENCES economic_indicators (indicator_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_conditions_has_bound
        CHECK (min_value IS NOT NULL OR max_value IS NOT NULL),
    CONSTRAINT chk_conditions_bound_order
        CHECK (min_value IS NULL OR max_value IS NULL OR min_value < max_value)
) ENGINE = InnoDB
  COMMENT = 'Macro regimes defined as value ranges on one indicator';


-- -----------------------------------------------------------------------------
-- 7. industry_monthly_returns  (derived)
--    Market-cap-weighted return of each industry per month:
--      SUM(monthly_return * start_market_cap) / SUM(start_market_cap)
--    over stocks with both values present. num_companies = stocks used.
-- -----------------------------------------------------------------------------
CREATE TABLE industry_monthly_returns (
    industry_id    INT            NOT NULL,
    month          DATE           NOT NULL,
    avg_return     DECIMAL(12,6)  NULL COMMENT 'market-cap weighted',
    num_companies  INT            NULL,

    PRIMARY KEY (industry_id, month),
    KEY idx_imr_month (month),

    CONSTRAINT industry_monthly_returns_ibfk_1
        FOREIGN KEY (industry_id) REFERENCES industries (industry_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT chk_imr_first_of_month  CHECK (DAY(month) = 1),
    CONSTRAINT chk_imr_return_floor    CHECK (avg_return IS NULL OR avg_return >= -1),
    CONSTRAINT chk_imr_num_companies   CHECK (num_companies IS NULL OR num_companies >= 1)
) ENGINE = InnoDB
  COMMENT = 'Market-cap-weighted industry returns per month (derived)';


-- -----------------------------------------------------------------------------
-- 8. condition_industry_performance  (derived)
--    For each (condition, industry), over the months where the condition held:
--      num_months        = number of such months
--      avg_return        = AVG(industry_monthly_returns.avg_return)
--      avg_excess_return = AVG(industry return - market return), where the
--                          market return is cap-weighted over ALL stocks
-- -----------------------------------------------------------------------------
CREATE TABLE condition_industry_performance (
    condition_id       INT            NOT NULL,
    industry_id        INT            NOT NULL,
    num_months         INT            NULL,
    avg_return         DECIMAL(12,6)  NULL,
    avg_excess_return  DECIMAL(12,6)  NULL COMMENT 'industry return minus market return',

    PRIMARY KEY (condition_id, industry_id),
    KEY industry_id (industry_id),

    CONSTRAINT condition_industry_performance_ibfk_1
        FOREIGN KEY (condition_id) REFERENCES economic_conditions (condition_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT condition_industry_performance_ibfk_2
        FOREIGN KEY (industry_id) REFERENCES industries (industry_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT chk_cip_num_months    CHECK (num_months IS NULL OR num_months >= 1),
    CONSTRAINT chk_cip_return_floor  CHECK (avg_return IS NULL OR avg_return >= -1)
) ENGINE = InnoDB
  COMMENT = 'Industry performance under each macro condition (derived)';
