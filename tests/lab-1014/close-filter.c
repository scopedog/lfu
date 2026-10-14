// SPDX-License-Identifier: GPL-2.0
/*
 * 10-14 lab, lreview finding 1 on 68726: close a batch scan whose
 * lfsp_filter rejects nearly everything, after one batch, and time the
 * close.  Batch 2; the filter passes three objects (one full batch, one
 * started) and rejects the rest, sleeping 20us each, so a close that waits
 * for the walk takes about 20us x the tree.  Usage: close-filter <dir>
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <lustre/lustreapi.h>

static unsigned int seen;

static int filter(const struct llapi_scan_rec *rec, void *data)
{
	unsigned int n = __atomic_add_fetch(&seen, 1, __ATOMIC_RELAXED);

	usleep(20);
	return n <= 3 ? 0 : 1;
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = {
		.lfsp_size = sizeof(sp),
		.lfsp_thread_count = 1,
		.lfsp_filter = filter,
	};
	const struct llapi_scan_rec *const *recs;
	struct llapi_scan_handle *h;
	unsigned int n;
	double t;
	int rc;

	rc = llapi_scan_namespace_open(argv[1], &sp, 2, NULL, &h);
	if (rc)
		return 1;
	rc = llapi_scan_next(h, &recs, &n);
	printf("first batch: rc %d, %u records\n", rc, n);
	/* the consumer works on the batch; the scan moves on meanwhile */
	usleep(100000);
	t = now();
	rc = llapi_scan_close(h);
	printf("close rc %d after %.3f s; the filter saw %u objects\n", rc,
	       now() - t, seen);
	return 0;
}
