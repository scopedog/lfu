/*
 * Does llapi_scan_namespace() work on a tree that is not Lustre?
 *
 * The test harness refuses one (llapi_test_utils.c gates on
 * llapi_search_mounts), and lfs find plainly does work off Lustre -- so the
 * question is what the LIBRARY does, and which sr_valid bits come back, which
 * neither of those answers.  Print one line per object: what was gathered,
 * and what was not.
 *
 *   cc -o probe probe.c -llustreapi && ./probe /tmp/ptree
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>

static const struct {
	unsigned long long bit;
	const char *name;
} bits[] = {
	{ LLAPI_SCAN_FID,	"FID" },
	{ LLAPI_SCAN_TYPE,	"TYPE" },
	{ LLAPI_SCAN_MODE,	"MODE" },
	{ LLAPI_SCAN_NLINK,	"NLINK" },
	{ LLAPI_SCAN_UID,	"UID" },
	{ LLAPI_SCAN_GID,	"GID" },
	{ LLAPI_SCAN_SIZE,	"SIZE" },
	{ LLAPI_SCAN_BLOCKS,	"BLOCKS" },
	{ LLAPI_SCAN_ATIME,	"ATIME" },
	{ LLAPI_SCAN_MTIME,	"MTIME" },
	{ LLAPI_SCAN_CTIME,	"CTIME" },
	{ LLAPI_SCAN_BTIME,	"BTIME" },
	{ LLAPI_SCAN_ATTRS,	"ATTRS" },
	{ LLAPI_SCAN_LAYOUT,	"LAYOUT" },
	{ LLAPI_SCAN_MDT_INDEX,	"MDT_INDEX" },
	{ LLAPI_SCAN_LMV,	"LMV" },
	{ LLAPI_SCAN_PROJID,	"PROJID" },
	{ LLAPI_SCAN_HSM,	"HSM" },
	{ 0, NULL }
};

static unsigned long long seen_all = ~0ULL;
static unsigned long long seen_any;
static unsigned long objects;

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	char have[512] = "";
	int i;

	for (i = 0; bits[i].name != NULL; i++) {
		if (!(rec->sr_valid & bits[i].bit))
			continue;
		if (have[0] != '\0')
			strncat(have, ",", sizeof(have) - strlen(have) - 1);
		strncat(have, bits[i].name, sizeof(have) - strlen(have) - 1);
	}

	printf("%-28s mode=%06o size=%-8llu uid=%-6u fid="DFID"\n"
	       "    valid=0x%llx [%s]\n",
	       rec->sr_path ? rec->sr_path : "(no path)",
	       rec->sr_mode, (unsigned long long)rec->sr_size_bytes,
	       rec->sr_uid, PFID(&rec->sr_fid),
	       (unsigned long long)rec->sr_valid, have);

	objects++;
	seen_all &= rec->sr_valid;
	seen_any |= rec->sr_valid;
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .sp_size = sizeof(sp) };
	int rc;

	if (argc != 2) {
		fprintf(stderr, "usage: %s DIR\n", argv[0]);
		return 2;
	}

	llapi_msg_set_level(LLAPI_MSG_ERROR);
	rc = llapi_scan_namespace(argv[1], &sp, cb, NULL);
	printf("\nllapi_scan_namespace(%s) = %d (%s), %lu objects\n",
	       argv[1], rc, rc ? strerror(-rc) : "ok", objects);
	if (objects > 0)
		printf("every object had 0x%llx; some object had 0x%llx\n",
		       (unsigned long long)seen_all,
		       (unsigned long long)seen_any);
	return rc ? 1 : 0;
}
