#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-write-read")"
mysqlfs_pid=""
test_file="$mountpoint/roundtrip.txt"
expected_content="mysqlfs roundtrip test content"
log_prefix="mysqlfs-test-write-read"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf '%s' "$expected_content" > "$test_file"

if ! wait_for_file "$test_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "round-trip test file was not created through the mount"
fi

assert_eq "$expected_content" "$(cat "$test_file")" \
    "expected to read back the same content that was written"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='roundtrip.txt';")" \
    "expected the new file to appear in the tree table"

assert_eq "${#expected_content}" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='roundtrip.txt';")" \
    "expected inode size to match the written content length"
