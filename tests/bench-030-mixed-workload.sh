#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/test-lib.sh"

DURATION_SECONDS="${MYSQLFS_MIXED_BENCH_DURATION:-60}"
BENCH_DIR_NAME="${MYSQLFS_MIXED_BENCH_DIR_NAME:-mixbench}"
SEED="${MYSQLFS_MIXED_BENCH_SEED:-12345}"
RESULTS_FILE="${MYSQLFS_MIXED_BENCH_RESULTS_FILE:-}"
BENCH_MOUNTPOINT=""
BENCH_MYSQLFS_PID=""
BENCH_SETUP_LOG=""
BENCH_SAVED_NOAPPLEDOUBLE="0"

record_csv_results() {
    local label="$1"
    local value="$2"

    if [ -n "$RESULTS_FILE" ]; then
        printf "%s,%s,%s,%s\n" \
            "$(date +%F)" \
            "$DURATION_SECONDS" \
            "$label" \
            "$value" >>"$RESULTS_FILE"
    fi
}

run_mixed_workload() {
    local target_dir="$1"
    local duration="$2"
    local seed="$3"

    python3 - "$target_dir" "$duration" "$seed" <<'PY'
import collections
import os
import random
import sys
import time


root = os.path.abspath(sys.argv[1])
duration = float(sys.argv[2])
seed = int(sys.argv[3])
rng = random.Random(seed)

dirs = set(["."])
files = {}
symlinks = {}
name_counters = collections.Counter()
success = collections.Counter()
failures = collections.Counter()


def rel_join(parent, name):
    if parent == ".":
        return name
    return parent + "/" + name


def abs_path(relpath):
    if relpath == ".":
        return root
    return os.path.join(root, relpath)


def unique_name(prefix, suffix=""):
    name_counters[prefix] += 1
    return f"{prefix}_{name_counters[prefix]:06d}{suffix}"


def existing_entries():
    entries = [(".", "dir")]
    entries.extend((relpath, "dir") for relpath in dirs if relpath != ".")
    entries.extend((relpath, "file") for relpath in files)
    entries.extend((relpath, "symlink") for relpath in symlinks)
    return entries


def choose_dir():
    return rng.choice(tuple(dirs))


def choose_file():
    return rng.choice(tuple(files))


def choose_symlink():
    return rng.choice(tuple(symlinks))


def empty_dirs():
    empties = []
    for relpath in dirs:
        if relpath == ".":
            continue
        path = abs_path(relpath)
        if os.path.isdir(path) and not os.listdir(path):
            empties.append(relpath)
    return empties


def operation_weights():
    ops = [
        ("mkdir", 12),
        ("create_file", 14),
        ("list_dir", 10),
        ("stat_path", 10),
    ]

    if files:
        ops.extend([
            ("write_file", 16),
            ("read_file", 16),
            ("rename_file", 8),
            ("unlink_file", 8),
        ])

    if files or len(dirs) > 1:
        ops.append(("create_symlink", 8))

    if symlinks:
        ops.extend([
            ("read_symlink", 6),
            ("rename_symlink", 4),
            ("unlink_symlink", 4),
        ])

    if empty_dirs():
        ops.append(("rmdir", 6))

    return ops


def mkdir_op():
    parent = choose_dir()
    relpath = rel_join(parent, unique_name("dir"))
    os.mkdir(abs_path(relpath))
    dirs.add(relpath)


def create_file_op():
    parent = choose_dir()
    relpath = rel_join(parent, unique_name("file", ".dat"))
    payload = os.urandom(rng.randint(32, 256))
    with open(abs_path(relpath), "wb") as fh:
        fh.write(payload)
    files[relpath] = len(payload)


def write_file_op():
    relpath = choose_file()
    path = abs_path(relpath)
    size = files[relpath]
    payload = os.urandom(rng.randint(32, 512))

    if size == 0 or rng.random() < 0.5:
        with open(path, "ab") as fh:
            fh.write(payload)
        files[relpath] = size + len(payload)
        return

    offset = rng.randint(0, size)
    with open(path, "r+b") as fh:
        fh.seek(offset)
        fh.write(payload)
    files[relpath] = max(size, offset + len(payload))


def read_file_op():
    relpath = choose_file()
    path = abs_path(relpath)
    size = files[relpath]

    if size == 0:
        with open(path, "rb") as fh:
            fh.read()
        return

    offset = rng.randint(0, max(0, size - 1))
    length = rng.randint(1, min(4096, size - offset))
    with open(path, "rb") as fh:
        fh.seek(offset)
        fh.read(length)


def rename_file_op():
    old_relpath = choose_file()
    new_parent = choose_dir()
    new_relpath = rel_join(new_parent, unique_name("file", ".dat"))
    os.rename(abs_path(old_relpath), abs_path(new_relpath))
    files[new_relpath] = files.pop(old_relpath)


def unlink_file_op():
    relpath = choose_file()
    os.unlink(abs_path(relpath))
    files.pop(relpath, None)


def create_symlink_op():
    parent = choose_dir()
    link_relpath = rel_join(parent, unique_name("link", ".lnk"))

    if files and (not dirs or rng.random() < 0.8):
        target_relpath = choose_file()
    else:
        target_relpath = rng.choice(tuple(rel for rel in dirs if rel != ".")) if len(dirs) > 1 else "."

    target_abspath = abs_path(target_relpath)
    os.symlink(target_abspath, abs_path(link_relpath))
    symlinks[link_relpath] = target_abspath


def read_symlink_op():
    relpath = choose_symlink()
    os.readlink(abs_path(relpath))


def rename_symlink_op():
    old_relpath = choose_symlink()
    new_parent = choose_dir()
    new_relpath = rel_join(new_parent, unique_name("link", ".lnk"))
    os.rename(abs_path(old_relpath), abs_path(new_relpath))
    symlinks[new_relpath] = symlinks.pop(old_relpath)


def unlink_symlink_op():
    relpath = choose_symlink()
    os.unlink(abs_path(relpath))
    symlinks.pop(relpath, None)


def rmdir_op():
    relpath = rng.choice(empty_dirs())
    os.rmdir(abs_path(relpath))
    dirs.remove(relpath)


def list_dir_op():
    os.listdir(abs_path(choose_dir()))


def stat_path_op():
    relpath, kind = rng.choice(existing_entries())
    if kind == "symlink":
        os.lstat(abs_path(relpath))
    else:
        os.stat(abs_path(relpath))


ops = {
    "mkdir": mkdir_op,
    "create_file": create_file_op,
    "write_file": write_file_op,
    "read_file": read_file_op,
    "rename_file": rename_file_op,
    "unlink_file": unlink_file_op,
    "create_symlink": create_symlink_op,
    "read_symlink": read_symlink_op,
    "rename_symlink": rename_symlink_op,
    "unlink_symlink": unlink_symlink_op,
    "rmdir": rmdir_op,
    "list_dir": list_dir_op,
    "stat_path": stat_path_op,
}


def weighted_choice(options):
    total = sum(weight for _, weight in options)
    pick = rng.uniform(0, total)
    upto = 0.0
    for name, weight in options:
        upto += weight
        if pick <= upto:
            return name
    return options[-1][0]


deadline = time.monotonic() + duration

while time.monotonic() < deadline:
    opname = weighted_choice(operation_weights())
    try:
        ops[opname]()
        success[opname] += 1
    except OSError:
        failures[opname] += 1

total_success = sum(success.values())
total_failures = sum(failures.values())
ops_per_sec = total_success / duration if duration > 0 else 0.0

print(f"duration:       {duration:.3f} s")
print(f"seed:           {seed}")
print(f"total success:  {total_success}")
print(f"total failures: {total_failures}")
print(f"ops/sec:        {ops_per_sec:.3f}")
print(f"final dirs:     {len(dirs)}")
print(f"final files:    {len(files)}")
print(f"final symlinks: {len(symlinks)}")
print("success by op:")
for name in sorted(success):
    print(f"  {name}: {success[name]}")
print("failures by op:")
if failures:
    for name in sorted(failures):
        print(f"  {name}: {failures[name]}")
else:
    print("  none: 0")
PY
}

main() {
    local repo_root=""
    local bench_dir=""
    local log_prefix="mysqlfs-bench-mixed-workload"

    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    init_mysqlfs_test_env "$repo_root"
    init_mysql_admin_args
    BENCH_SAVED_NOAPPLEDOUBLE="${MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE:-0}"
    MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE=1
    BENCH_SETUP_LOG="$(mktemp "$(default_mount_root)/mysqlfs-bench-mixed-setup.XXXXXX.log")"
    BENCH_MOUNTPOINT="$(make_mountpoint "mysqlfs-bench-mixed-workload")"
    trap 'MYSQLFS_TEST_MACOS_NOAPPLEDOUBLE="$BENCH_SAVED_NOAPPLEDOUBLE"; cleanup_mount "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID"; rm -f "$BENCH_SETUP_LOG"' EXIT

    if ! bootstrap_mysqlfs_test_database "$repo_root" >"$BENCH_SETUP_LOG" 2>&1; then
        cat "$BENCH_SETUP_LOG" >&2
        fail "unable to prepare the benchmark database"
    fi

    BENCH_MYSQLFS_PID="$(start_mysqlfs_test "$BENCH_MOUNTPOINT" "$log_prefix")"
    wait_for_mysqlfs_ready "$BENCH_MOUNTPOINT" "$BENCH_MYSQLFS_PID" "$log_prefix"

    bench_dir="$BENCH_MOUNTPOINT/$BENCH_DIR_NAME"
    mkdir "$bench_dir"

    echo "Benchmark: mixed-workload (single-step)"
    echo "path:           $bench_dir"
    echo "duration:       $DURATION_SECONDS s"
    echo "seed:           $SEED"
    echo

    run_mixed_workload "$bench_dir" "$DURATION_SECONDS" "$SEED" | tee /tmp/mysqlfs-bench-mixed-workload.results

    record_csv_results "duration" "$DURATION_SECONDS"
}

main "$@"
