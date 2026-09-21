/*
 * Round 21 lab: print what a namespace scan actually answered for, per
 * object.  lfs find reads lmd_stx directly, so nothing it prints can show
 * whether LLAPI_SCAN_ATTRS was set; this does.
 *
 * usage: scanrec DIR
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lustre/lustreapi.h>

static int cb(const struct llapi_scan_rec *rec, void *data)
{
	printf("%-28s attrs=%-3s stx_attributes=%#llx attrs_mask=%#llx size=%-7s blocks=%-7s sz=%llu blk=%llu\n",
	       rec->lfsr_name ? rec->lfsr_name : "(noname)",
	       (rec->lfsr_valid & LLAPI_SCAN_ATTRS) ? "yes" : "no",
	       (unsigned long long)rec->lfsr_stx.stx_attributes,
	       (unsigned long long)rec->lfsr_stx.stx_attributes_mask,
	       (rec->lfsr_stx.stx_mask & STATX_SIZE) ? "known" : "unknown",
	       (rec->lfsr_stx.stx_mask & STATX_BLOCKS) ? "known" : "unknown",
	       (unsigned long long)rec->lfsr_stx.stx_size,
	       (unsigned long long)rec->lfsr_stx.stx_blocks);
	return 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	int rc;

	if (argc < 2) {
		fprintf(stderr, "usage: %s DIR\n", argv[0]);
		return 2;
	}
	/* lfsp_want 0 is the scanner's own default: everything it answers */
	rc = llapi_scan_namespace(argv[1], &sp, cb, NULL);
	if (rc < 0) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(-rc));
		return 1;
	}
	return 0;
}
