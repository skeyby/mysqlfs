#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-truncate")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-truncate"
test_file="$mountpoint/truncate.bin"
expected_file="$(mktemp "${TMPDIR:-/tmp}/mysqlfs-truncate-expected.XXXXXX")"
initial_size=140004
shrink_size=1024
grow_size=150000

cleanup() {
    rm -f "$expected_file"
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

dd if=/dev/zero bs=140000 count=1 2>/dev/null | tr '\0' 'A' > "$expected_file"
printf 'TAIL' >> "$expected_file"

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

cp "$expected_file" "$test_file"

if ! wait_for_file "$test_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "truncate test file was not created through the mount"
fi

assert_eq "$initial_size" "$(wc -c < "$test_file" | tr -d ' ')" \
    "expected initial multi-block test file size to match"

truncate_file "$test_file" "$shrink_size"

assert_eq "$shrink_size" "$(wc -c < "$test_file" | tr -d ' ')" \
    "expected file size to shrink after truncate"

if ! head -c "$shrink_size" "$expected_file" | cmp -s - "$test_file"; then
    fail "expected truncated file prefix to match the original content"
fi

truncate_file "$test_file" "$grow_size"

assert_eq "$grow_size" "$(wc -c < "$test_file" | tr -d ' ')" \
    "expected file size to grow after truncate"

if ! head -c "$shrink_size" "$expected_file" | cmp -s - <(head -c "$shrink_size" "$test_file"); then
    fail "expected grown file to preserve the original truncated prefix"
fi

assert_eq "0" "$(dd if="$test_file" bs=1 skip="$shrink_size" count=$((grow_size - shrink_size)) 2>/dev/null | tr -d '\0' | wc -c | tr -d ' ')" \
    "expected the grown section to be zero-filled"

assert_eq "$grow_size" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='truncate.bin';")" \
    "expected inode size to match the final truncate length"
