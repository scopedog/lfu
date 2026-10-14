// SPDX-License-Identifier: GPL-2.0
/*
 * 10-14 lab: the batch API against the callback API on one tree.  Port of
 * bench-data/2026-09-05/stress.c to the lfsr_/lfsp_ names, with a key that
 * holds every field a batch copies (path, name, FID, masks, size, mode and
 * the bytes behind lmm, lmv and linkea), so a field lost or mis-copied in
 * the batch shows as DIFFERENT.  Usage: stress-batch <dir>
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <pthread.h>
#include <lustre/lustreapi.h>

struct set { char **v; size_t n, cap; pthread_mutex_t lock; };

static unsigned long long fnv(const void *p, size_t len)
{
	const unsigned char *c = p;
	unsigned long long h = 1469598103934665603ULL;

	if (p == NULL)
		return 0;
	while (len--)
		h = (h ^ *c++) * 1099511628211ULL;
	return h;
}

static char *key(const struct llapi_scan_rec *r)
{
	char *k;

	if (asprintf(&k, "%s|%s|" DFID "|%llx|%x|%llu|%o|%u:%llx|%u:%llx|%u:%llx|%s|%s",
		     r->lfsr_path, r->lfsr_name ? r->lfsr_name : "-",
		     PFID(&r->lfsr_fid), (unsigned long long)r->lfsr_valid,
		     r->lfsr_stx.stx_mask,
		     (unsigned long long)r->lfsr_stx.stx_size,
		     r->lfsr_stx.stx_mode,
		     r->lfsr_lmmsize, fnv(r->lfsr_lmm, r->lfsr_lmmsize),
		     r->lfsr_lmvsize, fnv(r->lfsr_lmv, r->lfsr_lmvsize),
		     r->lfsr_linkeasize, fnv(r->lfsr_linkea, r->lfsr_linkeasize),
		     r->lfsr_src_name ? r->lfsr_src_name : "-",
		     r->lfsr_event_jobid ? r->lfsr_event_jobid : "-") < 0)
		abort();
	return k;
}

static void set_add(struct set *s, char *k)
{
	pthread_mutex_lock(&s->lock);
	if (s->n == s->cap) {
		s->cap = s->cap ? s->cap * 2 : 1024;
		s->v = realloc(s->v, s->cap * sizeof(*s->v));
	}
	s->v[s->n++] = k;
	pthread_mutex_unlock(&s->lock);
}

static int cmp(const void *a, const void *b)
{
	return strcmp(*(char *const *)a, *(char *const *)b);
}

static int cb(const struct llapi_scan_rec *r, void *d)
{
	set_add(d, key(r));
	return 0;
}

int main(int argc, char **argv)
{
	const char *root = argv[1];
	unsigned int batches[] = { 1, 7, 100, 1000, 4096 };
	unsigned char threads[] = { 1, 8 };
	struct set ref = { .lock = PTHREAD_MUTEX_INITIALIZER };
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp),
				       .lfsp_thread_count = 8 };
	unsigned int lmm = 0, lmv = 0, bad = 0;
	int rc;

	if (argc != 2)
		return 2;
	setvbuf(stdout, NULL, _IOLBF, 0);
	rc = llapi_scan_namespace(root, &sp, cb, &ref);
	if (rc) {
		fprintf(stderr, "callback scan: %s\n", strerror(-rc));
		return 1;
	}
	qsort(ref.v, ref.n, sizeof(*ref.v), cmp);
	printf("callback: %zu objects\n", ref.n);

	for (unsigned int bi = 0; bi < 5; bi++)
	for (unsigned int ti = 0; ti < 2; ti++) {
		struct set got = { .lock = PTHREAD_MUTEX_INITIALIZER };
		const struct llapi_scan_rec *const *recs;
		struct llapi_scan_handle *h;
		unsigned int n, nb = 0;
		int same;

		lmm = lmv = 0;
		sp.lfsp_thread_count = threads[ti];
		rc = llapi_scan_namespace_open(root, &sp, batches[bi], NULL,
					       &h);
		if (rc) {
			fprintf(stderr, "open: %s\n", strerror(-rc));
			return 1;
		}
		while ((rc = llapi_scan_next(h, &recs, &n)) == 0 && n) {
			nb++;
			for (unsigned int i = 0; i < n; i++) {
				set_add(&got, key(recs[i]));
				lmm += recs[i]->lfsr_lmm != NULL;
				lmv += recs[i]->lfsr_lmv != NULL;
				if (recs[i]->lfsr_fd != -1 ||
				    recs[i]->lfsr_parent_fd != -1)
					bad++;
			}
		}
		if (rc) {
			fprintf(stderr, "next: %s\n", strerror(-rc));
			return 1;
		}
		rc = llapi_scan_close(h);
		qsort(got.v, got.n, sizeof(*got.v), cmp);
		same = got.n == ref.n;
		for (size_t i = 0; same && i < got.n; i++)
			same = strcmp(got.v[i], ref.v[i]) == 0;
		printf("batch %4u threads %u: %zu objects in %u batches, %u lmm, %u lmv, %u fd, close rc %d, %s\n",
		       batches[bi], threads[ti], got.n, nb, lmm, lmv, bad, rc,
		       same ? "IDENTICAL" : "DIFFERENT");
		if (!same || bad)
			return 1;
		for (size_t i = 0; i < got.n; i++)
			free(got.v[i]);
		free(got.v);
	}
	/* early close, many times, to shake out a hang in the stop path */
	for (int k = 0; k < 200; k++) {
		const struct llapi_scan_rec *const *recs;
		struct llapi_scan_handle *h;
		unsigned int n;

		sp.lfsp_thread_count = 8;
		if (llapi_scan_namespace_open(root, &sp, 1 + k % 50, NULL, &h))
			return 1;
		for (int j = 0; j < k % 7; j++)
			if (llapi_scan_next(h, &recs, &n) || n == 0)
				break;
		if (llapi_scan_close(h) != 0) {
			fprintf(stderr, "early close rc\n");
			return 1;
		}
	}
	printf("200 early closes: ok\n");
	for (size_t i = 0; i < ref.n; i++)
		free(ref.v[i]);
	free(ref.v);
	return 0;
}
