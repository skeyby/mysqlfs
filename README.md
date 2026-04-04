# mysqlfs

MySQLfs is a FUSE filesystem driver which stores files in a MySQL database.

See [docs/ChangeLog.md](docs/ChangeLog.md) for a consolidated release history.

## Requirements

To use this package you need:

- mysql-client libraries 5.0 or later on the local machine
- a MySQL server 5.0 or later somewhere on the network, or on the local machine
- FUSE 2.6 or later

## Building

To build the package you need:

- CMake
- FUSE development libraries
- MySQL development libraries

On FreeBSD 12.x or later:

```sh
pkg install mysql80-client cmake gmake fusefs-libs
```

Remember to load `fusefs` before starting MySQLfs:

```sh
kldload fusefs
```

On Debian 9:

```sh
sudo apt install -y cmake g++ libfuse-dev libmariadbclient-dev-compat
```

On macOS with Homebrew and macFUSE:

```sh
brew install cmake pkgconf mysql@8.4
brew install --cask macfuse
./build-macos.sh
```

The macOS helper script auto-detects Homebrew MySQL and macFUSE paths
and performs an out-of-tree build in `./build-macos`.

Generic build flow:

```sh
cmake .
make
make install
```

Instead of `make install` you can use `checkinstall` to build a package.

## First Installation And Upgrade

If you are upgrading, skip directly to step 2.

1. Create a database and a MySQL account:

```sql
CREATE DATABASE mysqlfs;
GRANT ALL PRIVILEGES ON mysqlfs.* TO mysqlfs@"%" IDENTIFIED BY 'pass';
FLUSH PRIVILEGES;
```

2. Execute `mysqlfs_setup` and answer the questions about your database.
   On servers with binary logging enabled, the setup or upgrade process
   may also require elevated privileges to create the triggers used by
   the `statistics` table. In that case, either grant the MySQL account
   enough privilege to create triggers on the target server, or enable
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

## Upgrading From 0.4.0 Or Lower

To upgrade an existing installation, you unfortunately need to make
database changes.

The recommended solution is to compile a new MySQLfs, create a new
filesystem in a new database, mount it alongside the old one, and then
copy the data from the old filesystem to the new one. This is the
recommended, and probably the only certain, solution.

In the SQL directory you can find a `0.4.0_to_0.4.1.sql` file, but it is
informative only and is not meant to be run on a live filesystem.

The problem lies in the handling of sparse files: increasing the block
size without proper remapping of the underlying database can cause
improper results. More specifically, files may be filled with zeroes.

## Running Options

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

Ask FUSE or the kernel to enforce standard Unix permission checks based on
the `uid`, `gid`, and `mode` metadata stored by mysqlfs.

This option is strongly recommended.

If you use `-oallow_other`, you should also use `-odefault_permissions`.
Using `-oallow_other` without `-odefault_permissions` may allow
operations that mysqlfs does not block on its own.

## Compatibility Matrix

During development mysqlfs has been checked against:

- FreeBSD 10
- Fedora Linux 15
- Debian Linux 6
- Debian Linux 7
- Debian Linux 9
- macOS 26
- MySQL 5.1
- MySQL 5.5
- MySQL 5.6
- MariaDB 10.1

Note:

- FreeBSD 9 with FUSE-KMOD is not supported

## Development Notes

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

- Tsukasa Hamano <code@cuspy.org>
- Michal Ludvig <michal@logix.cz> - http://www.logix.cz/michal
- Andrea Brancatelli <andrea@brancatelli.it> - http://andrea.brancatelli.it/
