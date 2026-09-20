/*
 * Lift-and-compare: the real scan_classify() and scan_size() out of the
 * unfixed (8680c5570a) and fixed (r0920-tip) liblustreapi_scan_device.c,
 * side by side over the same inputs.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/stat.h>

#include <asm/byteorder.h>
#include <linux/lustre/lustre_fid.h>
#include <linux/lustre/lustre_idl.h>
#include <linux/lustre/lustre_user.h>
#include <lustre/lustreapi.h>

#include "lustreapi_scan_backend.h"

#include "f_old.inc"
#include "f_new.inc"

static const char *clsname(int c)
{
	static const char * const n[] = { "VISIBLE", "INTERNAL", "OST_OBJ",
					  "AGENT", "NO_LMA", "BAD", "ORPHAN" };
	return (c >= 0 && c < (int)(sizeof(n) / sizeof(n[0]))) ? n[c] : "?";
}

static int fails;

static void cls_case(const char *what, struct lustre_mdt_attrs *lma,
		     bool have_lma, int want_old, int want_new)
{
	int o = scan_classify_old(lma, have_lma);
	int n = scan_classify_new(lma, have_lma);
	bool ok = (o == want_old && n == want_new);

	if (!ok)
		fails++;
	printf("%-44s old=%-8s new=%-8s %s\n", what, clsname(o), clsname(n),
	       ok ? "ok" : "MISMATCH");
}

static void size_case(const char *what, __u16 mode, __u64 size, __u64 blocks,
		      bool has_lov, __u64 want_old_blk, __u64 want_new_blk)
{
	struct llapi_scan_obj obj;
	struct llapi_scan_rec ro, rn;

	memset(&obj, 0, sizeof(obj));
	memset(&ro, 0, sizeof(ro));
	memset(&rn, 0, sizeof(rn));
	obj.so_mode = mode;
	obj.so_size = size;
	obj.so_blocks = blocks;
	if (has_lov)
		obj.so_xa_present |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LOV);

	scan_size_old(&obj, LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS, &ro);
	scan_size_new(&obj, LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS, &rn);

	bool ok = ro.lfsr_stx.stx_blocks == want_old_blk &&
		  rn.lfsr_stx.stx_blocks == want_new_blk &&
		  ro.lfsr_stx.stx_size == rn.lfsr_stx.stx_size;
	if (!ok)
		fails++;
	printf("%-44s old_blocks=%-6llu new_blocks=%-6llu size=%llu %s\n",
	       what, (unsigned long long)ro.lfsr_stx.stx_blocks,
	       (unsigned long long)rn.lfsr_stx.stx_blocks,
	       (unsigned long long)rn.lfsr_stx.stx_size,
	       ok ? "ok" : "MISMATCH");
}

int main(void)
{
	struct lustre_mdt_attrs lma;
	char buf[sizeof(struct lustre_mdt_attrs)];
	struct llapi_scan_obj obj;

	/* the LMA is decoded already by the time scan_classify() sees it */
#define LMA_SET(compat, incompat, seq, oid)				\
	do {								\
		memset(&lma, 0, sizeof(lma));				\
		lma.lma_compat = (compat);				\
		lma.lma_incompat = (incompat);				\
		lma.lma_self_fid.f_seq = (seq);				\
		lma.lma_self_fid.f_oid = (oid);				\
	} while (0)

	(void)buf; (void)obj;

	printf("== scan_classify()\n");
	LMA_SET(0, 0, FID_SEQ_NORMAL + 4, 7);
	cls_case("ordinary file, no flags", &lma, true,
		 LLAPI_SCAN_CLS_VISIBLE, LLAPI_SCAN_CLS_VISIBLE);

	LMA_SET(0, LMAI_ORPHAN, FID_SEQ_NORMAL + 4, 7);
	cls_case("open-unlinked file in PENDING", &lma, true,
		 LLAPI_SCAN_CLS_VISIBLE, LLAPI_SCAN_CLS_ORPHAN);

	LMA_SET(0, LMAI_ORPHAN | LMAI_ENCRYPT, FID_SEQ_NORMAL + 4, 7);
	cls_case("encrypted volatile in PENDING", &lma, true,
		 LLAPI_SCAN_CLS_VISIBLE, LLAPI_SCAN_CLS_ORPHAN);

	/* LMAI_RELEASED is not in LMA_INCOMPAT_SUPP: BAD, before and after */
	LMA_SET(0, LMAI_ORPHAN | LMAI_RELEASED, FID_SEQ_NORMAL + 4, 7);
	cls_case("LMAI_RELEASED, an unsupported bit", &lma, true,
		 LLAPI_SCAN_CLS_BAD, LLAPI_SCAN_CLS_BAD);

	LMA_SET(0, LMAI_AGENT, FID_SEQ_NORMAL + 4, 7);
	cls_case("agent inode", &lma, true,
		 LLAPI_SCAN_CLS_AGENT, LLAPI_SCAN_CLS_AGENT);

	LMA_SET(0, LMAI_AGENT | LMAI_ORPHAN, FID_SEQ_NORMAL + 4, 7);
	cls_case("agent inode, also marked orphan", &lma, true,
		 LLAPI_SCAN_CLS_AGENT, LLAPI_SCAN_CLS_AGENT);

	LMA_SET(LMAC_NOT_IN_OI, LMAI_ORPHAN, FID_SEQ_NORMAL + 4, 7);
	cls_case("the OSD's own object, marked orphan", &lma, true,
		 LLAPI_SCAN_CLS_INTERNAL, LLAPI_SCAN_CLS_INTERNAL);

	LMA_SET(LMAC_FID_ON_OST, LMAI_ORPHAN, FID_SEQ_NORMAL + 4, 7);
	cls_case("OST data object, marked orphan", &lma, true,
		 LLAPI_SCAN_CLS_OST_OBJ, LLAPI_SCAN_CLS_OST_OBJ);

	LMA_SET(0, LMAI_ORPHAN, FID_SEQ_IDIF, 7);
	cls_case("IDIF object, marked orphan", &lma, true,
		 LLAPI_SCAN_CLS_OST_OBJ, LLAPI_SCAN_CLS_OST_OBJ);

	LMA_SET(0, LMAI_ORPHAN, FID_SEQ_ROOT, 1);
	cls_case("the root, marked orphan (cannot happen)", &lma, true,
		 LLAPI_SCAN_CLS_VISIBLE, LLAPI_SCAN_CLS_ORPHAN);

	LMA_SET(0, 0x1000 | LMAI_ORPHAN, FID_SEQ_NORMAL + 4, 7);
	cls_case("unknown incompat bit wins over orphan", &lma, true,
		 LLAPI_SCAN_CLS_BAD, LLAPI_SCAN_CLS_BAD);

	LMA_SET(0, 0, 0, 0);
	cls_case("no LMA", &lma, false,
		 LLAPI_SCAN_CLS_NO_LMA, LLAPI_SCAN_CLS_NO_LMA);

	printf("\n== scan_size(), no trusted.lov\n");
	size_case("regular file, no layout", S_IFREG | 0644, 4096, 8, false,
		  8, 0);
	size_case("regular file, empty, no layout", S_IFREG | 0644, 0, 0,
		  false, 0, 0);
	size_case("directory", S_IFDIR | 0755, 4096, 8, false, 8, 8);
	size_case("symlink", S_IFLNK | 0777, 12, 0, false, 0, 0);
	size_case("regular file with a layout", S_IFREG | 0644, 4096, 8, true,
		  0, 0);

	printf("\n%s\n", fails == 0 ? "ALL AS EXPECTED" : "SOME MISMATCHED");
	return fails != 0;
}

/*
 * Build:
 *   gcc -o harness classify-size-harness.c -D_GNU_SOURCE -Wall \
 *       -I <tree>/include -I <tree>/include/uapi -I <tree>/lustre/utils
 * with f_old.inc and f_new.inc beside it: scan_xattr(), scan_lov_released(),
 * scan_classify() and scan_size() lifted from liblustreapi_scan_device.c at
 * 8680c5570a (unfixed) and r0920-tip (fixed), each suffixed _old / _new.
 */
