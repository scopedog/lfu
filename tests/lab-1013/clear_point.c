/*
 * 10-10 lab: llapi_scan_changelog() with _CLEAR from record 0, event mode.
 * Usage: clear_point <mdtname> <user> [follow].  Prints the return value.
 */
#include <stdio.h>
#include <string.h>
#include <lustre/lustreapi.h>

static unsigned long n;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	n++;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc = { 0 };
	int rc;

	if (argc < 3)
		return 2;
	sc.sc_size = sizeof(sc);
	sc.sc_mdtname = argv[1];
	sc.sc_user = argv[2];
	sc.sc_flags = LLAPI_SCAN_CL_F_CLEAR;
	if (argc > 3 && strcmp(argv[3], "follow") == 0)
		sc.sc_flags |= LLAPI_SCAN_CL_F_FOLLOW;
	rc = llapi_scan_changelog(&sc, cb, NULL);
	printf("RETURNED rc=%d after %lu records\n", rc, n);
	return 0;
}
