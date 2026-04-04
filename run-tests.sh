#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

MYSQLFS_TEST_DB_HOST="${MYSQLFS_TEST_DB_HOST:-localhost}"
MYSQLFS_TEST_DB_NAME="${MYSQLFS_TEST_DB_NAME:-mysqlfs_test}"
MYSQLFS_TEST_DB_USER="${MYSQLFS_TEST_DB_USER:-mysqlfs_test}"
MYSQLFS_TEST_DB_PASS="${MYSQLFS_TEST_DB_PASS:-mysqlfs_test}"
MYSQLFS_TEST_SOCKET="${MYSQLFS_TEST_SOCKET:-}"
MYSQLFS_TEST_ADMIN_USER="${MYSQLFS_TEST_ADMIN_USER:-$MYSQLFS_TEST_DB_USER}"
MYSQLFS_TEST_ADMIN_PASS="${MYSQLFS_TEST_ADMIN_PASS:-$MYSQLFS_TEST_DB_PASS}"

default_build_dir() {
    case "$(uname -s)" in
        Darwin)
            printf '%s\n' "build-macos"
            ;;
        *)
            printf '%s\n' "build"
            ;;
    esac
}

find_mysqlfs_test_binary() {
    local candidate
    local build_dir

    if [ -n "${MYSQLFS_TEST_BIN:-}" ]; then
        printf '%s\n' "$MYSQLFS_TEST_BIN"
        return 0
    fi

    build_dir="${MYSQLFS_BUILD_DIR:-$(default_build_dir)}"

    for candidate in \
        "$SCRIPT_DIR/$build_dir/src/mysqlfs" \
        "$SCRIPT_DIR/build-macos/src/mysqlfs" \
        "$SCRIPT_DIR/build/src/mysqlfs"
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

find_mysql_socket() {
    local candidate

    if [ -n "$MYSQLFS_TEST_SOCKET" ]; then
        printf '%s\n' "$MYSQLFS_TEST_SOCKET"
        return 0
    fi

    for candidate in \
        /tmp/mysql.sock \
        /private/tmp/mysql.sock \
        /opt/homebrew/var/mysql/mysql.sock \
        /var/run/mysql/mysql.sock
    do
        if [ -S "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

init_mysql_admin_args() {
    mysql_admin_args=(
        -u "$MYSQLFS_TEST_ADMIN_USER"
    )

    if [ -n "$MYSQLFS_TEST_ADMIN_PASS" ]; then
        mysql_admin_args+=("--password=$MYSQLFS_TEST_ADMIN_PASS")
    fi

    if MYSQLFS_TEST_SOCKET="$(find_mysql_socket)"; then
        mysql_admin_args+=("--socket=$MYSQLFS_TEST_SOCKET")
    else
        mysql_admin_args+=("-h" "$MYSQLFS_TEST_DB_HOST")
    fi
}

bootstrap_database() {
    echo "Resetting test database $MYSQLFS_TEST_DB_NAME"

    mysql "${mysql_admin_args[@]}" <<SQL
DROP DATABASE IF EXISTS \`$MYSQLFS_TEST_DB_NAME\`;
CREATE DATABASE \`$MYSQLFS_TEST_DB_NAME\`;
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

    if ! MYSQLFS_TEST_BIN="$(find_mysqlfs_test_binary)"; then
        echo "error: mysqlfs test binary not found in the configured build directory" >&2
        exit 1
    fi

    if [ ! -x "$MYSQLFS_TEST_BIN" ]; then
        echo "error: mysqlfs test binary not found at $MYSQLFS_TEST_BIN" >&2
        exit 1
    fi

    init_mysql_admin_args
    bootstrap_database

    for test_script in "$TESTS_DIR"/[0-9][0-9][0-9]-*.sh; do
        run_test "$test_script"
    done
}

main "$@"
