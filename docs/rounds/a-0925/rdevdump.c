/* rdevdump: print rdev and blksize of every device node a scan returns.
 * rdevdump n <dir> | rdevdump d <device> [search]
 */
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	mode_t m = rec->lfsr_stx.stx_mode;

	if (!S_ISCHR(m) && !S_ISBLK(m))
		return 0;
	printf("%c ino=%llu fid=" DFID " rdev=%u:%u blksize=%u\n",
	       S_ISCHR(m) ? 'c' : 'b', (unsigned long long)rec->lfsr_ino,
	       PFID(&rec->lfsr_fid), rec->lfsr_stx.stx_rdev_major,
	       rec->lfsr_stx.stx_rdev_minor, rec->lfsr_stx.stx_blksize);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	int rc;

	if (argc != 3 && argc != 4)
		return 2;
	memset(&sp, 0, sizeof(sp));
	sp.lfsp_size = sizeof(sp);
	sp.lfsp_want = 0;
	if (argc == 4)
		sp.lfsp_search = argv[3];
	if (argv[1][0] == 'n')
		rc = llapi_scan_namespace(argv[2], &sp, cb, NULL);
	else
		rc = llapi_scan_device(argv[2], &sp, cb, NULL);
	fprintf(stderr, "rc=%d\n", rc);
	return rc != 0;
}
