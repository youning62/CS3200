-- =============================================================================
-- 01_create_tables.sql
-- CS3200 Project: Analyzing Stock Market Performance Across Different
--                 Macroeconomic Environments
-- Team: Martin Villa, Youning Zheng, Ryan Marshall, Corey Rattray
--
-- Target: MySQL 8.0.16+ (CHECK constraints are enforced from 8.0.16 onward)
-- Schema version: 1.0 (Phase 1 schema lock)
--
-- !! WARNING: this script DROPS and recreates all 10 tables. Running it on a
-- !! loaded database deletes all data. Back up first (mysqldump) if needed.
--
-- Conventions (full detail in schema/SCHEMA_CONTRACT.md):
--   * Every monthly/quarterly period is stored as a DATE on the FIRST day of
--     the period (YYYY-MM-01). Enforced with CHECK (DAY(col) = 1).
--   * Columns named *_return are DECIMAL FRACTIONS   (0.0123 = +1.23%).
--   * Columns named *_rate / *_pct are PERCENT POINTS (5.33  = 5.33%).
--   * Tickers are uppercase ASCII, stored with a binary (case-sensitive)
--     collation that is identical in every table that references them.
--
-- Table build order (parents before children):
--   industries -> companies -> daily_stock_prices -> monthly_stock_prices
--   economic_indicators -> economic_data
--   economic_conditions
--   industry_monthly_returns -> condition_industry_performance
--   annual_economic_summary
-- =============================================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS stock_macro_db
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE stock_macro_db;

-- Drop in any order (FK checks off), so the script is safely re-runnable.
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS
    condition_industry_performance,
    industry_monthly_returns,
    annual_economic_summary,
    economic_conditions,
    economic_data,
    economic_indicators,
    monthly_stock_prices,
    daily_stock_prices,
    companies,
    industries;
SET FOREIGN_KEY_CHECKS = 1;


-- -----------------------------------------------------------------------------
-- 1. industries
--    Lookup table. We use the Fama-French 12-industry classification, which
--    is derived deterministically from the CRSP SIC code (SICCD). IDs 1-12
--    match the FF12 numbering and are inserted explicitly by the seed script
--    so every teammate's database has identical IDs.
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
--    One row per security. `ticker` is the natural key used by every price
--    table. `permno` (CRSP permanent security ID) is kept for traceability
--    back to CRSP because tickers change and are reused over time.
-- -----------------------------------------------------------------------------
CREATE TABLE companies (
    ticker         VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    permno         INT UNSIGNED      NULL,
    company_name   VARCHAR(150)      NOT NULL,
    industry_id    SMALLINT UNSIGNED NOT NULL,
    exchange       ENUM('NYSE', 'AMEX', 'NASDAQ', 'OTHER') NOT NULL,
    active_status  ENUM('ACTIVE', 'DELISTED')              NOT NULL DEFAULT 'ACTIVE',

    PRIMARY KEY (ticker),
    UNIQUE KEY uq_companies_permno   (permno),
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
-- 3. daily_stock_prices
--    Raw CRSP daily data (largest table). Composite PK (ticker, trade_date) is
--    the clustered index -> fast "one ticker over a date range" scans.
--    Secondary index on trade_date -> fast "all tickers on/between dates".
-- -----------------------------------------------------------------------------
CREATE TABLE daily_stock_prices (
    ticker         VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    trade_date     DATE              NOT NULL,
    close_price    DECIMAL(12, 4)    NOT NULL,   -- ABS(CRSP PRC); unadjusted
    volume         BIGINT UNSIGNED   NOT NULL DEFAULT 0,   -- shares traded
    daily_return   DECIMAL(10, 6)    NULL,       -- CRSP RET (split/dividend adjusted), fraction

    PRIMARY KEY (ticker, trade_date),
    KEY idx_daily_trade_date (trade_date),

    CONSTRAINT fk_daily_company
        FOREIGN KEY (ticker) REFERENCES companies (ticker)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_daily_close_positive  CHECK (close_price > 0),
    CONSTRAINT chk_daily_return_floor    CHECK (daily_return IS NULL OR daily_return >= -1),
    CONSTRAINT chk_daily_weekday         CHECK (DAYOFWEEK(trade_date) BETWEEN 2 AND 6)
) ENGINE = InnoDB
  COMMENT = 'CRSP daily stock file (DSF) subset';


-- -----------------------------------------------------------------------------
-- 4. monthly_stock_prices
--    Aggregated from daily_stock_prices by etl_stocks. One row per ticker per
--    calendar month; period_date is always the 1st of the month.
-- -----------------------------------------------------------------------------
CREATE TABLE monthly_stock_prices (
    ticker             VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    period_date        DATE              NOT NULL,   -- YYYY-MM-01
    month_open_price   DECIMAL(12, 4)    NOT NULL,   -- close on FIRST trading day of month
    month_close_price  DECIMAL(12, 4)    NOT NULL,   -- close on LAST trading day of month
    monthly_return     DECIMAL(10, 6)    NOT NULL,   -- compounded daily_return, fraction
    total_volume       BIGINT UNSIGNED   NOT NULL DEFAULT 0,
    trading_days       TINYINT UNSIGNED  NOT NULL,   -- # daily rows aggregated (QA)

    PRIMARY KEY (ticker, period_date),
    KEY idx_monthly_period_date (period_date),

    CONSTRAINT fk_monthly_company
        FOREIGN KEY (ticker) REFERENCES companies (ticker)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_monthly_first_of_month  CHECK (DAY(period_date) = 1),
    CONSTRAINT chk_monthly_open_positive   CHECK (month_open_price > 0),
    CONSTRAINT chk_monthly_close_positive  CHECK (month_close_price > 0),
    CONSTRAINT chk_monthly_return_floor    CHECK (monthly_return >= -1),
    CONSTRAINT chk_monthly_trading_days    CHECK (trading_days BETWEEN 1 AND 23)
) ENGINE = InnoDB
  COMMENT = 'Monthly stock aggregates derived from daily_stock_prices';


-- -----------------------------------------------------------------------------
-- 5. economic_indicators
--    Lookup of FRED series we track. indicator_code = the exact FRED series ID.
-- -----------------------------------------------------------------------------
CREATE TABLE economic_indicators (
    indicator_id    SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    indicator_code  VARCHAR(20)       NOT NULL,   -- FRED series ID, e.g. 'FEDFUNDS'
    indicator_name  VARCHAR(100)      NOT NULL,
    frequency       ENUM('M', 'Q', 'A') NOT NULL, -- Monthly / Quarterly / Annual (as stored)
    units           VARCHAR(80)       NOT NULL,   -- e.g. 'Percent', 'Index 1982-1984=100'

    PRIMARY KEY (indicator_id),
    UNIQUE KEY uq_indicators_code (indicator_code),

    CONSTRAINT chk_indicators_code_upper
        CHECK (REGEXP_LIKE(indicator_code, '^[A-Z0-9_]{2,20}$', 'c'))
) ENGINE = InnoDB
  COMMENT = 'FRED series metadata';


-- -----------------------------------------------------------------------------
-- 6. economic_data
--    One observation per indicator per period, exactly as FRED reports it
--    (FRED already dates observations on the first day of the period:
--    monthly 2024-01-01 = Jan 2024, quarterly 2024-01-01 = Q1 2024).
-- -----------------------------------------------------------------------------
CREATE TABLE economic_data (
    indicator_id      SMALLINT UNSIGNED NOT NULL,
    observation_date  DATE              NOT NULL,   -- first day of the period
    value             DECIMAL(18, 6)    NOT NULL,   -- in economic_indicators.units

    PRIMARY KEY (indicator_id, observation_date),
    KEY idx_econdata_observation_date (observation_date),

    CONSTRAINT fk_econdata_indicator
        FOREIGN KEY (indicator_id) REFERENCES economic_indicators (indicator_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_econdata_first_of_period CHECK (DAY(observation_date) = 1)
) ENGINE = InnoDB
  COMMENT = 'FRED observations (monthly or coarser, first-of-period dated)';


-- -----------------------------------------------------------------------------
-- 7. economic_conditions
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
-- 8. industry_monthly_returns
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
-- 9. condition_industry_performance
--    Derived join table (M:N between economic_conditions and industries).
--    Computed from industry_monthly_returns over the months inside each
--    condition episode.
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


-- -----------------------------------------------------------------------------
-- 10. annual_economic_summary
--     One row per calendar year. Rates in percent points, return as fraction.
--       avg_fed_funds_rate      = AVG of 12 monthly FEDFUNDS values
--       annual_inflation_rate   = % change of annual-average CPIAUCSL vs prior year
--       gdp_growth_rate         = % change of annual-average real GDP (GDPC1) vs prior year
--       avg_unemployment_rate   = AVG of 12 monthly UNRATE values
--       market_benchmark_return = compounded monthly equal-weighted market return
-- -----------------------------------------------------------------------------
CREATE TABLE annual_economic_summary (
    year                     SMALLINT UNSIGNED NOT NULL,
    avg_fed_funds_rate       DECIMAL(8, 4)     NULL,   -- percent
    annual_inflation_rate    DECIMAL(8, 4)     NULL,   -- percent
    gdp_growth_rate          DECIMAL(8, 4)     NULL,   -- percent
    avg_unemployment_rate    DECIMAL(8, 4)     NULL,   -- percent
    market_benchmark_return  DECIMAL(10, 6)    NULL,   -- fraction

    PRIMARY KEY (year),

    CONSTRAINT chk_annual_year_range     CHECK (year BETWEEN 1925 AND 2100),
    CONSTRAINT chk_annual_unemp_range    CHECK (avg_unemployment_rate IS NULL
                                                OR avg_unemployment_rate BETWEEN 0 AND 100),
    CONSTRAINT chk_annual_market_floor   CHECK (market_benchmark_return IS NULL
                                                OR market_benchmark_return >= -1)
) ENGINE = InnoDB
  COMMENT = 'Yearly macro benchmarks (derived from economic_data + monthly_stock_prices)';
