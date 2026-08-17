/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU Device Input Scanner — common core (design §3: one scanner, N backends).
 *
 * Everything above the device layer is shared: the classification ladder,
 * tier-0 filter ordering, record format, worker pool and CLI.  A backend
 * supplies a struct lfu_target_ops and its device-specific open/read code,
 * and gets classification, filtering, emission, statistics and the parallel
 * chunked scan for free.
 *
 * The split of responsibilities:
 *
 *   core   — owns the per-object pipeline (prefilter → classify → emit),
 *            the chunk dispatcher and worker threads, common options,
 *            stats accumulation and merge.
 *   backend— owns target open/close, per-worker state, enumeration within
 *            a chunk, attribute + LMA extraction, and the stats report
 *            (each backend's summary format is part of its test suite's
 *            contract, so it stays with the backend).
 *
 * Control is inverted relative to a next()/read() iterator API: the backend
 * loops over its chunk and calls lfu_prefilter() / lfu_object() per object.
 * The two enumeration styles (libext2fs buffered inode scan, ZFS
 * dmu_object_next()) are different enough that forcing them through one
 * iterator signature made both worse.
 */
#ifndef LFU_SCAN_H
#define LFU_SCAN_H

#include <stdint.h>
#include <time.h>
#include <getopt.h>

#include "lfu_lustre.h"
#include "lfu_filter.h"

enum lfu_class {
	LFU_CLS_VISIBLE = 0,	/* namespace-visible MDT object — emit */
	LFU_CLS_INTERNAL,	/* local/internal object */
	LFU_CLS_OST_OBJ,	/* OST data object */
	LFU_CLS_AGENT,		/* HSM agent inode */
	LFU_CLS_NO_LMA,		/* no LMA — IGIF candidate, or (osd-zfs) the
				 * OSD's own xattr-less hierarchy */
	LFU_CLS_BAD,		/* failed validation / unsupported */
	LFU_CLS_MAX
};

extern const char *const lfu_class_name[LFU_CLS_MAX];

/* struct lfu_rec — the record — is defined in lfu_filter.h, because the
 * kernel-side evaluator sees the same structure. */

/*
 * One stats struct for all backends: common counters plus each backend's
 * own.  A field a backend never touches stays zero and its report never
 * prints it.  Keeping them in one struct is what lets the core merge
 * per-worker stats without a backend callback.
 */
struct lfu_stats {
	uint64_t seen;
	uint64_t cls[LFU_CLS_MAX];
	uint64_t emitted;
	uint64_t filtered;	/* rejected at tier 0 */
	uint64_t filtered1;	/* rejected at tier 1 */
	uint64_t unknown;	/* §4.4 — a size test with no trusted.som to
				 * answer it: neither match nor no-match */
	/* ldiskfs */
	uint64_t free_ino;
	uint64_t deleted;
	uint64_t in_use;
	uint64_t tier2;		/* objects with an external EA block at all */
	uint64_t tier2_read;	/* objects where a demanded xattr actually had
				 * to be read from outside the inode — the
				 * countable tier-2 event of design §9 */
	uint64_t csum_bad;
	uint64_t validate_bad;
	/* zfs */
	uint64_t not_znode;
	uint64_t sa_fail;
	uint64_t unlinked;
	uint64_t no_dxattr;
	uint64_t max_bonus;	/* merged with max(), not sum */
};

#define LFU_MAX_SEARCH 16

struct lfu_opts {
	const char *target;	/* device path / pool/dataset[@snap] */
	int verbose;
	int show_internal;
	int quiet;
	uint64_t limit;		/* stop after N emitted records; forces -j 1 */
	int threads;		/* -j: parallel workers, default 1 */
	int emit_unknown;	/* also emit records whose filter outcome is
				 * unknown, tagged; default is to count only */
	struct lfu_filter filter;
	/* zfs backend */
	int import;
	int force_active;
	char *search[LFU_MAX_SEARCH];
	int nsearch;
};

/*
 * Per-worker context handed to the backend's scan_chunk().  The backend
 * calls lfu_prefilter() and lfu_object() against it; `stop` is set by the
 * core when --limit is reached and must end the backend's chunk loop.
 */
struct lfu_ctx {
	const struct lfu_opts *o;
	struct lfu_stats *st;
	const struct lfu_target_ops *ops;
	time_t now;
	uint32_t needs;		/* lfu_needs bits the compiled filter wants;
				 * the backend reads exactly these xattrs and
				 * no more (design §9) */
	int stop;
};

struct lfu_target_ops {
	const char *name;	/* "ldiskfs" / "zfs" */
	const char *id_label;	/* "ino" / "obj" — record field name */
	const char *usage_target;	/* "<device>" / "pool/dataset[@snapshot]" */
	const char *usage_extra;	/* backend option help text, or NULL */

	/*
	 * Which xattrs this backend can supply, as lfu_needs bits.  A filter
	 * demanding anything outside this set is refused at parse time: the
	 * alternative is a scan that silently answers a narrower question than
	 * the one asked.
	 */
	uint32_t can_supply;

	/*
	 * Which --attrs bits this backend's flag word can actually carry.
	 * ldiskfs passes ext4's i_flags through and covers all five; ZFS's
	 * z_pflags has no per-file compressed or encrypted bit.  A filter
	 * asking for one this backend cannot see is refused, because "no
	 * matches" would be indistinguishable from "not supported".
	 */
	uint32_t attr_mask;

	/*
	 * Bitmask over enum lfu_field (LFU_FIELD_BIT) of tier-0 fields this
	 * backend leaves zero — the kernel ring, for one, carries neither
	 * crtime nor projid nor flags.  Refused, not silently compared.
	 */
	uint32_t missing_fields;

	/*
	 * The backend evaluates the whole filter itself -- the kmdt stream,
	 * where the kernel applies tier 0 and tier 1 before a record enters
	 * the ring -- so the core must neither prefilter nor re-run tier 1,
	 * and rec->unknown says what the backend decided.  Its tier-1 values
	 * arrive already decoded in rec->t1.
	 */
	int pushdown;

	/* backend-specific CLI additions */
	const char *optstring_extra;
	const struct option *lopts_extra;
	int (*parse_opt)(int c, const char *arg, struct lfu_opts *o);

	/*
	 * Open the target.  Returns an opaque handle or NULL on error.
	 * Anything the backend wants to print once (superblock banner,
	 * live-dataset warning) happens here.
	 */
	void *(*open)(const struct lfu_opts *o);
	void (*close)(void *tgt);

	/*
	 * Per-worker state.  A backend whose handle is shareable across
	 * threads (ZFS objset) returns tgt itself; one whose library is
	 * not thread-safe (libext2fs) opens a second handle per worker.
	 */
	void *(*worker_init)(void *tgt, const struct lfu_opts *o);
	void (*worker_fini)(void *tgt, void *wctx);

	/*
	 * Scan chunk `idx` of the object-id space, calling the core per
	 * object.  Sets *done when the backend knows there is nothing at
	 * or beyond this chunk.  Returns 0, or -1 on a fatal error.
	 */
	int (*scan_chunk)(void *tgt, void *wctx, struct lfu_ctx *cx,
			  uint64_t idx, int *done);

	/* Final summary to stderr — format is the backend suite's contract */
	void (*report)(const struct lfu_stats *st, double secs, void *tgt);
};

/*
 * Tier-0 prefilter (design §7): evaluated on inode-resident attributes
 * BEFORE any xattr work, so a rejected object never costs an LMA parse
 * (ldiskfs) or a DXATTR unpack (ZFS).  Returns 1 if the object survives;
 * on 0 the core has already counted it filtered and the backend skips
 * the rest of its read path.  Objects rejected here are never classified.
 */
int lfu_prefilter(struct lfu_ctx *cx, const struct lfu_rec *rec);

/*
 * Classify one fully-read object, apply the tier-1 predicates against the
 * xattrs the backend fetched, and emit it if it matches.  Sets cx->stop when
 * --limit is reached.  With -v, emits a class-tagged diagnostic line per
 * object instead of the plain record.
 *
 * `eas` may be NULL for a backend that reads no xattr beyond the LMA; a
 * tier-1 predicate then has nothing to work with and matches nothing, which
 * is why lfu_main() refuses such a filter up front rather than answering the
 * wrong question quietly.
 */
void lfu_object(struct lfu_ctx *cx, struct lfu_rec *rec, int have_lma,
		const struct lfu_eas *eas);

/* Shared classification ladder (§5) — exposed for backends that need it */
enum lfu_class lfu_classify(const struct lfu_rec *rec, int have_lma);

/* Common entry point: parse options, run the scan, report. */
int lfu_main(const struct lfu_target_ops *ops, int argc, char **argv);

#endif /* LFU_SCAN_H */
