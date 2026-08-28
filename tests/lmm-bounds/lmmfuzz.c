/* Feed find_lmm_fits() the buffers a torn on-disk EA can produce. */
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <stddef.h>
#include <byteswap.h>
#include <linux/lustre/lustre_user.h>
#define __swab32 bswap_32
#define __swab16 bswap_16


#include "flf_body.inc"

static char buf[8192];
static int fails;

static void check(const char *what, __u32 size, bool expect)
{
	bool got = find_lmm_fits((struct lov_user_md *)buf, size);
	const char *verdict = got == expect ? "ok" : "*** WRONG ***";
	if (got != expect) fails++;
	printf("  %-52s %-8s %s\n", what, got ? "accept" : "REJECT", verdict);
}

int main(void)
{
	struct lov_comp_md_v1 *c = (void *)buf;
	struct lov_user_md_v1 *v1 = (void *)buf;
	__u32 sz;

	printf("host-order composite:\n");
	memset(buf, 0, sizeof(buf));
	sz = sizeof(*c) + 2 * sizeof(c->lcm_entries[0]) + 2 * sizeof(*v1);
	c->lcm_magic = LOV_USER_MAGIC_COMP_V1;
	c->lcm_size = sz;
	c->lcm_entry_count = 2;
	c->lcm_entries[0].lcme_offset = sizeof(*c) + 2*sizeof(c->lcm_entries[0]);
	c->lcm_entries[0].lcme_size = sizeof(*v1);
	c->lcm_entries[1].lcme_offset = c->lcm_entries[0].lcme_offset + sizeof(*v1);
	c->lcm_entries[1].lcme_size = sizeof(*v1);
	check("well-formed 2-entry composite", sz, true);

	c->lcm_entry_count = 65535;
	check("lcm_entry_count = 65535 (the OOB-write case)", sz, false);

	c->lcm_entry_count = 2;
	c->lcm_entries[1].lcme_offset = 0xfffff000;
	check("lcme_offset = 0xfffff000 (arbitrary store target)", sz, false);

	c->lcm_entries[1].lcme_offset = sz;
	c->lcm_entries[1].lcme_size = 0;
	check("lcme_offset == size, lcme_size 0 (48-byte over-read)", sz, false);

	c->lcm_entries[1].lcme_offset = sz - 4;
	check("offset leaves < sizeof(lov_user_md_v1) in the buffer", sz, false);

	c->lcm_entries[1].lcme_offset = 0;
	c->lcm_entries[1].lcme_size = 0;
	check("uninstantiated component: offset 0, size 0 (VALID)", sz, true);

	c->lcm_entries[1].lcme_offset = c->lcm_entries[0].lcme_offset + sizeof(*v1);
	c->lcm_entries[1].lcme_size = sizeof(*v1);
	c->lcm_size = sz + 1;
	check("lcm_size larger than the buffer", sz, false);
	c->lcm_size = sz;

	printf("byte-swapped composite (what the swab would have walked):\n");
	memset(buf, 0, sizeof(buf));
	c->lcm_magic = __swab32(LOV_USER_MAGIC_COMP_V1);
	c->lcm_size = __swab32(sz);
	c->lcm_entry_count = __swab16(2);
	c->lcm_entries[0].lcme_offset = __swab32(sizeof(*c) + 2*sizeof(c->lcm_entries[0]));
	c->lcm_entries[0].lcme_size = __swab32(sizeof(*v1));
	c->lcm_entries[1].lcme_offset = __swab32(sizeof(*c) + 2*sizeof(c->lcm_entries[0]) + sizeof(*v1));
	c->lcm_entries[1].lcme_size = __swab32(sizeof(*v1));
	check("well-formed, swapped", sz, true);

	c->lcm_entry_count = __swab16(65535);
	check("swapped lcm_entry_count = 65535", sz, false);

	c->lcm_entry_count = __swab16(2);
	c->lcm_entries[1].lcme_offset = __swab32(0xfffff000);
	check("swapped lcme_offset = 0xfffff000", sz, false);

	printf("simple layouts:\n");
	memset(buf, 0, sizeof(buf));
	v1->lmm_magic = LOV_USER_MAGIC_V1;
	v1->lmm_stripe_count = 1;
	check("v1, 1 stripe, buffer too small", sizeof(*v1), false);
	check("v1, 1 stripe, buffer big enough",
	      lov_user_md_size(1, LOV_USER_MAGIC_V1), true);
	v1->lmm_stripe_count = __swab16(1);
	v1->lmm_magic = __swab32(LOV_USER_MAGIC_V1);
	check("swapped v1, 1 stripe, big enough",
	      lov_user_md_size(1, LOV_USER_MAGIC_V1), true);
	v1->lmm_magic = 0xdeadbeef;
	check("garbage magic", sizeof(*v1), false);

	/*
	 * A foreign layout in host order is a layout.  The same one swapped
	 * is refused on purpose: layout_swab_lov_user_md() does not swab a
	 * top-level foreign magic, so accepting it here would hand the rest
	 * of find an EA still in the target's byte order, and --foreign
	 * would then miss every HSM-released or PCC file on a big-endian
	 * host.  Refused, it takes the no-layout path instead.
	 */
	printf("foreign layouts:\n");
	memset(buf, 0, sizeof(buf));
	{
		struct lov_foreign_md *lfm = (void *)buf;
		__u32 fsz;

		/*
		 * 64 and not 8: the entry guard rejects anything shorter
		 * than a lov_user_md_v1, as the caller does before it, so a
		 * foreign EA that small never reaches the switch.  A real
		 * one -- lov_hsm_md -- is longer than that.
		 */
		lfm->lfm_magic = LOV_USER_MAGIC_FOREIGN;
		lfm->lfm_length = 64;
		fsz = lov_foreign_md_size(64);
		check("foreign, host order, buffer big enough", fsz, true);
		check("foreign, host order, buffer too small", fsz - 1, false);

		lfm->lfm_magic = __swab32(LOV_USER_MAGIC_FOREIGN);
		lfm->lfm_length = __swab32(64);
		check("foreign, byte-swapped (the swab cannot undo it)",
		      fsz, false);
	}

	printf("\n%s (%d wrong)\n", fails ? "FAILURES" : "ALL EXPECTATIONS MET", fails);
	return fails != 0;
}
