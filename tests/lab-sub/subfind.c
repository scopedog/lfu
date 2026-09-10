/* Root-vs-subtree harness.  The same predicate, "-mtime -30 -type f", through
 * llapi_scan_mount() (the offload, restricted to PATH's subtree when PATH is
 * not the root) or llapi_scan_namespace() (the walk, the oracle).  Prints
 * the count on stdout, or every matching FID with "fids", so the two arms
 * can be diffed as sets and not just as numbers. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>
#include <lustre/lustreapi.h>

/* -mtime, not -type alone: a type is in the dirent, so "-type f" is a
 * readdir for a walk and measures no per-object cost at all
 */
static time_t cutoff;
static int print_fids;
/* the callback runs on the scan's workers once lfsp_thread_count > 1 */
static unsigned long match;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	if (!(rec->lfsr_stx.stx_mask & STATX_TYPE) ||
	    !S_ISREG(rec->lfsr_stx.stx_mode))
		return 0;
	if (!(rec->lfsr_stx.stx_mask & STATX_MTIME) ||
	    rec->lfsr_stx.stx_mtime.tv_sec <= cutoff)
		return 0;
	__atomic_add_fetch(&match, 1, __ATOMIC_RELAXED);
	if (print_fids)
		printf(DFID"\n", PFID(&rec->lfsr_fid));
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_stats stats = { .ss_size = sizeof(stats) };
	/* only what -type f needs: the walk pays a round trip per field it
	 * cannot answer from the dirent, so asking for everything would
	 * measure the fields rather than the scan
	 */
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp),
				       .lfsp_want = LLAPI_SCAN_FID |
						    LLAPI_SCAN_TYPE |
						    LLAPI_SCAN_MTIME,
				       .lfsp_stats = &stats };
	struct timespec a, b;
	const char *mode, *path;
	int rc;

	if (argc < 3) {
		fprintf(stderr, "usage: subfind mount|ns PATH [fids] [threads]\n");
		return 64;
	}
	mode = argv[1];
	path = argv[2];
	print_fids = argc > 3 && strcmp(argv[3], "fids") == 0;
	/* a thread count, after "fids" or in its place */
	if (argc > 3 && !print_fids)
		sp.lfsp_thread_count = atoi(argv[3]);
	else if (argc > 4)
		sp.lfsp_thread_count = atoi(argv[4]);
	cutoff = time(NULL) - 30 * 86400;	/* -mtime -30 */

	clock_gettime(CLOCK_MONOTONIC, &a);
	if (strcmp(mode, "mount") == 0)
		rc = llapi_scan_mount(path, &sp, cb, NULL);
	else if (strcmp(mode, "ns") == 0)
		rc = llapi_scan_namespace(path, &sp, cb, NULL);
	else
		return 64;
	clock_gettime(CLOCK_MONOTONIC, &b);
	if (rc < 0) {
		fprintf(stderr, "%s: %s\n", mode, strerror(-rc));
		return 2;
	}
	fprintf(stderr,
		"%s %s: threads=%u match=%lu seen=%llu emitted=%llu filtered=%llu skipped=%llu wall=%.3f\n",
		mode, path, sp.lfsp_thread_count, match, (unsigned long long)stats.ss_seen,
		(unsigned long long)stats.ss_emitted,
		(unsigned long long)stats.ss_filtered,
		(unsigned long long)stats.ss_skipped,
		(b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9);
	if (!print_fids)
		printf("%lu\n", match);
	return 0;
}
