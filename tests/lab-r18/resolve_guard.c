/*
 * The --resolve-without-changelog guard exists twice with the same
 * condition: in lfs_find_parse(), which lfs find and lfind both go
 * through, and in llapi_find_since().  The parser refuses first, so the
 * library's message is reachable only by a direct llapi caller -- which
 * is what this is.
 */
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

int main(int argc, char **argv)
{
	struct find_param param;
	int rc;

	memset(&param, 0, sizeof(param));
	param.fp_max_depth = (unsigned int)-1;
	param.fp_resolve = 1;			/* and no fp_changelog_mdt */
	if (argc > 2)
		param.fp_since_cookie = argv[2];

	rc = llapi_find_since(argv[1], &param);
	printf("llapi_find_since rc=%d\n", rc);
	return 0;
}
