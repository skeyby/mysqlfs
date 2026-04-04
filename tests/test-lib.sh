#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

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
    local script_root="$1"
    local build_dir
    local candidate

    if [ -n "${MYSQLFS_TEST_BIN:-}" ]; then
        printf '%s\n' "$MYSQLFS_TEST_BIN"
        return 0
    fi

    build_dir="${MYSQLFS_BUILD_DIR:-$(default_build_dir)}"

    for candidate in \
        "$script_root/$build_dir/src/mysqlfs" \
        "$script_root/build-macos/src/mysqlfs" \
        "$script_root/build/src/mysqlfs"
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

    if [ -n "${MYSQLFS_TEST_SOCKET:-}" ]; then
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

init_mysqlfs_test_env() {
    local script_root="$1"

    MYSQLFS_TEST_DB_HOST="${MYSQLFS_TEST_DB_HOST:-localhost}"
    MYSQLFS_TEST_DB_NAME="${MYSQLFS_TEST_DB_NAME:-mysqlfs_test}"
    MYSQLFS_TEST_DB_USER="${MYSQLFS_TEST_DB_USER:-mysqlfs_test}"
    MYSQLFS_TEST_DB_PASS="${MYSQLFS_TEST_DB_PASS:-mysqlfs_test}"
    MYSQLFS_TEST_SOCKET="${MYSQLFS_TEST_SOCKET:-}"
    MYSQLFS_TEST_CACHE_TTL="${MYSQLFS_TEST_CACHE_TTL:-0}"
    MYSQLFS_TEST_ADMIN_USER="${MYSQLFS_TEST_ADMIN_USER:-$MYSQLFS_TEST_DB_USER}"
    MYSQLFS_TEST_ADMIN_PASS="${MYSQLFS_TEST_ADMIN_PASS:-$MYSQLFS_TEST_DB_PASS}"

    if ! MYSQLFS_TEST_BIN="$(find_mysqlfs_test_binary "$script_root")"; then
        fail "mysqlfs test binary not found in the configured build directory"
    fi

    if [ ! -x "$MYSQLFS_TEST_BIN" ]; then
        fail "mysqlfs test binary not found at $MYSQLFS_TEST_BIN"
    fi

    if [ -z "$MYSQLFS_TEST_SOCKET" ]; then
        MYSQLFS_TEST_SOCKET="$(find_mysql_socket || true)"
    fi
}

init_mysql_admin_args() {
    mysql_admin_args=(
        -u "$MYSQLFS_TEST_ADMIN_USER"
    )

    if [ -n "$MYSQLFS_TEST_ADMIN_PASS" ]; then
        mysql_admin_args+=("--password=$MYSQLFS_TEST_ADMIN_PASS")
    fi

    if [ -n "$MYSQLFS_TEST_SOCKET" ]; then
        mysql_admin_args+=("--socket=$MYSQLFS_TEST_SOCKET")
    else
        mysql_admin_args+=("-h" "$MYSQLFS_TEST_DB_HOST")
    fi
}

bootstrap_mysqlfs_test_database() {
    local script_root="$1"

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
    "$script_root/mysqlfs_setup"

    echo "Test database is ready."
}

dump_mysqlfs_logs() {
    local log_prefix="$1"

    cat "/tmp/${log_prefix}.stdout.log" >&2 || true
    cat "/tmp/${log_prefix}.stderr.log" >&2 || true
}

default_mount_root() {
    case "$(uname -s)" in
        Darwin)
            printf '%s\n' "${MYSQLFS_TEST_TMPDIR:-/private/tmp}"
            ;;
        *)
            printf '%s\n' "${MYSQLFS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
            ;;
    esac
}

make_mountpoint() {
    local mount_root

    mount_root="$(default_mount_root)"
    mktemp -d "$mount_root/$1.XXXXXX"
}

start_mysqlfs_test() {
    local mountpoint="$1"
    local log_prefix="$2"
    local mysqlfs_args=()

    if [ -n "${MYSQLFS_TEST_SOCKET:-}" ]; then
        mysqlfs_args+=("-osocket=$MYSQLFS_TEST_SOCKET")
    else
        mysqlfs_args+=("-ohost=${MYSQLFS_TEST_DB_HOST:-localhost}")
    fi

    mysqlfs_args+=(
        -f
        -s
        -obig_writes
        -odefault_permissions
        "-ocache_ttl=$MYSQLFS_TEST_CACHE_TTL"
        "-odatabase=$MYSQLFS_TEST_DB_NAME"
        "-ouser=$MYSQLFS_TEST_DB_USER"
        "-opassword=$MYSQLFS_TEST_DB_PASS"
    )

    if [ "${MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE:-0}" = "1" ] &&
       [ "$(uname -s)" = "Darwin" ]; then
        mysqlfs_args+=("-onoappledouble")
    fi

    mysqlfs_args+=("$mountpoint")

    "$MYSQLFS_TEST_BIN" \
        "${mysqlfs_args[@]}" \
        >"/tmp/${log_prefix}.stdout.log" \
        2>"/tmp/${log_prefix}.stderr.log" &

    echo $!
}

mysql_test_args() {
    if [ -n "${MYSQLFS_TEST_SOCKET:-}" ]; then
        printf -- "--socket=%s\n" "$MYSQLFS_TEST_SOCKET"
    else
        printf -- "-h\n%s\n" "${MYSQLFS_TEST_DB_HOST:-localhost}"
    fi
}

mysql_query() {
    local mysql_args=()

    while IFS= read -r arg; do
        mysql_args+=("$arg")
    done < <(mysql_test_args)

    mysql \
        "${mysql_args[@]}" \
        -u "$MYSQLFS_TEST_DB_USER" \
        --password="$MYSQLFS_TEST_DB_PASS" \
        -D "$MYSQLFS_TEST_DB_NAME" \
        -N \
        -e "$1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [ "$expected" != "$actual" ]; then
        fail "$message (expected '$expected', got '$actual')"
    fi
}

stat_mode() {
    local path="$1"

    if stat -f '%Mp%Lp' "$path" >/dev/null 2>&1; then
        stat -f '%Mp%Lp' "$path"
        return 0
    fi

    if stat -c '%a' "$path" >/dev/null 2>&1; then
        printf '0%s\n' "$(stat -c '%a' "$path")"
        return 0
    fi

    return 1
}

wait_for_mount_ready() {
    local mountpoint="$1"
    local expected_mode="$2"
    local attempt=0
    local mode=""

    while [ "$attempt" -lt 50 ]; do
        mode="$(stat_mode "$mountpoint" || true)"
        if [ "$mode" = "$expected_mode" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done

    return 1
}

wait_for_mysqlfs_ready() {
    local mountpoint="$1"
    local pid="$2"
    local log_prefix="$3"

    if ! kill -0 "$pid" >/dev/null 2>&1; then
        dump_mysqlfs_logs "$log_prefix"
        fail "mysqlfs did not stay alive long enough to initialize the filesystem"
    fi

    if ! wait_for_mount_ready "$mountpoint" "0755"; then
        dump_mysqlfs_logs "$log_prefix"
        fail "mysqlfs did not become ready on the mountpoint in time"
    fi

    if ! wait_for_query_result "1" "SELECT COUNT(*) FROM tree WHERE name='/' AND parent IS NULL;"; then
        dump_mysqlfs_logs "$log_prefix"
        fail "mysqlfs did not create the root directory entry in time"
    fi
}

wait_for_query_result() {
    local expected="$1"
    local query="$2"
    local attempt=0
    local actual=""

    while [ "$attempt" -lt 50 ]; do
        actual="$(mysql_query "$query")"
        if [ "$actual" = "$expected" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done

    return 1
}

wait_for_file() {
    local path="$1"
    local attempt=0

    while [ "$attempt" -lt 50 ]; do
        if [ -f "$path" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done

    return 1
}

assert_path_missing() {
    local path="$1"
    local message="$2"

    if [ -e "$path" ]; then
        fail "$message"
    fi
}

truncate_file() {
    local path="$1"
    local size="$2"

    perl -e 'truncate($ARGV[0], $ARGV[1]) or die "$ARGV[0]: $!\n";' "$path" "$size"
}

cleanup_mount() {
    local mountpoint="$1"
    local pid="$2"

    if mount | grep "on $mountpoint " >/dev/null 2>&1; then
        /sbin/umount "$mountpoint" >/dev/null 2>&1 || /usr/sbin/diskutil unmount force "$mountpoint" >/dev/null 2>&1 || true
    fi

    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    fi

    rmdir "$mountpoint" >/dev/null 2>&1 || true
}
