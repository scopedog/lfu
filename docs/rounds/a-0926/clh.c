#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>
static int cb(const struct llapi_scan_rec *r, void *d) { return 0; }
int main(void)
{
	struct llapi_scan_changelog_param sc;
	int i, rc;
	for (i = 0; i < 3; i++) {
		memset(&sc, 0, sizeof(sc));
		sc.sc_size = sizeof(sc);
		sc.sc_mdtname = "nofs-MDT0000";
		sc.sc_user = "cl1";
		if (i != 2) sc.sc_type_mask = 1ULL << CL_UNLINK;
		if (i != 1) sc.sc_flags = LLAPI_SCAN_CL_F_CLEAR;
		rc = llapi_scan_changelog(&sc, cb, NULL);
		printf("mask=%d clear=%d rc=%d\n", i != 2, i != 1, rc);
	}
	return 0;
}
