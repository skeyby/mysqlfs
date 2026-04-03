#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-readdir")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-readdir"
target_dir="$mountpoint/listing"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

mkdir "$target_dir"
printf 'one' > "$target_dir/alpha.txt"
printf 'two' > "$target_dir/beta.txt"
printf 'three' > "$target_dir/gamma.txt"

assert_eq "alpha.txt
beta.txt
gamma.txt" "$(find "$target_dir" -maxdepth 1 -type f -exec basename {} \; | grep -v '^[.]_' | sort)" \
    "expected readdir-visible file names to match the created entries"

assert_eq "3" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE parent=(SELECT inode FROM tree WHERE name='listing') AND name NOT LIKE '._%';")" \
    "expected the listing directory to contain exactly three file entries"
