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
	uint64_t size;
	uint64_t blocks;	/* 512-byte units; see docs — semantics differ
				 * across backends for compressed data */
	uint32_t atime, mtime, ctime, crtime;
	int has_ext_ea;		/* ldiskfs tier-2 marker; ZFS never sets it */
};

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
	uint64_t filtered;
	/* ldiskfs */
	uint64_t free_ino;
	uint64_t deleted;
	uint64_t in_use;
	uint64_t tier2;
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
	/* tier-0 filters */
	int64_t atime_older_than;	/* seconds; <0 = unset */
	int64_t blocks_gt;		/* 512B units; <0 = unset */
	int64_t projid_eq;		/* <0 = unset */
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
	int stop;
};

struct lfu_target_ops {
	const char *name;	/* "ldiskfs" / "zfs" */
	const char *id_label;	/* "ino" / "obj" — record field name */
	const char *usage_target;	/* "<device>" / "pool/dataset[@snapshot]" */
	const char *usage_extra;	/* backend option help text, or NULL */

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
 * Classify + emit one fully-read object.  Sets cx->stop when --limit is
 * reached.  With -v, emits a class-tagged diagnostic line per object
 * instead of the plain record.
 */
void lfu_object(struct lfu_ctx *cx, struct lfu_rec *rec, int have_lma);

/* Shared classification ladder (§5) — exposed for backends that need it */
enum lfu_class lfu_classify(const struct lfu_rec *rec, int have_lma);

/* Common entry point: parse options, run the scan, report. */
int lfu_main(const struct lfu_target_ops *ops, int argc, char **argv);

#endif /* LFU_SCAN_H */
