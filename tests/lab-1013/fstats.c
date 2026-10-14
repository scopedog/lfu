/*
 * 10-13 lab (item 6): llapi_find_device() with the caller's lfsp_stats set.
 * Usage: fstats <device>.  The matches go to stdout; the counters to stderr.
 */
#include <stdio.h>
#include <lustre/lustreapi.h>

int main(int argc, char **argv)
{
	struct llapi_scan_stats stats = { .ss_size = sizeof(stats) };
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	struct find_param *param;
	int rc;

	if (argc < 2)
		return 2;
	param = llapi_find_param_alloc();
	if (param == NULL)
		return 1;
	param->fp_max_depth = -1;
	sp.lfsp_stats = &stats;
	rc = llapi_find_device(argv[1], param, &sp);
	fprintf(stderr, "rc=%d ss_size=%u seen=%llu emitted=%llu skipped=%llu\n",
		rc, stats.ss_size, (unsigned long long)stats.ss_seen,
		(unsigned long long)stats.ss_emitted,
		(unsigned long long)stats.ss_skipped);
	llapi_find_param_free(param);
	return 0;
}
