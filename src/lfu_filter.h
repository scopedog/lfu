/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU filter compiler and evaluator — shared by every device-scanner backend.
 *
 * docs/filter-levels.md is the design.  Three things it asks for are the
 * reason this is a module rather than three `if`s in the core:
 *
 *  1. A **demand mask** (§9).  The filter is compiled at parse time and
 *     publishes which xattrs the query needs — NEEDS_SOM, NEEDS_LOV,
 *     NEEDS_LMV, NEEDS_LINKEA.  A pure tier-0 query never opens the xattr
 *     area at all, which is what keeps `-mtime +30 -uid 1000 -type f` running
 *     at the full block-parse rate.
 *
 *  2. **Tier-ordered evaluation** (§7).  lfu_filter_tier0() runs on
 *     inode-resident attributes before any xattr work; lfu_filter_tier1() runs
 *     once the demanded xattrs are in hand.  A filter presented as one opaque
 *     match function would forfeit both.
 *
 *  3. A third outcome, **unknown** (§4.4).  An MDT-only scan is `lfs find
 *     --lazy`: for a striped regular file with no trusted.som, the size is
 *     not known to be a match *or* a non-match.  Callers must not fold that
 *     into "no".
 *
 * The predicate vocabulary is closed — `lfs find`'s 34 items (lfs.c:473-505),
 * every one of the form (field, op, value) with uniform `!` negation and
 * `+`/`-` comparison — so evaluation is one switch over a compiled array and
 * costs no dynamic dispatch per object.
 */
#ifndef LFU_FILTER_H
#define LFU_FILTER_H

#include <stdint.h>
#include <time.h>
#include <getopt.h>

#include "lfu_lustre.h"

/* ------------------------------------------------------------------ */
/* What a query demands from the object beyond its inode/dnode         */

enum lfu_needs {
	LFU_NEED_SOM	= 0x01,		/* trusted.som — size, blocks */
	LFU_NEED_LOV	= 0x02,		/* trusted.lov — layout, and the
					 * stripe count that decides whether
					 * i_size means anything (§4) */
	LFU_NEED_LMV	= 0x04,		/* trusted.lmv — mdt-count, mdt-hash */
	LFU_NEED_LINK	= 0x08,		/* trusted.link — name */
};

/*
 * Raw tier-1 xattr values, filled by the backend and decoded by this module.
 *
 * The split matters: fetching an xattr is device-specific (libext2fs
 * ext2fs_xattr_get() vs one nvlist_lookup_byte_array() against an already
 * unpacked SA_ZPL_DXATTR), but *interpreting* it is Lustre, identical on both.
 * `external` records that at least one value had to come from outside the
 * inode — the tier-2 event §9 asks to be counted rather than merely suffered.
 */
struct lfu_ea {
	const void *buf;
	size_t len;
};

struct lfu_eas {
	struct lfu_ea som;
	struct lfu_ea lov;
	struct lfu_ea lmv;
	struct lfu_ea link;
	int external;
};

/* ------------------------------------------------------------------ */
/* Compiled predicates                                                 */

enum lfu_field {
	/* tier 0 — inode/dnode resident */
	LFU_F_ATIME, LFU_F_MTIME, LFU_F_CTIME, LFU_F_BTIME,
	LFU_F_UID, LFU_F_GID, LFU_F_TYPE, LFU_F_PERM, LFU_F_LINKS,
	LFU_F_PROJID, LFU_F_ATTRS, LFU_F_DEV_BLOCKS,
	/* tier 1 — xattr resident */
	LFU_F_SIZE, LFU_F_BLOCKS,
	LFU_F_STRIPE_COUNT, LFU_F_STRIPE_SIZE, LFU_F_OST, LFU_F_POOL,
	LFU_F_LAYOUT, LFU_F_MIRROR_COUNT, LFU_F_COMP_COUNT,
	LFU_F_MDT_COUNT, LFU_F_MDT_HASH,
	LFU_F_NAME,
	LFU_F_MAX
};

enum lfu_op {
	LFU_OP_EQ,		/* value == val (times: within margin) */
	LFU_OP_GT,		/* value >  val   ('+') */
	LFU_OP_LT,		/* value <  val   ('-') */
	LFU_OP_ALL,		/* (value & val) == val — --perm -MODE, --attrs */
	LFU_OP_ANY,		/* (value & val) != 0  — --perm /MODE */
	LFU_OP_LIST,		/* value is in the index list */
	LFU_OP_STR,		/* fnmatch(str, value) */
};

#define LFU_MAX_LIST	64

struct lfu_pred {
	uint8_t field;
	uint8_t op;
	uint8_t neg;			/* preceding `!` */
	uint64_t val;
	uint64_t val2;			/* --attrs: bits required absent;
					 * times: the equality margin */
	uint32_t list[LFU_MAX_LIST];	/* --ost / --stripe-index */
	int nlist;
	char str[64];			/* --pool / --name pattern */
};

#define LFU_MAX_PRED	32

struct lfu_filter {
	struct lfu_pred p[LFU_MAX_PRED];
	int n;
	uint32_t needs;
	int neg_pending;		/* a bare `!` seen, awaiting its option */
};

/* ------------------------------------------------------------------ */
/* Outcome of an evaluation                                            */

enum lfu_match {
	LFU_NOMATCH = 0,
	LFU_MATCH   = 1,
	LFU_UNKNOWN = 2,	/* §4.4 — neither, and must not be folded */
};

/* ------------------------------------------------------------------ */
/* Decoded tier-1 attributes                                           */

/*
 * Filled by lfu_ea_decode() from whatever the backend supplied.  Kept
 * separate from struct lfu_rec so that a backend that reads no xattr beyond
 * the LMA still compiles unchanged, and so the "did we see it" flags stay
 * next to the values they qualify.
 */
struct lfu_tier1 {
	int have_som;
	uint16_t som_valid;
	uint64_t som_size;
	uint64_t som_blocks;

	int have_lov;
	uint32_t lov_magic;
	uint32_t pattern;		/* OR of every component's pattern */
	uint32_t stripe_count;		/* summed over data components */
	uint32_t stripe_size;		/* of the first data component */
	uint32_t comp_count;
	uint32_t mirror_count;		/* actual mirrors, not the on-disk n-1 */
	char pool[LOV_MAXPOOLNAME + 1];

	int have_lmv;
	uint32_t lmv_count;
	uint32_t lmv_hash;

	int have_link;
};

/* ------------------------------------------------------------------ */
/* API                                                                 */

/* Long-option ids for the filter vocabulary.  Values are above any short
 * option so the core can hand unrecognised codes straight to lfu_filter_opt().
 */
enum {
	LFU_OPT_BASE = 0x200,
	LFU_OPT_ATIME, LFU_OPT_MTIME, LFU_OPT_CTIME, LFU_OPT_BTIME,
	LFU_OPT_UID, LFU_OPT_GID, LFU_OPT_TYPE, LFU_OPT_PERM, LFU_OPT_LINKS,
	LFU_OPT_PROJID, LFU_OPT_ATTRS, LFU_OPT_DEV_BLOCKS,
	LFU_OPT_SIZE, LFU_OPT_BLOCKS,
	LFU_OPT_STRIPE_COUNT, LFU_OPT_STRIPE_SIZE,
	/* There is deliberately no LFU_OPT_STRIPE_INDEX: `lfs find` handles -i
	 * and -O in one case (lfs.c:7804), so --stripe-index is a spelling of
	 * --ost, not a predicate of its own.
	 */
	LFU_OPT_OST, LFU_OPT_POOL, LFU_OPT_LAYOUT,
	LFU_OPT_MIRROR_COUNT, LFU_OPT_COMP_COUNT,
	LFU_OPT_MDT_COUNT, LFU_OPT_MDT_HASH, LFU_OPT_NAME,
	LFU_OPT_NOT,
	LFU_OPT_MAX
};

/* The filter's own long options, NULL-terminated, for the core's table. */
extern const struct option lfu_filter_options[];

/* Help text for the filter options, for the core's usage(). */
extern const char *const lfu_filter_usage;

/*
 * Compile one option occurrence.  Returns 0 on success, -1 if `opt` is not a
 * filter option, or -2 if it is but `arg` is malformed (message already
 * printed).  A bare `!` is LFU_OPT_NOT and negates the next predicate.
 */
int lfu_filter_opt(struct lfu_filter *f, int opt, const char *arg);

/* Reject a trailing `!` with nothing after it; returns 0 if the filter is
 * well formed.
 */
int lfu_filter_check(const struct lfu_filter *f);

static inline int lfu_filter_active(const struct lfu_filter *f)
{
	return f->n > 0;
}

static inline uint32_t lfu_filter_needs(const struct lfu_filter *f)
{
	return f->needs;
}

/* Which --attrs bits the filter tests, so a backend that cannot see one of
 * them can refuse instead of answering "no matches".
 */
uint32_t lfu_filter_attrs_used(const struct lfu_filter *f);

/* Bitmask over enum lfu_field of every field the filter tests.  A backend
 * declares the tier-0 fields it cannot fill (lfu_target_ops.missing_fields)
 * and the core refuses the query rather than comparing against a zero.
 */
uint32_t lfu_filter_fields_used(const struct lfu_filter *f);

/* Human name of a field, for the refusal message. */
const char *lfu_field_name(enum lfu_field f);

#define LFU_FIELD_BIT(f)	(1u << (f))

/* Decode the xattrs the backend supplied.  Safe against short and malformed
 * values: an unparseable EA leaves its have_* flag clear.
 */
void lfu_ea_decode(struct lfu_tier1 *t1, const struct lfu_eas *eas);

struct lfu_rec;		/* the record; see lfu_scan.h */

/*
 * Tier 0 — inode/dnode-resident predicates only, so this is what the backend
 * calls before it touches the xattr area.  1 = survives, 0 = rejected.  There
 * is no unknown outcome at tier 0: every field is present by construction.
 */
int lfu_filter_tier0(const struct lfu_filter *f, const struct lfu_rec *rec,
		     time_t now);

/*
 * Tier 1 — the rest, once the demanded xattrs are in hand.  Returns
 * LFU_UNKNOWN when a predicate's input is genuinely absent (§4.4), which for
 * now means a size or blocks test on a striped regular file with no
 * trusted.som.  Unknown wins over match, because "we do not know" is the
 * honest answer for the whole record.
 */
enum lfu_match lfu_filter_tier1(const struct lfu_filter *f,
				const struct lfu_rec *rec,
				const struct lfu_tier1 *t1,
				const struct lfu_eas *eas);

#endif /* LFU_FILTER_H */
