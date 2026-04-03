#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

mountpoint="$(make_mountpoint "mysqlfs-write-read")"
mysqlfs_pid=""
test_file="$mountpoint/roundtrip.txt"
expected_content="mysqlfs roundtrip test content"

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
    >/tmp/mysqlfs-test-write-read.stdout.log \
    2>/tmp/mysqlfs-test-write-read.stderr.log &
mysqlfs_pid=$!

if ! wait_for_query_result "1" "SELECT COUNT(*) FROM tree WHERE name='/' AND parent IS NULL;"; then
    cat /tmp/mysqlfs-test-write-read.stdout.log >&2 || true
    cat /tmp/mysqlfs-test-write-read.stderr.log >&2 || true
    fail "mysqlfs did not create the root directory entry in time"
fi

if ! wait_for_mount_ready "$mountpoint" "0755"; then
    cat /tmp/mysqlfs-test-write-read.stdout.log >&2 || true
    cat /tmp/mysqlfs-test-write-read.stderr.log >&2 || true
    fail "mysqlfs did not become ready on the mountpoint in time"
fi

printf '%s' "$expected_content" > "$test_file"

if ! wait_for_file "$test_file"; then
    cat /tmp/mysqlfs-test-write-read.stdout.log >&2 || true
    cat /tmp/mysqlfs-test-write-read.stderr.log >&2 || true
    fail "round-trip test file was not created through the mount"
fi

assert_eq "$expected_content" "$(cat "$test_file")" \
    "expected to read back the same content that was written"

assert_eq "1" "$(mysql_query "SELECT COUNT(*) FROM tree WHERE name='roundtrip.txt';")" \
    "expected the new file to appear in the tree table"

assert_eq "${#expected_content}" "$(mysql_query "SELECT inodes.size FROM inodes INNER JOIN tree ON tree.inode = inodes.inode WHERE tree.name='roundtrip.txt';")" \
    "expected inode size to match the written content length"
