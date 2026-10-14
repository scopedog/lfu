/*
 * 10-13 lab (item 4): two threads open two datasets of one exported pool,
 * the second <delay_ms> after the first.
 * Usage: zrace <devA> <devB> <search> <delay_ms>
 * Prints each scan's return value and record count.
 */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <lustre/lustreapi.h>

struct arm {
	const char *dev, *search;
	int delay_ms, rc;
	unsigned long n;
};

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	__sync_fetch_and_add(&((struct arm *)data)->n, 1);
	return 0;
}

static void *run(void *p)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	struct arm *a = p;

	usleep(a->delay_ms * 1000);
	sp.lfsp_search = a->search;
	sp.lfsp_thread_count = 1;
	a->rc = llapi_scan_device(a->dev, &sp, cb, a);
	return NULL;
}

int main(int argc, char **argv)
{
	struct arm a = { 0 }, b = { 0 };
	pthread_t ta, tb;

	if (argc < 5)
		return 2;
	llapi_msg_set_level(LLAPI_MSG_OFF);
	a.dev = argv[1]; b.dev = argv[2];
	a.search = b.search = argv[3];
	b.delay_ms = atoi(argv[4]);
	pthread_create(&ta, NULL, run, &a);
	pthread_create(&tb, NULL, run, &b);
	pthread_join(ta, NULL);
	pthread_join(tb, NULL);
	printf("A rc=%d n=%lu  B rc=%d n=%lu\n", a.rc, a.n, b.rc, b.n);
	return 0;
}
