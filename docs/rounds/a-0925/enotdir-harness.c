#define _GNU_SOURCE
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdlib.h>
static int run(int mnt_fd, const char *at)
{
	int d, rc = 0;
	struct statx stx;
	statx(mnt_fd, at, 0, STATX_TYPE, &stx);          /* the statx: a directory */
	if (!S_ISDIR(stx.stx_mode)) return 1000;
	unlinkat(mnt_fd, at, AT_REMOVEDIR);               /* replaced underneath */
	close(openat(mnt_fd, at, O_CREAT | O_WRONLY, 0644));
#include ARM
		}
	return 0;
out:
	return rc;
}
int main(void)
{
	char t[] = "/tmp/enotdirXXXXXX";
	int m = open(mkdtemp(t), O_RDONLY | O_DIRECTORY);
	mkdirat(m, "d", 0755);
	int rc = run(m, "d");
	printf("rc=%d (%s)\n", rc, strerror(-rc));
	unlinkat(m, "d", 0); rmdir(t);
	return 0;
}
