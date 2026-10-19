#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <linux/lustre/lustre_idl.h>
#include <linux/lustre/lustre_ostid.h>
#include "lustreapi_scan_backend.h"
struct scan_dev { struct llapi_scan_tgt sd_tgt_info; };
#include "lifted.h"
/* the OSD: osd_check_lma() takes an old LMA (index 0) as the FID built with
 * the real index, as fid_to_ostid() + ostid_to_fid(idx) give */
static struct lu_fid osd(const struct scan_dev *d, struct lu_fid f)
{
	struct ost_id oi; struct lu_fid t;
	__u32 idx = d->sd_tgt_info.tt_index;
	if (!(d->sd_tgt_info.tt_flags & LLAPI_SCAN_TGT_OST) ||
	    !fid_is_idif(&f) || idx == 0 || fid_idif_ost_idx(&f) != 0)
		return f;
	memset(&oi, 0, sizeof(oi));
	t = f;
	if (fid_to_ostid(&f, &oi) != 0 || ostid_to_fid(&t, &oi, idx) != 0)
		return f;	/* no such IDIF: the OSD answers -EREMCHG */
	return t;
}
int main(void)
{
	struct { const char *what; __u32 fl; __u32 idx; struct lu_fid f; } c[] = {
	{ "OST0003 IDIF idx0",          1|4, 3, { 0x100000000ULL, 0x1234, 0 } },
	{ "OST0003 IDIF idx0 oid>2^32", 1|4, 3, { 0x100000001ULL, 0x5, 0 } },
		{ "OST0003 IDIF idx3 (new)",    1|4, 3, { 0x100030000ULL, 0x1234, 0 } },
	{ "OST0000 IDIF idx0",          1|4, 0, { 0x100000000ULL, 0x1234, 0 } },
	{ "OST00ff IDIF idx0",          1|4, 0xff, { 0x100000000ULL, 0x99, 0 } },
	{ "OST0003 FID-on-OST",         1|4, 3, { 0x2c0000401ULL, 0x10, 0 } },
	{ "OST, no index in label",     1,   3, { 0x100000000ULL, 0x1234, 0 } },
	{ "MDT0003 IDIF idx0",          2|4, 3, { 0x100000000ULL, 0x1234, 0 } },
	};
	int i, bad_old = 0, bad_new = 0;
	for (i = 0; i < (int)(sizeof(c)/sizeof(c[0])); i++) {
		struct scan_dev d = { 0 };
		struct lu_fid o = c[i].f, n = c[i].f, w;
		d.sd_tgt_info.tt_flags = (c[i].fl & 1 ? LLAPI_SCAN_TGT_OST : 0) | (c[i].fl & 2 ? LLAPI_SCAN_TGT_MDT : 0) | (c[i].fl & 4 ? LLAPI_SCAN_TGT_INDEX : 0);
		d.sd_tgt_info.tt_index = c[i].idx;
		scan_idif_set_index(&d, &n);
		w = osd(&d, c[i].f);
		bad_old += !lu_fid_eq(&o, &w); bad_new += !lu_fid_eq(&n, &w);
		printf("%-28s old " DFID " %s  new " DFID " %s  osd " DFID "\n", c[i].what,
		       PFID(&o), lu_fid_eq(&o,&w)?"ok  ":"DIFF", PFID(&n), lu_fid_eq(&n,&w)?"ok  ":"DIFF", PFID(&w));
	}
	printf("old differs from the OSD on %d, new on %d\n", bad_old, bad_new);
	return bad_new != 0;
}
