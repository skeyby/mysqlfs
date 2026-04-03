/*
 * mysqlfs - MySQL Filesystem
 * Copyright (C) 2006 Tsukasa Hamano <code@cuspy.org>
 * Copyright (C) 2006 Michal Ludvig <michal@logix.cz>
 * Copyright (C) 2012-2020 Andrea Brancatelli <andrea@brancatelli.it>
 *
 * This program can be distributed under the terms of the GNU GPL.
 * See the file COPYING.
 */

#include "Config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>

#include <fuse/fuse.h>

#include <mysql/mysql.h>

#include <pthread.h>
#include <sys/stat.h>

#ifdef DEBUG
#include <mcheck.h>
#endif
#include <stddef.h>

#include "mysqlfs.h"
#include "query.h"
#include "pool.h"
#include "log.h"

static int mysqlfs_getattr(const char *path, struct stat *stbuf)
{
    int ret;
    MYSQL *dbconn;

    // This is called far too often
    log_printf(LOG_D_CALL, "mysqlfs_getattr(\"%s\")\n", path);

    memset(stbuf, 0, sizeof(struct stat));

    if ((dbconn = pool_get()) == NULL)
        return -EMFILE;

    ret = query_getattr(dbconn, path, stbuf);

    if (ret) {
        if (ret != -ENOENT)
            log_printf(LOG_ERROR, "Error: query_getattr()\n");
        pool_put(dbconn);
        return ret;
    }

    stbuf->st_blocks = (blkcnt_t)((stbuf->st_size + 511) / 512);

    pool_put(dbconn);

    return ret;
}

static int mysqlfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                           off_t offset, struct fuse_file_info *fi)
{
    (void) offset;
    (void) fi;
    int ret;
    MYSQL *dbconn;
    long inode;

    log_printf(LOG_D_CALL, "mysqlfs_readdir(\"%s\")\n", path);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, path);
    if(inode < 0){
        log_printf(LOG_ERROR, "Error: query_inode()\n");
        pool_put(dbconn);
        return inode;
    }

    
    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);

    ret = query_readdir(dbconn, inode, buf, filler);
    pool_put(dbconn);

    if (ret < 0)
        log_printf(LOG_ERROR, "Error: query_readdir(%s)\n", path);

    return ret;
}

/** FUSE function for mknod(const char *pathname, mode_t mode, dev_t dev); API call.  @see http://linux.die.net/man/2/mknod */
static int mysqlfs_mknod(const char *path, mode_t mode, dev_t rdev)
{
    int ret;
    MYSQL *dbconn;
    long parent_inode;
    char tmppath[PATH_MAX];
    char *dir_path;

    log_printf(LOG_D_CALL, "mysqlfs_mknod(\"%s\", %o): %s\n", path, mode,
	       S_ISREG(mode) ? "file" :
	       S_ISDIR(mode) ? "directory" :
	       S_ISLNK(mode) ? "symlink" :
	       "other");

    if(!(strlen(path) < PATH_MAX)){
        log_printf(LOG_ERROR, "Error: Filename too long\n");
        return -ENAMETOOLONG;
    }

    /* this is crazy bullshit for linux/freebsd/posix/whateverelse compatibility */
    strcpy(tmppath, path);
    dir_path = dirname(tmppath);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    parent_inode = query_inode(dbconn, dir_path);
    if(parent_inode < 0){
        log_printf(LOG_ERROR, "Error getting parent inode dirpath %s\n", dir_path);
        pool_put(dbconn);
        return -ENOENT;
    }

    ret = query_mknod(dbconn, path, mode, rdev, parent_inode, S_ISREG(mode) || S_ISLNK(mode));
    if(ret < 0){
        log_printf(LOG_ERROR, "Error invoking query mknod\n");
        pool_put(dbconn);
        return ret;
    }

    pool_put(dbconn);
    return 0;
}

static int mysqlfs_mkdir(const char *path, mode_t mode){
    int ret;
    MYSQL *dbconn;
    long inode;
    char tmppath[PATH_MAX];
    char *dir_path;

    log_printf(LOG_D_CALL, "mysqlfs_mkdir(\"%s\", 0%o)\n", path, mode);
    
    if(!(strlen(path) < PATH_MAX)){
        log_printf(LOG_ERROR, "Error: Filename too long\n");
        return -ENAMETOOLONG;
    }
 
    /* this is crazy bullshit for linux compatibility */
    strcpy(tmppath, path);
    dir_path = dirname(tmppath);
    
    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, dir_path);
    if(inode < 0){
        pool_put(dbconn);
        return -ENOENT;
    }

    ret = query_mkdir(dbconn, path, mode, inode);
    if(ret < 0){
        log_printf(LOG_ERROR, "Error: query_mkdir()\n");
        pool_put(dbconn);
        return ret;
    }

    pool_put(dbconn);
    return 0;
}


/**
 * Delete a path - doesn't matter if it's a file
 * or a directory.
 *
 * @param char path
 */

static int mysqlfs_unlink(const char *path)
{
    int ret;
    long inode, parent, nlinks;
    char name[PATH_MAX];
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysqlfs_unlink(\"%s\")\n", path);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    ret = query_inode_full(dbconn, path, name, sizeof(name),
			   &inode, &parent, &nlinks);
    if (ret < 0) {
        if (ret != -ENOENT)
            log_printf(LOG_ERROR, "Error: query_inode_full(%s): %s\n",
		       path, strerror(ret));
	goto err_out;
    }

    ret = query_rmdirentry(dbconn, name, parent);
    if (ret < 0) {
        log_printf(LOG_ERROR, "Error: query_rmdirentry()\n");
	goto err_out;
    }

    /* Only the last unlink() must set deleted flag. 
     * This is a shortcut - query_set_deleted() wouldn't
     * set the flag if there is still an existing direntry
     * anyway. But we'll save some DB processing here. */
    if (nlinks > 1)
        return 0;
    
    /* Due to the introduction of InnoDB referencial integrity
     * (and cascading), this should be totaly useless,
     * But let's keep it here for a while. */
    /* Useless_Start... */

    ret = query_set_deleted(dbconn, inode);
    if (ret < 0) {
        log_printf(LOG_ERROR, "Error: query_set_deleted()\n");
	goto err_out;
    }

    ret = query_purge_deleted(dbconn, inode);
    if (ret < 0) {
        log_printf(LOG_ERROR, "Error: query_purge_deleted()\n");
	goto err_out;
    }

    /* ...Useless_End */

    pool_put(dbconn);

    return 0;

err_out:
    pool_put(dbconn);
    return ret;
}

static int mysqlfs_chmod(const char* path, mode_t mode)
{
    int ret;
    long inode;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysql_chmod(\"%s\", 0%3o)\n", path, mode);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, path);
    if (inode < 0) {
        pool_put(dbconn);
        return inode;
    }

    ret = query_chmod(dbconn, inode, mode);
    if(ret){
        log_printf(LOG_ERROR, "Error: query_chmod()\n");
        pool_put(dbconn);
        return -EIO;
    }

    pool_put(dbconn);

    return ret;
}

static int mysqlfs_chown(const char *path, uid_t uid, gid_t gid)
{
    int ret;
    long inode;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysql_chown(\"%s\", %ld, %ld)\n", path, uid, gid);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, path);
    if (inode < 0) {
        pool_put(dbconn);
        return inode;
    }

    ret = query_chown(dbconn, inode, uid, gid);
    if(ret){
        log_printf(LOG_ERROR, "Error: query_chown()\n");
        pool_put(dbconn);
        return -EIO;
    }

    pool_put(dbconn);

    return ret;
}

static int mysqlfs_truncate(const char* path, off_t length)
{
    int ret;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysql_truncate(\"%s\"): len=%lld\n", path, length);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    ret = query_truncate(dbconn, path, length);
    if (ret < 0) {
        log_printf(LOG_ERROR, "Error: query_length()\n");
        pool_put(dbconn);
        return -EIO;
    }

    pool_put(dbconn);

    return 0;
}

static int mysqlfs_utime(const char *path, struct utimbuf *time)
{
    int ret;
    long inode;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysql_utime(\"%s\")\n", path);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, path);
    if (inode < 0) {
        pool_put(dbconn);
        return inode;
    }

    ret = query_utime(dbconn, inode, time);
    if (ret < 0) {
        log_printf(LOG_ERROR, "Error: query_utime()\n");
        pool_put(dbconn);
        return -EIO;
    }

    pool_put(dbconn);

    return 0;
}

static int mysqlfs_open(const char *path, struct fuse_file_info *fi)
{
    MYSQL *dbconn;
    long inode;
    int ret;

    log_printf(LOG_D_CALL, "mysqlfs_open(\"%s\")\n", path);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, path);
    if(inode < 0){
        pool_put(dbconn);
        return -ENOENT;
    }

    /* Save inode for future use. Lets us skip path->inode translation.  */
    fi->fh = inode;

    log_printf(LOG_D_OTHER, "inode(\"%s\") = %d\n", path, fi->fh);

    ret = query_inuse_inc(dbconn, inode, 1);
    if (ret < 0) {
        pool_put(dbconn);
        return ret;
    }

    pool_put(dbconn);

    return 0;
}

static int mysqlfs_read(const char *path, char *buf, size_t size, off_t offset,
                        struct fuse_file_info *fi)
{
    int ret;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysqlfs_read(\"%s\" %zu@%llu)\n", path, size, offset);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    ret = query_read(dbconn, fi->fh, buf, size, offset);
    pool_put(dbconn);

    return ret;
}

static int mysqlfs_write(const char *path, const char *buf, size_t size,
                         off_t offset, struct fuse_file_info *fi)
{
    int ret;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysqlfs_write(\"%s\" %zu@%lld)\n", path, size, offset);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    ret = query_write(dbconn, fi->fh, buf, size, offset);
    pool_put(dbconn);

    return ret;
}

static int mysqlfs_release(const char *path, struct fuse_file_info *fi)
{
    int ret;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "mysqlfs_release(\"%s\")\n", path);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    ret = query_inuse_inc(dbconn, fi->fh, -1);
    if (ret < 0) {
        pool_put(dbconn);
        return ret;
    }

    ret = query_purge_deleted(dbconn, fi->fh);
    if (ret < 0) {
        pool_put(dbconn);
        return ret;
    }

    pool_put(dbconn);

    return 0;
}

static int mysqlfs_link(const char *from, const char *to)
{
    int ret;
    long inode, new_parent;
    MYSQL *dbconn;
    char *tmp, *name, esc_name[PATH_MAX * 2];

    log_printf(LOG_D_CALL, "link(%s, %s)\n", from, to);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, from);
    if(inode < 0){
        pool_put(dbconn);
        return inode;
    }

    tmp = strdup(to);
    name = dirname(tmp);
    new_parent = query_inode(dbconn, name);
    free(tmp);
    if (new_parent < 0) {
        pool_put(dbconn);
        return new_parent;
    }

    tmp = strdup(to);
    name = basename(tmp);
    mysql_real_escape_string(dbconn, esc_name, name, strlen(name));
    free(tmp);

    ret = query_mkdirentry(dbconn, inode, esc_name, new_parent);
    if(ret < 0){
        pool_put(dbconn);
        return ret;
    }

    pool_put(dbconn);

    return 0;
}

static int mysqlfs_symlink(const char *from, const char *to)
{
    int ret;
    int inode;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "%s(\"%s\" -> \"%s\")\n", __func__, from, to);

    ret = mysqlfs_mknod(to, S_IFLNK | 0755, 0);
    if (ret < 0)
      return ret;

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, to);
    if(inode < 0){
        pool_put(dbconn);
        return -ENOENT;
    }

    ret = query_write(dbconn, inode, from, strlen(from), 0);
    if (ret > 0) ret = 0;

    pool_put(dbconn);

    return ret;
}

static int mysqlfs_readlink(const char *path, char *buf, size_t size)
{
    int ret;
    long inode;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "%s(\"%s\")\n", __func__, path);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    inode = query_inode(dbconn, path);
    if(inode < 0){
        pool_put(dbconn);
        return -ENOENT;
    }

    memset (buf, 0, size);
    ret = query_read(dbconn, inode, buf, size, 0);
    log_printf(LOG_DEBUG, "readlink(%s): %s [%zd -> %d]\n", path, buf, size, ret);
    pool_put(dbconn);

    if (ret > 0) ret = 0;
    return ret;
}

static int mysqlfs_rename(const char *from, const char *to)
{
    int ret;
    MYSQL *dbconn;

    log_printf(LOG_D_CALL, "%s(%s -> %s)\n", __func__, from, to);

    if ((dbconn = pool_get()) == NULL)
      return -EMFILE;

    ret = query_rename(dbconn, from, to);
    if (ret < 0)
        log_printf(LOG_ERROR, "Error: query_rename(%s -> %s)\n", from, to);

    pool_put(dbconn);

    return ret;
}

/* All the new FUSE 2.6 functions start from here.... */
/* All the new FUSE 2.6 functions start from here.... */
/* All the new FUSE 2.6 functions start from here.... */

/**

int(* fuse_operations::create)(const char *, mode_t, struct fuse_file_info *)
Create and open a file

If the file does not exist, first create it with the specified mode, and then open it.

If this method is not implemented or under Linux kernel versions earlier than 2.6.15, the mknod() and open() methods will be called instead.

Introduced in version 2.5

**/
static int mysqlfs_create(const char *path, mode_t mode, struct fuse_file_info *fi)
{

   int ret;
   dev_t rdev;

   rdev = S_IFREG;

   log_printf(LOG_D_CALL, "Creating path %s mode %o \n", path, mode);

   ret = mysqlfs_mknod(path, mode, rdev);
   if(ret<0){
	log_printf(LOG_ERROR, "Error create_mknod : Error creating node\n");
	return ret;
   }

   ret = mysqlfs_open(path, fi);
   if(ret<0){
	log_printf(LOG_ERROR, "Error create_open: Error opening path\n");
	return ret;
   }

   return 0;

}

/**

int(* fuse_operations::statfs)(const char *, struct statvfs *)
Get file system statistics

The 'f_frsize', 'f_favail', 'f_fsid' and 'f_flag' fields are ignored

Replaced 'struct statfs' parameter with 'struct statvfs' in version 2.5

**/
static int mysqlfs_statfs(const char *path, struct statvfs *buf)
{

	MYSQL *dbconn;

	log_printf(LOG_D_CALL, "mysqlfs_unlink(\"%s\")\n", path);

	if ((dbconn = pool_get()) == NULL)
		return -EMFILE;


        buf->f_namemax = 255;

        buf->f_bsize = DATA_BLOCK_SIZE;

        /*
         * df seems to use f_bsize instead of f_frsize, so make them
         * the same
         */
        buf->f_frsize = buf->f_bsize;

	buf->f_files = query_total_inodes(dbconn)+1024;
	buf->f_ffree = 1024; /* arbitrary value */
	buf->f_favail = buf->f_ffree;

	buf->f_blocks = query_total_blocks(dbconn)+10240;
	buf->f_bfree = 10240; /* arbitrary value */
	buf->f_bavail = buf->f_bfree;

	pool_put(dbconn);

        return 0;
}


/** used below in fuse_main() to define the entry points for a FUSE filesystem; this is the same VMT-like jump table used throughout the UNIX kernel. */
static struct fuse_operations mysqlfs_oper = {
    .getattr	= mysqlfs_getattr,
    .readdir	= mysqlfs_readdir,
    .mknod	= mysqlfs_mknod,
    .mkdir	= mysqlfs_mkdir,
    .unlink	= mysqlfs_unlink,
    .rmdir	= mysqlfs_unlink,
    .chmod	= mysqlfs_chmod,
    .chown	= mysqlfs_chown,
    .truncate	= mysqlfs_truncate,
    .utime	= mysqlfs_utime,
    .open	= mysqlfs_open,
    .read	= mysqlfs_read,
    .write	= mysqlfs_write,
    .release	= mysqlfs_release,
    .link	= mysqlfs_link,
    .symlink	= mysqlfs_symlink,
    .readlink	= mysqlfs_readlink,
    .rename	= mysqlfs_rename,
    .create	= mysqlfs_create,
    .statfs     = mysqlfs_statfs,
};

/** print out a brief usage aide-memoire to stderr */
void usage(){
    fprintf(stderr,
            "usage: mysqlfs [opts] <mountpoint>\n\n");
    fprintf(stderr,
            "       mysqlfs [-osocket=/tmp/mysql.sock] [-obig_writes] [-oallow_other] [-odefault_permissions] [-oport=####] [-otable_prefix=prefix] -ohost=host -ouser=user -opassword=password "
            "-odatabase=database ./mountpoint\n");
    fprintf(stderr,
            "       mysqlfs [-d] [-ologfile=filename] [-obig_writes] [-oallow_other] [-odefault_permissions] [-otable_prefix=prefix] -ohost=host -ouser=user -opassword=password "
            "-odatabase=database ./mountpoint\n");
    fprintf(stderr,
            "       mysqlfs [-mycnf_group=group_name] [-obig_writes] [-oallow_other] [-odefault_permissions] [-otable_prefix=prefix] -ohost=host -ouser=user -opassword=password "
            "-odatabase=database ./mountpoint\n");
    fprintf(stderr, "\n(mimick mysql options)\n");
    fprintf(stderr,
            "       mysqlfs [-obig_writes] [-oallow_other] [-odefault_permissions] [--table_prefix=prefix] --host=host --user=user --password=password --database=database ./mountpoint\n");
    fprintf(stderr,
            "       mysqlfs [-obig_writes] [-oallow_other] [-odefault_permissions] [-tp=prefix] -h host -u user --password=password -D database ./mountpoint\n");
}

/** macro to set a call value with a default -- defined yet? */
#define MYSQLFS_OPT_KEY(t, p, v) { t, offsetof(struct mysqlfs_opt, p), v }

/** FUSE_OPT_xxx keys defines for use with fuse_opt_parse() */
enum
  {
    KEY_BACKGROUND,	/**< debug: key for option to activate mysqlfs::bg to force-background the server */
    KEY_DEBUG_DNQ,	/**< debug: Dump (Config) and Quit */
    KEY_HELP,
    KEY_VERSION,
    KEY_BIGWRITES,
    KEY_NOPRIVATE,
    KEY_NOPERMISSIONS,
  };

/** fuse_opt for use with fuse_opt_parse() */
static struct fuse_opt mysqlfs_opts[] =
  {
    MYSQLFS_OPT_KEY(  "background",	bg,	1),
    MYSQLFS_OPT_KEY(  "database=%s",	db,	1),
    MYSQLFS_OPT_KEY("--database=%s",	db,	1),
    MYSQLFS_OPT_KEY( "-D %s",		db,	1),
    MYSQLFS_OPT_KEY(  "fsck",		fsck,	1),
    MYSQLFS_OPT_KEY(  "fsck=%d",	fsck,	1),
    MYSQLFS_OPT_KEY("--fsck=%d",	fsck,	1),
    MYSQLFS_OPT_KEY("nofsck",		fsck,	0),
    MYSQLFS_OPT_KEY(  "host=%s",	host,	0),
    MYSQLFS_OPT_KEY("--host=%s",	host,	0),
    MYSQLFS_OPT_KEY( "-h %s",		host,	0),
    MYSQLFS_OPT_KEY(  "logfile=%s",	logfile,	0),
    MYSQLFS_OPT_KEY("--logfile=%s",	logfile,	0),
    MYSQLFS_OPT_KEY(  "mycnf_group=%s",	mycnf_group,	0), /* Read defaults from specified group in my.cnf  -- Command line options still have precedence.  */
    MYSQLFS_OPT_KEY("--mycnf_group=%s",	mycnf_group,	0),
    MYSQLFS_OPT_KEY(  "password=%s",	passwd,	0),
    MYSQLFS_OPT_KEY("--password=%s",	passwd,	0),
    MYSQLFS_OPT_KEY(  "port=%d",	port,	0),
    MYSQLFS_OPT_KEY("--port=%d",	port,	0),
    MYSQLFS_OPT_KEY( "-P %d",		port,	0),
    MYSQLFS_OPT_KEY(  "socket=%s",	socket,	0),
    MYSQLFS_OPT_KEY("--socket=%s",	socket,	0),
    MYSQLFS_OPT_KEY( "-S %s",		socket,	0),
    MYSQLFS_OPT_KEY(  "table_prefix=%s",tableprefix,    0),
    MYSQLFS_OPT_KEY("--table_prefix=%s",tableprefix,    0),
    MYSQLFS_OPT_KEY( "-tp %s",          tableprefix,    0),
    MYSQLFS_OPT_KEY(  "user=%s",	user,	0),
    MYSQLFS_OPT_KEY("--user=%s",	user,	0),
    MYSQLFS_OPT_KEY( "-u %s",		user,	0),

    FUSE_OPT_KEY("debug-dnq",	        KEY_DEBUG_DNQ),
    FUSE_OPT_KEY("allow_other",         KEY_NOPRIVATE),
    FUSE_OPT_KEY("default_permissions", KEY_NOPERMISSIONS),
    FUSE_OPT_KEY("big_writes",          KEY_BIGWRITES),
    FUSE_OPT_KEY("-v",		        KEY_VERSION),
    FUSE_OPT_KEY("--version",	        KEY_VERSION),
    FUSE_OPT_KEY("--help",	        KEY_HELP),
    FUSE_OPT_END
  };



static int mysqlfs_opt_proc(void *data, const char *arg, int key, struct fuse_args *outargs)
{
    struct mysqlfs_opt *opt = (struct mysqlfs_opt *)data;

    switch (key) {
        case FUSE_OPT_KEY_OPT: /* dig through the list for matches */
            /*
             * There are primitives for this in FUSE, but no need to change at this point
             */
            fprintf(stderr, "Ignoring option %s\n", arg);
            break;

        case KEY_DEBUG_DNQ:
            /*
             * Debug: Dump Config and Quit -- used to debug options-handling changes
             */
            fprintf(stderr, "DEBUG: Dump and Quit\n\n");
            fprintf(stderr, "connect: mysql://%s:%s@%s:%d/%s\n", opt->user, opt->passwd, opt->host, opt->port, opt->db);
            fprintf(stderr, "connect: sock://%s\n", opt->socket);
            fprintf(stderr, "fsck? %s\n", (opt->fsck ? "yes" : "no"));
            fprintf(stderr, "group: %s\n", opt->mycnf_group);
            fprintf(stderr, "pool: %d initial connections\n", opt->init_conns);
            fprintf(stderr, "pool: %d idling connections\n", opt->max_idling_conns);
            fprintf(stderr, "logfile: file://%s\n", opt->logfile);
            fprintf(stderr, "bg? %s (debug)\n", (opt->bg ? "yes" : "no"));
            fprintf(stderr, "table prefix: %s\n\n", opt->tableprefix);

            exit(2);

        case KEY_HELP: /* trigger usage call */
            usage();
            exit(0);

        case KEY_VERSION: /* show version and quit */
            fprintf(stderr, "MySQLfs %d.%d fuse-%d\n\n", MySQLfs_VERSION_MAJOR, MySQLfs_VERSION_MINOR, FUSE_VERSION);
            exit(0);

        case KEY_NOPRIVATE:
            opt->allow_other = 1;
            fprintf(stderr, " * File system will be shared (check fuse.conf to confirm this!)\n");
            fuse_opt_add_arg(outargs, "-oallow_other");
            break;

        case KEY_NOPERMISSIONS:
            opt->default_permissions = 1;
            fprintf(stderr, " * Using default permissions\n");
            fuse_opt_add_arg(outargs, "-odefault_permissions");
            break;

        case KEY_BIGWRITES:
            fprintf(stderr, " * Enabling big writes...\n");
            fuse_opt_add_arg(outargs, "-obig_writes");
            break;

        default: /* key != FUSE_OPT_KEY_OPT */
            fuse_opt_add_arg(outargs, arg);
            return 0;
    }

    return 0;
}

/**
 * main
 */
int main(int argc, char *argv[])
{
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    struct mysqlfs_opt opt = {
        .init_conns = 1,
        .max_idling_conns = 5,
        .mycnf_group = "mysqlfs",
        .logfile = "mysqlfs.log",
    };

    log_file = stderr;

    fprintf(stderr, "\nMySQLfs version %d.%d startup. Using fuse-%d\n\n", MySQLfs_VERSION_MAJOR, MySQLfs_VERSION_MINOR, FUSE_VERSION);

    fuse_opt_parse(&args, &opt, mysqlfs_opts, mysqlfs_opt_proc);

    if (!opt.default_permissions) {
        fprintf(stderr, "WARNING: default_permissions is not enabled.\n");
        fprintf(stderr, "WARNING: mysqlfs stores uid/gid/mode metadata, but it relies primarily on FUSE/kernel default permission checks for enforcement.\n");
    }

    if (opt.allow_other && !opt.default_permissions) {
        fprintf(stderr, "WARNING: allow_other is enabled without default_permissions.\n");
        fprintf(stderr, "WARNING: THIS CONFIGURATION MAY ALLOW OPERATIONS THAT MYSQLFS DOES NOT BLOCK ON ITS OWN.\n");
        fprintf(stderr, "WARNING: STRONGLY RECOMMENDED: enable -odefault_permissions when using -oallow_other.\n");
    }

    if (pool_init(&opt) < 0) {
        log_printf(LOG_ERROR, "Error: pool_init() failed\n");
        fuse_opt_free_args(&args);
        return EXIT_FAILURE;
    }

    /*
     * I found that -- running from a script (ie no term?) -- the MySQLfs would not background, so the terminal is held; this makes automated testing difficult.
     *
     * I (allanc) put this into here to allow for AUTOTEST, but then autotest has to seek-and-destroy the app.  This isn't quite perfect yet, I get some flakiness here, othertines the pid is 4 more than the parent, which is odd.
     */
    if (0 < opt.bg) {
        if (0 < fork())
            return EXIT_SUCCESS;
        //else
        //    fprintf (stderr, "forked %d\n", getpid());
    }

    log_file = log_init(opt.logfile, 1);

    fprintf(stderr, "\nCommand line parsing finished, starting FUSE...\n");

    fuse_main(args.argc, args.argv, &mysqlfs_oper, NULL);
    fuse_opt_free_args(&args);

    pool_cleanup();

    return EXIT_SUCCESS;
}
