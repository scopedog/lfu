/* In one llapi_scan_mount() pass, how many objects arrive after every
 * ancestor directory (path composable on arrival)?  Single-MDT only. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <lustre/lustreapi.h>

#define MAXD 1000000
static struct { struct lu_fid f, p; } d[MAXD];
static unsigned long nd, now, later, nodir;

static int seen(const struct lu_fid *f)
{
	struct lu_fid root = { 0x200000007ULL, 1, 0 };
	unsigned long i;

	for (;;) {
		if (f->f_seq == root.f_seq && f->f_oid == root.f_oid)
			return 1;
		for (i = 0; i < nd; i++)
			if (!memcmp(&d[i].f, f, sizeof(*f)))
				break;
		if (i == nd)
			return 0;
		f = &d[i].p;
	}
}

static int cb(const struct llapi_scan_rec *r, void *data)
{
	if (!(r->lfsr_valid & LLAPI_SCAN_PARENT)) {
		nodir++;
		return 0;
	}
	if (S_ISDIR(r->lfsr_stx.stx_mode) && nd < MAXD) {
		d[nd].f = r->lfsr_fid;
		d[nd++].p = r->lfsr_parent_fid;
	}
	if (seen(&r->lfsr_parent_fid))
		now++;
	else
		later++;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp),
		.lfsp_want = LLAPI_SCAN_FID | LLAPI_SCAN_TYPE | LLAPI_SCAN_MODE |
			     LLAPI_SCAN_PARENT | LLAPI_SCAN_LINKEA,
		.lfsp_thread_count = 1 };
	int rc = llapi_scan_mount(argv[1], &sp, cb, NULL);

	printf("rc=%d dirs=%lu composable-on-arrival=%lu deferred=%lu no-parent=%lu\n",
	       rc, nd, now, later, nodir);
	return 0;
}
