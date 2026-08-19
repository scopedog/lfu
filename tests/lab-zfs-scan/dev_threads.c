/* Lab harness: scan a target at a given thread count and print one FID per
 * line, so that the object set can be diffed across thread counts.
 *
 * The contract test covers 1, 2, 4 and 8 internally; this is the external
 * check, and it is what adds 16.  lfind has no thread option, by design --
 * it is a find, not a benchmark.
 *
 * Usage: dev_threads <device> [threads]
 */
#include <stdio.h>
#include <stdlib.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	(void)data;
	if (rec->sr_valid & LLAPI_SCAN_FID)
		printf(DFID"\n", PFID(&rec->sr_fid));
	else
		printf("ino:%llu\n", (unsigned long long)rec->sr_ino);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .sp_size = sizeof(sp) };
	int rc;

	if (argc < 2) {
		fprintf(stderr, "Usage: %s <device> [threads]\n", argv[0]);
		return 2;
	}
	sp.sp_flags = LLAPI_SCAN_F_INTERNAL;
	sp.sp_thread_count = argc > 2 ? atoi(argv[2]) : 1;

	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	if (rc != 0) {
		fprintf(stderr, "scan of %s failed: %d\n", argv[1], rc);
		return 1;
	}
	return 0;
}
