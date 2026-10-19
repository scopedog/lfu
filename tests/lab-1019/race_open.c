/* LD_PRELOAD shim: on the first open() of $RACE_PATH, move $RACE_PATH to
 * $RACE_BACKUP (if set) and rename $RACE_FROM over $RACE_PATH, then open.
 * Forces the rename between llapi_scan_fid()'s getinfo and the gather's
 * reopen by name.  The trigger is reported on stderr.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

static int fired;

static void race(const char *path)
{
	const char *p = getenv("RACE_PATH");
	const char *from = getenv("RACE_FROM");
	const char *bak = getenv("RACE_BACKUP");

	/* armed by the harness just before llapi_scan_fid() */
	if (fired || getenv("RACE_ARM") == NULL || p == NULL || from == NULL ||
	    strcmp(path, p) != 0)
		return;
	fired = 1;
	if (bak != NULL && rename(p, bak) != 0)
		perror("race: rename to backup");
	if (rename(from, p) != 0)
		perror("race: rename over");
	fprintf(stderr, "race: fired on open(%s)%s\n", path,
		bak ? " with backup" : "");
}

#define SHIM(name)							\
int name(const char *path, int flags, ...)				\
{									\
	static int (*real)(const char *, int, ...);			\
	mode_t mode = 0;						\
	va_list ap;							\
									\
	if (real == NULL)						\
		real = dlsym(RTLD_NEXT, #name);				\
	if (flags & (O_CREAT | O_TMPFILE)) {				\
		va_start(ap, flags);					\
		mode = va_arg(ap, mode_t);				\
		va_end(ap);						\
	}								\
	race(path);							\
	return real(path, flags, mode);					\
}
SHIM(open)
SHIM(open64)

int __open_2(const char *path, int flags)
{
	return open(path, flags);
}

int __open64_2(const char *path, int flags)
{
	return open64(path, flags);
}
