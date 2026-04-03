#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-root-bootstrap")"
mysqlfs_pid=""

cleanup() {
    cleanup_mount "$mountpoint" "$mysqlfs_pid"
}

trap cleanup EXIT

"$MYSQLFS_TEST_BIN" \
    -f \
    -s \
    -obig_writes \
    -odefault_permissions \
    -osocket="$MYSQLFS_TEST_SOCKET" \
    -odatabase="$MYSQLFS_TEST_DB_NAME" \
    -ouser="$MYSQLFS_TEST_DB_USER" \
    -opassword="$MYSQLFS_TEST_DB_PASS" \
    "$mountpoint" \
    >/tmp/mysqlfs-test-root-bootstrap.stdout.log \
    2>/tmp/mysqlfs-test-root-bootstrap.stderr.log &
mysqlfs_pid=$!

if ! kill -0 "$mysqlfs_pid" >/dev/null 2>&1; then
    cat /tmp/mysqlfs-test-root-bootstrap.stdout.log >&2 || true
    cat /tmp/mysqlfs-test-root-bootstrap.stderr.log >&2 || true
    fail "mysqlfs did not stay alive long enough to initialize the filesystem"
fi

if ! wait_for_mount_ready "$mountpoint" "0755"; then
    cat /tmp/mysqlfs-test-root-bootstrap.stdout.log >&2 || true
    cat /tmp/mysqlfs-test-root-bootstrap.stderr.log >&2 || true
    fail "mysqlfs did not become ready on the mountpoint in time"
fi

if ! wait_for_query_result "1" "SELECT COUNT(*) FROM tree WHERE name='/' AND parent IS NULL;"; then
    cat /tmp/mysqlfs-test-root-bootstrap.stdout.log >&2 || true
    cat /tmp/mysqlfs-test-root-bootstrap.stderr.log >&2 || true
    fail "mysqlfs did not create the root directory entry in time"
fi

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='/' AND parent IS NULL;")" \
    "expected the root directory to be created during mysqlfs startup"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='/' AND tree.parent IS NULL;")" \
    "expected the root inode metadata to exist after startup"
