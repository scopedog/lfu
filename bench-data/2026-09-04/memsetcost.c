/*
 * Is the difference just the per-object memset of a bigger record?
 * scan_rec_obj() does memset(rec, 0, sizeof(*rec)) once per object.
 */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <stdlib.h>

static double run(size_t sz, unsigned long n)
{
	struct timespec a, b;
	unsigned char buf[1024];
	volatile unsigned char sink = 0;
	unsigned long i;

	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &a);
	for (i = 0; i < n; i++) {
		memset(buf, 0, sz);
		sink += buf[0];
	}
	clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &b);
	(void)sink;
	return (b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9;
}

int main(void)
{
	unsigned long n = 1000007;
	double a = 0, c = 0;
	int i;

	run(512, n);				/* warm up */
	for (i = 0; i < 5; i++) {
		double x = run(328, n), y = run(512, n);

		if (i == 0 || x < a) a = x;
		if (i == 0 || y < c) c = y;
	}
	printf("memset 328B x %lu: %.4f s\n", n, a);
	printf("memset 512B x %lu: %.4f s\n", n, c);
	printf("difference        : %.4f s  (%.1f ns/object)\n",
	       c - a, 1e9 * (c - a) / n);
	return 0;
}
