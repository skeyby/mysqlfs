#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

TOP_DIRS="${MYSQLFS_TREE_BENCH_TOP_DIRS:-100}"
SUBDIRS_PER_TOP="${MYSQLFS_TREE_BENCH_SUBDIRS_PER_TOP:-100}"
FILES_PER_SUBDIR="${MYSQLFS_TREE_BENCH_FILES_PER_SUBDIR:-1}"
BENCH_DIR_NAME="${MYSQLFS_TREE_BENCH_DIR_NAME:-treebench}"
RESULTS_FILE="${MYSQLFS_TREE_BENCH_RESULTS_FILE:-}"
READ_COMMAND="${MYSQLFS_TREE_BENCH_READ_COMMAND:-find . >/dev/null}"
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

create_tree_benchmark() {
    local target_dir="$1"
    local top_dirs="$2"
    local subdirs_per_top="$3"
    local files_per_subdir="$4"

    perl -e '
        use File::Path qw(make_path);

        my ($root, $top_count, $sub_count, $file_count) = @ARGV;

        for my $top (1 .. $top_count) {
            my $top_dir = sprintf("%s/dir_%03d", $root, $top);
            make_path($top_dir) or die "$top_dir: $!\n";

            for my $sub (1 .. $sub_count) {
                my $sub_dir = sprintf("%s/sub_%03d", $top_dir, $sub);
                make_path($sub_dir) or die "$sub_dir: $!\n";

                for my $file (1 .. $file_count) {
                    my $path = sprintf("%s/file_%03d", $sub_dir, $file);
                    open my $fh, ">", $path or die "$path: $!\n";
                    close $fh or die "$path: $!\n";
                }
            }
        }
    ' "$target_dir" "$top_dirs" "$subdirs_per_top" "$files_per_subdir"
}

record_result() {
    local label="$1"
    local seconds="$2"

    printf "%-16s %s s\n" "$label:" "$seconds"

    if [ -n "$RESULTS_FILE" ]; then
        printf "%s,%s,%s,%s,%s,%s\n" \
            "$(date +%F)" \
            "$TOP_DIRS" \
            "$SUBDIRS_PER_TOP" \
            "$FILES_PER_SUBDIR" \
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
    local setup_log_prefix="mysqlfs-bench-tree-walk-setup"
    local read_log_prefix="mysqlfs-bench-tree-walk-read"
    local seconds=""
    local total_dirs=""
    local total_files=""

    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    init_mysqlfs_test_env "$repo_root"
    init_mysql_admin_args
    BENCH_SAVED_NOAPPLEDOUBLE="${MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE:-0}"
    MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE=1
    BENCH_SETUP_LOG="$(mktemp "$(default_mount_root)/mysqlfs-bench-tree-setup.XXXXXX.log")"
    BENCH_MOUNTPOINT="$(make_mountpoint "mysqlfs-bench-tree-walk")"
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
            create_tree_benchmark "$bench_dir" "$TOP_DIRS" "$SUBDIRS_PER_TOP" "$FILES_PER_SUBDIR"

            if [ "$BENCH_PHASE" = "setup" ]; then
                echo "Benchmark setup completed."
                echo "path:         $bench_dir"
                echo "top_dirs:     $TOP_DIRS"
                echo "subdirs/top:  $SUBDIRS_PER_TOP"
                echo "files/subdir: $FILES_PER_SUBDIR"
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
    total_dirs=$((1 + TOP_DIRS + (TOP_DIRS * SUBDIRS_PER_TOP)))
    total_files=$((TOP_DIRS * SUBDIRS_PER_TOP * FILES_PER_SUBDIR))

    echo "Benchmark: tree-walk (two-step)"
    echo "phase:        $BENCH_PHASE"
    echo "path:         $bench_dir"
    echo "top_dirs:     $TOP_DIRS"
    echo "subdirs/top:  $SUBDIRS_PER_TOP"
    echo "files/subdir: $FILES_PER_SUBDIR"
    echo "total_dirs:   $total_dirs"
    echo "total_files:  $total_files"
    echo "read command: $READ_COMMAND"
    echo

    seconds="$(run_timed_shell "cd '$bench_dir'")"
    record_result "cd" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && find . -type d >/dev/null")"
    record_result "find dirs" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && $READ_COMMAND")"
    record_result "read #1" "$seconds"

    seconds="$(run_timed_shell "cd '$bench_dir' && $READ_COMMAND")"
    record_result "read #2" "$seconds"
}

main "$@"
