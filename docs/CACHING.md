# mysqlfs Caching

mysqlfs includes a small in-memory metadata cache to reduce repeated
database lookups on metadata-heavy workloads.

The cache is intentionally simple:

- it lives only inside the mounting mysqlfs process
- it is controlled by a single TTL value
- it is never shared across multiple mysqlfs clients
- it is invalidated conservatively on namespace and metadata changes

This document summarizes how the cache works, how to configure it, and
what kind of performance impact has been observed in practice.

## What Is Cached

mysqlfs currently keeps two short-lived caches in memory:

- a metadata cache mapping `path -> struct stat`
- an inode cache mapping `path -> inode`

The metadata cache is most useful for patterns such as:

- `readdir()` followed by many `getattr()` calls on the same directory
- repeated `stat()` on the same paths
- repeated listings of the same directory tree

The inode cache is more useful for path-heavy workloads such as:

- recursive tree walks
- repeated path resolution on nested directories
- workloads that revisit the same path prefixes many times

Both caches are TTL-based. Once an entry expires, mysqlfs falls back to
the normal SQL path and refreshes the cache from live data.

## What Is Not Cached

The cache does not currently store:

- file contents
- data blocks
- xattrs
- ACLs
- negative lookups
- shared state across clients or mounts

Each mysqlfs mount maintains its own local cache. If multiple mysqlfs
clients mount the same database, each one has its own independent view
until entries expire or are invalidated locally.

## Configuration

The cache is configured with a single mount option:

```sh
mysqlfs -ocache_ttl=<seconds> ...
```

Examples:

```sh
mysqlfs -ocache_ttl=0 ...
mysqlfs -ocache_ttl=2 ...
mysqlfs -ocache_ttl=60 ...
```

Semantics:

- `cache_ttl=0` disables the cache completely
- `cache_ttl>0` enables both metadata and inode caching
- the value is interpreted in seconds

There is no separate enable/disable flag. The TTL controls both whether
the cache is active and how long entries remain valid.

## Cache Invalidation

mysqlfs invalidates cached paths conservatively when filesystem state
changes.

In practice this means:

- file writes and truncates invalidate cached metadata for the target
  path
- metadata changes such as mode, ownership, or timestamps invalidate
  cached metadata for the target path
- namespace changes such as create, unlink, mkdir, rmdir, symlink, and
  rename invalidate cached directory and path mappings

The current strategy is intentionally simple. It favors correctness and
predictability over trying to keep partially stale entries alive.

## Consistency Model

The cache is local to one mysqlfs process. It does not coordinate with
other clients mounting the same database.

This has an important operational consequence:

- with a single mysqlfs client, a higher TTL is usually acceptable
- with multiple mysqlfs clients sharing the same database, a higher TTL
  increases the window in which one client may observe metadata that was
  changed by another client

mysqlfs does not attempt cluster-wide cache invalidation.

## Choosing A TTL

There is no single correct value. The right TTL depends on how the
filesystem is used.

### Good Starting Points

- `0` if you want fully uncached behavior
- `1-3` seconds for multi-client or highly concurrent shared usage
- `10-60` seconds for a single client doing repeated scans on a mostly
  stable dataset

### Single-Client Guidance

If one mysqlfs client is the only active writer and reader for the
database, it is usually reasonable to choose a more aggressive TTL.

Typical examples:

- a personal mount on one machine
- a backup or archival mount
- a batch workload that repeatedly scans the same tree
- a local analysis or indexing process

In those scenarios, values such as `10`, `30`, or `60` seconds can be a
very practical tradeoff.

### Multi-Client Guidance

If multiple mysqlfs mounts point at the same database at the same time,
the cache should be treated more conservatively.

A second client can change metadata or namespace state while the first
client still holds a cached view.

For that reason, a good rule of thumb is:

- keep TTL values very small
- in many cases stay under `3` seconds
- lower the TTL further when the workload is rename-heavy or update-heavy

Examples where low TTL is advisable:

- multiple application servers sharing the same mysqlfs database
- administrative and user mounts active at the same time
- test runners or automation jobs that modify the tree concurrently

### Pattern-Based Guidance

Short TTLs are safer when the workload is dominated by:

- frequent creates and deletes
- frequent renames
- many concurrent writers
- many clients sharing the same database

Longer TTLs are more rewarding when the workload is dominated by:

- repeated `ls -l`
- repeated tree walks
- repeated metadata reads
- mostly static directory trees

## Benchmarks

The numbers below were collected from the current benchmark scripts in
`tests/`. They should be read as practical guidance, not as universal
guarantees.

All benchmark results below were measured on the same machine and the
same database setup used during development.

### Large Directory Listing

Script:

- `tests/bench-010-large-directory-listing.sh`

Dataset:

- `15000` files in one directory

Mode:

- setup phase once
- read phase measured separately
- macOS benchmark run mounted with `-onoappledouble` to avoid
  AppleDouble sidecar noise during measurement

Results:

| Metric | TTL 0 | TTL 60 | Improvement |
|---|---:|---:|---:|
| `cd+ls` | `2.245 s` | `0.277 s` | `8.1x` |
| `ls -l #1` | `4.811 s` | `0.577 s` | `8.3x` |
| `ls -l #2` | `4.743 s` | `0.520 s` | `9.1x` |

This benchmark mostly highlights the metadata cache.

### Tree Walk

Script:

- `tests/bench-020-tree-walk.sh`

Dataset:

- `100` top-level directories
- `100` subdirectories per top-level directory
- `1` file per subdirectory
- total: `10101` directories and `10000` files

Mode:

- setup phase once
- read phase measured separately

Results:

| Metric | TTL 0 | TTL 60 | Improvement |
|---|---:|---:|---:|
| `find . -type d` | `10.730 s` | `8.693 s` | `1.23x` |
| `find . #1` | `10.530 s` | `3.523 s` | `2.99x` |
| `find . #2` | `10.387 s` | `2.460 s` | `4.22x` |

This benchmark is more sensitive to path-to-inode reuse and repeated
tree traversal.

### Mixed Workload

Script:

- `tests/bench-030-mixed-workload.sh`

Mode:

- single-step benchmark
- fixed-duration random workload
- `60` seconds per run
- same random seed reused across TTL sweeps for comparability

The benchmark includes a mixed set of operations such as:

- mkdir
- file create, read, write, rename, unlink
- symlink create, read, rename, unlink
- directory listing
- path stat
- empty directory removal

Results from a `60` second sweep:

| Metric | TTL 0 | TTL 10 | TTL 20 | TTL 30 | TTL 40 | TTL 50 | TTL 60 |
|---|---:|---:|---:|---:|---:|---:|---:|
| total operations | `1723` | `2469` | `2504` | `2652` | `2742` | `2681` | `2828` |
| operations/sec | `28.717` | `41.150` | `41.733` | `44.200` | `45.700` | `44.683` | `47.133` |
| vs baseline | `0.0%` | `+43.3%` | `+45.3%` | `+53.9%` | `+59.1%` | `+55.6%` | `+64.1%` |

This benchmark is useful as a more realistic mixed-pattern proxy. It is
less “pure” than the directory and tree benchmarks, but it gives a good
high-level view of end-to-end improvement under varied operations.

## Interpreting The Results

A few practical conclusions emerged from the benchmark work:

- the cache gives the biggest win on metadata-heavy and traversal-heavy
  workloads
- repeated listings and repeated tree walks benefit strongly
- a mixed real-world workload also improves noticeably
- the benefit is visible well before a `60` second TTL
- the best TTL is workload-dependent, not universal

During testing on macOS, AppleDouble sidecar traffic (`._*`) turned out
to dominate the uncached read path unless the benchmark mount used
`-onoappledouble`. That was a benchmarking concern rather than a defect
in the cache logic itself.

## Operational Recommendations

If you are unsure where to start:

- use `cache_ttl=0` when validating behavior or debugging consistency
- use `cache_ttl=1` or `cache_ttl=2` on shared multi-client mounts
- use `cache_ttl=10` as a cautious starting point for single-client
  interactive usage
- move toward `30-60` only when the dataset is mostly stable and the
  mount is not being modified concurrently by other clients

If correctness under concurrent external modification matters more than
throughput, prefer smaller TTL values.

If throughput on repeated scans matters more than immediate visibility
of changes made by another client, a larger TTL is usually worth trying.
