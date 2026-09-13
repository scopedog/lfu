/* aa575ca1: does sc_got under a resolve name the lazy size and blocks? */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int stop_cb(const struct llapi_scan_rec *rec, void *data)
{
	(void)rec;
	(void)data;
	return 1;
}

int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc;
	__u64 got = 0;
	int rc;

	if (argc != 3) {
		fprintf(stderr, "usage: %s MDTNAME MOUNT\n", argv[0]);
		return 2;
	}
	memset(&sc, 0, sizeof(sc));
	sc.sc_size = sizeof(sc);
	sc.sc_mdtname = argv[1];
	sc.sc_mnt = argv[2];
	sc.sc_flags = LLAPI_SCAN_CL_F_RESOLVE;
	sc.sc_want = LLAPI_SCAN_FID | LLAPI_SCAN_MTIME |
		     LLAPI_SCAN_LAZY_SIZE | LLAPI_SCAN_LAZY_BLOCKS;
	sc.sc_got = &got;
	rc = llapi_scan_changelog(&sc, stop_cb, NULL);
	printf("rc=%d got=%#llx lazy_size=%d lazy_blocks=%d\n", rc,
	       (unsigned long long)got, !!(got & LLAPI_SCAN_LAZY_SIZE),
	       !!(got & LLAPI_SCAN_LAZY_BLOCKS));
	return !((got & LLAPI_SCAN_LAZY_SIZE) && (got & LLAPI_SCAN_LAZY_BLOCKS));
}
