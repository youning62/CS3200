-- =============================================================================
-- 01_create_tables.sql
-- CS3200 Project: Analyzing Stock Market Performance Across Different
--                 Macroeconomic Environments
-- Team: Martin Villa, Youning Zheng, Ryan Marshall, Corey Rattray
--
-- Target: MySQL 8.0.16+ (CHECK constraints are enforced from 8.0.16 onward)
-- Schema version: 2.0 (monthly-only, 8 tables)
--
-- !! WARNING: this script DROPS and recreates all tables. Running it on a
-- !! loaded database deletes all data. Back up first (mysqldump) if needed.
--
-- Conventions (full detail in schema/SCHEMA_CONTRACT.md):
--   * Every table is MONTHLY. Every period column is a DATE on the first day
--     of the month (YYYY-MM-01), enforced with CHECK (DAY(col) = 1).
--     Stock and macro tables share the column name `period_date` so they join
--     directly on equality.
--   * Columns named *_return / volatility are DECIMAL FRACTIONS (0.0123 = +1.23%).
--   * Columns named *_pct are PERCENT POINTS (55.00 = 55%).
--   * FRED values are stored in the units FRED publishes (economic_indicators.units).
--   * Tickers are uppercase ASCII with a binary (case-sensitive) collation
--     that is identical in every table that references them.
--
-- Table build order (parents before children):
--   industries -> companies -> monthly_stock_prices
--   economic_indicators -> economic_data
--   economic_conditions
--   industry_monthly_returns -> condition_industry_performance
-- =============================================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS stock_macro_db
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE stock_macro_db;

-- Drop current tables AND the two tables removed in v2.0, so an older v1.0
-- database is upgraded cleanly. FK checks off so drop order doesn't matter.
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS
    condition_industry_performance,
    industry_monthly_returns,
    economic_conditions,
    economic_data,
    economic_indicators,
    monthly_stock_prices,
    companies,
    industries,
    daily_stock_prices,        -- removed in v2.0
    annual_economic_summary;   -- removed in v2.0
SET FOREIGN_KEY_CHECKS = 1;


-- -----------------------------------------------------------------------------
-- 1. industries
--    Lookup table: Fama-French 12-industry classification, derived from the
--    CRSP SIC code (SICCD). IDs 1-12 follow FF12 numbering and are inserted by
--    02_reference_data.sql so every teammate's database has identical IDs.
-- -----------------------------------------------------------------------------
CREATE TABLE industries (
    industry_id    SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    industry_name  VARCHAR(60)       NOT NULL,
    sector_code    VARCHAR(10)       NOT NULL,   -- FF12 short code, e.g. 'BUSEQ'
    description    VARCHAR(500)      NULL,

    PRIMARY KEY (industry_id),
    UNIQUE KEY uq_industries_name        (industry_name),
    UNIQUE KEY uq_industries_sector_code (sector_code),

    CONSTRAINT chk_industries_sector_code_upper
        CHECK (REGEXP_LIKE(sector_code, '^[A-Z]{2,10}$', 'c'))
) ENGINE = InnoDB
  COMMENT = 'Industry lookup (Fama-French 12 classification from CRSP SICCD)';


-- -----------------------------------------------------------------------------
-- 2. companies
--    One row per security in our ~500-company universe. `ticker` is the
--    natural key used by monthly_stock_prices. `permno` (CRSP permanent
--    security ID) is kept because tickers change and are reused over time.
-- -----------------------------------------------------------------------------
CREATE TABLE companies (
    ticker         VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    permno         INT UNSIGNED      NOT NULL,
    company_name   VARCHAR(150)      NOT NULL,
    industry_id    SMALLINT UNSIGNED NOT NULL,
    exchange       ENUM('NYSE', 'AMEX', 'NASDAQ', 'OTHER') NOT NULL,
    active_status  ENUM('ACTIVE', 'DELISTED')              NOT NULL DEFAULT 'ACTIVE',

    PRIMARY KEY (ticker),
    UNIQUE KEY uq_companies_permno    (permno),
    KEY        idx_companies_industry (industry_id),

    CONSTRAINT fk_companies_industry
        FOREIGN KEY (industry_id) REFERENCES industries (industry_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    -- Uppercase letters/digits, optional '.' share-class suffix (e.g. BRK.B)
    CONSTRAINT chk_companies_ticker_format
        CHECK (REGEXP_LIKE(ticker, '^[A-Z0-9]{1,8}([.][A-Z])?$', 'c'))
) ENGINE = InnoDB
  COMMENT = 'Securities in our CRSP sample (includes delisted names to avoid survivorship bias)';


-- -----------------------------------------------------------------------------
-- 3. monthly_stock_prices
--    Primary stock performance table, loaded from the CRSP Monthly Stock File
--    (MSF). One row per ticker per calendar month.
--    PK (ticker, period_date) = clustered index -> fast "one stock over time".
--    Secondary index on period_date             -> fast "all stocks in month X".
-- -----------------------------------------------------------------------------
CREATE TABLE monthly_stock_prices (
    ticker             VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    period_date        DATE              NOT NULL,   -- YYYY-MM-01
    month_close_price  DECIMAL(12, 4)    NOT NULL,   -- ABS(CRSP PRC), unadjusted
    monthly_return     DECIMAL(10, 6)    NOT NULL,   -- CRSP RET (total return), fraction
    total_volume       BIGINT UNSIGNED   NOT NULL DEFAULT 0,   -- SHARES (CRSP VOL x 100)
    trading_days       TINYINT UNSIGNED  NULL,       -- NYSE trading days in month (see contract)

    PRIMARY KEY (ticker, period_date),
    KEY idx_monthly_period_date (period_date),

    CONSTRAINT fk_monthly_company
        FOREIGN KEY (ticker) REFERENCES companies (ticker)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_monthly_first_of_month  CHECK (DAY(period_date) = 1),
    CONSTRAINT chk_monthly_close_positive  CHECK (month_close_price > 0),
    CONSTRAINT chk_monthly_return_floor    CHECK (monthly_return >= -1),
    CONSTRAINT chk_monthly_trading_days    CHECK (trading_days IS NULL
                                                  OR trading_days BETWEEN 1 AND 23)
) ENGINE = InnoDB
  COMMENT = 'CRSP monthly stock file (MSF) for ~500 US companies';


-- -----------------------------------------------------------------------------
-- 4. economic_indicators
--    Lookup of FRED series. indicator_code = the exact FRED series ID.
--    native_frequency  = how FRED publishes the series.
--    monthly_alignment = how etl_macro turned it into one row per month:
--      DIRECT          monthly series stored as is
--      MONTHLY_AVERAGE daily/weekly series averaged within each month
--      QUARTER_REPEAT  quarterly value repeated in each of its 3 months
-- -----------------------------------------------------------------------------
CREATE TABLE economic_indicators (
    indicator_id       SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    indicator_code     VARCHAR(20)       NOT NULL,   -- FRED series ID, e.g. 'FEDFUNDS'
    indicator_name     VARCHAR(100)      NOT NULL,
    native_frequency   ENUM('D', 'W', 'M', 'Q') NOT NULL,
    monthly_alignment  ENUM('DIRECT', 'MONTHLY_AVERAGE', 'QUARTER_REPEAT') NOT NULL,
    units              VARCHAR(80)       NOT NULL,   -- e.g. 'Percent', 'Index 1982-1984=100'

    PRIMARY KEY (indicator_id),
    UNIQUE KEY uq_indicators_code (indicator_code),

    CONSTRAINT chk_indicators_code_upper
        CHECK (REGEXP_LIKE(indicator_code, '^[A-Z0-9_]{2,20}$', 'c')),
    -- Alignment method must make sense for the native frequency
    CONSTRAINT chk_indicators_alignment CHECK (
           (native_frequency = 'M'        AND monthly_alignment = 'DIRECT')
        OR (native_frequency IN ('D','W') AND monthly_alignment = 'MONTHLY_AVERAGE')
        OR (native_frequency = 'Q'        AND monthly_alignment = 'QUARTER_REPEAT'))
) ENGINE = InnoDB
  COMMENT = 'FRED series metadata and how each is aligned to months';


-- -----------------------------------------------------------------------------
-- 5. economic_data
--    Exactly one MONTHLY value per indicator per month, so it joins to
--    monthly_stock_prices on period_date equality. Quarterly series (GDP,
--    GDPC1) repeat the quarter's value in each of its three months.
-- -----------------------------------------------------------------------------
CREATE TABLE economic_data (
    indicator_id  SMALLINT UNSIGNED NOT NULL,
    period_date   DATE              NOT NULL,   -- YYYY-MM-01
    value         DECIMAL(18, 6)    NOT NULL,   -- in economic_indicators.units

    PRIMARY KEY (indicator_id, period_date),
    KEY idx_econdata_period_date (period_date),

    CONSTRAINT fk_econdata_indicator
        FOREIGN KEY (indicator_id) REFERENCES economic_indicators (indicator_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_econdata_first_of_month CHECK (DAY(period_date) = 1)
) ENGINE = InnoDB
  COMMENT = 'FRED values aligned to one row per indicator per month';


-- -----------------------------------------------------------------------------
-- 6. economic_conditions
--    One row per regime EPISODE (a contiguous run of months meeting a rule).
--    The same condition_name may appear several times with different dates
--    (e.g. "High Interest Rate" 2006-2007 and 2023-2024).
--    Date range is INCLUSIVE and month-aligned: start_date = first month in
--    the regime, end_date = first day of the LAST month in the regime.
--    end_date NULL = regime still ongoing at the end of our data.
-- -----------------------------------------------------------------------------
CREATE TABLE economic_conditions (
    condition_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    condition_name        VARCHAR(60)   NOT NULL,
    condition_category    ENUM('INTEREST_RATE', 'INFLATION', 'GROWTH',
                               'LABOR', 'COMPOSITE') NOT NULL,
    start_date            DATE          NOT NULL,
    end_date              DATE          NULL,
    criteria_description  VARCHAR(500)  NOT NULL,   -- the exact rule used

    PRIMARY KEY (condition_id),
    UNIQUE KEY uq_conditions_name_start (condition_name, start_date),
    KEY idx_conditions_dates    (start_date, end_date),
    KEY idx_conditions_category (condition_category),

    CONSTRAINT chk_conditions_start_month CHECK (DAY(start_date) = 1),
    CONSTRAINT chk_conditions_end_month   CHECK (end_date IS NULL OR DAY(end_date) = 1),
    CONSTRAINT chk_conditions_date_order  CHECK (end_date IS NULL OR end_date >= start_date)
) ENGINE = InnoDB
  COMMENT = 'Macroeconomic regime episodes derived from economic_data';


-- -----------------------------------------------------------------------------
-- 7. industry_monthly_returns
--    Derived: equal-weighted average of monthly_stock_prices.monthly_return
--    over all companies in the industry for that month.
--    volatility = cross-sectional STDDEV_SAMP of those returns (NULL if
--    stock_count < 2).
-- -----------------------------------------------------------------------------
CREATE TABLE industry_monthly_returns (
    industry_id         SMALLINT UNSIGNED NOT NULL,
    period_date         DATE              NOT NULL,   -- YYYY-MM-01
    avg_monthly_return  DECIMAL(10, 6)    NOT NULL,   -- fraction
    volatility          DECIMAL(10, 6)    NULL,       -- fraction
    stock_count         INT UNSIGNED      NOT NULL,

    PRIMARY KEY (industry_id, period_date),
    KEY idx_imr_period_date (period_date),

    CONSTRAINT fk_imr_industry
        FOREIGN KEY (industry_id) REFERENCES industries (industry_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT chk_imr_first_of_month  CHECK (DAY(period_date) = 1),
    CONSTRAINT chk_imr_return_floor    CHECK (avg_monthly_return >= -1),
    CONSTRAINT chk_imr_volatility      CHECK (volatility IS NULL OR volatility >= 0),
    CONSTRAINT chk_imr_stock_count     CHECK (stock_count >= 1)
) ENGINE = InnoDB
  COMMENT = 'Equal-weighted industry returns per month (derived)';


-- -----------------------------------------------------------------------------
-- 8. condition_industry_performance
--    Derived join table (M:N between economic_conditions and industries),
--    computed from industry_monthly_returns over the months in each episode.
--      avg_monthly_return      = AVG(industry avg_monthly_return) over episode months
--      win_rate_pct            = % of episode months with industry return > 0
--      excess_return_vs_market = avg_monthly_return - avg market return over the
--                                same months (market = equal-weighted average of
--                                ALL stocks in monthly_stock_prices)
--      sample_months           = # months with data inside the episode
-- -----------------------------------------------------------------------------
CREATE TABLE condition_industry_performance (
    condition_id             INT UNSIGNED      NOT NULL,
    industry_id              SMALLINT UNSIGNED NOT NULL,
    avg_monthly_return       DECIMAL(10, 6)    NOT NULL,   -- fraction
    win_rate_pct             DECIMAL(6, 2)     NOT NULL,   -- percent points 0-100
    excess_return_vs_market  DECIMAL(10, 6)    NOT NULL,   -- fraction
    sample_months            SMALLINT UNSIGNED NOT NULL,

    PRIMARY KEY (condition_id, industry_id),
    KEY idx_cip_industry (industry_id),

    CONSTRAINT fk_cip_condition
        FOREIGN KEY (condition_id) REFERENCES economic_conditions (condition_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_cip_industry
        FOREIGN KEY (industry_id) REFERENCES industries (industry_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT chk_cip_win_rate       CHECK (win_rate_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_cip_return_floor   CHECK (avg_monthly_return >= -1),
    CONSTRAINT chk_cip_sample_months  CHECK (sample_months >= 1)
) ENGINE = InnoDB
  COMMENT = 'Industry performance summarised per macro regime episode (derived)';
