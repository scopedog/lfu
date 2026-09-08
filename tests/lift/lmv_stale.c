/*
 * 68156 7e92da87 -- sw_lmv keeps a previous object's bytes.
 *
 * scan_lmv_to_user() clears only lmv_user_md_size(0, LMV_USER_MAGIC) of the
 * worker's one buffer, so for a striped directory the shard area past the
 * header is whatever the last object left there.  lum_stripe_count is the
 * real count, but the size returned is header-only, so a consumer that
 * sizes lum_objects[] from the count -- as lmv_dump_user_lmm() does -- reads
 * those bytes.
 *
 * The function is cut out of the tree by lift.py, not retyped.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <lustre/lustreapi.h>
#include "lustreapi_internal.h"

#include "lifted_lmv.inc"

#define SCAN_LMV_BUF 4096

static char sw_lmv[SCAN_LMV_BUF];
static int pass, fail;

static void arm(const char *what, int ok, const char *detail)
{
	if (ok) {
		printf("  PASS  %s\n", what);
		pass++;
	} else {
		printf("  FAIL  %s\n        %s\n", what, detail);
		fail++;
	}
}

/* trusted.lmv as the target holds it: little-endian lmv_mds_md_v1. */
static size_t disk_striped(void *buf, __u32 count)
{
	struct lmv_mds_md_v1 *md = buf;
	__u32 i;

	memset(buf, 0, sizeof(*md) + count * sizeof(struct lu_fid));
	md->lmv_magic = __cpu_to_le32(LMV_MAGIC_V1);
	md->lmv_stripe_count = __cpu_to_le32(count);
	md->lmv_master_mdt_index = 0;
	md->lmv_hash_type = __cpu_to_le32(LMV_HASH_TYPE_FNV_1A_64);
	for (i = 0; i < count; i++) {
		md->lmv_stripe_fids[i].f_seq = __cpu_to_le64(0x200000400 + i);
		md->lmv_stripe_fids[i].f_oid = __cpu_to_le32(i + 1);
	}
	return sizeof(*md) + count * sizeof(struct lu_fid);
}

/* trusted.lmv for a foreign directory: header plus an opaque value. */
static size_t disk_foreign(void *buf, size_t vlen, char fillc)
{
	struct lmv_foreign_md *lfm = buf;

	lfm->lfm_magic = __cpu_to_le32(LMV_MAGIC_FOREIGN);
	lfm->lfm_length = __cpu_to_le32(vlen);
	lfm->lfm_type = 0;
	lfm->lfm_flags = 0;
	memset(lfm->lfm_value, fillc, vlen);
	return offsetof(struct lmv_foreign_md, lfm_value) + vlen;
}

int main(void)
{
	char disk[SCAN_LMV_BUF];
	struct lmv_user_md *lmv = (void *)sw_lmv;
	const __u32 count = 4;
	unsigned int i, dirty;
	size_t dlen;
	__u32 out;
	char msg[256];

	printf("=== scan_lmv_to_user() into one reused worker buffer\n");

	/* object 1: a foreign directory with a big value */
	dlen = disk_foreign(disk, 2048, 'X');
	out = scan_lmv_to_user(disk, dlen, sw_lmv, sizeof(sw_lmv));
	snprintf(msg, sizeof(msg), "returned %u", out);
	arm("a foreign LMV converts", out == dlen, msg);

	/* object 2: a 4-stripe directory through the SAME buffer */
	dlen = disk_striped(disk, count);
	out = scan_lmv_to_user(disk, dlen, sw_lmv, sizeof(sw_lmv));

	snprintf(msg, sizeof(msg), "returned %u", out);
	arm("a striped LMV converts", out != 0, msg);

	snprintf(msg, sizeof(msg), "lum_stripe_count is %d, want %u",
		 lmv->lum_stripe_count, count);
	arm("lum_stripe_count is the real count",
	    (__u32)lmv->lum_stripe_count == count, msg);

	/*
	 * The disagreement: the record says 48 bytes while the count says
	 * lmv_user_md_size(4, SPECIFIC) == 144.  Reported, not judged --
	 * a scan has no shard FIDs to put there.
	 */
	printf("  NOTE  size answered %u, count implies %u\n",
	       out, lmv_user_md_size(count, LMV_USER_MAGIC_SPECIFIC));

	/* the defect: what a consumer sizing by the count actually reads */
	dirty = 0;
	for (i = 0; i < count; i++) {
		const unsigned char *p = (const void *)&lmv->lum_objects[i];
		unsigned int j;

		for (j = 0; j < sizeof(lmv->lum_objects[i]); j++)
			if (p[j] != 0)
				dirty++;
	}
	snprintf(msg, sizeof(msg),
		 "%u of %zu shard bytes still hold the previous object's LMV",
		 dirty, count * sizeof(lmv->lum_objects[0]));
	arm("the shard area a count-sized read touches is clear",
	    dirty == 0, msg);

	printf("=== %d pass, %d fail\n", pass, fail);
	return fail != 0;
}
