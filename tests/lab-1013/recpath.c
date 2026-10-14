/*
 * 10-13 lab (item 3): scan a target and name every directory record with
 * llapi_scan_rec_path().  Usage: recpath <device> <mnt>
 * Prints one line per directory: its pathname, or "rc=<errno>".
 */
#include <stdio.h>
#include <sys/stat.h>
#include <linux/limits.h>
#include <lustre/lustreapi.h>

static int mnt_fd;
static const char *mnt;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	char path[PATH_MAX];
	int rc;

	if (!(rec->lfsr_stx.stx_mask & STATX_TYPE) ||
	    !S_ISDIR(rec->lfsr_stx.stx_mode))
		return 0;
	rc = llapi_scan_rec_path(mnt_fd, mnt, rec, path, sizeof(path));
	if (rc == 0)
		printf("%s%s\n", path,
		       rec->lfsr_valid & LLAPI_SCAN_LMV_SHARD ? "  <-shard" : "");
	else
		printf("rc=%d%s\n", rc,
		       rec->lfsr_valid & LLAPI_SCAN_LMV_SHARD ? "  <-shard" : "");
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	int rc;

	if (argc < 3)
		return 2;
	llapi_msg_set_level(LLAPI_MSG_OFF);
	mnt = argv[2];
	rc = llapi_root_path_open(mnt, &mnt_fd);
	if (rc < 0)
		return 1;
	sp.lfsp_thread_count = 1;
	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	fprintf(stderr, "scan rc=%d\n", rc);
	return rc != 0;
}
