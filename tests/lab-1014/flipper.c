// 10-14 lab: rename directory a to b and make a FILE at a, back to back in
// one process, so a lookup of a/sub/f in between meets ENOTDIR.
// Usage: flipper <dir> -- runs until killed.
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv)
{
	char a[4096], b[4096];
	int fd;

	snprintf(a, sizeof(a), "%s/a", argv[1]);
	snprintf(b, sizeof(b), "%s/b", argv[1]);
	for (;;) {
		if (rename(a, b) < 0)
			continue;
		fd = open(a, O_CREAT | O_WRONLY, 0644);
		if (fd >= 0)
			close(fd);
		unlink(a);
		rename(b, a);
	}
}
