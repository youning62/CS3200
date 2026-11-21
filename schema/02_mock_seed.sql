-- =============================================================================
-- 02_mock_seed.sql  --  MOCK / SYNTHETIC DATA FOR LOCAL TESTING ONLY
--
-- Run AFTER 01_create_tables.sql. Re-runnable (truncates all 10 tables first).
--
-- What is real vs. synthetic:
--   * industries ............ real Fama-French 12 definitions (keep these IDs!)
--   * companies ............. real names/tickers; PERMNOs should be re-verified
--                             against CRSP during ingestion
--   * daily/monthly prices .. SYNTHETIC random walk starting near real late-2023
--                             price levels. Do NOT use for analysis.
--   * economic_data ......... approximately real FRED values (rounded / may
--                             differ from the latest revised vintage)
--   * economic_conditions ... plausible episode dates under the contract rules
--   * industry_monthly_returns / condition 1 rows of condition_industry_performance
--                             are COMPUTED EXACTLY from the mock monthly rows,
--                             so derived-table checks in 03_validate_schema.sql pass.
--   * other condition_industry_performance rows + annual_economic_summary are
--     illustrative placeholders (no underlying mock months exist for them).
--
-- Coverage: daily rows for Jan 2024 (21 trading days x 7 tickers);
--           monthly rows for Dec 2023, Jan 2024, Feb 2024.
-- =============================================================================

USE stock_macro_db;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE condition_industry_performance;
TRUNCATE TABLE industry_monthly_returns;
TRUNCATE TABLE annual_economic_summary;
TRUNCATE TABLE economic_conditions;
TRUNCATE TABLE economic_data;
TRUNCATE TABLE economic_indicators;
TRUNCATE TABLE monthly_stock_prices;
TRUNCATE TABLE daily_stock_prices;
TRUNCATE TABLE companies;
TRUNCATE TABLE industries;
SET FOREIGN_KEY_CHECKS = 1;

START TRANSACTION;

-- 1. industries (Fama-French 12; IDs are FIXED and shared by the whole team)
INSERT INTO industries (industry_id, industry_name, sector_code, description) VALUES
    (1, 'Consumer NonDurables', 'NODUR', 'Food, tobacco, textiles, apparel, leather, toys'),
    (2, 'Consumer Durables', 'DURBL', 'Cars, TVs, furniture, household appliances'),
    (3, 'Manufacturing', 'MANUF', 'Machinery, trucks, planes, office furniture, paper, commercial printing'),
    (4, 'Energy', 'ENRGY', 'Oil, gas, and coal extraction and products'),
    (5, 'Chemicals', 'CHEMS', 'Chemicals and allied products'),
    (6, 'Business Equipment', 'BUSEQ', 'Computers, software, and electronic equipment (technology)'),
    (7, 'Telecom', 'TELCM', 'Telephone and television transmission'),
    (8, 'Utilities', 'UTILS', 'Electric, gas, and water utilities'),
    (9, 'Shops', 'SHOPS', 'Wholesale, retail, and some services (laundries, repair shops)'),
    (10, 'Healthcare', 'HLTH', 'Healthcare, medical equipment, and drugs'),
    (11, 'Finance', 'MONEY', 'Banks, insurance, brokers, real estate'),
    (12, 'Other', 'OTHER', 'Mines, construction, transportation, hotels, entertainment; also unmapped SIC codes');

-- 2. companies (LEH included as a DELISTED example: survivorship-bias rule)
INSERT INTO companies (ticker, permno, company_name, industry_id, exchange, active_status) VALUES
    ('AAPL', 14593, 'Apple Inc.', 6, 'NASDAQ', 'ACTIVE'),
    ('MSFT', 10107, 'Microsoft Corp.', 6, 'NASDAQ', 'ACTIVE'),
    ('XOM', 11850, 'Exxon Mobil Corp.', 4, 'NYSE', 'ACTIVE'),
    ('CVX', 14541, 'Chevron Corp.', 4, 'NYSE', 'ACTIVE'),
    ('JNJ', 22111, 'Johnson & Johnson', 10, 'NYSE', 'ACTIVE'),
    ('PFE', 21936, 'Pfizer Inc.', 10, 'NYSE', 'ACTIVE'),
    ('JPM', 47896, 'JPMorgan Chase & Co.', 11, 'NYSE', 'ACTIVE'),
    ('LEH', NULL, 'Lehman Brothers Holdings Inc.', 11, 'NYSE', 'DELISTED');

-- 3. daily_stock_prices (SYNTHETIC, January 2024, 21 NYSE trading days)
INSERT INTO daily_stock_prices (ticker, trade_date, close_price, volume, daily_return) VALUES
    ('AAPL', '2024-01-02', 193.9300, 54230463, 0.007272),
    ('AAPL', '2024-01-03', 196.0800, 33856830, 0.011086),
    ('AAPL', '2024-01-04', 201.1200, 59840312, 0.025704),
    ('AAPL', '2024-01-05', 200.5700, 44086843, -0.002735),
    ('AAPL', '2024-01-08', 202.9800, 51963913, 0.012016),
    ('AAPL', '2024-01-09', 202.2300, 61857222, -0.003695),
    ('AAPL', '2024-01-10', 201.7700, 76826524, -0.002275),
    ('AAPL', '2024-01-11', 201.6500, 69347111, -0.000595),
    ('AAPL', '2024-01-12', 199.7800, 55983739, -0.009273),
    ('AAPL', '2024-01-16', 196.1400, 52086366, -0.018220),
    ('AAPL', '2024-01-17', 196.5300, 51137637, 0.001988),
    ('AAPL', '2024-01-18', 197.1200, 66698176, 0.003002),
    ('AAPL', '2024-01-19', 198.2800, 67596501, 0.005885),
    ('AAPL', '2024-01-22', 201.3600, 71526139, 0.015534),
    ('AAPL', '2024-01-23', 203.6500, 73425600, 0.011373),
    ('AAPL', '2024-01-24', 205.8600, 35300081, 0.010852),
    ('AAPL', '2024-01-25', 206.1800, 62816024, 0.001554),
    ('AAPL', '2024-01-26', 208.0700, 76384891, 0.009167),
    ('AAPL', '2024-01-29', 204.0200, 48240435, -0.019465),
    ('AAPL', '2024-01-30', 205.1700, 45110050, 0.005637),
    ('AAPL', '2024-01-31', 204.5000, 74399107, -0.003266),
    ('MSFT', '2024-01-02', 379.7600, 32345534, 0.009893),
    ('MSFT', '2024-01-03', 389.7600, 32323474, 0.026332),
    ('MSFT', '2024-01-04', 386.3400, 30129087, -0.008775),
    ('MSFT', '2024-01-05', 387.7600, 24393579, 0.003676),
    ('MSFT', '2024-01-08', 384.8400, 19078627, -0.007530),
    ('MSFT', '2024-01-09', 379.6400, 24358510, -0.013512),
    ('MSFT', '2024-01-10', 375.7000, 22365929, -0.010378),
    ('MSFT', '2024-01-11', 377.2800, 30731840, 0.004205),
    ('MSFT', '2024-01-12', 380.6700, 32301406, 0.008985),
    ('MSFT', '2024-01-16', 384.1800, 16892593, 0.009221),
    ('MSFT', '2024-01-17', 377.8400, 13310401, -0.016503),
    ('MSFT', '2024-01-18', 380.5800, 29564812, 0.007252),
    ('MSFT', '2024-01-19', 374.0300, 31701877, -0.017211),
    ('MSFT', '2024-01-22', 383.9400, 32350028, 0.026495),
    ('MSFT', '2024-01-23', 382.3700, 26567764, -0.004089),
    ('MSFT', '2024-01-24', 383.2700, 24046091, 0.002354),
    ('MSFT', '2024-01-25', 389.0400, 17586541, 0.015055),
    ('MSFT', '2024-01-26', 378.0800, 28681495, -0.028172),
    ('MSFT', '2024-01-29', 381.9200, 26807620, 0.010157),
    ('MSFT', '2024-01-30', 381.1200, 14365724, -0.002095),
    ('MSFT', '2024-01-31', 385.0200, 23564930, 0.010233),
    ('XOM', '2024-01-02', 100.7900, 14230053, 0.008102),
    ('XOM', '2024-01-03', 103.0100, 22715985, 0.022026),
    ('XOM', '2024-01-04', 102.1100, 13348736, -0.008737),
    ('XOM', '2024-01-05', 101.1700, 24395966, -0.009206),
    ('XOM', '2024-01-08', 102.0000, 16304911, 0.008204),
    ('XOM', '2024-01-09', 104.0400, 19961157, 0.020000),
    ('XOM', '2024-01-10', 103.3400, 25128491, -0.006728),
    ('XOM', '2024-01-11', 102.6900, 16713016, -0.006290),
    ('XOM', '2024-01-12', 103.2100, 12745582, 0.005064),
    ('XOM', '2024-01-16', 104.4800, 15986438, 0.012305),
    ('XOM', '2024-01-17', 102.7900, 23559435, -0.016175),
    ('XOM', '2024-01-18', 100.8500, 17599151, -0.018873),
    ('XOM', '2024-01-19', 100.7000, 10870914, -0.001487),
    ('XOM', '2024-01-22', 98.2700, 21583900, -0.024131),
    ('XOM', '2024-01-23', 97.5600, 11121036, -0.007225),
    ('XOM', '2024-01-24', 97.5400, 19716589, -0.000205),
    ('XOM', '2024-01-25', 96.9700, 13789662, -0.005844),
    ('XOM', '2024-01-26', 97.2500, 11203509, 0.002887),
    ('XOM', '2024-01-29', 96.5400, 22479763, -0.007301),
    ('XOM', '2024-01-30', 94.9900, 15440030, -0.016056),
    ('XOM', '2024-01-31', 96.9300, 20240139, 0.020423),
    ('CVX', '2024-01-02', 150.7200, 4831448, 0.010459),
    ('CVX', '2024-01-03', 149.7300, 6081194, -0.006568),
    ('CVX', '2024-01-04', 145.3000, 5956091, -0.029587),
    ('CVX', '2024-01-05', 144.1700, 11909112, -0.007777),
    ('CVX', '2024-01-08', 144.3100, 5657725, 0.000971),
    ('CVX', '2024-01-09', 145.4400, 11082496, 0.007830),
    ('CVX', '2024-01-10', 144.0500, 5437928, -0.009557),
    ('CVX', '2024-01-11', 141.2600, 11235392, -0.019368),
    ('CVX', '2024-01-12', 144.5400, 5128591, 0.023220),
    ('CVX', '2024-01-16', 145.2600, 6307985, 0.004981),
    ('CVX', '2024-01-17', 146.5500, 8844993, 0.008881),
    ('CVX', '2024-01-18', 147.3300, 10581521, 0.005322),
    ('CVX', '2024-01-19', 149.2400, 10152607, 0.012964),
    ('CVX', '2024-01-22', 152.2600, 7681702, 0.020236),
    ('CVX', '2024-01-23', 151.5800, 8778170, -0.004466),
    ('CVX', '2024-01-24', 153.8100, 5917829, 0.014712),
    ('CVX', '2024-01-25', 151.1300, 7427857, -0.017424),
    ('CVX', '2024-01-26', 152.1300, 11504714, 0.006617),
    ('CVX', '2024-01-29', 151.0800, 8892004, -0.006902),
    ('CVX', '2024-01-30', 149.3700, 6020037, -0.011319),
    ('CVX', '2024-01-31', 149.8500, 5331739, 0.003213),
    ('JNJ', '2024-01-02', 159.4800, 8354853, 0.017481),
    ('JNJ', '2024-01-03', 159.8000, 8236487, 0.002007),
    ('JNJ', '2024-01-04', 160.1600, 9042069, 0.002253),
    ('JNJ', '2024-01-05', 157.7700, 5779157, -0.014923),
    ('JNJ', '2024-01-08', 159.1300, 9800403, 0.008620),
    ('JNJ', '2024-01-09', 163.8600, 8171269, 0.029724),
    ('JNJ', '2024-01-10', 162.9600, 8707612, -0.005492),
    ('JNJ', '2024-01-11', 162.0800, 4542058, -0.005400),
    ('JNJ', '2024-01-12', 163.1300, 4758230, 0.006478),
    ('JNJ', '2024-01-16', 163.1000, 7077591, -0.000184),
    ('JNJ', '2024-01-17', 159.9400, 6608451, -0.019375),
    ('JNJ', '2024-01-18', 158.5300, 10466486, -0.008816),
    ('JNJ', '2024-01-19', 156.4100, 5328678, -0.013373),
    ('JNJ', '2024-01-22', 159.4200, 4598775, 0.019244),
    ('JNJ', '2024-01-23', 160.9300, 9203017, 0.009472),
    ('JNJ', '2024-01-24', 160.8300, 9684750, -0.000621),
    ('JNJ', '2024-01-25', 161.2200, 4881763, 0.002425),
    ('JNJ', '2024-01-26', 159.7900, 10386449, -0.008870),
    ('JNJ', '2024-01-29', 162.2800, 9117033, 0.015583),
    ('JNJ', '2024-01-30', 163.0000, 10183354, 0.004437),
    ('JNJ', '2024-01-31', 161.0600, 9271442, -0.011902),
    ('PFE', '2024-01-02', 28.8800, 47605803, 0.003126),
    ('PFE', '2024-01-03', 28.7500, 23659942, -0.004501),
    ('PFE', '2024-01-04', 28.8400, 48348850, 0.003130),
    ('PFE', '2024-01-05', 29.2800, 39992144, 0.015257),
    ('PFE', '2024-01-08', 29.9600, 30323102, 0.023224),
    ('PFE', '2024-01-09', 29.8500, 26942169, -0.003672),
    ('PFE', '2024-01-10', 29.9700, 48271785, 0.004020),
    ('PFE', '2024-01-11', 30.0000, 29544638, 0.001001),
    ('PFE', '2024-01-12', 30.2000, 34789675, 0.006667),
    ('PFE', '2024-01-16', 29.8000, 31584706, -0.013245),
    ('PFE', '2024-01-17', 29.9900, 37331424, 0.006376),
    ('PFE', '2024-01-18', 29.7500, 49788764, -0.008003),
    ('PFE', '2024-01-19', 30.0200, 43513660, 0.009076),
    ('PFE', '2024-01-22', 30.6200, 34490339, 0.019987),
    ('PFE', '2024-01-23', 30.6200, 41944812, 0.000000),
    ('PFE', '2024-01-24', 31.0200, 38941140, 0.013063),
    ('PFE', '2024-01-25', 31.4200, 43957826, 0.012895),
    ('PFE', '2024-01-26', 31.1200, 43602245, -0.009548),
    ('PFE', '2024-01-29', 30.2600, 27788300, -0.027635),
    ('PFE', '2024-01-30', 30.2600, 22251824, 0.000000),
    ('PFE', '2024-01-31', 30.3300, 35905582, 0.002313),
    ('JPM', '2024-01-02', 167.3700, 6158678, -0.016049),
    ('JPM', '2024-01-03', 169.9500, 13228240, 0.015415),
    ('JPM', '2024-01-04', 172.1400, 13219040, 0.012886),
    ('JPM', '2024-01-05', 175.2500, 8805708, 0.018067),
    ('JPM', '2024-01-08', 175.7900, 8200773, 0.003081),
    ('JPM', '2024-01-09', 178.8000, 12539224, 0.017123),
    ('JPM', '2024-01-10', 176.0500, 9661259, -0.015380),
    ('JPM', '2024-01-11', 173.7900, 7668884, -0.012837),
    ('JPM', '2024-01-12', 176.1300, 7517661, 0.013465),
    ('JPM', '2024-01-16', 176.2100, 11306063, 0.000454),
    ('JPM', '2024-01-17', 177.3300, 9280308, 0.006356),
    ('JPM', '2024-01-18', 173.7500, 7042262, -0.020188),
    ('JPM', '2024-01-19', 175.0600, 5952963, 0.007540),
    ('JPM', '2024-01-22', 174.1200, 11929745, -0.005370),
    ('JPM', '2024-01-23', 172.9700, 8640590, -0.006605),
    ('JPM', '2024-01-24', 169.6000, 6435205, -0.019483),
    ('JPM', '2024-01-25', 168.4500, 13121521, -0.006781),
    ('JPM', '2024-01-26', 167.6800, 13034275, -0.004571),
    ('JPM', '2024-01-29', 166.3600, 12915124, -0.007872),
    ('JPM', '2024-01-30', 168.0400, 10116485, 0.010099),
    ('JPM', '2024-01-31', 168.3400, 5554626, 0.001785);

-- 4. monthly_stock_prices (Jan 2024 rows are aggregated exactly from the daily rows)
INSERT INTO monthly_stock_prices
    (ticker, period_date, month_open_price, month_close_price, monthly_return, total_volume, trading_days) VALUES
    ('AAPL', '2023-12-01', 189.9500, 192.5300, 0.014101, 1137790632, 20),
    ('AAPL', '2024-01-01', 193.9300, 204.5000, 0.062172, 1232713964, 21),
    ('AAPL', '2024-02-01', 203.9474, 221.5476, 0.083362, 1234879571, 20),
    ('CVX', '2023-12-01', 145.5200, 149.1600, 0.025453, 147891337, 20),
    ('CVX', '2024-01-01', 150.7200, 149.8500, 0.004626, 164761135, 21),
    ('CVX', '2024-02-01', 149.4287, 162.2563, 0.082791, 181835029, 20),
    ('JNJ', '2023-12-01', 154.8700, 156.7400, 0.011686, 119704512, 20),
    ('JNJ', '2024-01-01', 159.4800, 161.0600, 0.027561, 164199927, 21),
    ('JNJ', '2024-02-01', 160.9633, 167.5090, 0.040041, 134173148, 20),
    ('JPM', '2023-12-01', 157.9400, 170.1000, 0.076903, 179547595, 20),
    ('JPM', '2024-01-01', 167.3700, 168.3400, -0.010345, 202328634, 21),
    ('JPM', '2024-02-01', 167.6520, 169.2614, 0.005473, 205317327, 20),
    ('MSFT', '2023-12-01', 369.1400, 376.0400, 0.019585, 387234803, 20),
    ('MSFT', '2024-01-01', 379.7600, 385.0200, 0.023881, 533467862, 21),
    ('MSFT', '2024-02-01', 386.6107, 361.5055, -0.061073, 445151688, 20),
    ('PFE', '2023-12-01', 30.6200, 28.7900, -0.057199, 684447228, 20),
    ('PFE', '2024-01-01', 28.8800, 30.3300, 0.053491, 780578730, 21),
    ('PFE', '2024-02-01', 29.8122, 32.4886, 0.071171, 736015050, 20),
    ('XOM', '2023-12-01', 102.7900, 99.9800, -0.028186, 295772494, 20),
    ('XOM', '2024-01-01', 100.7900, 96.9300, -0.030506, 369134463, 21),
    ('XOM', '2024-02-01', 96.3656, 100.2462, 0.034212, 340626634, 20);

-- 5. economic_indicators (indicator_code = exact FRED series ID; IDs FIXED)
INSERT INTO economic_indicators (indicator_id, indicator_code, indicator_name, frequency, units) VALUES
    (1, 'FEDFUNDS', 'Effective Federal Funds Rate', 'M', 'Percent'),
    (2, 'CPIAUCSL', 'Consumer Price Index for All Urban Consumers: All Items (SA)', 'M', 'Index 1982-1984=100'),
    (3, 'GDP',      'Gross Domestic Product (nominal, SAAR)', 'Q', 'Billions of Dollars'),
    (4, 'UNRATE',   'Unemployment Rate', 'M', 'Percent'),
    (5, 'GDPC1',    'Real Gross Domestic Product (SAAR)', 'Q', 'Billions of Chained 2017 Dollars');

-- 6. economic_data (approximate FRED values; FRED dates = first day of period)
--    CPI includes Dec 2022 - Feb 2023 so year-over-year inflation can be tested.
INSERT INTO economic_data (indicator_id, observation_date, value) VALUES
    (1, '2023-12-01', 5.330000),
    (1, '2024-01-01', 5.330000),
    (1, '2024-02-01', 5.330000),
    (2, '2022-12-01', 298.812000),
    (2, '2023-01-01', 300.356000),
    (2, '2023-02-01', 301.509000),
    (2, '2023-12-01', 308.742000),
    (2, '2024-01-01', 309.685000),
    (2, '2024-02-01', 311.054000),
    (3, '2023-10-01', 28296.967000),
    (3, '2024-01-01', 28624.069000),
    (4, '2023-12-01', 3.700000),
    (4, '2024-01-01', 3.700000),
    (4, '2024-02-01', 3.900000),
    (5, '2023-10-01', 22960.600000),
    (5, '2024-01-01', 23053.545000);

-- 7. economic_conditions (one row per episode; inclusive month-start ranges)
INSERT INTO economic_conditions
    (condition_id, condition_name, condition_category, start_date, end_date, criteria_description) VALUES
    (1, 'High Interest Rate', 'INTEREST_RATE', '2023-02-01', '2024-11-01',
        'FEDFUNDS monthly value >= 4.00 for >= 3 consecutive months'),
    (2, 'High Interest Rate', 'INTEREST_RATE', '2006-06-01', '2007-11-01',
        'FEDFUNDS monthly value >= 4.00 for >= 3 consecutive months'),
    (3, 'Low Interest Rate',  'INTEREST_RATE', '2009-01-01', '2015-11-01',
        'FEDFUNDS monthly value <= 1.00 for >= 3 consecutive months'),
    (4, 'Low Interest Rate',  'INTEREST_RATE', '2020-04-01', '2022-03-01',
        'FEDFUNDS monthly value <= 1.00 for >= 3 consecutive months'),
    (5, 'High Inflation',     'INFLATION',     '2021-04-01', '2023-05-01',
        'CPIAUCSL year-over-year % change >= 4.00 for >= 3 consecutive months'),
    (6, 'Stagflation',        'COMPOSITE',     '2008-06-01', '2008-09-01',
        'CPIAUCSL YoY % change >= 4.00 AND UNRATE >= 5.50 in the same month, >= 3 consecutive months');

-- 8. industry_monthly_returns (COMPUTED from mock monthly_stock_prices)
INSERT INTO industry_monthly_returns (industry_id, period_date, avg_monthly_return, volatility, stock_count) VALUES
    (4, '2023-12-01', -0.001366, 0.037929, 2),
    (4, '2024-01-01', -0.012940, 0.024842, 2),
    (4, '2024-02-01', 0.058502, 0.034351, 2),
    (6, '2023-12-01', 0.016843, 0.003878, 2),
    (6, '2024-01-01', 0.043026, 0.027076, 2),
    (6, '2024-02-01', 0.011145, 0.102131, 2),
    (10, '2023-12-01', -0.022757, 0.048709, 2),
    (10, '2024-01-01', 0.040526, 0.018335, 2),
    (10, '2024-02-01', 0.055606, 0.022012, 2),
    (11, '2023-12-01', 0.076903, NULL, 1),
    (11, '2024-01-01', -0.010345, NULL, 1),
    (11, '2024-02-01', 0.005473, NULL, 1);

-- 9. condition_industry_performance
--    Condition 1 rows: COMPUTED from the mock months (Dec 2023 - Feb 2024).
--    Conditions 3 and 5 rows: ILLUSTRATIVE placeholders (no mock months behind them).
INSERT INTO condition_industry_performance
    (condition_id, industry_id, avg_monthly_return, win_rate_pct, excess_return_vs_market, sample_months) VALUES
    (1, 4, 0.014732, 33.33, -0.006658, 3),
    (1, 6, 0.023671, 100.00, 0.002281, 3),
    (1, 10, 0.024458, 66.67, 0.003068, 3),
    (1, 11, 0.024010, 66.67, 0.002620, 3),
    (3, 4, 0.004100, 55.95, -0.006200, 83),
    (3, 6, 0.015800, 63.86, 0.005500, 83),
    (3, 10, 0.011900, 62.65, 0.001600, 83),
    (3, 11, 0.009700, 59.04, -0.000600, 83),
    (5, 4, 0.031200, 65.38, 0.024800, 26),
    (5, 6, 0.002300, 50.00, -0.004100, 26),
    (5, 10, 0.005600, 53.85, -0.000800, 26),
    (5, 11, 0.008900, 57.69, 0.002500, 26);

-- 10. annual_economic_summary (illustrative; rates in percent, return as fraction)
INSERT INTO annual_economic_summary
    (year, avg_fed_funds_rate, annual_inflation_rate, gdp_growth_rate, avg_unemployment_rate, market_benchmark_return) VALUES
    (2021, 0.0800, 4.6980, 6.0550, 5.3500,  0.268900),
    (2022, 1.6800, 8.0000, 2.5120, 3.6500, -0.181100),
    (2023, 5.0200, 4.1200, 2.8870, 3.6250,  0.262900);

COMMIT;

-- Quick row-count check
SELECT 'industries' AS table_name, COUNT(*) AS row_count FROM industries
UNION ALL SELECT 'companies', COUNT(*) FROM companies
UNION ALL SELECT 'daily_stock_prices', COUNT(*) FROM daily_stock_prices
UNION ALL SELECT 'monthly_stock_prices', COUNT(*) FROM monthly_stock_prices
UNION ALL SELECT 'economic_indicators', COUNT(*) FROM economic_indicators
UNION ALL SELECT 'economic_data', COUNT(*) FROM economic_data
UNION ALL SELECT 'economic_conditions', COUNT(*) FROM economic_conditions
UNION ALL SELECT 'industry_monthly_returns', COUNT(*) FROM industry_monthly_returns
UNION ALL SELECT 'condition_industry_performance', COUNT(*) FROM condition_industry_performance
UNION ALL SELECT 'annual_economic_summary', COUNT(*) FROM annual_economic_summary;
