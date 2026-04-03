#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-large-file")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-large-file"
source_file="$(mktemp "${TMPDIR:-/tmp}/mysqlfs-large-source.XXXXXX")"
mounted_file="$mountpoint/large.bin"
file_size_bytes=$((16 * 1024 * 1024))

cleanup() {
    rm -f "$source_file"
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

dd if=/dev/urandom of="$source_file" bs=1048576 count=16 status=none
cp "$source_file" "$mounted_file"

if ! wait_for_file "$mounted_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "large checksum test file was not created through the mount"
fi

assert_eq "$file_size_bytes" "$(wc -c < "$mounted_file" | tr -d ' ')" \
    "expected the mounted file size to match the generated source data"

assert_eq "$(shasum -a 256 "$source_file" | awk '{print $1}')" \
    "$(shasum -a 256 "$mounted_file" | awk '{print $1}')" \
    "expected the mounted file checksum to match the source checksum"

if ! cmp -s "$source_file" "$mounted_file"; then
    fail "expected the mounted file bytes to match the generated source file"
fi

assert_eq "$file_size_bytes" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='large.bin';")" \
    "expected inode size to match the copied large file size"
