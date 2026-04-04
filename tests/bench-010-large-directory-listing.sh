#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

FILE_COUNT="${MYSQLFS_BENCH_FILE_COUNT:-15000}"
BENCH_DIR_NAME="${MYSQLFS_BENCH_DIR_NAME:-benchdir}"
RESULTS_FILE="${MYSQLFS_BENCH_RESULTS_FILE:-}"
BENCH_MOUNTPOINT=""
BENCH_MYSQLFS_PID=""
BENCH_SETUP_LOG=""

run_timed_shell() {
    local command="$1"

    perl -MTime::HiRes=time -e '
        my $start = time();
        system @ARGV;
        my $status = $?;
        printf "%.6f\n", time() - $start;
        exit($status >> 8);
    ' sh -c "$command"
}

create_benchmark_files() {
    local target_dir="$1"
    local file_count="$2"

    perl -e '
        my ($dir, $count) = @ARGV;
        for my $i (1 .. $count) {
            my $path = sprintf("%s/file_%05d", $dir, $i);
            open my $fh, ">", $path or die "$path: $!\n";
            close $fh or die "$path: $!\n";
        }
    ' "$target_dir" "$file_count"
}

record_result() {
    local label="$1"
    local seconds="$2"

    printf "%-16s %s s\n" "$label:" "$seconds"

    if [ -n "$RESULTS_FILE" ]; then
        printf "%s,%s,%s,%s\n" \
            "$(date +%F)" \
            "$FILE_COUNT" \
            "$label" \
            "$seconds" >>"$RESULTS_FILE"
    fi
}

main() {
    local repo_root=""
    local bench_dir=""
    local log_prefix="mysqlfs-bench-large-directory"
    local seconds=""

    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    init_mysqlfs_test_env "$repo_root"
    init_mysql_admin_args
    BENCH_SETUP_LOG="$(mktemp "$(default_mount_root)/mysqlfs-bench-setup.XXXXXX.log")"
    if ! bootstrap_mysqlfs_test_database "$repo_root" >"$BENCH_SETUP_LOG" 2>&1; then
        cat "$BENCH_SETUP_LOG" >&2
        fail "unable to prepare the benchmark database"
    fi

    BENCH_MOUNTPOINT="$(make_mountpoint "mysqlfs-bench-large-directory")"
    trap 'cleanup_mount "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID"; rm -f "$BENCH_SETUP_LOG"' EXIT

    BENCH_MYSQLFS_PID="$(start_mysqlfs_test "$BENCH_MOUNTPOINT" "$log_prefix")"
    wait_for_mysqlfs_ready "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID" "$log_prefix"

    bench_dir="$BENCH_MOUNTPOINT/$BENCH_DIR_NAME"
    mkdir "$bench_dir"
    create_benchmark_files "$bench_dir" "$FILE_COUNT"

    echo "Benchmark: large-directory-listing"
    echo "files:     $FILE_COUNT"
    echo "path:      $bench_dir"
    echo

    seconds="$(run_timed_shell "cd '$bench_dir'")"
    record_result "cd" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && ls >/dev/null")"
    record_result "cd+ls" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && ls -l >/dev/null")"
    record_result "cd+ls -l #1" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && ls -l >/dev/null")"
    record_result "cd+ls -l #2" "$seconds"
}

main "$@"
