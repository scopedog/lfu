/* cldump MDTNAME: each changelog record's type, parent bit and prev;
 * then a run whose callback stops at the first record, for ss_emitted */
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int dump_cb(const struct llapi_scan_rec *r, void *data)
{
	(void)data;
	printf("type=%-6s parent=%d pfid=" DFID " prev=%llu\n",
	       changelog_type2str(r->lfsr_event_type),
	       (r->lfsr_valid & LLAPI_SCAN_PARENT) != 0,
	       PFID(&r->lfsr_parent_fid),
	       (unsigned long long)r->lfsr_event_prev);
	return 0;
}

static int stop_cb(const struct llapi_scan_rec *r, void *data)
{
	(void)r; (void)data;
	return -1;
}

int main(int argc, char **argv)
{
	struct llapi_scan_stats st = { .ss_size = sizeof(st) };
	struct llapi_scan_changelog_param sc = {
		.sc_size = sizeof(sc), .sc_mdtname = argv[1],
		.sc_want = LLAPI_SCAN_EVENT | LLAPI_SCAN_PARENT |
			   LLAPI_SCAN_FID,
		.sc_stats = &st,
	};
	int rc;

	rc = llapi_scan_changelog(&sc, dump_cb, NULL);
	printf("dump rc=%d seen=%llu emitted=%llu\n", rc,
	       (unsigned long long)st.ss_seen,
	       (unsigned long long)st.ss_emitted);
	memset(&st, 0, sizeof(st));
	st.ss_size = sizeof(st);
	rc = llapi_scan_changelog(&sc, stop_cb, NULL);
	printf("stop rc=%d emitted=%llu\n", rc,
	       (unsigned long long)st.ss_emitted);
	return 0;
}
