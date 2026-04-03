#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-unlink")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-unlink"
test_file="$mountpoint/delete-me.txt"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf 'delete me' > "$test_file"

if ! wait_for_file "$test_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "unlink test file was not created through the mount"
fi

rm "$test_file"

assert_path_missing "$test_file" \
    "expected file to disappear from the mount after unlink"

assert_eq "0" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='delete-me.txt';")" \
    "expected unlinked file to disappear from the tree table"
