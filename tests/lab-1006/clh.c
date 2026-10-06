/* C1 harness: llapi_scan_changelog() with _CLEAR.  clh MDT USER [STOP_AFTER] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>

static long n, stop_after;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	n++;
	return (stop_after > 0 && n >= stop_after) ? 7 : 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc;
	int rc;

	if (argc < 3)
		return 2;
	stop_after = argc > 3 ? atol(argv[3]) : 0;
	memset(&sc, 0, sizeof(sc));
	sc.sc_size = sizeof(sc);
	sc.sc_flags = LLAPI_SCAN_CL_F_CLEAR;
	sc.sc_mdtname = argv[1];
	sc.sc_user = argv[2];
	rc = llapi_scan_changelog(&sc, cb, NULL);
	printf("rc=%d (%s) delivered=%ld\n", rc, rc < 0 ? strerror(-rc) : "-", n);
	return 0;
}
