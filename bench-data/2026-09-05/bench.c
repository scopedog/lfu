#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <lustre/lustreapi.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static unsigned long sink;
static int cb(const struct llapi_scan_rec *r, void *d) { sink += r->sr_stx.stx_size + r->sr_name[0]; return 0; }
static int cmpd(const void *a, const void *b) { double x = *(double*)a, y = *(double*)b; return x < y ? -1 : x > y; }
int main(int argc, char **argv)
{
	const char *root = argv[1]; unsigned char thr = atoi(argv[2]); unsigned batch = atoi(argv[3]);
	struct llapi_scan_param sp = { .sp_size = sizeof(sp), .sp_thread_count = thr };
	enum { N = 15 }; double tc[N], tb[N]; unsigned long nobj = 0;
	for (int i = 0; i < N; i++) {
		double t0 = now(); llapi_scan_namespace(root, &sp, cb, NULL); tc[i] = now() - t0;
		struct llapi_scan_handle *h; const struct llapi_scan_rec *const *recs; unsigned n; nobj = 0;
		t0 = now(); llapi_scan_namespace_open(root, &sp, batch, NULL, &h);
		while (llapi_scan_next(h, &recs, &n) == 0 && n) { for (unsigned j = 0; j < n; j++) cb(recs[j], NULL); nobj += n; }
		llapi_scan_close(h); tb[i] = now() - t0;
	}
	qsort(tc, N, sizeof(double), cmpd); qsort(tb, N, sizeof(double), cmpd);
	printf("threads %u batch %5u: callback %.1f ms  batch %.1f ms  (%+.1f%%, %+.0f ns/obj over %lu objects; medians of %d alternating runs)\n",
	       thr, batch, tc[N/2]*1e3, tb[N/2]*1e3, (tb[N/2]/tc[N/2]-1)*100, (tb[N/2]-tc[N/2])/nobj*1e9, nobj, N);
	return sink == 1;
}
