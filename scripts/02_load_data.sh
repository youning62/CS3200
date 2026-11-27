#!/usr/bin/env bash
# =============================================================================
# 02_load_data.sh -- load the team's real-data dump into the v3.0 schema
#
# Usage:
#   bash scripts/02_load_data.sh <path/to/DumpYYYYMMDD.sql> [mysql client options]
#   e.g.
#   bash scripts/02_load_data.sh ~/Downloads/Dump20261126.sql -u root -p
#
# Why not just `mysql < dump.sql`?
#   A full mysqldump contains its own DROP/CREATE TABLE statements. Loading it
#   directly would replace our tables with the dump's own DDL and silently drop
#   every CHECK constraint, index and NOT NULL rule in sql/01_create_tables.sql.
#   This script keeps ONLY the dump's INSERT statements and loads them into
#   the tables 01_create_tables.sql created.
#
# Re-runnable: empties all 8 tables first, then reloads everything in one
# transaction. CHECK constraints stay enforced during the load. FK checks are
# off only because the dump inserts tables alphabetically (children before
# parents); 03_validate_schema.sql verifies there are no orphans afterwards.
#
# Run order: sql/01_create_tables.sql -> scripts/02_load_data.sh -> sql/03_validate_schema.sql
# The dump contains licensed CRSP data: never commit it to git.
# =============================================================================
set -euo pipefail

if [[ $# -lt 1 || ! -f "$1" ]]; then
    echo "Usage: bash $0 <dump.sql> [mysql options, e.g. -u root -p]" >&2
    exit 1
fi
DUMP="$1"; shift

n_inserts=$(grep -c '^INSERT INTO `' "$DUMP" || true)
if [[ "$n_inserts" -eq 0 ]]; then
    echo "No INSERT statements found in $DUMP" >&2
    exit 1
fi
echo "Loading $n_inserts INSERT statements from $DUMP into stock_analysis ..."

{
    echo "USE stock_analysis;"
    echo "SET NAMES utf8mb4;"
    echo "SET FOREIGN_KEY_CHECKS = 0;"
    echo "SET UNIQUE_CHECKS = 0;"
    for t in condition_industry_performance industry_monthly_returns economic_conditions \
             economic_data economic_indicators monthly_stock_prices companies industries; do
        echo "TRUNCATE TABLE $t;"
    done
    echo "SET autocommit = 0;"
    grep '^INSERT INTO `' "$DUMP"
    echo "COMMIT;"
    echo "SET UNIQUE_CHECKS = 1;"
    echo "SET FOREIGN_KEY_CHECKS = 1;"
    echo "SELECT 'industries' AS table_name, COUNT(*) AS row_count FROM industries"
    echo "UNION ALL SELECT 'companies', COUNT(*) FROM companies"
    echo "UNION ALL SELECT 'monthly_stock_prices', COUNT(*) FROM monthly_stock_prices"
    echo "UNION ALL SELECT 'economic_indicators', COUNT(*) FROM economic_indicators"
    echo "UNION ALL SELECT 'economic_data', COUNT(*) FROM economic_data"
    echo "UNION ALL SELECT 'economic_conditions', COUNT(*) FROM economic_conditions"
    echo "UNION ALL SELECT 'industry_monthly_returns', COUNT(*) FROM industry_monthly_returns"
    echo "UNION ALL SELECT 'condition_industry_performance', COUNT(*) FROM condition_industry_performance;"
} | mysql --max-allowed-packet=256M -t "$@"

echo "Done. Next: mysql $* < sql/03_validate_schema.sql"
