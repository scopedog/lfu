/*
 * Time llapi_scan_device() over a target, with the cheapest possible
 * consumer: the question is what the record itself costs, so the callback
 * must do as little as possible while still touching the record.
 *
 * Prints: objects elapsed_s objects_per_s
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <lustre/lustreapi.h>

static unsigned long long seen;
static unsigned long long acc;	/* keeps the compiler from eliding the read */

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	seen++;
	acc += rec->sr_size;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp;
	struct llapi_scan_stats st;
	struct timespec t0, t1, c0, c1;
	double el, cpu;
	int rc;

	if (argc < 2) {
		fprintf(stderr,
			"usage: %s <device> [threads] [want] [search]\n",
			argv[0]);
		return 2;
	}
	memset(&sp, 0, sizeof(sp));
	memset(&st, 0, sizeof(st));
	sp.sp_size = sizeof(sp);
	st.ss_size = sizeof(st);
	sp.sp_stats = &st;
	if (argc > 2)
		sp.sp_thread_count = (unsigned char)atoi(argv[2]);
	if (argc > 3)
		sp.sp_want = strtoull(argv[3], NULL, 0);
	if (argc > 4 && argv[4][0] != '\0')
		sp.sp_search = argv[4];

	/*
	 * CPU time as well as wall clock: the scan is single-threaded here,
	 * so process CPU time is what the record's own cost lands in, and it
	 * is not moved by the scheduler the way wall clock is.
	 */
	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &c0);
	clock_gettime(CLOCK_MONOTONIC, &t0);
	rc = llapi_scan_device(argv[1], &sp, cb, NULL);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &c1);
	if (rc < 0) {
		fprintf(stderr, "scan failed: %d\n", rc);
		return 1;
	}
	el = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
	cpu = (c1.tv_sec - c0.tv_sec) + (c1.tv_nsec - c0.tv_nsec) / 1e9;
	/* seen emitted wall rate acc cpu */
	printf("%llu %llu %.4f %.0f %llu %.4f\n",
	       (unsigned long long)st.ss_seen, seen, el,
	       el > 0 ? seen / el : 0.0, acc, cpu);
	return 0;
}
