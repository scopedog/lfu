/*
 * 09-27 follow-up 2 (68415): llapi_scan_changelog() in event mode with
 * LLAPI_SCAN_CL_F_RESOLVE, one line per record delivered.
 * usage: clres MDT MNT STARTREC WANT(hex, 0 = all)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *r, void *d)
{
	const struct statx *s = &r->lfsr_stx;

	printf("idx=%llu type=%s fid=" DFID " valid=%#llx lazy_size=%d lazy_blocks=%d stx_mask=%#x size=%llu blocks=%llu mtime=%lld.%09u btime=%s%lld.%09u\n",
	       (unsigned long long)r->lfsr_event_index,
	       changelog_type2str(r->lfsr_event_type), PFID(&r->lfsr_fid),
	       (unsigned long long)r->lfsr_valid,
	       !!(r->lfsr_valid & LLAPI_SCAN_LAZY_SIZE),
	       !!(r->lfsr_valid & LLAPI_SCAN_LAZY_BLOCKS), s->stx_mask,
	       (unsigned long long)s->stx_size,
	       (unsigned long long)s->stx_blocks,
	       (long long)s->stx_mtime.tv_sec, s->stx_mtime.tv_nsec,
	       (s->stx_mask & STATX_BTIME) ? "" : "(absent)",
	       (long long)s->stx_btime.tv_sec, s->stx_btime.tv_nsec);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc;
	int rc;

	if (argc != 5) {
		fprintf(stderr, "usage: %s MDT MNT STARTREC WANT\n", argv[0]);
		return 2;
	}
	memset(&sc, 0, sizeof(sc));
	sc.sc_size = sizeof(sc);
	sc.sc_mdtname = argv[1];
	sc.sc_mnt = argv[2];
	sc.sc_startrec = strtoull(argv[3], NULL, 0);
	sc.sc_want = strtoull(argv[4], NULL, 0);
	sc.sc_flags = LLAPI_SCAN_CL_F_RESOLVE;
	rc = llapi_scan_changelog(&sc, cb, NULL);
	printf("rc=%d\n", rc);
	return rc != 0;
}
