# mysqlfs TODO

- Verify whether timestamp updates (`ctime`, `atime`, `mtime`) are always consistent.

- Handle deletion of files that are still in use more safely.
  Deleting an open file can currently purge data blocks immediately, which
  does not match normal Unix expectations for deleted-but-still-open files.

- Improve connection-pool robustness.
  Avoid returning `-EMFILE` when no pooled connection is immediately available.
  Also remove the dependency on the deprecated MySQL
  `MYSQL_OPT_RECONNECT` option. A better approach would be to treat a
  dead connection as an operation failure, drop it from the pool, and
  reopen a fresh connection explicitly on the next checkout instead of
  relying on transparent reconnect inside the client library.

- Improve security behavior.
  mysqlfs stores permission metadata, but it still relies mainly on
  `default_permissions` for enforcement.

- Add path-to-inode and inode-to-stat caches.
  - `getattr()` would benefit significantly.
  - `query_inode_full()` should eventually support walking a path in chunks
    from an intermediate inode instead of always building one large SQL
    query from the root.
  - `query_getattr()` could eventually expose the inode it already resolves
    so `mysqlfs_getattr()` can avoid a second path lookup.

- Add file buffering.
  Running a database query after every `write()` is still too expensive.

- Add support for xattrs and ACLs.
  FUSE exposes methods for xattrs, but mysqlfs does not implement them yet.

- Add explicit `fallocate()` support.
  Sparse file semantics already work through normal read, write, and
  truncate operations, but mysqlfs does not currently implement the
  dedicated FUSE `fallocate` path.

- Plan a migration to the `libfuse 3.x` interfaces.
  This should be treated as an API-compatibility pass rather than just
  adding new callbacks: existing operations such as `getattr()`,
  `rename()`, `readdir()`, `truncate()`, and timestamp handling need to
  be checked against the newer signatures and semantics.
