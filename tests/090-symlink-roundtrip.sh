#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-symlink")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-symlink"
target_file="$mountpoint/original.txt"
link_file="$mountpoint/linked.txt"
target_content="symlink target content"
updated_content="symlink updated through the target"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

printf '%s' "$target_content" > "$target_file"

if ! wait_for_file "$target_file"; then
    dump_mysqlfs_logs "$log_prefix"
    fail "symlink target file was not created through the mount"
fi

ln -s "$(basename "$target_file")" "$link_file"

if [ ! -L "$link_file" ]; then
    dump_mysqlfs_logs "$log_prefix"
    fail "symbolic link was not created through the mount"
fi

assert_eq "$(basename "$target_file")" "$(readlink "$link_file")" \
    "expected readlink to return the stored symlink target"

assert_eq "$target_content" "$(cat "$link_file")" \
    "expected reading the symbolic link path to resolve to the target content"

printf '%s' "$updated_content" > "$target_file"

assert_eq "$updated_content" "$(cat "$link_file")" \
    "expected symbolic link reads to track updates to the target file"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='linked.txt' AND parent=(SELECT inode FROM tree WHERE name='/' AND parent IS NULL);")" \
    "expected the symbolic link direntry to exist in the root directory"
