#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-rename-file")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-rename-file"
source_file="$mountpoint/source.txt"
target_file="$mountpoint/renamed.txt"
expected_content="rename roundtrip content"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf '%s' "$expected_content" > "$source_file"

if ! wait_for_file "$source_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "source file was not created through the mount"
fi

mv "$source_file" "$target_file"

assert_path_missing "$source_file" \
    "expected the source path to disappear after rename"

if ! wait_for_file "$target_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "renamed file did not appear through the mount"
fi

assert_eq "$expected_content" "$(cat "$target_file")" \
    "expected renamed file content to stay unchanged"

assert_eq "0" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='source.txt';")" \
    "expected the old tree entry to disappear after rename"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='renamed.txt' AND parent=(SELECT inode FROM tree WHERE name='/' AND parent IS NULL);")" \
    "expected the renamed file to appear in the root directory entry list"
