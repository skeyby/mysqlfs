#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-sparse-file")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-sparse-file"
test_file="$mountpoint/sparse.bin"
prefix="BEGIN"
suffix="END"
hole_offset=$((2 * 1024 * 1024))
expected_size=$((hole_offset + ${#suffix}))

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf '%s' "$prefix" > "$test_file"
printf '%s' "$suffix" | dd of="$test_file" bs=1 seek="$hole_offset" conv=notrunc status=none

if ! wait_for_file "$test_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "sparse test file was not created through the mount"
fi

assert_eq "$expected_size" "$(wc -c < "$test_file" | tr -d ' ')" \
    "expected sparse file logical size to include the hole"

assert_eq "$expected_size" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='sparse.bin';")" \
    "expected inode size to reflect the sparse file logical size"

assert_eq "$prefix" "$(head -c "${#prefix}" "$test_file")" \
    "expected the sparse file prefix to remain readable"

assert_eq "$suffix" "$(tail -c "${#suffix}" "$test_file")" \
    "expected the sparse file suffix to remain readable"

assert_eq "0" "$(dd if="$test_file" bs=1 skip="${#prefix}" count=$((hole_offset - ${#prefix})) 2>/dev/null | tr -d '\0' | wc -c | tr -d ' ')" \
    "expected the sparse hole to read back as zero-filled bytes"
