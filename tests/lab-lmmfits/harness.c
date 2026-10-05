#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdbool.h>
#include <byteswap.h>
#include <linux/lustre/lustre_user.h>
#include <linux/lustre/lustre_idl.h>
#define __swab32(x) bswap_32(x)
#define __swab16(x) bswap_16(x)
#include "old.inc"
#include "new.inc"

/* what llapi_layout_get_by_xattr() reads of each composite entry */
static unsigned int reader(const char *buf, size_t size)
{
	const struct lov_comp_md_v1 *c = (const void *)buf;
	unsigned int sum = 0, i;
	for (i = 0; i < c->lcm_entry_count; i++) {
		const char *e = buf + c->lcm_entries[i].lcme_offset;
		const struct lov_user_md *v1 = (const void *)e;
		if (v1->lmm_magic == LOV_MAGIC_FOREIGN) {
			const struct lov_hsm_md *h = (const void *)e;
			sum += h->lhm_archive_id + h->lhm_archive_ver +
			       h->lhm_archive_uuid[sizeof(h->lhm_archive_uuid) - 1];
		} else if (v1->lmm_magic != LOV_USER_MAGIC_V1) {
			const struct lov_user_md_v3 *v3 = (const void *)e;
			sum += strnlen(v3->lmm_pool_name, sizeof(v3->lmm_pool_name));
			sum += (unsigned char)v3->lmm_pool_name[15];
		}
	}
	return sum;
}

/* a composite of n entries, entry i of magic m[i] and length len[i], packed at the end */
static char *mk(int n, const __u32 *m, const __u32 *len, size_t *szp)
{
	size_t hdr = sizeof(struct lov_comp_md_v1) + n * sizeof(struct lov_comp_md_entry_v1);
	size_t sz = hdr; int i;
	for (i = 0; i < n; i++) sz += len[i];
	char *b = calloc(1, sz);
	struct lov_comp_md_v1 *c = (void *)b;
	c->lcm_magic = LOV_USER_MAGIC_COMP_V1; c->lcm_size = sz; c->lcm_entry_count = n;
	size_t off = hdr;
	for (i = 0; i < n; i++) {
		c->lcm_entries[i].lcme_offset = off; c->lcm_entries[i].lcme_size = len[i];
		struct lov_user_md *v = (void *)(b + off);
		v->lmm_magic = m[i];
		if (m[i] == LOV_MAGIC_FOREIGN) {
			struct lov_hsm_md *h = (void *)v;
			h->lhm_type = LU_FOREIGN_TYPE_POSIX;
			h->lhm_length = len[i] >= sizeof(struct lov_hsm_md) ?
				sizeof(struct lov_hsm_base) : 40;
		}
		off += len[i];
	}
	*szp = sz;
	return b;
}

int main(int argc, char **argv)
{
	int which = atoi(argv[1]);	/* 0 old, 1 new */
	struct { const char *name; int n; __u32 m[2]; __u32 len[2]; int legal; } t[] = {
		{ "v1 + v3, whole",         2, { LOV_USER_MAGIC_V1, LOV_USER_MAGIC_V3 }, { 32, 48 }, 1 },
		{ "v1 + foreign hsm, whole",2, { LOV_USER_MAGIC_V1, LOV_MAGIC_FOREIGN }, { 32, sizeof(struct lov_hsm_md) }, 1 },
		{ "torn: garbage magic, 32 at the end", 2, { LOV_USER_MAGIC_V1, 0xdeadbeef }, { 32, 32 }, 0 },
		{ "torn: foreign, 32 at the end",       2, { LOV_USER_MAGIC_V1, LOV_MAGIC_FOREIGN }, { 32, 32 }, 0 },
	};
	unsigned int i;
	for (i = argc > 2 ? atoi(argv[2]) : 0; i < (argc > 2 ? atoi(argv[2]) + 1 : sizeof(t) / sizeof(t[0])); i++) {
		size_t sz; char *b = mk(t[i].n, t[i].m, t[i].len, &sz);
		/* exact-size heap copy, so ASan sees the end */
		char *x = malloc(sz); memcpy(x, b, sz); free(b);
		bool ok = which ? fits_new((void *)x, sz) : fits_old((void *)x, sz);
		printf("%-38s fits=%d (legal=%d)%s\n", t[i].name, ok, t[i].legal,
		       ok != t[i].legal ? "  <-- WRONG" : "");
		fflush(stdout);
		if (ok) reader(x, sz);
		free(x);
	}
	return 0;
}
