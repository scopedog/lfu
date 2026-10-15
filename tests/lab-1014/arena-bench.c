// 10-14: lift-and-compare for lreview finding 1 on 68726'.  Includes the real
// liblustreapi_scan_batch.c (old or new, -DSRC) and drives its arena the way
// a batch of widely striped files does: NREC payloads of PAYLOAD bytes, then
// a reset, BATCHES times.  Prints the time per batch and the chunk count.
#include SRC
#include <time.h>
#ifndef PAYLOAD
#define PAYLOAD (47 * 1024)	/* lov_user_md_size(2000, V1), about */
#endif
int main(void)
{
	struct scan_batch b = { 0 };
	struct timespec t0, t1;
	struct scan_arena_chunk *c;
	int nrec = 1024, batches = 50, chunks = 0, i, k;

	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (k = 0; k < batches; k++) {
		for (i = 0; i < nrec; i++)
			if (scan_arena_alloc(&b, PAYLOAD) == NULL)
				return 1;
		scan_batch_reset(&b);
	}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	for (c = b.sb_arena; c != NULL; c = c->ac_next)
		chunks++;
	printf("%-4s payload %6d B x %d: %8.1f us per batch, %d chunks\n",
	       NAME, PAYLOAD, nrec,
	       ((t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec)) / 1e3 / batches,
	       chunks);
	return 0;
}
