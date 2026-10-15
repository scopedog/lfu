#define _GNU_SOURCE
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>
#include <linux/types.h>
#define NSEC_PER_SEC 1000000000ULL
#include "rate.h"
#include RATE_C
static struct scan_rate R; static volatile int go = 1; static unsigned long cnt[64];
static void *w(void *a) { long i = (long)a; while (go) { scan_rate_wait(&R); cnt[i]++; } return NULL; }
int main(int argc, char **argv)
{
	__u32 rate = atoi(argv[1]); int th = atoi(argv[2]); pthread_t t[64];
	unsigned long tot = 0; long i;
	scan_rate_init(&R, rate);
	for (i = 0; i < th; i++) pthread_create(&t[i], NULL, w, (void *)i);
	struct timespec d = { 2, 0 }; nanosleep(&d, NULL); go = 0;
	for (i = 0; i < th; i++) { pthread_join(t[i], NULL); tot += cnt[i]; }
	printf("rate=%u threads=%d achieved=%lu/s\n", rate, th, tot / 2);
	/* burst after a 100 ms stall: slots taken without sleeping */
	struct timespec s = { 0, 100000000 }; nanosleep(&s, NULL);
	unsigned long free_slots = 0; __u64 t0 = scan_rate_now();
	for (;;) { scan_rate_wait(&R); if (scan_rate_now() - t0 > 20000) break; free_slots++; }
	printf("  after a stall: %lu slots free, allowed %llu\n", free_slots,
	       (unsigned long long)rate / 1000 + 1);
	return 0;
}
