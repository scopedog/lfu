#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <lustre/lustreapi.h>

static int find_cl_oldest(const char *mdtname, __u64 *oldest)
{
	(void)mdtname;
	*oldest = 0;
	return 0;
}

static int find_cookie_check(const char *fsname, const char *cookie,
			     const int *mdts, int mdt_count,
			     const __u64 *starts, __u64 *reached);

/* run B's pre-pass probe in the window between run A's write and rename */
static const char *hook_cookie;
static int hook_rename(const char *a, const char *b)
{
	if (hook_cookie != NULL) {
		const char *ck = hook_cookie;

		hook_cookie = NULL;
		printf("  B probes while A holds '%s'\n", a);
		find_cookie_check("lustre", ck, NULL, 0, NULL, NULL);
	}
	return (rename)(a, b);
}
#define rename(a, b) hook_rename(a, b)

#include "lifted.c"

int main(int argc, char **argv)
{
	const char *ck = argv[1];
	__u64 seen[1];
	char buf[512] = "";
	FILE *fp;
	int rc;

	unlink(ck);
	seen[0] = 42;
	rc = find_cookie_write(ck, "lustre", "/mnt/lustre", seen, 1);
	printf("  first write rc=%d\n", rc);

	seen[0] = 43;
	hook_cookie = ck;
	rc = find_cookie_write(ck, "lustre", "/mnt/lustre", seen, 1);
	printf("  A's write rc=%d\n", rc);

	fp = fopen(ck, "r");
	if (fp != NULL) {
		size_t n = fread(buf, 1, sizeof(buf) - 1, fp);

		buf[n] = '\0';
		fclose(fp);
	}
	printf("  cookie now: %s", buf[0] ? buf : "(empty)\n");
	return !(rc == 0 && strstr(buf, "lustre-MDT0000 43") != NULL);
}
