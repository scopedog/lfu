/* llapi_scan_fid() on one file, printing what the record says and which
 * object its lfsr_fd is.  Usage: scanfid_race MOUNT FILE
 */
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	struct lu_fid ffid = { 0 };
	int frc = -1;

	if (rec->lfsr_fd >= 0)
		frc = llapi_fd2fid(rec->lfsr_fd, &ffid);
	printf("record: path=%s fid=" DFID " size=%llu projid=%s%u fd_fid=",
	       rec->lfsr_path, PFID(&rec->lfsr_fid),
	       (unsigned long long)rec->lfsr_stx.stx_size,
	       (rec->lfsr_valid & LLAPI_SCAN_PROJID) ? "" : "(unset)",
	       rec->lfsr_projid);
	if (frc == 0)
		printf(DFID "\n", PFID(&ffid));
	else
		printf("(none, fd=%d)\n", rec->lfsr_fd);
	(*(int *)data)++;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	struct lu_fid fid;
	Dl_info di;
	int calls = 0;
	int mnt_fd;
	int rc;

	if (argc != 3)
		return 2;
	if (dladdr((void *)llapi_scan_fid, &di))
		printf("lib: %s\n", di.dli_fname);
	rc = llapi_path2fid(argv[2], &fid);
	if (rc < 0) {
		printf("path2fid: %d\n", rc);
		return 1;
	}
	rc = llapi_root_path_open(argv[1], &mnt_fd);
	if (rc < 0) {
		printf("root_path_open: %d\n", rc);
		return 1;
	}
	printf("asked: fid=" DFID "\n", PFID(&fid));
	memset(&sp, 0, sizeof(sp));
	sp.lfsp_size = sizeof(sp);
	sp.lfsp_want = LLAPI_SCAN_TYPE | LLAPI_SCAN_FID | LLAPI_SCAN_SIZE |
		       LLAPI_SCAN_PROJID | LLAPI_SCAN_MDT_INDEX;
	setenv("RACE_ARM", "1", 1);
	rc = llapi_scan_fid(mnt_fd, argv[1], &fid, &sp, cb, &calls);
	printf("rc=%d (%s) callbacks=%d\n", rc, rc < 0 ? strerror(-rc) : "ok",
	       calls);
	return 0;
}
