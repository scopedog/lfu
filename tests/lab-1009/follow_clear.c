/*
 * 10-09 lab: llapi_scan_changelog() with _FOLLOW|_CLEAR, event mode.
 * Usage: follow_clear <mdtname> <user>.  Prints the return value; the lab
 * deregisters <user> mid-stream so every clear after that fails.
 */
#include <stdio.h>
#include <stdlib.h>
#include <lustre/lustreapi.h>

static unsigned long n;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	if (++n % 500 == 0)
		fprintf(stderr, "%lu records\n", n);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_changelog_param sc = { 0 };
	int rc;

	if (argc != 3)
		return 2;
	sc.sc_size = sizeof(sc);
	sc.sc_mdtname = argv[1];
	sc.sc_user = argv[2];
	sc.sc_flags = LLAPI_SCAN_CL_F_FOLLOW | LLAPI_SCAN_CL_F_CLEAR;
	rc = llapi_scan_changelog(&sc, cb, NULL);
	printf("RETURNED rc=%d after %lu records\n", rc, n);
	return 0;
}
