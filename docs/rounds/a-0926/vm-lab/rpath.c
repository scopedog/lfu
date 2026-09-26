/* 09-26 68288 lab: llapi_scan_rec_path() on every non-VISIBLE record of a
 * stopped OST, scanned with LLAPI_SCAN_F_INTERNAL */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <lustre/lustreapi.h>
static int mnt_fd;
static const char *mnt;
static unsigned long seen[LLAPI_SCAN_CLS_MAX], enoent[LLAPI_SCAN_CLS_MAX],
	other[LLAPI_SCAN_CLS_MAX], asked;
static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}
static int cb(const struct llapi_scan_rec *r, void *d)
{
	char buf[PATH_MAX];
	double t0;
	int rc, c;

	if (!(r->lfsr_valid & LLAPI_SCAN_CLASS))
		return 0;
	c = r->lfsr_class;
	if (c < 0 || c >= LLAPI_SCAN_CLS_MAX)
		return 0;
	seen[c]++;
	if (c == LLAPI_SCAN_CLS_VISIBLE)
		return 0;
	if (c == LLAPI_SCAN_CLS_INTERNAL)
		printf("  ask class=%d fid=" DFID " ...", c,
		       PFID(&r->lfsr_fid));
	fflush(stdout);
	t0 = now();
	asked++;
	rc = llapi_scan_rec_path(mnt_fd, mnt, r, buf, sizeof(buf));
	if (c == LLAPI_SCAN_CLS_INTERNAL)
		printf(" rc=%d (%.3fs)%s%s\n", rc, now() - t0,
		       rc == 0 ? " " : "", rc == 0 ? buf : "");
	if (rc == -ENOENT)
		enoent[c]++;
	else
		other[c]++;
	return 0;
}
int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	struct llapi_scan_stats st;
	int rc, i;

	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc != 3) {
		fprintf(stderr, "usage: %s DEVICE MOUNT\n", argv[0]);
		return 2;
	}
	mnt = argv[2];
	rc = llapi_root_path_open(mnt, &mnt_fd);
	if (rc < 0) {
		fprintf(stderr, "open %s: %d\n", mnt, rc);
		return 1;
	}
	memset(&sp, 0, sizeof(sp));
	memset(&st, 0, sizeof(st));
	sp.lfsp_size = sizeof(sp);
	sp.lfsp_flags = LLAPI_SCAN_F_INTERNAL;
	sp.lfsp_thread_count = 1;
	st.ss_size = sizeof(st);
	sp.lfsp_stats = &st;
	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	printf("scan rc=%d asked=%lu\n", rc, asked);
	for (i = 0; i < LLAPI_SCAN_CLS_MAX; i++)
		if (seen[i])
			printf("  class %d: seen %lu, -ENOENT %lu, other %lu\n",
			       i, seen[i], enoent[i], other[i]);
	return 0;
}
