/*
 * Does an object the caller cannot open drop out of a namespace scan when
 * the demand mask names LLAPI_SCAN_MDT_INDEX?  Same tree, two scans: one
 * asking only for what the dirent settles, one also asking for the MDT
 * index.  A difference in the count is the answer.
 */
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int count_cb(const struct llapi_scan_rec *rec, void *data)
{
	unsigned long *n = data;

	(*n)++;
	return 0;
}

static int scan(const char *path, __u64 want, unsigned long *n)
{
	struct llapi_scan_param sp = { .sp_size = sizeof(sp), .sp_want = want };

	*n = 0;
	return llapi_scan_namespace(path, &sp, count_cb, n);
}

int main(int argc, char **argv)
{
	unsigned long base = 0, with = 0;
	int rc1, rc2;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <path>\n", argv[0]);
		return 2;
	}

	rc1 = scan(argv[1], LLAPI_SCAN_TYPE, &base);
	rc2 = scan(argv[1], LLAPI_SCAN_TYPE | LLAPI_SCAN_MDT_INDEX, &with);

	printf("  TYPE only            : %lu objects (rc %d)\n", base, rc1);
	printf("  TYPE | MDT_INDEX     : %lu objects (rc %d)\n", with, rc2);
	if (base == with)
		printf("  SAME -- nothing dropped\n");
	else
		printf("  DIFFERENT -- %lu object(s) dropped, silently (rc %d)\n",
		       base - with, rc2);
	return 0;
}
