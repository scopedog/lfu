/*
 * Drive the filter evaluator directly -- no parser, no scanner -- against
 * xattr bytes tests/mkimage.sh's encoders wrote and records built by hand,
 * and print one line per case.  tests/filter_eval_test.sh compiles this
 * twice, once along lfu_filter.h's userspace branch and once along its kernel
 * branch (-DLFU_KERNEL_TEST, with tests/kstubs standing in for the four
 * kernel headers), and requires the two outputs to be identical and to match
 * the expected list.  What that proves: the code the lfu_ring module compiles
 * in makes the same decisions the device scanners make, on the same bytes.
 *
 * The filters here are built field by field, exactly as they arrive in the
 * kernel through the ioctl -- there is no lfs find syntax on that side.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lfu_filter.h"

static void *slurp(const char *dir, const char *name, uint32_t *len)
{
	char path[512];
	FILE *fp;
	void *buf;
	long sz;

	snprintf(path, sizeof(path), "%s/%s", dir, name);
	fp = fopen(path, "rb");
	if (fp == NULL) {
		*len = 0;
		return NULL;
	}
	fseek(fp, 0, SEEK_END);
	sz = ftell(fp);
	fseek(fp, 0, SEEK_SET);
	buf = malloc(sz > 0 ? sz : 1);
	if (fread(buf, 1, sz, fp) != (size_t)sz)
		sz = 0;
	fclose(fp);
	*len = (uint32_t)sz;
	return buf;
}

/* --- building filters the way the kernel receives them ------------------ */

static struct lfu_pred *add(struct lfu_filter *f, int field, int op,
			    uint64_t val, uint64_t val2, uint32_t needs)
{
	struct lfu_pred *p = &f->p[f->n++];

	memset(p, 0, sizeof(*p));
	p->field = field;
	p->op = op;
	p->val = val;
	p->val2 = val2;
	f->needs |= needs;
	return p;
}

static void reset(struct lfu_filter *f)
{
	memset(f, 0, sizeof(*f));
}

/* --- records ------------------------------------------------------------ */

static void mkrec(struct lfu_rec *r, uint16_t mode, uint64_t size,
		  uint64_t blocks, uint32_t age_days, uint32_t flags,
		  uint32_t projid)
{
	memset(r, 0, sizeof(*r));
	r->mode = mode;
	r->nlink = 1;
	r->size = size;
	r->blocks = blocks;
	r->flags = flags;
	r->projid = projid;
	r->atime = r->mtime = r->ctime = r->crtime =
		(uint32_t)(1000000000 - (uint64_t)age_days * 86400);
}

static const char *mname(enum lfu_match m)
{
	return m == LFU_MATCH ? "match" : m == LFU_NOMATCH ? "nomatch"
						 : "unknown";
}

static void say(const char *what, enum lfu_match m)
{
	printf("%-52s %s\n", what, mname(m));
}

int main(int argc, char **argv)
{
	const char *dir = argc > 1 ? argv[1] : ".";
	struct lfu_filter f;
	struct lfu_rec striped, nosom, plain, dir_, released, comp, big;
	struct lfu_eas eas_striped, eas_nosom, eas_plain, eas_rel, eas_comp,
		       eas_none;
	struct lfu_tier1 t1;
	uint32_t l;
	int64_t now = 1000000000;

	memset(&eas_striped, 0, sizeof(eas_striped));
	memset(&eas_nosom, 0, sizeof(eas_nosom));
	memset(&eas_plain, 0, sizeof(eas_plain));
	memset(&eas_rel, 0, sizeof(eas_rel));
	memset(&eas_comp, 0, sizeof(eas_comp));
	memset(&eas_none, 0, sizeof(eas_none));

	/* the fixture bytes */
	eas_striped.som.buf = slurp(dir, "som.bin", &l);  eas_striped.som.len = l;
	eas_striped.lov.buf = slurp(dir, "lov.bin", &l);  eas_striped.lov.len = l;
	eas_striped.link.buf = slurp(dir, "link.bin", &l); eas_striped.link.len = l;
	eas_striped.lmv.buf = slurp(dir, "lmv.bin", &l);  eas_striped.lmv.len = l;
	eas_nosom.lov = eas_striped.lov;		/* striped, never closed */
	eas_rel.lov.buf = slurp(dir, "lovrel.bin", &l);   eas_rel.lov.len = l;
	eas_comp.lov.buf = slurp(dir, "lovcomp.bin", &l); eas_comp.lov.len = l;
	eas_comp.som = eas_striped.som;

	/* the same shapes tests/mkimage.sh builds:
	 *   striped   2 stripes on OSTs 3,7, SOM says 2 GiB; 8 own blocks
	 *   nosom     same layout, no SOM: the undecided case
	 *   plain     unstriped, i_size 200000 is authoritative
	 *   dir_      a directory, i_size 4096
	 *   released  HSM-released, layout says so, MDT holds the size
	 *   comp      PFL: DoM + one OST stripe, SOM 2 GiB
	 *   big       an immutable file, projid 1999, 400 days old
	 */
	mkrec(&striped, LFU_S_IFREG | 0644, 6, 8, 1, 0, 0);
	mkrec(&nosom,   LFU_S_IFREG | 0644, 6, 8, 1, 0, 0);
	mkrec(&plain,   LFU_S_IFREG | 0644, 200000, 400, 1, 0, 0);
	mkrec(&dir_,    LFU_S_IFDIR | 0755, 4096, 8, 1, 0, 0);
	mkrec(&released, LFU_S_IFREG | 0644, 123456, 0, 1, 0, 0);
	mkrec(&comp,    LFU_S_IFREG | 0644, 6, 8, 1, 0, 0);
	mkrec(&big,     LFU_S_IFREG | 0600, 6, 8, 400, LFU_ATTR_IMMUTABLE, 1999);

	/* --- validation --------------------------------------------------- */
	reset(&f);
	printf("%-52s %s\n", "validate: empty filter", lfu_filter_validate(&f) == 0 ? "ok" : "BAD");
	reset(&f); f.n = LFU_MAX_PRED + 1;
	printf("%-52s %s\n", "validate: n too large", lfu_filter_validate(&f) != 0 ? "rejected" : "BAD");
	reset(&f); add(&f, LFU_F_MAX, LFU_OP_EQ, 0, 0, 0);
	printf("%-52s %s\n", "validate: bad field", lfu_filter_validate(&f) != 0 ? "rejected" : "BAD");
	reset(&f); add(&f, LFU_F_UID, LFU_OP_MAX, 0, 0, 0);
	printf("%-52s %s\n", "validate: bad op", lfu_filter_validate(&f) != 0 ? "rejected" : "BAD");
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_POOL, LFU_OP_STR, 0, 0, LFU_NEED_LOV); memset(p->str, 'x', sizeof(p->str)); }
	printf("%-52s %s\n", "validate: unterminated pattern", lfu_filter_validate(&f) != 0 ? "rejected" : "BAD");
	reset(&f); add(&f, LFU_F_OST, LFU_OP_LIST, 0, 0, LFU_NEED_LOV); f.p[0].nlist = LFU_MAX_LIST + 1;
	printf("%-52s %s\n", "validate: list too long", lfu_filter_validate(&f) != 0 ? "rejected" : "BAD");
	reset(&f); f.neg_pending = 1;
	printf("%-52s %s\n", "validate: dangling !", lfu_filter_validate(&f) != 0 ? "rejected" : "BAD");

	/* --- tier 0 --------------------------------------------------------- */
	reset(&f); add(&f, LFU_F_TYPE, LFU_OP_EQ, LFU_S_IFDIR, 0, 0);
	say("t0: --type d on a dir", lfu_filter_tier0(&f, &dir_, now));
	say("t0: --type d on a file", lfu_filter_tier0(&f, &plain, now));
	reset(&f); add(&f, LFU_F_ATIME, LFU_OP_GT, 365ULL * 86400, 86400, 0);
	say("t0: --atime +1y, 400 days old", lfu_filter_tier0(&f, &big, now));
	say("t0: --atime +1y, 1 day old", lfu_filter_tier0(&f, &plain, now));
	reset(&f); add(&f, LFU_F_PROJID, LFU_OP_EQ, 1999, 0, 0);
	say("t0: --projid 1999", lfu_filter_tier0(&f, &big, now));
	reset(&f); add(&f, LFU_F_ATTRS, LFU_OP_ALL, LFU_ATTR_IMMUTABLE, 0, 0);
	say("t0: --attrs i on the immutable file", lfu_filter_tier0(&f, &big, now));
	say("t0: --attrs i on a plain file", lfu_filter_tier0(&f, &plain, now));
	reset(&f); add(&f, LFU_F_ATTRS, LFU_OP_ALL, 0, LFU_ATTR_IMMUTABLE, 0);
	say("t0: --attrs ^i on the immutable file", lfu_filter_tier0(&f, &big, now));
	reset(&f); add(&f, LFU_F_DEV_BLOCKS, LFU_OP_GT, 1ULL << 30, 0, 0);
	say("t0: --dev-blocks +1G on the striped inode", lfu_filter_tier0(&f, &striped, now));
	reset(&f); add(&f, LFU_F_PERM, LFU_OP_ANY, 0044, 0, 0);
	say("t0: --perm /044 on 0600", lfu_filter_tier0(&f, &big, now));
	say("t0: --perm /044 on 0644", lfu_filter_tier0(&f, &plain, now));
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_TYPE, LFU_OP_EQ, LFU_S_IFREG, 0, 0); p->neg = 1; }
	say("t0: ! --type f on a dir", lfu_filter_tier0(&f, &dir_, now));

	/* --- the size trap (§4) ------------------------------------------- */
	reset(&f); add(&f, LFU_F_BLOCKS, LFU_OP_GT, 1ULL << 30, 0, LFU_NEED_SOM | LFU_NEED_LOV);
	lfu_ea_decode(&t1, &eas_striped);
	say("t1: --blocks +1G, striped with SOM 2G", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	lfu_ea_decode(&t1, &eas_nosom);
	say("t1: --blocks +1G, striped, no SOM", lfu_filter_tier1(&f, &nosom, &t1, &eas_nosom));
	lfu_ea_decode(&t1, &eas_plain);
	say("t1: --blocks +1G, unstriped 200000B", lfu_filter_tier1(&f, &plain, &t1, &eas_plain));
	reset(&f); add(&f, LFU_F_SIZE, LFU_OP_GT, 100 << 10, 0, LFU_NEED_SOM | LFU_NEED_LOV);
	lfu_ea_decode(&t1, &eas_plain);
	say("t1: --size +100K, unstriped 200000B (i_size)", lfu_filter_tier1(&f, &plain, &t1, &eas_plain));
	lfu_ea_decode(&t1, &eas_striped);
	say("t1: --size +100K, striped SOM 2G", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	lfu_ea_decode(&t1, &eas_none);
	say("t1: --size +100K, a 4096B dir", lfu_filter_tier1(&f, &dir_, &t1, &eas_none));
	lfu_ea_decode(&t1, &eas_rel);
	say("t1: --size +100K, released 123456B (MDT)", lfu_filter_tier1(&f, &released, &t1, &eas_rel));
	reset(&f); add(&f, LFU_F_SIZE, LFU_OP_EQ, 1 << 20, 1 << 20, LFU_NEED_SOM | LFU_NEED_LOV);
	lfu_ea_decode(&t1, &eas_plain);
	say("t1: --size 1M (0,1M] on 200000B", lfu_filter_tier1(&f, &plain, &t1, &eas_plain));

	/* --- layout ------------------------------------------------------- */
	reset(&f); add(&f, LFU_F_STRIPE_COUNT, LFU_OP_EQ, 2, 0, LFU_NEED_LOV);
	lfu_ea_decode(&t1, &eas_striped);
	say("t1: --stripe-count 2", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	lfu_ea_decode(&t1, &eas_comp);
	say("t1: --stripe-count 2 on PFL (DoM+1)", lfu_filter_tier1(&f, &comp, &t1, &eas_comp));
	reset(&f); add(&f, LFU_F_STRIPE_COUNT, LFU_OP_EQ, 1, 0, LFU_NEED_LOV);
	say("t1: --stripe-count 1 on PFL (DoM+1)", lfu_filter_tier1(&f, &comp, &t1, &eas_comp));
	reset(&f); add(&f, LFU_F_COMP_COUNT, LFU_OP_EQ, 2, 0, LFU_NEED_LOV);
	say("t1: --comp-count 2 on PFL", lfu_filter_tier1(&f, &comp, &t1, &eas_comp));
	reset(&f); add(&f, LFU_F_LAYOUT, LFU_OP_ANY, LOV_PATTERN_MDT, 0, LFU_NEED_LOV);
	say("t1: --layout mdt on PFL", lfu_filter_tier1(&f, &comp, &t1, &eas_comp));
	reset(&f); add(&f, LFU_F_LAYOUT, LFU_OP_ANY, LOV_PATTERN_F_RELEASED, 0, LFU_NEED_LOV);
	lfu_ea_decode(&t1, &eas_rel);
	say("t1: --layout released", lfu_filter_tier1(&f, &released, &t1, &eas_rel));
	lfu_ea_decode(&t1, &eas_striped);
	say("t1: --layout released on striped", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_OST, LFU_OP_LIST, 0, 0, LFU_NEED_LOV); p->list[0] = 7; p->nlist = 1; }
	say("t1: --ost 7", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_OST, LFU_OP_LIST, 0, 0, LFU_NEED_LOV); p->list[0] = 9; p->nlist = 1; }
	say("t1: --ost 9", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_POOL, LFU_OP_STR, 0, 0, LFU_NEED_LOV); strcpy(p->str, "fast"); }
	say("t1: --pool fast on a v1 (no pool) layout", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); add(&f, LFU_F_STRIPE_SIZE, LFU_OP_EQ, 1 << 20, 1, LFU_NEED_LOV);
	say("t1: --stripe-size 1M", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));

	/* --- name and directory striping ---------------------------------- */
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_NAME, LFU_OP_STR, 0, 0, LFU_NEED_LINK); strcpy(p->str, "report*"); }
	say("t1: --name report*", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_NAME, LFU_OP_STR, 0, 0, LFU_NEED_LINK); strcpy(p->str, "second_link.txt"); }
	say("t1: --name second_link.txt (2nd entry)", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); { struct lfu_pred *p = add(&f, LFU_F_NAME, LFU_OP_STR, 0, 0, LFU_NEED_LINK); strcpy(p->str, "nosuch"); }
	say("t1: --name nosuch", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); add(&f, LFU_F_MDT_COUNT, LFU_OP_EQ, 4, 0, LFU_NEED_LMV);
	say("t1: --mdt-count 4", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));
	reset(&f); add(&f, LFU_F_MDT_HASH, LFU_OP_EQ, 2, 0, LFU_NEED_LMV);
	say("t1: --mdt-hash fnv_1a_64", lfu_filter_tier1(&f, &striped, &t1, &eas_striped));

	/* --- combined: unknown wins over match, nomatch wins over unknown -- */
	reset(&f);
	add(&f, LFU_F_STRIPE_COUNT, LFU_OP_EQ, 2, 0, LFU_NEED_LOV);
	add(&f, LFU_F_SIZE, LFU_OP_GT, 1, 0, LFU_NEED_SOM | LFU_NEED_LOV);
	lfu_ea_decode(&t1, &eas_nosom);
	say("t1: stripes=2 (match) + size (unknown)", lfu_filter_tier1(&f, &nosom, &t1, &eas_nosom));
	reset(&f);
	add(&f, LFU_F_STRIPE_COUNT, LFU_OP_EQ, 3, 0, LFU_NEED_LOV);
	add(&f, LFU_F_SIZE, LFU_OP_GT, 1, 0, LFU_NEED_SOM | LFU_NEED_LOV);
	say("t1: stripes=3 (nomatch) + size (unknown)", lfu_filter_tier1(&f, &nosom, &t1, &eas_nosom));

	/* the decoded values the wire record would carry */
	lfu_ea_decode(&t1, &eas_striped);
	printf("%-52s som=%llu/%llu stripes=%u ssize=%u lmv=%u/%u\n", "decode: striped",
	       (unsigned long long)t1.som_size, (unsigned long long)t1.som_blocks,
	       t1.stripe_count, t1.stripe_size, t1.lmv_count, t1.lmv_hash);
	lfu_ea_decode(&t1, &eas_comp);
	printf("%-52s comps=%u mirrors=%u stripes=%u pattern=%#x\n", "decode: PFL",
	       t1.comp_count, t1.mirror_count, t1.stripe_count, t1.pattern);

	return 0;
}
