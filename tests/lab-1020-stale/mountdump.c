/* llapi_scan_mount() from a client: one line per record, "fid name".
 * Build: gcc -O2 -I<tree>/lustre/include -I<tree>/include ... -llustreapi
 */
#include <stdio.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	printf(DFID" %s %u %u %u\n", PFID(&rec->lfsr_fid),
	       rec->lfsr_name ? rec->lfsr_name : "-",
	       rec->lfsr_stx.stx_uid, rec->lfsr_stx.stx_gid,
	       rec->lfsr_projid);
	return 0;
}

int main(int argc, char **argv)
{
	int rc;

	if (argc != 2) {
		fprintf(stderr, "usage: %s /mnt/lustre\n", argv[0]);
		return 2;
	}
	rc = llapi_scan_mount(argv[1], NULL, cb, NULL);
	fprintf(stderr, "llapi_scan_mount rc=%d\n", rc);
	return rc ? 1 : 0;
}
