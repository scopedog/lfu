/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU filter — the compiled form, and the evaluator's contract.
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
 *
 * Two builds, one header
 * ----------------------
 * The evaluator (lfu_filter_eval.c) is also built into the lfu_ring kernel
 * module, so that a filter can be applied to the OSD iterator's records
 * before they enter the ring (design-osd-scanner.md §4).  Everything below
 * the "userspace only" line is therefore kept free of libc: fixed-width
 * types, no allocation, and the on-disk Lustre structures come from the
 * kernel's own uapi headers in that build and from lfu_lustre.h in this one.
 * struct lfu_filter is a fixed-size POD and crosses the kernel boundary as
 * the ioctl payload; its layout is part of the ring's UAPI (lfu_ring.h).
 */
#ifndef LFU_FILTER_H
#define LFU_FILTER_H

#if defined(__KERNEL__) || defined(LFU_KERNEL_TEST)
# include <linux/types.h>
# include <linux/string.h>
# include <linux/glob.h>
# include <uapi/linux/lustre/lustre_idl.h>
/* uint8_t..uint64_t and int64_t come from <linux/types.h> in the kernel */
/* glob_match() is the kernel's fnmatch(): '*', '?', '[...]', no flags */
static inline int lfu_glob(const char *pat, const char *str)
{
	return glob_match(pat, str) ? 1 : 0;
}
#else
# include <stdint.h>
# include <stddef.h>
# include <string.h>
# include <fnmatch.h>
# include "lfu_lustre.h"
static inline int lfu_glob(const char *pat, const char *str)
{
	return fnmatch(pat, str, 0) == 0;
}
#endif

/* The file-type bits of st_mode / i_mode / la_mode: POSIX-fixed octal
 * values, spelled here rather than taken from <sys/stat.h> so that this
 * header pulls in no system header a device library might shadow (libspl
 * ships its own sys/stat.h) and needs none in the kernel. */
#define LFU_S_IFMT	0170000
#define LFU_S_IFSOCK	0140000
#define LFU_S_IFLNK	0120000
#define LFU_S_IFREG	0100000
#define LFU_S_IFBLK	0060000
#define LFU_S_IFDIR	0040000
#define LFU_S_IFCHR	0020000
#define LFU_S_IFIFO	0010000

/*
 * Every on-disk structure the evaluator decodes is read out of a buffer at an
 * arbitrary offset, so load through memcpy rather than a cast: an xattr value
 * inside an inode is not aligned for a uint64_t, and on-disk order is
 * little-endian regardless of the host.
 */
static inline uint16_t lfu_le16(const void *p)
{
	uint16_t v;

	memcpy(&v, p, sizeof(v));
	return __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ ? __builtin_bswap16(v) : v;
}

static inline uint32_t lfu_le32(const void *p)
{
	uint32_t v;

	memcpy(&v, p, sizeof(v));
	return __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ ? __builtin_bswap32(v) : v;
}

static inline uint64_t lfu_le64(const void *p)
{
	uint64_t v;

	memcpy(&v, p, sizeof(v));
	return __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ ? __builtin_bswap64(v) : v;
}

/* Host order, no conversion — for linkea, whose header is stored in the
 * writing host's byte order and normalised by the reader (lfu_lustre.h).
 */
static inline uint32_t lfu_host32(const void *p)
{
	uint32_t v;

	memcpy(&v, p, sizeof(v));
	return v;
}

static inline uint64_t lfu_host64(const void *p)
{
	uint64_t v;

	memcpy(&v, p, sizeof(v));
	return v;
}

/*
 * Attribute bits for --attrs.  lfs find names them from attrs_array
 * (lustreapi.h:1416) using STATX_ATTR_* values, which lustre_user.h:236-243
 * notes were chosen to coincide with the FS_IOC_GETFLAGS bits — and therefore
 * with ext4's on-disk i_flags, and with LUSTRE_*_FL, for exactly these five.
 * That is what lets both the ldiskfs device scanner and the kernel evaluator
 * compare a flag word directly; osd-zfs converts its own flag word first
 * (attrs_zfs2fs(), osd_internal.h:838).
 *
 * STATX_ATTR_AUTOMOUNT is deliberately absent: ext4 reuses 0x1000 for
 * EXT4_INDEX_FL, so on a device scan that bit means "hash-indexed directory".
 */
#define LFU_ATTR_COMPRESSED	0x00000004
#define LFU_ATTR_IMMUTABLE	0x00000010
#define LFU_ATTR_APPEND		0x00000020
#define LFU_ATTR_NODUMP		0x00000040
#define LFU_ATTR_ENCRYPTED	0x00000800
#define LFU_ATTR_ALL		(LFU_ATTR_COMPRESSED | LFU_ATTR_IMMUTABLE | \
				 LFU_ATTR_APPEND | LFU_ATTR_NODUMP | \
				 LFU_ATTR_ENCRYPTED)

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
 * ext2fs_xattr_get(), one nvlist_lookup_byte_array() against an already
 * unpacked SA_ZPL_DXATTR, or rec(DORA_XATTR) on the OSD iterator), but
 * *interpreting* it is Lustre, identical everywhere.  `external` records that
 * at least one value had to come from outside the inode — the tier-2 event §9
 * asks to be counted rather than merely suffered.
 */
struct lfu_ea {
	const void *buf;
	uint32_t len;
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

/* Which tier does a field live in? */
static inline int lfu_field_tier(enum lfu_field f)
{
	return f >= LFU_F_SIZE ? 1 : 0;
}

enum lfu_op {
	LFU_OP_EQ,		/* value == val (times: within margin) */
	LFU_OP_GT,		/* value >  val   ('+') */
	LFU_OP_LT,		/* value <  val   ('-') */
	LFU_OP_ALL,		/* (value & val) == val — --perm -MODE, --attrs */
	LFU_OP_ANY,		/* (value & val) != 0  — --perm /MODE */
	LFU_OP_LIST,		/* value is in the index list */
	LFU_OP_STR,		/* glob(str, value) */
	LFU_OP_MAX
};

#define LFU_MAX_LIST	64
#define LFU_STR_MAX	64

/*
 * One predicate.  Fixed size, no pointers: this is what crosses the kernel
 * boundary, and what makes the evaluator bounded and non-allocating.
 */
struct lfu_pred {
	uint8_t field;
	uint8_t op;
	uint8_t neg;			/* preceding `!` */
	uint8_t pad_[5];
	uint64_t val;
	uint64_t val2;			/* --attrs: bits required absent;
					 * times/sizes: the equality margin */
	uint32_t list[LFU_MAX_LIST];	/* --ost / --stripe-index */
	int32_t nlist;
	char str[LFU_STR_MAX];		/* --pool / --name pattern */
};

#define LFU_MAX_PRED	32

struct lfu_filter {
	struct lfu_pred p[LFU_MAX_PRED];
	int32_t n;
	uint32_t needs;
	int32_t neg_pending;		/* a bare `!` seen, awaiting its option */
	int32_t pad_;
};

/* The layout is a wire contract once it goes through an ioctl. */
_Static_assert(sizeof(struct lfu_pred) == 352, "lfu_pred layout");
_Static_assert(sizeof(struct lfu_filter) == 32 * 352 + 16, "lfu_filter layout");

/* ------------------------------------------------------------------ */
/* Outcome of an evaluation                                            */

enum lfu_match {
	LFU_NOMATCH = 0,
	LFU_MATCH   = 1,
	LFU_UNKNOWN = 2,	/* §4.4 — neither, and must not be folded */
};

/* ------------------------------------------------------------------ */
/* Decoded tier-1 attributes                                           */

#ifndef LOV_MAXPOOLNAME
#define LOV_MAXPOOLNAME 15
#endif

/*
 * Filled by lfu_ea_decode() from whatever the backend supplied.  Kept
 * separate from the record's tier-0 fields so that a backend that reads no
 * xattr beyond the LMA still compiles unchanged, and so the "did we see it"
 * flags stay next to the values they qualify.
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
/* The record the evaluator sees                                       */

/*
 * One object's tier-0 attributes, as every backend fills them: the device
 * scanners from the raw inode/dnode, the kernel producer from the OSD
 * iterator's lu_attr, and the kmdt consumer from the wire record.  Field
 * semantics are the ldiskfs device scanner's; see lfu_scan.h for the notes on
 * blocks and flags.
 */
struct lfu_rec {
	struct lu_fid fid;
	uint32_t lma_compat;
	uint32_t lma_incompat;
	uint64_t id;		/* backend object id: inode number / dnode */
	uint16_t mode;
	uint32_t nlink;
	uint32_t uid;
	uint32_t gid;
	uint32_t projid;
	uint32_t flags;		/* FS_IOC_GETFLAGS-style attribute bits, which
				 * coincide with STATX_ATTR_* for the five
				 * --attrs names LFU supports (LFU_ATTR_*).
				 * ldiskfs passes i_flags through; osd-zfs
				 * converts its own flag word first. */
	uint64_t size;
	uint64_t blocks;	/* 512-byte units; see docs — semantics differ
				 * across backends for compressed data.  This
				 * is the target's own allocation, which for a
				 * striped file is NOT the file's: --size and
				 * --blocks read trusted.som instead (§4). */
	uint32_t atime, mtime, ctime, crtime;
	int has_ext_ea;		/* ldiskfs tier-2 marker; ZFS never sets it */

	/*
	 * Tier-1 state, so a backend that decoded (or received) it can hand
	 * it to the core, and the core can print it, without a second
	 * decode.  t1_valid says whether t1 means anything.
	 */
	struct lfu_tier1 t1;
	int t1_valid;
	int unknown;		/* a pushdown backend's verdict: the filter's
				 * outcome for this object was undecided */
};

/* ------------------------------------------------------------------ */
/* Evaluator API — shared by userspace and kernel                     */

static inline int lfu_filter_active(const struct lfu_filter *f)
{
	return f->n > 0;
}

static inline uint32_t lfu_filter_needs(const struct lfu_filter *f)
{
	return f->needs;
}

/*
 * Is this a well-formed compiled filter?  Every count in range, every field
 * and op a known one, every pattern NUL-terminated.  The kernel calls this on
 * the ioctl payload before it will evaluate it; userspace calls it as a
 * self-check.  Returns 0 if sound, -1 otherwise.
 */
int lfu_filter_validate(const struct lfu_filter *f);

/* Decode the xattrs the backend supplied.  Safe against short and malformed
 * values: an unparseable EA leaves its have_* flag clear.
 */
void lfu_ea_decode(struct lfu_tier1 *t1, const struct lfu_eas *eas);

/*
 * Tier 0 — inode/dnode-resident predicates only, so this is what the backend
 * calls before it touches the xattr area.  1 = survives, 0 = rejected.  There
 * is no unknown outcome at tier 0: every field is present by construction.
 * `now` is seconds since the epoch.
 */
int lfu_filter_tier0(const struct lfu_filter *f, const struct lfu_rec *rec,
		     int64_t now);

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

/* Which --attrs bits the filter tests, so a backend that cannot see one of
 * them can refuse instead of answering "no matches".
 */
uint32_t lfu_filter_attrs_used(const struct lfu_filter *f);

/* Bitmask over enum lfu_field of every field the filter tests.  A backend
 * declares the tier-0 fields it cannot fill (lfu_target_ops.missing_fields)
 * and the core refuses the query rather than comparing against a zero.
 */
uint32_t lfu_filter_fields_used(const struct lfu_filter *f);

#define LFU_FIELD_BIT(f)	(1u << (f))

/* ------------------------------------------------------------------ */
/* Compiler API — userspace only                                       */

#if !defined(__KERNEL__) && !defined(LFU_KERNEL_TEST)
#include <getopt.h>

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

/* Human name of a field, for the refusal message. */
const char *lfu_field_name(enum lfu_field f);

#endif /* userspace only */

#endif /* LFU_FILTER_H */
