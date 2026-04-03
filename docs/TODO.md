# mysqlfs TODO

- Verify whether timestamp updates (`ctime`, `atime`, `mtime`) are always consistent.

- Handle deletion of files that are still in use more safely.
  Deleting an open file can currently purge data blocks immediately, which
  does not match normal Unix expectations for deleted-but-still-open files.

- Improve connection-pool robustness.
  Avoid returning `-EMFILE` when no pooled connection is immediately available.

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
