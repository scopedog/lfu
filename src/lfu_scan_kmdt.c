/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU kernel-MDT Input Scanner — the userspace half of Option 2 (step 4,
 * filter pushdown 2026-08-17).
 *
 * Reads the Object Stream the lfu_ring kernel module produces from the
 * otable iterator of a MOUNTED MDT, and hands each record to the common
 * core (lfu_core.c).  This is the third lfu_target_ops backend: same
 * classification ladder, record format and stats as the ldiskfs and ZFS
 * device scanners — different device layer, and the only one that works
 * while the target is serving.
 *
 * The filter is not applied here.  It is compiled here, from the same lfs
 * find vocabulary as everywhere else, and handed to the kernel through
 * LFU_RING_IOC_SET_FILTER before the first read(); the module evaluates it
 * tier by tier against each object before the record enters the ring, so what
 * arrives is already the answer.  This backend therefore sets .pushdown, and
 * the core neither prefilters nor re-runs tier 1 on what it receives.  The
 * per-tier counts come back through LFU_RING_IOC_STATS at EOF and are folded
 * into the ordinary summary.
 *
 * Before trusting a single record, LFU_RING_IOC_INFO is checked: wire
 * version and record size (a mismatch is refused, not misparsed), and which
 * xattrs and --attrs bits the module's OSD can serve.  Those become this
 * backend's can_supply/attr_mask at open time, so a filter the kernel cannot
 * answer is refused with the same message the device scanners give.
 *
 * Prototype honesty:
 *   - the stream is inherently ordered and single-reader: -j is forced
 *     to 1.  Parallelism belongs behind the enumerator in the kernel
 *     (measured in lfu_par), not here.
 *   - the wire carries the LMA orphan/encrypted bits (via la_flags) but not
 *     LMAC_NOT_IN_OI/LMAI_AGENT; the OSD iterator skips those objects itself
 *     (osd_iit_iget), so nothing is lost, but the consumer cannot *see* them.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/types.h>
#include <inttypes.h>

#include "lfu_scan.h"
#include "kernel/lfu_ring.h"

#define LFU_KMDT_BATCH	8192	/* records per read() */

struct lfu_kmdt {
	int fd;
	const char *path;
	struct lfu_ring_info info;
	struct lfu_ring_stats st;	/* from the kernel, at EOF */
	int have_stats;
};

/*
 * INFO tells us what the kernel side can do; that becomes this backend's
 * capability set, and lfu_main() has already been told the static worst
 * case (see the ops table), so the only work here is to refuse what the
 * running module cannot serve and to send the filter.
 */
static int lfu_kmdt_negotiate(struct lfu_kmdt *t, const struct lfu_opts *o)
{
	struct lfu_ring_filter *rf;
	uint32_t missing, attrs;

	if (ioctl(t->fd, LFU_RING_IOC_INFO, &t->info) != 0) {
		fprintf(stderr,
			"lfu: %s: LFU_RING_IOC_INFO: %s — module too old for "
			"this scanner (no filter pushdown)\n",
			t->path, strerror(errno));
		return -1;
	}
	if (t->info.ri_wire_version != LFU_RING_WIRE_VERSION ||
	    t->info.ri_rec_size != sizeof(struct lfu_wire_rec)) {
		fprintf(stderr,
			"lfu: %s: wire version %u/%u bytes, this scanner "
			"speaks %u/%zu — refusing rather than misparse\n",
			t->path, t->info.ri_wire_version, t->info.ri_rec_size,
			LFU_RING_WIRE_VERSION, sizeof(struct lfu_wire_rec));
		return -1;
	}
	if (t->info.ri_max_pred != LFU_MAX_PRED) {
		fprintf(stderr,
			"lfu: %s: module built with %u predicates, scanner "
			"with %u\n", t->path, t->info.ri_max_pred, LFU_MAX_PRED);
		return -1;
	}

	fprintf(stderr,
		"kernel side  : %s, wire v%u, %s iterator, tier 1%s%s%s%s%s\n",
		t->info.ri_dev, t->info.ri_wire_version,
		(t->info.ri_flags & LFU_RING_INFO_PRIVATE) ?
			"private (block parse)" : "singleton",
		t->info.ri_can_supply ? ":" : ": none",
		(t->info.ri_can_supply & LFU_NEED_SOM) ? " som" : "",
		(t->info.ri_can_supply & LFU_NEED_LOV) ? " lov" : "",
		(t->info.ri_can_supply & LFU_NEED_LMV) ? " lmv" : "",
		(t->info.ri_can_supply & LFU_NEED_LINK) ? " link" : "");

	if (!lfu_filter_active(&o->filter))
		return 0;

	/* Refuse what this module's OSD cannot answer, the way the device
	 * scanners refuse at parse time.  The kernel checks the same thing
	 * again on the ioctl; saying it here gives a better message. */
	missing = lfu_filter_needs(&o->filter) & ~t->info.ri_can_supply;
	if (missing != 0) {
		fprintf(stderr,
			"lfu: the kernel side cannot supply%s%s%s%s needed by "
			"this filter\n",
			(missing & LFU_NEED_SOM) ? " trusted.som" : "",
			(missing & LFU_NEED_LOV) ? " trusted.lov" : "",
			(missing & LFU_NEED_LMV) ? " trusted.lmv" : "",
			(missing & LFU_NEED_LINK) ? " trusted.link" : "");
		return -1;
	}
	attrs = lfu_filter_attrs_used(&o->filter) & ~t->info.ri_attr_mask;
	if (attrs != 0) {
		fprintf(stderr,
			"lfu: the kernel side cannot see%s%s of --attrs\n",
			(attrs & LFU_ATTR_COMPRESSED) ? " Compressed" : "",
			(attrs & LFU_ATTR_ENCRYPTED) ? " Encrypted" : "");
		return -1;
	}

	rf = calloc(1, sizeof(*rf));
	if (rf == NULL)
		return -1;
	rf->rf_magic = LFU_RING_FILTER_MAGIC;
	rf->rf_version = LFU_RING_WIRE_VERSION;
	rf->rf_size = sizeof(struct lfu_filter);
	rf->rf_flags = o->emit_unknown ? LFU_FILTER_EMIT_UNKNOWN : 0;
	rf->rf_filter = o->filter;
	if (ioctl(t->fd, LFU_RING_IOC_SET_FILTER, rf) != 0) {
		fprintf(stderr, "lfu: %s: LFU_RING_IOC_SET_FILTER: %s\n",
			t->path, strerror(errno));
		free(rf);
		return -1;
	}
	free(rf);
	return 0;
}

static void *lfu_kmdt_open(const struct lfu_opts *o)
{
	struct lfu_kmdt *t;

	t = calloc(1, sizeof(*t));
	if (t == NULL)
		return NULL;

	t->path = o->target;
	t->fd = open(t->path, O_RDONLY);
	if (t->fd < 0) {
		fprintf(stderr,
			"lfu: cannot open %s: %s%s\n", t->path,
			strerror(errno),
			errno == ENOENT ?
			" — is the lfu_ring module loaded?" :
			errno == EBUSY ?
			" — another scan is running (single reader)" : "");
		free(t);
		return NULL;
	}

	if (lfu_kmdt_negotiate(t, o) != 0) {
		close(t->fd);
		free(t);
		return NULL;
	}
	return t;
}

static void lfu_kmdt_close(void *tgt)
{
	struct lfu_kmdt *t = tgt;

	close(t->fd);
	free(t);
}

static void *lfu_kmdt_worker_init(void *tgt, const struct lfu_opts *o)
{
	return tgt;
}

static void lfu_kmdt_worker_fini(void *tgt, void *wctx)
{
}

/*
 * The wire record to the core's record.  Tier-1 values arrive decoded, so
 * rec.t1 is filled straight from the wire and marked valid; the core then
 * prints them without a second decode, and does not filter (pushdown).
 */
static void lfu_kmdt_rec(const struct lfu_wire_rec *wr, struct lfu_rec *rec)
{
	memset(rec, 0, sizeof(*rec));
	rec->id = wr->wr_oid;
	rec->fid.f_seq = wr->wr_fid_seq;
	rec->fid.f_oid = wr->wr_fid_oid;
	rec->fid.f_ver = wr->wr_fid_ver;
	rec->lma_compat = wr->wr_lma_compat;
	rec->lma_incompat = wr->wr_lma_incompat;
	rec->mode = (uint16_t)wr->wr_mode;
	rec->nlink = wr->wr_nlink;
	rec->uid = wr->wr_uid;
	rec->gid = wr->wr_gid;
	rec->projid = wr->wr_projid;
	/* la_flags is the LUSTRE_*_FL word; the five --attrs bits are the
	 * same numbers on ext4 and in STATX, so mask rather than translate */
	rec->flags = wr->wr_flags & LFU_ATTR_ALL;
	rec->size = wr->wr_size;
	rec->blocks = wr->wr_blocks;
	rec->atime = (uint32_t)wr->wr_atime;
	rec->mtime = (uint32_t)wr->wr_mtime;
	rec->ctime = (uint32_t)wr->wr_ctime;
	rec->crtime = (uint32_t)wr->wr_btime;
	rec->has_ext_ea = !!(wr->wr_lfu & LFU_WR_XA_EXTERNAL);
	rec->unknown = !!(wr->wr_lfu & LFU_WR_UNKNOWN);

	if (wr->wr_lfu & (LFU_WR_HAVE_SOM | LFU_WR_HAVE_LOV | LFU_WR_HAVE_LMV)) {
		struct lfu_tier1 *t1 = &rec->t1;

		if (wr->wr_lfu & LFU_WR_HAVE_SOM) {
			t1->have_som = 1;
			t1->som_valid = wr->wr_som_valid;
			t1->som_size = wr->wr_som_size;
			t1->som_blocks = wr->wr_som_blocks;
		}
		if (wr->wr_lfu & LFU_WR_HAVE_LOV) {
			t1->have_lov = 1;
			t1->stripe_count = wr->wr_stripe_count;
			t1->stripe_size = wr->wr_stripe_size;
			memcpy(t1->pool, wr->wr_pool, sizeof(t1->pool));
			t1->pool[sizeof(t1->pool) - 1] = '\0';
		}
		if (wr->wr_lfu & LFU_WR_HAVE_LMV) {
			t1->have_lmv = 1;
			t1->lmv_count = wr->wr_lmv_count;
			t1->lmv_hash = wr->wr_lmv_hash;
		}
		rec->t1_valid = 1;
	}
}

static int lfu_kmdt_scan_chunk(void *tgt, void *wctx, struct lfu_ctx *cx,
			       uint64_t idx, int *done)
{
	struct lfu_kmdt *t = tgt;
	struct lfu_wire_rec *wr;
	ssize_t got;
	size_t i, n;

	if (idx > 0) {		/* single sequential stream */
		*done = 1;
		return 0;
	}

	wr = malloc(LFU_KMDT_BATCH * sizeof(*wr));
	if (wr == NULL)
		return -1;

	while (!cx->stop) {
		got = read(t->fd, wr, LFU_KMDT_BATCH * sizeof(*wr));
		if (got < 0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "lfu: stream read: %s%s\n",
				strerror(errno),
				errno == EOPNOTSUPP ?
				" — the OSD could not serve a demanded xattr" :
				"");
			free(wr);
			return -1;
		}
		if (got == 0)
			break;	/* EOF: scan complete */

		n = (size_t)got / sizeof(*wr);
		for (i = 0; i < n; i++) {
			struct lfu_rec rec;
			int have_lma;

			/* --limit is reached mid-batch, and a batch is 8192
			 * records: without this the whole batch is still
			 * emitted (found on the lab, 2026-08-17). */
			if (cx->stop)
				break;

			cx->st->seen++;
			lfu_kmdt_rec(&wr[i], &rec);

			/* The FID itself came from the object's LMA in the
			 * OSD (or was synthesised for a pre-2.0 IGIF), so its
			 * presence is the have_lma signal. */
			have_lma = (rec.fid.f_seq != 0);

			/* prefilter is a no-op for a pushdown backend; kept
			 * so the pipeline reads the same in every backend */
			if (!lfu_prefilter(cx, &rec))
				continue;
			lfu_object(cx, &rec, have_lma, NULL);
		}
	}

	free(wr);

	/*
	 * The kernel's counters, folded into the ordinary summary: what the
	 * filter rejected at each tier, what was undecided, and where the
	 * xattr bytes came from.  Only the kernel knows these -- the records
	 * that reach us are the survivors.
	 */
	if (ioctl(t->fd, LFU_RING_IOC_STATS, &t->st) == 0) {
		t->have_stats = 1;
		cx->st->filtered = t->st.rs_filtered0;
		cx->st->filtered1 = t->st.rs_filtered1;
		cx->st->unknown = t->st.rs_unknown;
		cx->st->tier2_read = t->st.rs_xa_ext;
	}

	*done = 1;
	return 0;
}

static void lfu_kmdt_report(const struct lfu_stats *st, double secs, void *tgt)
{
	struct lfu_kmdt *t = tgt;
	int i;

	fprintf(stderr, "stream complete in %.2fs (live MDT via lfu_ring)\n",
		secs);
	fprintf(stderr, "  records seen  : %" PRIu64 "\n", st->seen);
	for (i = 0; i < LFU_CLS_MAX; i++)
		if (st->cls[i])
			fprintf(stderr, "  %-14s: %" PRIu64 "\n",
				lfu_class_name[i], st->cls[i]);
	fprintf(stderr, "  filtered (t0) : %" PRIu64 "  (in kernel)\n",
		st->filtered);
	fprintf(stderr, "  filtered (t1) : %" PRIu64 "  (in kernel)\n",
		st->filtered1);
	fprintf(stderr, "  undecided     : %" PRIu64 "\n", st->unknown);
	fprintf(stderr, "emitted         : %" PRIu64 "\n", st->emitted);
	if (t->have_stats) {
		const struct lfu_ring_stats *k = &t->st;
		uint64_t looked = k->rs_seen - k->rs_filtered0;

		fprintf(stderr,
			"kernel: seen=%" PRIu64 " emitted=%" PRIu64
			" raw=%" PRIu64 " fallback=%" PRIu64
			" xattr: inline=%" PRIu64 " external=%" PRIu64
			" iget=%" PRIu64 " toolarge=%" PRIu64 " err=%" PRIu64
			" stalls=%" PRIu64 " rc=%d\n",
			(uint64_t)k->rs_seen, (uint64_t)k->rs_emitted,
			(uint64_t)k->rs_raw, (uint64_t)k->rs_fallback,
			(uint64_t)k->rs_xa_inline, (uint64_t)k->rs_xa_ext,
			(uint64_t)k->rs_xa_iget, (uint64_t)k->rs_xa_toolarge,
			(uint64_t)k->rs_xa_err, (uint64_t)k->rs_stalls,
			k->rs_err);
		/* tier 2 as a rate over the objects the filter looked inside:
		 * a tier-0 reject never had an xattr read, so it is not in
		 * the denominator */
		fprintf(stderr,
			"tier-2 (read)   : %" PRIu64 " (%.2f%% of the %" PRIu64
			" objects tier 1 examined)\n",
			(uint64_t)k->rs_xa_ext,
			looked ? 100.0 * (double)k->rs_xa_ext / (double)looked
			       : 0.0,
			looked);
	}
	/*
	 * The rate must be over the objects the KERNEL walked, not over the
	 * records that reached us: with the filter pushed down those are the
	 * survivors, and dividing 1 survivor by the wall clock reports 9
	 * objects/sec for a scan that did 302,122 (found on the lab,
	 * 2026-08-17).  st->seen is right only when no filter was set.
	 */
	if (secs > 0.0) {
		uint64_t scanned = t->have_stats ? t->st.rs_seen : st->seen;

		fprintf(stderr, "objects scanned : %" PRIu64 "%s\n", scanned,
			t->have_stats ? " (in kernel)" : "");
		fprintf(stderr, "rate            : %.0f objects/sec\n",
			(double)scanned / secs);
	}
}

static int lfu_kmdt_parse_opt(int c, const char *arg, struct lfu_opts *o)
{
	return -1;
}

static const struct lfu_target_ops lfu_kmdt_ops = {
	.name		= "kmdt",
	.id_label	= "ino",
	.usage_target	= "/dev/" LFU_RING_DEVNAME,
	.usage_extra	=
"\nThe lfu_ring kernel module must be loaded with dev=<osd name>; the MDT\n"
"stays mounted and serving.  The stream is single-reader: -j is forced to 1.\n"
"\n"
"The filter is evaluated IN THE KERNEL, tier by tier, before a record enters\n"
"the ring; what this side receives is already the answer.  Whether tier-1\n"
"predicates (--size, --pool, --name, ...) are available depends on the OSD\n"
"under the module: yes on ldiskfs, not yet on ZFS.  It is asked at open time\n"
"and a filter the kernel cannot answer is refused before the scan starts.\n",
	/*
	 * The static declaration is the most permissive: everything is
	 * answerable somewhere.  What THIS module's OSD can do is asked at
	 * open time (LFU_RING_IOC_INFO) and refused there if narrower.
	 */
	.can_supply	= LFU_NEED_SOM | LFU_NEED_LOV | LFU_NEED_LMV |
			  LFU_NEED_LINK,
	.attr_mask	= LFU_ATTR_ALL,
	.missing_fields	= 0,	/* wire v2 carries btime, projid and flags */
	.pushdown	= 1,
	.parse_opt	= lfu_kmdt_parse_opt,
	.open		= lfu_kmdt_open,
	.close		= lfu_kmdt_close,
	.worker_init	= lfu_kmdt_worker_init,
	.worker_fini	= lfu_kmdt_worker_fini,
	.scan_chunk	= lfu_kmdt_scan_chunk,
	.report		= lfu_kmdt_report,
};

int main(int argc, char **argv)
{
	/* the stream is sequential; quietly run single-threaded */
	int i;

	for (i = 1; i < argc - 1; i++)
		if (strcmp(argv[i], "-j") == 0)
			argv[i + 1] = "1";

	return lfu_main(&lfu_kmdt_ops, argc, argv);
}
