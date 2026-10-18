/* One llapi_scan_mount() pass, counting records: no map, no paths. */
#include <stdio.h>
#include <stdlib.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	(*(unsigned long *)data)++;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp),
		.lfsp_want = LLAPI_SCAN_FID | LLAPI_SCAN_TYPE | LLAPI_SCAN_MTIME |
			     (argc > 2 ? LLAPI_SCAN_PARENT | LLAPI_SCAN_LINKEA : 0),
		.lfsp_thread_count = 1 };
	unsigned long n = 0;
	int rc = llapi_scan_mount(argv[1], &sp, cb, &n);

	printf("%lu rc=%d\n", n, rc);
	return rc != 0;
}
