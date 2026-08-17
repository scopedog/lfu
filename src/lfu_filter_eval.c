// SPDX-License-Identifier: LGPL-2.1+
/*
 * LFU filter evaluator — the half of the filter that runs per object.
 *
 * Built twice, from one source:
 *
 *   userspace  — linked into every device-scanner backend (lfu_core.c calls
 *                lfu_filter_tier0() before the xattr area is opened and
 *                lfu_filter_tier1() after), the way it always was;
 *   kernel     — #included into the lfu_ring module, where it runs on the
 *                record the OSD iterator returns, so a filtered object is
 *                rejected before it enters the ring (design-osd-scanner.md
 *                §4: "filter pushdown", cost-ordered, non-allocating).
 *
 * That is why this file is what it is: no stdio, no libc beyond memcpy and
 * friends, no allocation, no recursion, and no dependence on how the
 * predicates were parsed.  A struct lfu_filter is a fixed array of fixed-size
 * predicates, so evaluating one is bounded by construction, which is the
 * property a kernel-side filter program must have.  The parser that produces
 * that struct from lfs find syntax is lfu_filter.c and is userspace only.
 *
 * Portability seams are all in lfu_filter.h: lfu_glob() (fnmatch vs
 * glob_match), the S_IF* mode bits, and the fixed-width types.
 */
#include "lfu_filter.h"

/* ------------------------------------------------------------------ */
/* Introspection and validation                                        */

uint32_t lfu_filter_fields_used(const struct lfu_filter *f)
{
	uint32_t used = 0;
	int i;

	for (i = 0; i < f->n; i++)
		used |= LFU_FIELD_BIT(f->p[i].field);
	return used;
}

uint32_t lfu_filter_attrs_used(const struct lfu_filter *f)
{
	uint32_t used = 0;
	int i;

	for (i = 0; i < f->n; i++)
		if (f->p[i].field == LFU_F_ATTRS)
			used |= (uint32_t)(f->p[i].val | f->p[i].val2);
	return used;
}

/*
 * The bounded-and-verifiable property, made explicit.  A struct lfu_filter
 * arriving through an ioctl is bytes from userspace; nothing about it may be
 * trusted until every index that will be used as one has been range-checked.
 * The evaluator relies on this having been called.
 */
int lfu_filter_validate(const struct lfu_filter *f)
{
	int i;

	if (f->n < 0 || f->n > LFU_MAX_PRED)
		return -1;
	if (f->neg_pending != 0)
		return -1;	/* a dangling `!` never compiles */
	for (i = 0; i < f->n; i++) {
		const struct lfu_pred *p = &f->p[i];

		if (p->field >= LFU_F_MAX || p->op >= LFU_OP_MAX)
			return -1;
		if (p->neg > 1)
			return -1;
		if (p->nlist < 0 || p->nlist > LFU_MAX_LIST)
			return -1;
		if (memchr(p->str, '\0', sizeof(p->str)) == NULL)
			return -1;
	}
	return 0;
}

/* ------------------------------------------------------------------ */
/* xattr decode                                                        */

static void lfu_decode_som(struct lfu_tier1 *t1, const struct lfu_ea *ea)
{
	const unsigned char *b = ea->buf;

	if (b == NULL || ea->len < sizeof(struct lustre_som_attrs))
		return;

	t1->som_valid = lfu_le16(b);
	t1->som_size = lfu_le64(b + 8);
	t1->som_blocks = lfu_le64(b + 16);
	t1->have_som = 1;
}

/*
 * One LOV component — a plain v1/v3 EA, or one entry of a composite.  Sums
 * into the accumulator rather than overwriting, because a composite file's
 * stripe count is the sum over its data components, which is what lfs find
 * reports and therefore what --stripe-count has to compare.
 */
static void lfu_decode_lov_one(struct lfu_tier1 *t1, const unsigned char *b,
			       size_t len)
{
	uint32_t magic, pattern, stripe_size;
	uint16_t stripe_count;
	size_t hdr;

	if (len < sizeof(struct lov_mds_md_v1))
		return;

	magic = lfu_le32(b);
	pattern = lfu_le32(b + 4);
	stripe_size = lfu_le32(b + 24);
	stripe_count = lfu_le16(b + 28);

	switch (magic) {
	case LOV_MAGIC_V1:
		hdr = sizeof(struct lov_mds_md_v1);
		break;
	case LOV_MAGIC_V3:
	case LOV_MAGIC_SPECIFIC:
		hdr = sizeof(struct lov_mds_md_v3);
		if (len < hdr)
			return;
		/* The pool name is only in v3; keep the first one seen. */
		if (t1->pool[0] == '\0') {
			memcpy(t1->pool, b + 32, LOV_MAXPOOLNAME);
			t1->pool[LOV_MAXPOOLNAME] = '\0';
		}
		break;
	case LOV_MAGIC_FOREIGN:
		t1->pattern |= LOV_PATTERN_FOREIGN;
		t1->lov_magic = magic;
		return;
	default:
		return;
	}

	/* A released component has no objects on disk; the count is still the
	 * layout's, which is what lfs find compares (LOV_PATTERN_F_RELEASED).
	 */
	if (len < hdr + (size_t)stripe_count * sizeof(struct lov_ost_data_v1) &&
	    !(pattern & LOV_PATTERN_F_RELEASED))
		stripe_count = (uint16_t)((len - hdr) /
					  sizeof(struct lov_ost_data_v1));

	t1->pattern |= pattern;
	if (t1->stripe_size == 0)
		t1->stripe_size = stripe_size;
	/* An MDT (DoM) component holds no OST stripes. */
	if (!(pattern & LOV_PATTERN_MDT))
		t1->stripe_count += stripe_count;
}

static void lfu_decode_lov(struct lfu_tier1 *t1, const struct lfu_ea *ea)
{
	const unsigned char *b = ea->buf;
	uint32_t magic;

	if (b == NULL || ea->len < sizeof(uint32_t))
		return;

	magic = lfu_le32(b);
	t1->lov_magic = magic;
	t1->have_lov = 1;

	if (magic != LOV_MAGIC_COMP_V1) {
		t1->comp_count = 1;
		t1->mirror_count = 1;
		lfu_decode_lov_one(t1, b, ea->len);
		return;
	}

	if (ea->len < sizeof(struct lov_comp_md_v1))
		return;

	{
		uint16_t nent = lfu_le16(b + 14);
		uint16_t nmirror = lfu_le16(b + 16);
		size_t off = sizeof(struct lov_comp_md_v1);
		uint16_t i;

		t1->comp_count = nent;
		/* lcm_mirror_count is "actual mirrors minus 1" so that a
		 * non-FLR file stores 0 (lustre_user.h:1170-1173).
		 */
		t1->mirror_count = (uint32_t)nmirror + 1;

		for (i = 0; i < nent; i++,
		     off += sizeof(struct lov_comp_md_entry_v1)) {
			uint32_t eoff, esize;

			if (off + sizeof(struct lov_comp_md_entry_v1) > ea->len)
				return;
			eoff = lfu_le32(b + off + 24);
			esize = lfu_le32(b + off + 28);
			if (eoff >= ea->len || esize == 0 ||
			    (size_t)eoff + esize > ea->len)
				continue;
			lfu_decode_lov_one(t1, b + eoff, esize);
		}
	}
}

static void lfu_decode_lmv(struct lfu_tier1 *t1, const struct lfu_ea *ea)
{
	const unsigned char *b = ea->buf;
	uint32_t magic;

	if (b == NULL || ea->len < sizeof(struct lmv_mds_md_v1))
		return;

	magic = lfu_le32(b);
	if (magic != LMV_MAGIC_V1 && magic != LMV_MAGIC_STRIPE)
		return;

	t1->lmv_count = lfu_le32(b + 4);
	t1->lmv_hash = lfu_le32(b + 12);
	t1->have_lmv = 1;
}

void lfu_ea_decode(struct lfu_tier1 *t1, const struct lfu_eas *eas)
{
	memset(t1, 0, sizeof(*t1));
	if (eas == NULL)
		return;
	lfu_decode_som(t1, &eas->som);
	lfu_decode_lov(t1, &eas->lov);
	lfu_decode_lmv(t1, &eas->lmv);
	t1->have_link = eas->link.buf != NULL;
}

/* ------------------------------------------------------------------ */
/* Evaluation                                                          */

static int lfu_cmp(const struct lfu_pred *p, uint64_t value)
{
	switch (p->op) {
	case LFU_OP_GT:	 return value > p->val;
	case LFU_OP_LT:	 return value < p->val;
	case LFU_OP_EQ:
		/* val2 is the equality margin for quantities that carry a unit
		 * (find_value_cmp()'s 5th row): `--size 1M` is (0, 1M].
		 */
		return p->val2 ? (value <= p->val && value + p->val2 > p->val)
			       : value == p->val;
	case LFU_OP_ALL: return (value & p->val) == p->val &&
				(value & p->val2) == 0;
	case LFU_OP_ANY: return (value & p->val) != 0;
	case LFU_OP_LIST: {
		int i;

		for (i = 0; i < p->nlist; i++)
			if (p->list[i] == value)
				return 1;
		return 0;
	}
	default:
		return 0;
	}
}

/* Ages, not timestamps: see lfu_parse_sign(). */
static int lfu_cmp_age(const struct lfu_pred *p, int64_t now, uint32_t stamp)
{
	uint64_t age = (uint64_t)(now > (int64_t)stamp ? now - (int64_t)stamp : 0);

	if (p->op == LFU_OP_EQ)
		return age >= p->val && age < p->val + p->val2;
	return lfu_cmp(p, age);
}

int lfu_filter_tier0(const struct lfu_filter *f, const struct lfu_rec *rec,
		     int64_t now)
{
	int i;

	for (i = 0; i < f->n; i++) {
		const struct lfu_pred *p = &f->p[i];
		int hit;

		if (lfu_field_tier(p->field) != 0)
			continue;

		switch (p->field) {
		case LFU_F_ATIME: hit = lfu_cmp_age(p, now, rec->atime); break;
		case LFU_F_MTIME: hit = lfu_cmp_age(p, now, rec->mtime); break;
		case LFU_F_CTIME: hit = lfu_cmp_age(p, now, rec->ctime); break;
		case LFU_F_BTIME: hit = lfu_cmp_age(p, now, rec->crtime); break;
		case LFU_F_UID:	  hit = lfu_cmp(p, rec->uid); break;
		case LFU_F_GID:	  hit = lfu_cmp(p, rec->gid); break;
		case LFU_F_TYPE:  hit = (rec->mode & LFU_S_IFMT) == p->val; break;
		case LFU_F_PERM:  hit = lfu_cmp(p, rec->mode & 07777); break;
		case LFU_F_LINKS: hit = lfu_cmp(p, rec->nlink); break;
		case LFU_F_PROJID: hit = lfu_cmp(p, rec->projid); break;
		case LFU_F_ATTRS: hit = lfu_cmp(p, rec->flags); break;
		case LFU_F_DEV_BLOCKS:
			/* compared in bytes, like lfs find's --blocks */
			hit = lfu_cmp(p, rec->blocks * 512);
			break;
		default:
			continue;
		}

		if (p->neg)
			hit = !hit;
		if (!hit)
			return 0;
	}

	return 1;
}

/*
 * §4 — where an MDT's idea of a file's size is authoritative, and where it is
 * not.  Mirrors mdt_getattr_name_lock()'s decision table
 * (mdt_handler.c:874-904), which is the same question asked from the other
 * side of the wire.
 */
static enum lfu_match lfu_resolve_size(const struct lfu_rec *rec,
				       const struct lfu_tier1 *t1,
				       int want_blocks, uint64_t *out)
{
	int striped;

	/* Directories, symlinks and the rest: the MDT inode is the file. */
	if ((rec->mode & LFU_S_IFMT) != LFU_S_IFREG) {
		*out = want_blocks ? rec->blocks * 512 : rec->size;
		return LFU_MATCH;
	}

	/* HSM-released: the objects are gone and the MDT holds the size. */
	if (t1->have_lov && (t1->pattern & LOV_PATTERN_F_RELEASED)) {
		*out = want_blocks ? rec->blocks * 512 : rec->size;
		return LFU_MATCH;
	}

	/*
	 * No LOV at all, or a layout with no OST stripes (empty file, or
	 * data-on-MDT only): i_size is the whole story.
	 */
	striped = t1->have_lov && t1->stripe_count > 0;
	if (!striped) {
		*out = want_blocks ? rec->blocks * 512 : rec->size;
		return LFU_MATCH;
	}

	/*
	 * Striped: the data is on the OSTs.  trusted.som is the only number an
	 * MDT has, and it is written on close, so its absence is not an error
	 * — it is the unknown outcome.  A stale SOM is still what `lfs find
	 * --lazy` would answer from OBD_MD_FLLAZYSIZE, so it is used as-is.
	 */
	if (t1->have_som &&
	    (t1->som_valid & (SOM_FL_STRICT | SOM_FL_LAZY))) {
		/* lsa_blocks counts 512-byte blocks, like stx_blocks. */
		*out = want_blocks ? t1->som_blocks * 512 : t1->som_size;
		return LFU_MATCH;
	}

	return LFU_UNKNOWN;
}

/* --ost: walk the objects of every component and look for a listed index. */
static int lfu_lov_on_ost(const struct lfu_ea *ea, const struct lfu_pred *p)
{
	const unsigned char *b = ea->buf;
	uint32_t magic;
	size_t nent = 1, ent_off = 0, i;

	if (b == NULL || ea->len < sizeof(uint32_t))
		return 0;

	magic = lfu_le32(b);
	if (magic == LOV_MAGIC_COMP_V1) {
		if (ea->len < sizeof(struct lov_comp_md_v1))
			return 0;
		nent = lfu_le16(b + 14);
		ent_off = sizeof(struct lov_comp_md_v1);
	}

	for (i = 0; i < nent; i++) {
		const unsigned char *c = b;
		size_t clen = ea->len, hdr;
		uint32_t cmagic, pattern;
		uint16_t count, s;

		if (magic == LOV_MAGIC_COMP_V1) {
			size_t eo = ent_off +
				    i * sizeof(struct lov_comp_md_entry_v1);
			uint32_t coff, csize;

			if (eo + sizeof(struct lov_comp_md_entry_v1) > ea->len)
				return 0;
			coff = lfu_le32(b + eo + 24);
			csize = lfu_le32(b + eo + 28);
			if (coff >= ea->len || csize == 0 ||
			    (size_t)coff + csize > ea->len)
				continue;
			c = b + coff;
			clen = csize;
		}

		if (clen < sizeof(struct lov_mds_md_v1))
			continue;
		cmagic = lfu_le32(c);
		pattern = lfu_le32(c + 4);
		count = lfu_le16(c + 28);

		if (cmagic == LOV_MAGIC_V1)
			hdr = sizeof(struct lov_mds_md_v1);
		else if (cmagic == LOV_MAGIC_V3 || cmagic == LOV_MAGIC_SPECIFIC)
			hdr = sizeof(struct lov_mds_md_v3);
		else
			continue;

		/* A DoM component's "stripe" is the MDT itself, and a released
		 * component has no objects to look at.
		 */
		if (pattern & (LOV_PATTERN_MDT | LOV_PATTERN_F_RELEASED))
			continue;

		for (s = 0; s < count; s++) {
			size_t o = hdr + (size_t)s *
				   sizeof(struct lov_ost_data_v1);

			if (o + sizeof(struct lov_ost_data_v1) > clen)
				break;
			/* l_ost_idx is the last 4 bytes of the entry. */
			if (lfu_cmp(p, lfu_le32(c + o + 20)))
				return 1;
		}
	}

	return 0;
}

/*
 * --name against trusted.link.
 *
 * Two byte-order rules in one xattr (see lfu_lustre.h): the header is in the
 * writing host's order and is identified by its magic, exactly as
 * linkea_init_with_rec() does it, while each lee_reclen is big-endian and
 * unaligned.
 *
 * Caveat carried from docs/filter-levels.md §10: linkea is maintained by the
 * MDT but its completeness has not been verified by this project, so --name
 * answers from it are as good as linkea is.
 */
static int lfu_linkea_name(const struct lfu_ea *ea, const struct lfu_pred *p)
{
	const unsigned char *b = ea->buf;
	uint32_t reccount, magic, i;
	uint64_t leh_len;
	size_t off = sizeof(struct link_ea_header);
	int swap;

	if (b == NULL || ea->len < sizeof(struct link_ea_header))
		return 0;

	magic = lfu_host32(b);
	if (magic == LINK_EA_MAGIC)
		swap = 0;
	else if (magic == __builtin_bswap32((uint32_t)LINK_EA_MAGIC))
		swap = 1;
	else
		return 0;

	reccount = lfu_host32(b + 4);
	leh_len = lfu_host64(b + 8);
	if (swap) {
		reccount = __builtin_bswap32(reccount);
		leh_len = __builtin_bswap64(leh_len);
	}
	if (leh_len > ea->len)
		leh_len = ea->len;

	for (i = 0; i < reccount; i++) {
		char name[256];
		uint16_t reclen;
		size_t nlen;

		if (off + sizeof(struct link_ea_entry) > leh_len)
			return 0;
		/* big-endian, unaligned, 2 bytes */
		reclen = (uint16_t)((b[off] << 8) | b[off + 1]);
		if (reclen <= sizeof(struct link_ea_entry) ||
		    off + reclen > leh_len)
			return 0;

		nlen = reclen - sizeof(struct link_ea_entry);
		if (nlen >= sizeof(name))
			nlen = sizeof(name) - 1;
		memcpy(name, b + off + sizeof(struct link_ea_entry), nlen);
		name[nlen] = '\0';

		if (lfu_glob(p->str, name))
			return 1;

		off += reclen;
	}

	return 0;
}

enum lfu_match lfu_filter_tier1(const struct lfu_filter *f,
				const struct lfu_rec *rec,
				const struct lfu_tier1 *t1,
				const struct lfu_eas *eas)
{
	int unknown = 0;
	int i;

	for (i = 0; i < f->n; i++) {
		const struct lfu_pred *p = &f->p[i];
		int hit;

		if (lfu_field_tier(p->field) != 1)
			continue;

		switch (p->field) {
		case LFU_F_SIZE:
		case LFU_F_BLOCKS: {
			uint64_t value;
			enum lfu_match got =
				lfu_resolve_size(rec, t1,
						 p->field == LFU_F_BLOCKS,
						 &value);

			if (got == LFU_UNKNOWN) {
				/*
				 * Not a rejection: keep scanning the other
				 * predicates so a record that fails one of
				 * them outright is still a clean no-match.
				 */
				unknown = 1;
				continue;
			}
			hit = lfu_cmp(p, value);
			break;
		}
		case LFU_F_STRIPE_COUNT:
			hit = t1->have_lov && lfu_cmp(p, t1->stripe_count);
			break;
		case LFU_F_STRIPE_SIZE:
			hit = t1->have_lov && lfu_cmp(p, t1->stripe_size);
			break;
		case LFU_F_MIRROR_COUNT:
			hit = t1->have_lov && lfu_cmp(p, t1->mirror_count);
			break;
		case LFU_F_COMP_COUNT:
			hit = t1->have_lov && lfu_cmp(p, t1->comp_count);
			break;
		case LFU_F_LAYOUT:
			hit = t1->have_lov && lfu_cmp(p, t1->pattern);
			break;
		case LFU_F_POOL:
			hit = t1->have_lov &&
			      lfu_glob(p->str, t1->pool);
			break;
		case LFU_F_OST:
			hit = eas != NULL && lfu_lov_on_ost(&eas->lov, p);
			break;
		case LFU_F_MDT_COUNT:
			hit = t1->have_lmv && lfu_cmp(p, t1->lmv_count);
			break;
		case LFU_F_MDT_HASH:
			hit = t1->have_lmv &&
			      lfu_cmp(p, t1->lmv_hash & LMV_HASH_TYPE_MASK);
			break;
		case LFU_F_NAME:
			hit = eas != NULL && lfu_linkea_name(&eas->link, p);
			break;
		default:
			continue;
		}

		if (p->neg)
			hit = !hit;
		if (!hit)
			return LFU_NOMATCH;
	}

	return unknown ? LFU_UNKNOWN : LFU_MATCH;
}
