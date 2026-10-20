/* Drives the lifted find_cookie_check() over scripted changelog reads. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef unsigned long long __u64;
#define MAX_OBD_NAME 128
#define FIND_COOKIE_NONE (~0ULL)
#define LLAPI_MSG_ERROR 1
#define LLAPI_MSG_WARN 2
#define LLAPI_MSG_NO_ERRNO 0x100

static void llapi_error(int lvl, int rc, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	fprintf(stdout, "    %s(%d): ", (lvl & 3) == LLAPI_MSG_WARN ?
		"WARN" : "ERROR", rc);
	vfprintf(stdout, fmt, ap);
	fputc('\n', stdout);
	va_end(ap);
}

/* the scripted reads: answer[n] for the n-th call */
static __u64 answer[8];
static int nreads;

static int find_cl_first(const char *mdtname, __u64 startrec, __u64 *first)
{
	*first = answer[nreads];
	printf("    read %d from %llu -> %llu\n", nreads + 1, startrec, *first);
	nreads++;
	return 0;
}

static int find_cookie_tmp(const char *file, char *tmp, size_t len)
{
	snprintf(tmp, len, "%s.probe", file);
	return open(tmp, O_CREAT | O_WRONLY | O_TRUNC, 0600);
}

static bool find_cookie_may_replace(const char *cookie, const struct stat *st)
{
	return true;
}

#include "lifted.c"

int main(int argc, char **argv)
{
	static const struct {
		const char *what;
		__u64 anchor;
		__u64 reads[3];
	} c[] = {
		{ "RACE: 101..105 written+cleared between reads 2 and 3",
		  100, { 95, 0, 106 } },
		{ "control: cleared to empty between reads", 100, { 95, 0, 0 } },
		{ "control: cleared, oldest is anchor+1", 100, { 95, 0, 101 } },
		{ "control: restarted log (oldest 5)", 100, { 5, 0, 5 } },
		{ "edge: restarted log grew to the anchor", 100, { 5, 0, 100 } },
		{ "control: purged before read 1", 100, { 150, 0, 0 } },
		{ "control: anchor 0, log now starts at 7 (WARN)", 0, { 7, 0, 0 } },
	};
	const char *cookie = argv[1];
	int mdts[1] = { 0 };
	__u64 starts[1], reached[1];
	unsigned int i;

	for (i = 0; i < sizeof(c) / sizeof(c[0]); i++) {
		int rc;

		memcpy(answer, c[i].reads, sizeof(c[i].reads));
		nreads = 0;
		starts[0] = c[i].anchor;
		printf("[%u] %s, anchor %llu\n", i + 1, c[i].what, c[i].anchor);
		rc = find_cookie_check("lfsh", cookie, mdts, 1, starts,
				       reached);
		printf("  => rc %d (%s)\n", rc, rc == 0 ? "continues" :
		       strerror(-rc));
	}
	return 0;
}
