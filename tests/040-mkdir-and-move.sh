#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-mkdir-move")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-mkdir-move"
source_file="$mountpoint/move-me.txt"
target_dir="$mountpoint/subdir"
target_file="$target_dir/move-me.txt"
expected_content="move into directory content"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

mkdir "$target_dir"
printf '%s' "$expected_content" > "$source_file"

if ! wait_for_file "$source_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "move source file was not created through the mount"
fi

mv "$source_file" "$target_file"

assert_path_missing "$source_file" \
    "expected the source path to disappear after moving into a directory"

if ! wait_for_file "$target_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "moved file did not appear inside the target directory"
fi

assert_eq "$expected_content" "$(cat "$target_file")" \
    "expected moved file content to stay unchanged"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='subdir' AND parent=(SELECT inode FROM tree WHERE name='/' AND parent IS NULL);")" \
    "expected the new directory to appear under the root"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='move-me.txt' AND parent=(SELECT inode FROM tree WHERE name='subdir');")" \
    "expected the moved file to appear under the new directory"
