#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <pthread.h>
#include <lustre/lustreapi.h>

/* collect every path, sorted, so the two APIs' answers compare exactly */
struct set { char **v; size_t n, cap; pthread_mutex_t lock; };
static void set_add(struct set *s, const char *p) {
	pthread_mutex_lock(&s->lock);
	if (s->n == s->cap) { s->cap = s->cap ? s->cap * 2 : 1024; s->v = realloc(s->v, s->cap * sizeof(*s->v)); }
	s->v[s->n++] = strdup(p);
	pthread_mutex_unlock(&s->lock);
}
static int cmp(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
static int cb(const struct llapi_scan_rec *r, void *d) { set_add(d, r->sr_path); return 0; }

int main(int argc, char **argv)
{
	const char *root = argv[1];
	unsigned int batches[] = { 1, 7, 100, 1000, 4096 };
	unsigned char threads[] = { 1, 8 };
	struct set ref = { .lock = PTHREAD_MUTEX_INITIALIZER };
	struct llapi_scan_param sp = { .sp_size = sizeof(sp), .sp_thread_count = 8 };
	int rc = llapi_scan_namespace(root, &sp, cb, &ref);
	if (rc) { fprintf(stderr, "callback scan: %s\n", strerror(-rc)); return 1; }
	qsort(ref.v, ref.n, sizeof(*ref.v), cmp);
	printf("callback: %zu objects\n", ref.n);

	for (unsigned bi = 0; bi < 5; bi++) for (unsigned ti = 0; ti < 2; ti++) {
		struct set got = { .lock = PTHREAD_MUTEX_INITIALIZER };
		struct llapi_scan_handle *h;
		const struct llapi_scan_rec *const *recs;
		unsigned int n, nb = 0, lmm = 0;
		sp.sp_thread_count = threads[ti];
		rc = llapi_scan_namespace_open(root, &sp, batches[bi], NULL, &h);
		if (rc) { fprintf(stderr, "open: %s\n", strerror(-rc)); return 1; }
		while ((rc = llapi_scan_next(h, &recs, &n)) == 0 && n) {
			nb++;
			for (unsigned i = 0; i < n; i++) {
				set_add(&got, recs[i]->sr_path);
				if (recs[i]->sr_lmm) lmm++;
				if (recs[i]->sr_fd != -1 || recs[i]->sr_parent_fd != -1) { fprintf(stderr, "fd carried\n"); return 1; }
			}
		}
		if (rc) { fprintf(stderr, "next: %s\n", strerror(-rc)); return 1; }
		rc = llapi_scan_close(h);
		qsort(got.v, got.n, sizeof(*got.v), cmp);
		int same = got.n == ref.n;
		for (size_t i = 0; same && i < got.n; i++) same = strcmp(got.v[i], ref.v[i]) == 0;
		printf("batch %4u threads %u: %zu objects in %u batches, close rc %d, %s\n",
		       batches[bi], threads[ti], got.n, nb, rc, same ? "IDENTICAL" : "DIFFERENT");
		if (!same) return 1;
		for (size_t i = 0; i < got.n; i++) free(got.v[i]);
		free(got.v);
	}
	/* early close, many times, to shake out a hang in the stop path */
	for (int k = 0; k < 200; k++) {
		struct llapi_scan_handle *h;
		const struct llapi_scan_rec *const *recs;
		unsigned int n;
		sp.sp_thread_count = 8;
		if (llapi_scan_namespace_open(root, &sp, 1 + k % 50, NULL, &h)) return 1;
		for (int j = 0; j < k % 7; j++)
			if (llapi_scan_next(h, &recs, &n) || n == 0) break;
		if (llapi_scan_close(h) != 0) { fprintf(stderr, "early close rc\n"); return 1; }
	}
	printf("200 early closes: ok\n");
	return 0;
}
