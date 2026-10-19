/* 10-19 lab d: count what llapi_scan_changelog() delivers per type, for a
 * user and a type mask.  Usage: cltypes MDT USER MASK_HEX */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>

static unsigned long cnt[64];

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	if ((rec->lfsr_valid & LLAPI_SCAN_EVENT) && rec->lfsr_event_type < 64)
		cnt[rec->lfsr_event_type]++;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc;
	int rc, i, n = 0;

	memset(&sc, 0, sizeof(sc));
	sc.lfsc_size = sizeof(sc);
	sc.lfsc_mdtname = argv[1];
	sc.lfsc_user = argv[2];
	sc.lfsc_type_mask = strtoull(argv[3], NULL, 16);
	rc = llapi_scan_changelog(&sc, cb, NULL);
	printf("rc=%d", rc);
	for (i = 0; i < 64; i++)
		if (cnt[i]) {
			printf(" %s=%lu", changelog_type2str(i), cnt[i]);
			n++;
		}
	printf("%s\n", n ? "" : " (none)");
	return rc != 0;
}
