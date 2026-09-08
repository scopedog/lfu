/*
 * 68156 4d552522 -- the hand-written root test ignored f_ver.
 *
 * fid_is_namespace_visible() reaches the root through fid_is_root(), which
 * is lu_fid_eq() against LU_ROOT_FID -- a memcmp of the whole struct, f_ver
 * included.  scan_classify() compared f_seq and f_oid only, so a FID in
 * FID_SEQ_ROOT with FID_OID_ROOT and a non-zero f_ver was called
 * namespace-visible where the MDT would not.
 *
 * scan_classify() is cut out of the tree by lift_root.py, not retyped.
 */
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <lustre/lustreapi.h>
#include <linux/lustre/lustre_fid.h>
#include "lustreapi_internal.h"

#include "lifted_root.inc"

static int pass, fail;

static void arm(const char *what, int got, int want)
{
	if (got == want) {
		printf("  PASS  %s (%d)\n", what, got);
		pass++;
	} else {
		printf("  FAIL  %s: got %d, want %d\n", what, got, want);
		fail++;
	}
}

static enum llapi_scan_class cls(__u64 seq, __u32 oid, __u32 ver)
{
	struct lustre_mdt_attrs lma;

	memset(&lma, 0, sizeof(lma));
	lma.lma_self_fid.f_seq = seq;
	lma.lma_self_fid.f_oid = oid;
	lma.lma_self_fid.f_ver = ver;
	return scan_classify(&lma, true);
}

int main(void)
{
	printf("=== scan_classify() on the root FID\n");

	arm("the root itself is visible",
	    cls(FID_SEQ_ROOT, FID_OID_ROOT, 0), LLAPI_SCAN_CLS_VISIBLE);

	/* the drift: fid_is_root() is a whole-struct compare */
	arm("the root FID with f_ver set is not the root",
	    cls(FID_SEQ_ROOT, FID_OID_ROOT, 1), LLAPI_SCAN_CLS_INTERNAL);

	/* the case the spelled-out test exists for, unchanged */
	arm("the echo client's root stays internal",
	    cls(FID_SEQ_ROOT, FID_OID_ECHO_ROOT, 0), LLAPI_SCAN_CLS_INTERNAL);

	arm("a normal FID is visible",
	    cls(FID_SEQ_NORMAL + 1, 5, 0), LLAPI_SCAN_CLS_VISIBLE);

	printf("=== %d pass, %d fail\n", pass, fail);
	return fail != 0;
}
