/*
 * 10-13 lab (item 6): llapi_find_device() with the caller's lfsp_stats set.
 * Usage: fstats <device> [mdt-uuid].  The matches go to stdout; the counters
 * to stderr.  With an MDT name the counters are first set to 999, so a target
 * the search skips shows whether they were written.
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
	if (argc > 2) {
		static struct obd_uuid u;

		snprintf(u.uuid, sizeof(u.uuid), "%s", argv[2]);
		param->fp_mdt_uuid = &u;
		param->fp_num_mdts = 1;
		stats.ss_seen = stats.ss_emitted = stats.ss_skipped = 999;
	}
	sp.lfsp_stats = &stats;
	rc = llapi_find_device(argv[1], param, &sp);
	fprintf(stderr, "rc=%d ss_size=%u seen=%llu emitted=%llu skipped=%llu\n",
		rc, stats.ss_size, (unsigned long long)stats.ss_seen,
		(unsigned long long)stats.ss_emitted,
		(unsigned long long)stats.ss_skipped);
	llapi_find_param_free(param);
	return 0;
}
