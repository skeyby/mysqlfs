# mysqlfs

mysqlfs is a FUSE filesystem driver that stores files in a MySQL or
MariaDB database.

It is designed first of all as a usable filesystem, so this README is
organized around setup and usage. Build and developer notes are grouped
later in the document.

See [docs/ChangeLog.md](docs/ChangeLog.md) for a consolidated release
history.

Project repository: <https://github.com/skeyby/mysqlfs>

## Overview

To use mysqlfs you need:

- a MySQL-compatible server reachable from the machine that will mount
  the filesystem
- a mysqlfs database
- a MySQL account with full privileges on that database
- a FUSE 2.x compatible environment

mysqlfs currently uses the `libfuse 2.x` interfaces. Recent validation
has been performed on `2.9.x`-compatible environments on macOS,
FreeBSD, and Debian. Migration to `libfuse 3.x` is planned, but is not
complete yet.

## Compatibility Matrix

Recent validation has been performed against:

- macOS 26 (64-bit)
- FreeBSD 15 (64-bit)
- Debian 13 (64-bit)
- MySQL 8.0.x
- MySQL 8.4.x
- MariaDB 11.8.x

Note:

- FreeBSD 9 with FUSE-KMOD is not supported

## POSIX Differences

mysqlfs aims to behave like a normal Unix filesystem where practical,
but it does not currently match POSIX semantics in every edge case.

Known differences include:

- deleting an open file is not supported with normal Unix
  "deleted-but-still-open" semantics
- once the directory entry is removed, the underlying inode and data may
  be purged immediately by the current schema design
- applications that rely on keeping an already-unlinked file descriptor
  alive until the last `close()` should not assume that behavior on
  mysqlfs

This is a long-standing behavior of the project, and it should be kept
in mind when using mysqlfs for workloads that depend on temporary files
or other unlink-while-open patterns.

## Usage

### First Installation

1. Create a database and a MySQL account:

```sql
CREATE DATABASE mysqlfs;
GRANT ALL PRIVILEGES ON mysqlfs.* TO mysqlfs@"%" IDENTIFIED BY 'pass';
FLUSH PRIVILEGES;
```

For normal mysqlfs runtime, the MySQL account needs full privileges on
the target mysqlfs database.

2. Execute `mysqlfs_setup` and answer the questions about your database.

On servers with binary logging enabled, the setup or upgrade process may
also require elevated privileges to create the triggers used by the
`statistics` table. In that case, either grant the MySQL account enough
privilege to create triggers on the target server, or enable
`log_bin_trust_function_creators` for the setup phase.

3. Mount the filesystem, changing the parameters as needed:

```sh
mkdir /mnt/fs
mysqlfs -ohost=<host> -ouser=<user> -opassword=<pass> -odatabase=<mysqlfs> -odefault_permissions /mnt/fs
```

4. Instead of setting connection options on the command line, you may
create a `[mysqlfs]` section in your `~/.my.cnf` file and set the
parameters there.

5. To mount on boot, add a line like this to `/etc/fstab`:

```fstab
mysqlfs /mnt/fs fuse host=<host>,user=<user>,password=<pass>,database=<mysqlfs>,allow_other,default_permissions,big_writes,x-systemd.automount 0 2
```

### Upgrading An Existing Database

If you are upgrading, skip directly to the `mysqlfs_setup` step above.

To upgrade an existing installation from `0.4.0` or lower, you
unfortunately need to make database changes.

The recommended solution is to compile a new mysqlfs, create a new
filesystem in a new database, mount it alongside the old one, and then
copy the data from the old filesystem to the new one. This is the
recommended, and probably the only certain, solution.

In the SQL directory you can find a `0.4.0_to_0.4.1.sql` file, but it
is informative only and is not meant to be run on a live filesystem.

The problem lies in the handling of sparse files: increasing the block
size without proper remapping of the underlying database can cause
improper results. More specifically, files may be filled with zeroes.

### Important Mount Options

`-ohost=<hostname>`

MySQL server host.

`-ouser=<username>`

MySQL username.

`-opassword=<password>`

MySQL password.

`-odatabase=<db>`

MySQL database name.

`-obig_writes`

Enable `big_writes` (strongly suggested).

`-oallow_other`

Enable filesystem access for users other than the one who mounted it.
The corresponding option must be enabled in `/etc/fuse.conf`.

`-odefault_permissions`

Ask FUSE or the kernel to enforce standard Unix permission checks based
on the `uid`, `gid`, and `mode` metadata stored by mysqlfs.

This option is strongly recommended.

If you use `-oallow_other`, you should also use
`-odefault_permissions`. Using `-oallow_other` without
`-odefault_permissions` may allow operations that mysqlfs does not block
on its own.

## Building From Source

To build the package you need:

- CMake
- FUSE development libraries
- MySQL development libraries

### FreeBSD

On FreeBSD 15 or later:

```sh
pkg install mysql80-client cmake gmake fusefs-libs
./build.sh
```

Remember to load `fusefs` before starting mysqlfs:

```sh
kldload fusefs
```

If you want to mount mysqlfs as a regular user on FreeBSD, also enable
user mounts:

```sh
sysctl vfs.usermount=1
```

### Debian

On Debian 13:

```sh
sudo apt install -y cmake g++ pkg-config libfuse-dev libmariadb-dev-compat
./build.sh
```

### macOS

On macOS with Homebrew and macFUSE:

```sh
brew install cmake pkgconf mysql@8.4
brew install --cask macfuse
./build-macos.sh
```

The macOS helper script auto-detects Homebrew MySQL and macFUSE paths
and performs an out-of-tree build in `./build-macos`.

### Generic Build Flow

On Linux and BSD systems, `./build.sh` performs the same role with a
default out-of-tree build in `./build`.

```sh
mkdir build
cd build
cmake ..
cmake --build .
cmake --install .
```

Instead of `make install` you can use `checkinstall` to build a package.

## Testing And Development

The local regression suite is driven by:

```sh
bash run-tests.sh
```

For the local regression suite, the `mysqlfs_test` account should be
able to:

- use all privileges on `mysqlfs_test.*`
- drop and recreate the `mysqlfs_test` database
- create triggers during `mysqlfs_setup`

In practice, the test account should have privileges equivalent to:

```sql
GRANT ALL PRIVILEGES ON mysqlfs_test.* TO 'mysqlfs_test'@'localhost';
GRANT CREATE, DROP ON *.* TO 'mysqlfs_test'@'localhost';
GRANT SUPER ON *.* TO 'mysqlfs_test'@'localhost';
FLUSH PRIVILEGES;
```

`run-tests.sh` uses the mysqlfs test account itself for database reset
by default. If you prefer to keep those privileges on a separate MySQL
account, you can override the bootstrap credentials with
`MYSQLFS_TEST_ADMIN_USER` and `MYSQLFS_TEST_ADMIN_PASS`.

An initial Debian packaging layout is available in `./debian`. To build
the package on Debian, install the standard packaging tools and run:

```sh
dpkg-buildpackage -us -uc
```

A local FreeBSD packaging layout is available under `./pkg/freebsd`. To
build a `.pkg` on FreeBSD, run:

```sh
./pkg/freebsd/build-pkg.sh
```

The generated package is written under the current build directory.

Historical repository branch roles were:

- `origin/DEV`: experimental development work
- `origin/TEST`: staging or beta-testing work
- `origin/PROD`: production-ready history

For current open work and future ideas, see [docs/TODO.md](docs/TODO.md).

## Known Limitations

- Hard links are not supported. mysqlfs supports symbolic links, but it
  does not expose POSIX hard-link semantics. Attempting to create a hard
  link will fail with an operation not supported error.

## Authors

### Active Development

- Andrea Brancatelli <andrea@brancatelli.it> -
  https://andrea.brancatelli.it/

### Historical Authors

- Tsukasa Hamano <code@cuspy.org>
- Michal Ludvig <michal@logix.cz> - http://www.logix.cz/michal
