/* 09-26 68415 lab: llapi_scan_changelog() with a type mask, _CLEAR, both */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>
static unsigned long n;
static int cb(const struct llapi_scan_rec *r, void *d) { n++; return 0; }
int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc;
	int rc;

	if (argc != 4) {
		fprintf(stderr, "usage: %s MDT USER mask|clear|both\n", argv[0]);
		return 2;
	}
	memset(&sc, 0, sizeof(sc));
	sc.sc_size = sizeof(sc);
	sc.sc_mdtname = argv[1];
	sc.sc_user = argv[2];
	if (strcmp(argv[3], "clear") != 0)
		sc.sc_type_mask = 1ULL << CL_CREATE;
	if (strcmp(argv[3], "mask") != 0)
		sc.sc_flags = LLAPI_SCAN_CL_F_CLEAR;
	rc = llapi_scan_changelog(&sc, cb, NULL);
	printf("%s: rc=%d records=%lu\n", argv[3], rc, n);
	return 0;
}
