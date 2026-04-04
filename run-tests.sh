#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
. "$TESTS_DIR/test-lib.sh"

MYSQLFS_TEST_DB_HOST="${MYSQLFS_TEST_DB_HOST:-localhost}"
MYSQLFS_TEST_DB_NAME="${MYSQLFS_TEST_DB_NAME:-mysqlfs_test}"
MYSQLFS_TEST_DB_USER="${MYSQLFS_TEST_DB_USER:-mysqlfs_test}"
MYSQLFS_TEST_DB_PASS="${MYSQLFS_TEST_DB_PASS:-mysqlfs_test}"
MYSQLFS_TEST_SOCKET="${MYSQLFS_TEST_SOCKET:-}"
MYSQLFS_TEST_CACHE_TTL="${MYSQLFS_TEST_CACHE_TTL:-0}"
MYSQLFS_TEST_ADMIN_USER="${MYSQLFS_TEST_ADMIN_USER:-$MYSQLFS_TEST_DB_USER}"
MYSQLFS_TEST_ADMIN_PASS="${MYSQLFS_TEST_ADMIN_PASS:-$MYSQLFS_TEST_DB_PASS}"

run_test() {
    local test_script="$1"

    echo
    echo "==> Running $(basename "$test_script")"

    MYSQLFS_TEST_DB_HOST="$MYSQLFS_TEST_DB_HOST" \
    MYSQLFS_TEST_DB_NAME="$MYSQLFS_TEST_DB_NAME" \
    MYSQLFS_TEST_DB_USER="$MYSQLFS_TEST_DB_USER" \
    MYSQLFS_TEST_DB_PASS="$MYSQLFS_TEST_DB_PASS" \
    MYSQLFS_TEST_SOCKET="$MYSQLFS_TEST_SOCKET" \
    MYSQLFS_TEST_CACHE_TTL="$MYSQLFS_TEST_CACHE_TTL" \
    MYSQLFS_TEST_BIN="$MYSQLFS_TEST_BIN" \
    "$test_script"
}

main() {
    local test_script

    init_mysqlfs_test_env "$SCRIPT_DIR"

    init_mysql_admin_args
    bootstrap_mysqlfs_test_database "$SCRIPT_DIR"

    for test_script in "$TESTS_DIR"/[0-9][0-9][0-9]-*.sh; do
        run_test "$test_script"
    done
}

main "$@"
