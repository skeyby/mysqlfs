#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

MYSQLFS_TEST_DB_HOST="${MYSQLFS_TEST_DB_HOST:-localhost}"
MYSQLFS_TEST_DB_NAME="${MYSQLFS_TEST_DB_NAME:-mysqlfs_test}"
MYSQLFS_TEST_DB_USER="${MYSQLFS_TEST_DB_USER:-mysqlfs_test}"
MYSQLFS_TEST_DB_PASS="${MYSQLFS_TEST_DB_PASS:-mysqlfs_test}"
MYSQLFS_TEST_ROOT_USER="${MYSQLFS_TEST_ROOT_USER:-root}"
MYSQLFS_TEST_ROOT_PASS="${MYSQLFS_TEST_ROOT_PASS:-}"
MYSQLFS_TEST_SOCKET="${MYSQLFS_TEST_SOCKET:-}"
MYSQLFS_TEST_BIN="${MYSQLFS_TEST_BIN:-$SCRIPT_DIR/build-macos/src/mysqlfs}"

find_mysql_socket() {
    local candidate

    if [ -n "$MYSQLFS_TEST_SOCKET" ]; then
        printf '%s\n' "$MYSQLFS_TEST_SOCKET"
        return 0
    fi

    for candidate in \
        /tmp/mysql.sock \
        /private/tmp/mysql.sock \
        /opt/homebrew/var/mysql/mysql.sock
    do
        if [ -S "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

mysql_root_args=(
    -u "$MYSQLFS_TEST_ROOT_USER"
)

if [ -n "$MYSQLFS_TEST_ROOT_PASS" ]; then
    mysql_root_args+=("--password=$MYSQLFS_TEST_ROOT_PASS")
fi

if MYSQLFS_TEST_SOCKET="$(find_mysql_socket)"; then
    mysql_root_args+=("--socket=$MYSQLFS_TEST_SOCKET")
else
    mysql_root_args+=("-h" "$MYSQLFS_TEST_DB_HOST")
fi

bootstrap_database() {
    echo "Resetting test database $MYSQLFS_TEST_DB_NAME"

    mysql "${mysql_root_args[@]}" <<SQL
DROP DATABASE IF EXISTS \`$MYSQLFS_TEST_DB_NAME\`;
CREATE DATABASE \`$MYSQLFS_TEST_DB_NAME\`;
CREATE USER IF NOT EXISTS '$MYSQLFS_TEST_DB_USER'@'localhost' IDENTIFIED BY '$MYSQLFS_TEST_DB_PASS';
ALTER USER '$MYSQLFS_TEST_DB_USER'@'localhost' IDENTIFIED BY '$MYSQLFS_TEST_DB_PASS';
GRANT ALL PRIVILEGES ON \`$MYSQLFS_TEST_DB_NAME\`.* TO '$MYSQLFS_TEST_DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

    echo "Initializing schema with mysqlfs_setup"

    DBHost="$MYSQLFS_TEST_DB_HOST" \
    DBName="$MYSQLFS_TEST_DB_NAME" \
    DBUser="$MYSQLFS_TEST_DB_USER" \
    DBPass="$MYSQLFS_TEST_DB_PASS" \
    DBSocket="$MYSQLFS_TEST_SOCKET" \
    MYSQLFS_SETUP_ASSUME_YES=1 \
    "$SCRIPT_DIR/mysqlfs_setup"

    echo "Test database is ready."
}

run_test() {
    local test_script="$1"

    echo
    echo "==> Running $(basename "$test_script")"

    MYSQLFS_TEST_DB_HOST="$MYSQLFS_TEST_DB_HOST" \
    MYSQLFS_TEST_DB_NAME="$MYSQLFS_TEST_DB_NAME" \
    MYSQLFS_TEST_DB_USER="$MYSQLFS_TEST_DB_USER" \
    MYSQLFS_TEST_DB_PASS="$MYSQLFS_TEST_DB_PASS" \
    MYSQLFS_TEST_SOCKET="$MYSQLFS_TEST_SOCKET" \
    MYSQLFS_TEST_BIN="$MYSQLFS_TEST_BIN" \
    "$test_script"
}

main() {
    local test_script

    if [ ! -x "$MYSQLFS_TEST_BIN" ]; then
        echo "error: mysqlfs test binary not found at $MYSQLFS_TEST_BIN" >&2
        exit 1
    fi

    bootstrap_database

    for test_script in "$TESTS_DIR"/[0-9][0-9][0-9]-*.sh; do
        run_test "$test_script"
    done
}

main "$@"
