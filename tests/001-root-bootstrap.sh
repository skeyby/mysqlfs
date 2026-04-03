#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-root-bootstrap")"
mysqlfs_pid=""
log_prefix="mysqlfs-test-root-bootstrap"

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

mysqlfs_pid="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
wait_for_mysqlfs_ready "$mountpoint" "$mysqlfs_pid" "$log_prefix"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='/' AND parent IS NULL;")" \
    "expected the root directory to be created during mysqlfs startup"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='/' AND tree.parent IS NULL;")" \
    "expected the root inode metadata to exist after startup"
