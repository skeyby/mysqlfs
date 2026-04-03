#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-rename-replace")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-rename-replace"
source_file="$mountpoint/source.txt"
target_file="$mountpoint/target.txt"
source_content="replacement source payload"
target_content="old target payload"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf '%s' "$source_content" > "$source_file"
printf '%s' "$target_content" > "$target_file"

if ! wait_for_file "$source_file" || ! wait_for_file "$target_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "rename replacement inputs were not created through the mount"
fi

mv -f "$source_file" "$target_file"

assert_path_missing "$source_file" \
    "expected the source path to disappear after replacement rename"

if ! wait_for_file "$target_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "replacement target did not exist after rename"
fi

assert_eq "$source_content" "$(cat "$target_file")" \
    "expected the renamed target to expose the source content"

assert_eq "0" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='source.txt';")" \
    "expected the source direntry to disappear after replacement rename"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='target.txt' AND parent=(SELECT inode FROM tree WHERE name='/' AND parent IS NULL);")" \
    "expected the replacement target direntry to remain unique in the root directory"

assert_eq "${#source_content}" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='target.txt';")" \
    "expected inode size on the replacement target to match the source payload"
