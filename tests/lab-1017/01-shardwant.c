/*
 * a1017 (68159 cc0ef9d2): a namespace scan asking for LLAPI_SCAN_LMV_SHARD
 * alone.  Old: widened to LLAPI_SCAN_LMV, so lfsp_got says LMV and every
 * object pays the gather.  New: neither.  Prints got, records, records
 * carrying LMV, and the wall time.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <lustre/lustreapi.h>

static unsigned long nrec, nlmv;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	__atomic_fetch_add(&nrec, 1, __ATOMIC_RELAXED);
	if (rec->lfsr_valid & LLAPI_SCAN_LMV)
		__atomic_fetch_add(&nlmv, 1, __ATOMIC_RELAXED);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	struct timespec t0, t1;
	__u64 got = 0;
	int rc;

	if (argc != 2) {
		fprintf(stderr, "usage: %s DIR\n", argv[0]);
		return 2;
	}
	sp.lfsp_want = LLAPI_SCAN_LMV_SHARD;
	sp.lfsp_got = &got;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	rc = llapi_scan_namespace(argv[1], &sp, cb, NULL);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	printf("rc=%d got=%#llx got_lmv=%d records=%lu with_lmv=%lu ms=%.1f\n",
	       rc, (unsigned long long)got, !!(got & LLAPI_SCAN_LMV), nrec,
	       nlmv, (t1.tv_sec - t0.tv_sec) * 1e3 +
	       (t1.tv_nsec - t0.tv_nsec) / 1e6);
	return rc != 0;
}
