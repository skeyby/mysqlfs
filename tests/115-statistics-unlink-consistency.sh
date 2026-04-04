#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-statistics-unlink")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-statistics-unlink"
test_file="$mountpoint/statistics-delete-me.txt"
expected_content="1234567890"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

assert_statistics_match_inodes() {
    local expected_count
    local actual_count
    local expected_size
    local actual_size
    local phase="$1"

    expected_count="$(mysql_query "SELECT COUNT(*) FROM inodes;")"
    actual_count="$(mysql_query "SELECT CAST(value AS UNSIGNED) FROM statistics WHERE \`key\`='total_inodes_count';")"
    expected_size="$(mysql_query "SELECT COALESCE(SUM(size), 0) FROM inodes;")"
    actual_size="$(mysql_query "SELECT CAST(value AS UNSIGNED) FROM statistics WHERE \`key\`='total_inodes_size';")"

    assert_eq "$expected_count" "$actual_count" \
        "expected total_inodes_count to match live inode count $phase"
    assert_eq "$expected_size" "$actual_size" \
        "expected total_inodes_size to match live inode size $phase"
}

assert_statistics_match_inodes "before file creation"

printf '%s' "$expected_content" > "$test_file"

if ! wait_for_file "$test_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "statistics test file was not created through the mount"
fi

assert_statistics_match_inodes "after file creation"

rm "$test_file"

assert_path_missing "$test_file" \
    "expected statistics test file to disappear from the mount after unlink"

assert_statistics_match_inodes "after unlink"
