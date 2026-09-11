/* a stand-in for the lfind(8) of the next change: predicates over a target */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <lustre/lustreapi.h>
#include "lfs_find_parse.h"

const char *progname = "tdev";

int main(int argc, char **argv)
{
	struct find_param param;
	int pathstart, pathend;
	bool stopped;
	int rc;

	if (argc < 2)
		return 2;
	lfs_find_parse_init(&param);
	optind = 2;
	opterr = 0;
	rc = lfs_find_parse(argc, argv, &param, &pathstart, &pathend, &stopped);
	if (rc != 0 || stopped) {
		fprintf(stderr, "parse failed: %d\n", rc);
		return 2;
	}
	/*
	 * lfs.c never assigns fp_exclude_mdt (it sets fp_exclude_obd for both
	 * -m and -O), so the negated form of --mdt cannot be reached through
	 * the parser.  Set it here to exercise it.
	 */
	if (getenv("XMDT") != NULL)
		param.fp_exclude_mdt = 1;
	rc = llapi_find_device(argv[1], &param, NULL);
	lfs_find_parse_fini(&param);
	if (rc != 0)
		fprintf(stderr, "llapi_find_device: rc=%d\n", rc);
	return rc != 0 ? 1 : 0;
}
