/*
 * 10-13 lab: llapi_scan_fid() on one FID, over and over, while something
 * renames a directory above it.  Usage: scanfid_race <mnt> <file|[FID]> <count> [unlink]
 * Prints how many calls returned 0, -ENOENT, -ESTALE or anything else.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	return 0;
}

int main(int argc, char **argv)
{
	struct lu_fid fid;
	long ok = 0, noent = 0, stale = 0, other = 0, i, n;
	int mnt_fd, rc;

	if (argc < 4)
		return 2;
	n = atol(argv[3]);
	llapi_msg_set_level(LLAPI_MSG_OFF);
	/* a FID in brackets, taken before the renames started, or a path */
	if (argv[2][0] == '[')
		rc = sscanf(argv[2], "[0x%llx:0x%x:0x%x]", &fid.f_seq,
			    &fid.f_oid, &fid.f_ver) == 3 ? 0 : -EINVAL;
	else
		rc = llapi_path2fid(argv[2], &fid);
	if (rc < 0) {
		fprintf(stderr, "path2fid %s: %d\n", argv[2], rc);
		return 1;
	}
	/* "unlink": the FID is really gone, and every call must say so */
	if (argc > 4)
		unlink(argv[2]);
	rc = llapi_root_path_open(argv[1], &mnt_fd);
	if (rc < 0)
		return 1;
	for (i = 0; i < n; i++) {
		rc = llapi_scan_fid(mnt_fd, argv[1], &fid, NULL, cb, NULL);
		if (rc == 0)
			ok++;
		else if (rc == -ENOENT)
			noent++;
		else if (rc == -ESTALE)
			stale++;
		else
			other++;
	}
	printf("calls=%ld ok=%ld ENOENT=%ld ESTALE=%ld other=%ld\n", n, ok,
	       noent, stale, other);
	return 0;
}
