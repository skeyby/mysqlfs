#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-overwrite-middle")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-overwrite-middle"
test_file="$mountpoint/overwrite.txt"
initial_content="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
replacement="mysqlfs"
replacement_offset=10
expected_content="0123456789mysqlfsHIJKLMNOPQRSTUVWXYZ"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf '%s' "$initial_content" > "$test_file"

if ! wait_for_file "$test_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "overwrite test file was not created through the mount"
fi

printf '%s' "$replacement" | dd of="$test_file" bs=1 seek="$replacement_offset" conv=notrunc status=none

assert_eq "$expected_content" "$(cat "$test_file")" \
    "expected the middle overwrite to preserve the surrounding content"

assert_eq "${#expected_content}" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='overwrite.txt';")" \
    "expected inode size to stay unchanged after an in-place overwrite"
