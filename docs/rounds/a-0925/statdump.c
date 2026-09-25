/* statdump: a device scan's llapi_scan_stats, with --internal.
 * statdump <device> [search]
 */
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

static unsigned long long nofid;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	if (!(rec->lfsr_valid & LLAPI_SCAN_FID))
		nofid++;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	struct llapi_scan_stats st;
	int rc, i;

	if (argc != 2 && argc != 3)
		return 2;
	memset(&sp, 0, sizeof(sp));
	memset(&st, 0, sizeof(st));
	st.ss_size = sizeof(st);
	sp.lfsp_size = sizeof(sp);
	sp.lfsp_flags = LLAPI_SCAN_F_INTERNAL;
	sp.lfsp_stats = &st;
	if (argc == 3)
		sp.lfsp_search = argv[2];
	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	printf("rc=%d seen=%llu emitted=%llu skipped=%llu filtered=%llu nofid=%llu\n",
	       rc, st.ss_seen, st.ss_emitted, st.ss_skipped, st.ss_filtered,
	       nofid);
	for (i = 0; i < LLAPI_SCAN_CLS_MAX; i++)
		printf("class[%d]=%llu\n", i, st.ss_class[i]);
	return rc != 0;
}
