/*
  mysqlfs - MySQL Filesystem
  Copyright (C) 2006 Tsukasa Hamano <code@cuspy.org>
   
  This program can be distributed under the terms of the GNU GPL.
  See the file COPYING.
*/

/** @file */

/** maximum length of a full pathname */
#define PATH_MAX 1024

/** size of a single datablock written to the database; should be less than the size of a "blob" or mysqlfs.sql needs to be altered */
#ifdef FUSE_CAP_BIG_WRITES
 #define DATA_BLOCK_SIZE	131072
#else
 #define DATA_BLOCK_SIZE	4096
#endif


/** basic preprocessor-phase maximum macro */
#ifndef MIN
#define MIN(a,b)	((a) < (b) ? (a) : (b))
#endif
/** basic preprocessor-phase minimum macro */
#ifndef MAX
#define MAX(a,b)	((a) > (b) ? (a) : (b))
#endif
