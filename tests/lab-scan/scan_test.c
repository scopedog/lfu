// SPDX-License-Identifier: LGPL-2.1+
/*
 * Consumer for llapi_scan_namespace() (LU-20603).  Prints one line per
 * record so the FID set can be diffed against `lfs find` + `lfs path2fid`,
 * and exercises the parts of the contract that only a real filesystem can
 * check: the validity mask, thread counts, depth limiting, and a callback
 * that stops the scan.
 *
 * Usage: scan_test <path> [threads] [max_depth] [stop_after]
 */
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lustre/lustreapi.h>

struct ctx {
	pthread_mutex_t	 lock;
	unsigned long	 count;
	unsigned long	 stop_after;	/* 0: never stop */
	int		 quiet;
};

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	struct ctx *c = data;
	unsigned long n;

	pthread_mutex_lock(&c->lock);
	n = ++c->count;
	if (!c->quiet)
		printf(DFID" %s mode=%o nlink=%u uid=%u gid=%u size=%llu"
		       " blocks=%llu mtime=%lld mdt=%u valid=0x%llx"
		       " lmm=%s recsz=%u\n",
		       PFID(&rec->sr_fid), rec->sr_path,
		       rec->sr_mode & 07777, rec->sr_nlink, rec->sr_uid,
		       rec->sr_gid,
		       (unsigned long long)rec->sr_size_bytes,
		       (unsigned long long)rec->sr_blocks,
		       (long long)rec->sr_mtime, rec->sr_mdt_index,
		       (unsigned long long)rec->sr_valid,
		       (rec->sr_valid & LLAPI_SCAN_LAYOUT) ? "yes" : "no",
		       rec->sr_size);
	pthread_mutex_unlock(&c->lock);

	if (c->stop_after && n >= c->stop_after)
		return 42;	/* must come back out of llapi_scan_namespace */
	return 0;
}

int main(int argc, char *argv[])
{
	struct llapi_scan_param sp = { .sp_size = sizeof(sp) };
	struct ctx c = { .lock = PTHREAD_MUTEX_INITIALIZER };
	int rc;

	if (argc < 2) {
		fprintf(stderr, "usage: %s <path> [threads] [depth] [stop]\n",
			argv[0]);
		return 2;
	}
	if (argc > 2)
		sp.sp_thread_count = atoi(argv[2]);
	if (argc > 3)
		sp.sp_max_depth = atoi(argv[3]);
	if (argc > 4)
		c.stop_after = strtoul(argv[4], NULL, 0);
	if (getenv("SCAN_QUIET"))
		c.quiet = 1;

	rc = llapi_scan_namespace(argv[1], &sp, cb, &c);
	fprintf(stderr, "scanned=%lu rc=%d\n", c.count, rc);
	return rc == 0 ? 0 : (rc == 42 ? 42 : 1);
}
