#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

FILE_COUNT="${MYSQLFS_BENCH_FILE_COUNT:-15000}"
BENCH_DIR_NAME="${MYSQLFS_BENCH_DIR_NAME:-benchdir}"
RESULTS_FILE="${MYSQLFS_BENCH_RESULTS_FILE:-}"
READ_COMMAND="${MYSQLFS_BENCH_READ_COMMAND:-ls -l >/dev/null}"
BENCH_PHASE="${MYSQLFS_BENCH_PHASE:-full}"
BENCH_MOUNTPOINT=""
BENCH_MYSQLFS_PID=""
BENCH_SETUP_LOG=""
BENCH_SAVED_NOAPPLEDOUBLE="0"

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

restart_mysqlfs() {
    local mountpoint="$1"
    local log_prefix="$2"

    cleanup_mount "$mountpoint" "${BENCH_MYSQLFS_PID:-}"
    BENCH_MYSQLFS_PID="$(start_mysqlfs_test "$mountpoint" "$log_prefix")"
    wait_for_mysqlfs_ready "$mountpoint" "$BENCH_MYSQLFS_PID" "$log_prefix"
}

main() {
    local repo_root=""
    local bench_dir=""
    local setup_log_prefix="mysqlfs-bench-large-directory-setup"
    local read_log_prefix="mysqlfs-bench-large-directory-read"
    local seconds=""
    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    init_mysqlfs_test_env "$repo_root"
    init_mysql_admin_args
    BENCH_SAVED_NOAPPLEDOUBLE="${MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE:-0}"
    MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE=1
    BENCH_SETUP_LOG="$(mktemp "$(default_mount_root)/mysqlfs-bench-setup.XXXXXX.log")"
    BENCH_MOUNTPOINT="$(make_mountpoint "mysqlfs-bench-large-directory")"
    trap 'MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE="$BENCH_SAVED_NOAPPLEDOUBLE"; cleanup_mount "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID"; rm -f "$BENCH_SETUP_LOG"' EXIT

    case "$BENCH_PHASE" in
        full|setup)
            if ! bootstrap_mysqlfs_test_database "$repo_root" >"$BENCH_SETUP_LOG" 2>&1; then
                cat "$BENCH_SETUP_LOG" >&2
                fail "unable to prepare the benchmark database"
            fi

            BENCH_MYSQLFS_PID="$(start_mysqlfs_test "$BENCH_MOUNTPOINT" "$setup_log_prefix")"
            wait_for_mysqlfs_ready "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID" "$setup_log_prefix"

            bench_dir="$BENCH_MOUNTPOINT/$BENCH_DIR_NAME"
            mkdir "$bench_dir"
            create_benchmark_files "$bench_dir" "$FILE_COUNT"

            if [ "$BENCH_PHASE" = "setup" ]; then
                echo "Benchmark setup completed."
                echo "files:        $FILE_COUNT"
                echo "path:         $bench_dir"
                return 0
            fi

            restart_mysqlfs "$BENCH_MOUNTPOINT" "$read_log_prefix"
            ;;
        read)
            BENCH_MYSQLFS_PID="$(start_mysqlfs_test "$BENCH_MOUNTPOINT" "$read_log_prefix")"
            wait_for_mysqlfs_ready "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID" "$read_log_prefix"
            ;;
        *)
            fail "unknown BENCH_PHASE '$BENCH_PHASE' (expected: full, setup, read)"
            ;;
    esac

    bench_dir="$BENCH_MOUNTPOINT/$BENCH_DIR_NAME"

    echo "Benchmark: large-directory-listing (two-step)"
    echo "phase:        $BENCH_PHASE"
    echo "files:        $FILE_COUNT"
    echo "path:         $bench_dir"
    echo "read command: $READ_COMMAND"
    echo

    seconds="$(run_timed_shell "cd '$bench_dir'")"
    record_result "cd" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && ls >/dev/null")"
    record_result "cd+ls" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && $READ_COMMAND")"
    record_result "read #1" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && $READ_COMMAND")"
    record_result "read #2" "$seconds"
}

main "$@"
