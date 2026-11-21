-- =============================================================================
-- 02_reference_data.sql  --  REAL reference data (NOT mock data)
--
-- Populates the two lookup tables with FIXED IDs that every ETL script and
-- every teammate's database must share:
--   * industries          -> the 12 Fama-French industries (Ken French's
--                            Siccodes12 definitions)
--   * economic_indicators -> the FRED series we track, with their exact FRED
--                            series IDs and how each is aligned to months
--
-- Run right after 01_create_tables.sql and BEFORE loading any CRSP/FRED data
-- (companies.industry_id and economic_data.indicator_id are foreign keys into
-- these tables).
--
-- Re-runnable: upserts by primary key, so it never deletes loaded data.
-- To add a series or change a definition, open a PR against this file.
-- =============================================================================

USE stock_macro_db;

START TRANSACTION;

INSERT INTO industries (industry_id, industry_name, sector_code, description) VALUES
    ( 1, 'Consumer NonDurables', 'NODUR', 'Food, tobacco, textiles, apparel, leather, toys'),
    ( 2, 'Consumer Durables',    'DURBL', 'Cars, TVs, furniture, household appliances'),
    ( 3, 'Manufacturing',        'MANUF', 'Machinery, trucks, planes, office furniture, paper, commercial printing'),
    ( 4, 'Energy',               'ENRGY', 'Oil, gas, and coal extraction and products'),
    ( 5, 'Chemicals',            'CHEMS', 'Chemicals and allied products'),
    ( 6, 'Business Equipment',   'BUSEQ', 'Computers, software, and electronic equipment (technology)'),
    ( 7, 'Telecom',              'TELCM', 'Telephone and television transmission'),
    ( 8, 'Utilities',            'UTILS', 'Electric, gas, and water utilities'),
    ( 9, 'Shops',                'SHOPS', 'Wholesale, retail, and some services (laundries, repair shops)'),
    (10, 'Healthcare',           'HLTH',  'Healthcare, medical equipment, and drugs'),
    (11, 'Finance',              'MONEY', 'Banks, insurance, brokers, real estate'),
    (12, 'Other',                'OTHER', 'Mines, construction, transportation, hotels, entertainment; also missing/unmapped SIC codes')
AS new
ON DUPLICATE KEY UPDATE
    industry_name = new.industry_name,
    sector_code   = new.sector_code,
    description   = new.description;

INSERT INTO economic_indicators
    (indicator_id, indicator_code, indicator_name, native_frequency, monthly_alignment, units) VALUES
    (1, 'FEDFUNDS', 'Effective Federal Funds Rate (monthly average)',              'M', 'DIRECT',         'Percent'),
    (2, 'CPIAUCSL', 'Consumer Price Index for All Urban Consumers: All Items (SA)', 'M', 'DIRECT',         'Index 1982-1984=100'),
    (3, 'GDP',      'Gross Domestic Product (nominal, SAAR)',                       'Q', 'QUARTER_REPEAT', 'Billions of Dollars'),
    (4, 'GDPC1',    'Real Gross Domestic Product (SAAR)',                           'Q', 'QUARTER_REPEAT', 'Billions of Chained 2017 Dollars'),
    (5, 'UNRATE',   'Unemployment Rate (SA)',                                       'M', 'DIRECT',         'Percent')
AS new
ON DUPLICATE KEY UPDATE
    indicator_code    = new.indicator_code,
    indicator_name    = new.indicator_name,
    native_frequency  = new.native_frequency,
    monthly_alignment = new.monthly_alignment,
    units             = new.units;

COMMIT;

SELECT 'industries' AS table_name, COUNT(*) AS row_count FROM industries
UNION ALL
SELECT 'economic_indicators', COUNT(*) FROM economic_indicators;
