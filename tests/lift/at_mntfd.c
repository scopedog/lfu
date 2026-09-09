/*
 * The three special cases of llapi_scan_fid()'s move to mnt_fd, lifted out
 * and run against a plain directory tree: the mount root itself, an object
 * directly under it, and a nested one.  Each is opened both ways -- the old
 * absolute path and the new openat(mnt_fd, rel) -- and the two must name the
 * same inode.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

static int fails;

static void one(int mnt_fd, const char *mnt, const char *rel_in)
{
	char rel[4096], path[4096];
	struct stat a, b;
	const char *at;
	char *rp, *slash;
	int p = -1, d = -1, op = -1, od = -1;
	int isdir;

	snprintf(rel, sizeof(rel), "%s", rel_in);
	rp = rel;
	while (*rp == '/')
		rp++;
	at = *rp != '\0' ? rp : ".";

	if (*rp == '\0')
		snprintf(path, sizeof(path), "%s", mnt);
	else
		snprintf(path, sizeof(path), "%s/%s", mnt, rp);

	/* the type, both ways */
	if (fstatat(mnt_fd, at, &a, AT_SYMLINK_NOFOLLOW) < 0) {
		printf("FAIL fstatat(%s): %s\n", at, strerror(errno));
		fails++;
		return;
	}
	if (lstat(path, &b) < 0) {
		printf("FAIL lstat(%s): %s\n", path, strerror(errno));
		fails++;
		return;
	}
	if (a.st_ino != b.st_ino) {
		printf("FAIL stat ino %s: %llu vs %llu\n", rel_in,
		       (unsigned long long)a.st_ino,
		       (unsigned long long)b.st_ino);
		fails++;
	}
	isdir = S_ISDIR(a.st_mode);

	if (isdir) {
		d = openat(mnt_fd, at, O_RDONLY | O_NDELAY | O_DIRECTORY);
		od = open(path, O_RDONLY | O_NDELAY | O_DIRECTORY);
		if (d < 0 || od < 0) {
			printf("FAIL open dir %s: %d/%d\n", rel_in, d, od);
			fails++;
			goto done;
		}
		fstat(d, &a); fstat(od, &b);
	} else {
		char *copy = strdup(path);

		slash = strrchr(rp, '/');
		if (slash == NULL) {
			p = openat(mnt_fd, ".",
				   O_RDONLY | O_NDELAY | O_DIRECTORY);
		} else {
			*slash = '\0';
			p = openat(mnt_fd, rp,
				   O_RDONLY | O_NDELAY | O_DIRECTORY);
			*slash = '/';
		}
		op = open(dirname(copy), O_RDONLY | O_NDELAY | O_DIRECTORY);
		free(copy);
		if (p < 0 || op < 0) {
			printf("FAIL open parent %s: %d/%d\n", rel_in, p, op);
			fails++;
			goto done;
		}
		fstat(p, &a); fstat(op, &b);
	}
	if (a.st_ino != b.st_ino) {
		printf("FAIL fd ino %s: %llu vs %llu\n", rel_in,
		       (unsigned long long)a.st_ino,
		       (unsigned long long)b.st_ino);
		fails++;
		goto done;
	}
	/* and rel must survive the in-place split */
	if (strcmp(rel, rel_in) != 0) {
		printf("FAIL rel clobbered: '%s' != '%s'\n", rel, rel_in);
		fails++;
		goto done;
	}
	printf("ok   %-20s %s\n", rel_in[0] ? rel_in : "(root)",
	       isdir ? "dir" : "parent");
done:
	if (p >= 0) close(p);
	if (d >= 0) close(d);
	if (op >= 0) close(op);
	if (od >= 0) close(od);
}

int main(int argc, char **argv)
{
	int mnt_fd;

	if (argc != 2) {
		fprintf(stderr, "usage: %s MOUNT\n", argv[0]);
		return 2;
	}
	mnt_fd = open(argv[1], O_RDONLY | O_DIRECTORY);
	if (mnt_fd < 0) {
		perror("open mount");
		return 2;
	}
	one(mnt_fd, argv[1], "/");	/* fid2path's answer for the root */
	one(mnt_fd, argv[1], "");	/* already stripped */
	one(mnt_fd, argv[1], "top");	/* directly under the mount */
	one(mnt_fd, argv[1], "d");	/* a directory under it */
	one(mnt_fd, argv[1], "d/sub");	/* a nested directory */
	one(mnt_fd, argv[1], "d/sub/f2");	/* a nested file */
	close(mnt_fd);
	printf("%s\n", fails ? "FAILURES" : "all cases agree");
	return fails != 0;
}
