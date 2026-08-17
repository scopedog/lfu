/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * lfind — one command over the three scanner backends.
 *
 * The backends are separate binaries for a build reason, not a user-facing one:
 * a host that has only libext2fs, or only libzpool, must still be able to build
 * the backend it can (the MDS build hosts lack ZFS headers; a workstation may
 * lack libext2fs).  That is a packaging constraint and users should not have to
 * care about it, so this front-end picks the backend from the target and execs
 * it, passing every other argument through untouched.
 *
 *   lfind [options] [filters] <target>
 *
 *     a block device or a regular file   -> lfind-ldiskfs   (unmounted / image)
 *     pool/dataset[@snapshot]            -> lfind-zfs       (unmounted / snap)
 *     a character device                 -> lfind-kmdt      (a mounted, serving
 *                                                            target via lfu_ring)
 *
 * Why classify by what the target *is* rather than by a required flag: each
 * backend already takes a different kind of name, and those kinds are
 * distinguishable without ambiguity.  A ZFS dataset spec is the only one that is
 * not a filesystem path, which is exactly what tells it apart.
 *
 * This deliberately does NOT parse the filter vocabulary.  Duplicating that
 * table here would mean two places to update every time a predicate is added,
 * and the duplicate would drift.  Instead the target is found by scanning
 * arguments from the right, in two passes: first for one that really is a
 * device, an image or a stream, and only then for one merely *shaped* like a
 * dataset spec.  Predicate values (`+1G`, `report*`, `fast`, `1999`) match
 * neither, so they are skipped without this code knowing what they are, and that
 * ordering is what stops `lfind <image> --name a/b` dispatching on the pattern:
 * a slashed pattern that does not exist looks exactly like a dataset.  Found
 * while testing.  `--backend NAME` overrides the whole business.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum lfind_backend {
	LFIND_UNKNOWN = 0,
	LFIND_LDISKFS,
	LFIND_ZFS,
	LFIND_KMDT,
};

static const char *const lfind_backend_bin[] = {
	NULL, "lfind-ldiskfs", "lfind-zfs", "lfind-kmdt",
};

static const char *const lfind_backend_name[] = {
	NULL, "ldiskfs", "zfs", "kmdt",
};

/*
 * What kind of target is this?  Cheap and side-effect free: one stat().
 *
 * A regular file counts as ldiskfs because a loop-backed image is a normal way
 * to hold a test MDT, and mkfs.lustre writes one happily.
 */
static enum lfind_backend lfind_classify_path(const char *arg)
{
	struct stat st;

	if (arg == NULL || *arg == '\0' || stat(arg, &st) != 0)
		return LFIND_UNKNOWN;

	if (S_ISBLK(st.st_mode) || S_ISREG(st.st_mode))
		return LFIND_LDISKFS;
	if (S_ISCHR(st.st_mode))
		return LFIND_KMDT;
	return LFIND_UNKNOWN;		/* a directory is not a target */
}

/*
 * A ZFS dataset is pool/dataset[@snap]: it has a slash, does not start with
 * one, and has no whitespace.  Requiring the slash keeps a bare pool name from
 * swallowing a --pool argument.
 *
 * Only consulted after every argument has been tried as a real path, because
 * "looks like a dataset" is a guess where "is a block device" is a fact.
 */
static enum lfind_backend lfind_classify_dataset(const char *arg)
{
	const char *slash;

	if (arg == NULL || *arg == '\0')
		return LFIND_UNKNOWN;

	slash = strchr(arg, '/');
	if (*arg != '/' && slash != NULL && slash != arg &&
	    strpbrk(arg, " \t") == NULL)
		return LFIND_ZFS;

	return LFIND_UNKNOWN;
}

static void lfind_usage(const char *prog)
{
	fprintf(stderr,
"Usage: %s [options] [filters] <target>\n"
"\n"
"Scan a Lustre target and report one record per namespace-visible object.\n"
"The backend is chosen from the target:\n"
"\n"
"  /dev/sdb, /path/to/mdt.img   an unmounted ldiskfs target, or an image\n"
"  pool/dataset[@snapshot]      an unmounted ZFS target, or a snapshot\n"
"  /dev/lfu_scan                a MOUNTED, serving target, through lfu_ring\n"
"\n"
"      --backend ldiskfs|zfs|kmdt   choose it explicitly instead\n"
"      --list-backends              which backends this install has\n"
"\n"
"Every other argument is passed to the backend unchanged; run\n"
"`%s --backend ldiskfs --help` for the options and the filter vocabulary.\n"
"\n"
"Note this is not `lfs find`: it reads a target directly on the server rather\n"
"than walking the namespace from a client, so an MDT-only scan has `lfs find\n"
"--lazy` semantics, and a size filter can answer `unknown` as well as yes and\n"
"no -- for a striped file with no trusted.som yet.  See lfind(8).\n",
		prog, prog);
}

/*
 * Where the backends are.  Next to this binary first, so the build tree works
 * without installing, then $LFIND_LIBEXEC, then whatever PATH says.
 */
static char *lfind_locate(const char *self, const char *bin)
{
	char *dir_copy, *dir, *path;
	const char *env;

	if (self != NULL && strchr(self, '/') != NULL) {
		dir_copy = strdup(self);
		if (dir_copy == NULL)
			return NULL;
		dir = dirname(dir_copy);
		if (asprintf(&path, "%s/%s", dir, bin) < 0)
			path = NULL;
		free(dir_copy);
		if (path != NULL && access(path, X_OK) == 0)
			return path;
		free(path);
	}

	env = getenv("LFIND_LIBEXEC");
	if (env != NULL && *env != '\0') {
		if (asprintf(&path, "%s/%s", env, bin) < 0)
			path = NULL;
		if (path != NULL && access(path, X_OK) == 0)
			return path;
		free(path);
	}

	return strdup(bin);	/* let execvp search PATH */
}

static void lfind_list_backends(const char *self)
{
	int i;

	for (i = LFIND_LDISKFS; i <= LFIND_KMDT; i++) {
		char *p = lfind_locate(self, lfind_backend_bin[i]);
		int have = p != NULL &&
			   (strchr(p, '/') != NULL ? access(p, X_OK) == 0 : 1);

		printf("%-8s %-16s %s\n", lfind_backend_name[i],
		       lfind_backend_bin[i],
		       have ? (strchr(p, '/') ? p : "(on PATH)") : "not built");
		free(p);
	}
}

int main(int argc, char **argv)
{
	enum lfind_backend want = LFIND_UNKNOWN;
	char **pass;
	char *bin;
	int i, j, n = 0;

	/*
	 * --backend and --list-backends are ours; everything else belongs to
	 * the backend.  Consume ours out of the argument list so the backend
	 * never sees an option it would reject.
	 */
	pass = calloc(argc + 2, sizeof(*pass));
	if (pass == NULL)
		return 1;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--list-backends") == 0) {
			lfind_list_backends(argv[0]);
			free(pass);
			return 0;
		}
		if (strcmp(argv[i], "--backend") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr,
					"lfind: --backend needs a name\n");
				free(pass);
				return 2;
			}
			for (j = LFIND_LDISKFS; j <= LFIND_KMDT; j++)
				if (strcmp(argv[i + 1],
					   lfind_backend_name[j]) == 0)
					want = j;
			if (want == LFIND_UNKNOWN) {
				fprintf(stderr,
					"lfind: unknown backend '%s' (ldiskfs, zfs, kmdt)\n",
					argv[i + 1]);
				free(pass);
				return 2;
			}
			i++;		/* also skip its value */
			continue;
		}
		if (strncmp(argv[i], "--backend=", 10) == 0) {
			for (j = LFIND_LDISKFS; j <= LFIND_KMDT; j++)
				if (strcmp(argv[i] + 10,
					   lfind_backend_name[j]) == 0)
					want = j;
			if (want == LFIND_UNKNOWN) {
				fprintf(stderr,
					"lfind: unknown backend '%s' (ldiskfs, zfs, kmdt)\n",
					argv[i] + 10);
				free(pass);
				return 2;
			}
			continue;
		}
		pass[n++] = argv[i];
	}

	if (n == 0 && want == LFIND_UNKNOWN) {
		lfind_usage(argv[0]);
		free(pass);
		return 2;
	}

	/*
	 * Find the target by scanning from the right for the first argument
	 * that classifies.  A predicate's value does not classify, so it is
	 * skipped without this code having to know the filter vocabulary.
	 */
	if (want == LFIND_UNKNOWN) {
		/* pass 1: something that really is a device, image or stream */
		for (i = n - 1; i >= 0 && want == LFIND_UNKNOWN; i--)
			want = lfind_classify_path(pass[i]);
		/* pass 2: only then, something merely shaped like a dataset */
		for (i = n - 1; i >= 0 && want == LFIND_UNKNOWN; i--)
			want = lfind_classify_dataset(pass[i]);
	}

	if (want == LFIND_UNKNOWN) {
		/* --help and friends have no target and that is not an error */
		for (i = 0; i < n; i++)
			if (strcmp(pass[i], "-h") == 0 ||
			    strcmp(pass[i], "--help") == 0) {
				lfind_usage(argv[0]);
				free(pass);
				return 0;
			}
		fprintf(stderr,
			"lfind: cannot tell what kind of target '%s' is.\n"
			"       A block device or image is ldiskfs, pool/dataset is ZFS,\n"
			"       and a character device is a mounted target via lfu_ring.\n"
			"       Use --backend ldiskfs|zfs|kmdt to say which.\n",
			n > 0 ? pass[n - 1] : "");
		free(pass);
		return 2;
	}

	bin = lfind_locate(argv[0], lfind_backend_bin[want]);
	if (bin == NULL) {
		fprintf(stderr, "lfind: out of memory\n");
		free(pass);
		return 1;
	}

	/*
	 * argv[0] for the backend is "lfind", not the backend's own name: the
	 * backends build their usage line from argv[0], and a user who typed
	 * lfind should be told about lfind.  Running a backend directly still
	 * shows its own name, because then argv[0] is its own name.
	 */
	memmove(&pass[1], &pass[0], (size_t)n * sizeof(*pass));
	pass[0] = (char *)"lfind";
	pass[n + 1] = NULL;

	execvp(bin, pass);

	fprintf(stderr, "lfind: cannot run %s: %s%s\n", bin, strerror(errno),
		errno == ENOENT ?
		" — that backend is not built or installed (try --list-backends)" :
		"");
	free(bin);
	free(pass);
	return 127;
}
