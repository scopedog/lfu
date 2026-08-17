// SPDX-License-Identifier: LGPL-2.1+
/*
 * LFU Device Input Scanner — backend-independent core.
 *
 * See lfu_scan.h for the core/backend split.  Nothing in this file may
 * include a device library header; if a change here needs one, it belongs
 * in a backend.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <pthread.h>

#include "lfu_scan.h"

const char *const lfu_class_name[LFU_CLS_MAX] = {
	"visible", "internal", "ost-obj", "agent", "no-lma", "bad"
};

/* ------------------------------------------------------------------ */
/* §5 — classification ladder, mirroring osd_scrub_get_fid()          */

enum lfu_class lfu_classify(const struct lfu_rec *rec, int have_lma)
{
	uint64_t seq;

	if (!have_lma) {
		/* No LMA: pre-2.0 IGIF candidate on ldiskfs; on osd-zfs also
		 * the OSD's own xattr-less directory hierarchy (verified on a
		 * real MDT 2026-08-07).  Never synthesise a FID here — that
		 * is LFSCK's job (design §5.3).
		 */
		return LFU_CLS_NO_LMA;
	}

	if (rec->lma_incompat & ~(uint32_t)LMA_INCOMPAT_SUPP)
		return LFU_CLS_BAD;
	if (rec->lma_compat & LMAC_NOT_IN_OI)
		return LFU_CLS_INTERNAL;
	if (rec->lma_incompat & LMAI_AGENT)
		return LFU_CLS_AGENT;

	seq = rec->fid.f_seq;
	if (rec->lma_compat & LMAC_FID_ON_OST)
		return LFU_CLS_OST_OBJ;
	if (fid_seq_is_idif(seq))
		return LFU_CLS_OST_OBJ;
	if (fid_seq_is_internal(seq))
		return LFU_CLS_INTERNAL;
	if (fid_seq_is_namespace_visible(seq))
		return LFU_CLS_VISIBLE;
	return LFU_CLS_INTERNAL;
}

/* ------------------------------------------------------------------ */
/* §7 — tier-0 filter                                                  */

int lfu_prefilter(struct lfu_ctx *cx, const struct lfu_rec *rec)
{
	if (!lfu_filter_active(&cx->o->filter) || cx->ops->pushdown)
		return 1;
	if (lfu_filter_tier0(&cx->o->filter, rec, cx->now))
		return 1;
	cx->st->filtered++;
	return 0;
}

/* ------------------------------------------------------------------ */
/* Record emission                                                     */

static char lfu_type_char(uint16_t mode)
{
	switch (mode & 0170000) {
	case 0100000:	return 'f';
	case 0040000:	return 'd';
	case 0120000:	return 'l';
	case 0060000:	return 'b';
	case 0020000:	return 'c';
	case 0010000:	return 'p';
	case 0140000:	return 's';
	default:	return '?';
	}
}

/*
 * One printf per record: with -j >1 several workers share stdout, and glibc
 * locks the stream per call, so a single call is what keeps lines intact.
 *
 * Note: HSM released state is NOT an LMA flag — LMAI_RELEASED is vestigial
 * and not in LMA_INCOMPAT_SUPP.  Released files carry HS_RELEASED in
 * trusted.hsm, which is a tier-2 read (design §5).
 */
static void lfu_emit(const struct lfu_ctx *cx, const char *prefix,
		     const struct lfu_rec *rec, const char *suffix)
{
	const struct lfu_tier1 *t1 = rec->t1_valid ? &rec->t1 : NULL;
	char lay[96];

	/*
	 * Layout and SOM only appear once the filter has asked for them, so a
	 * pure tier-0 scan keeps the record format it has always had — the
	 * test suites compare these lines.
	 *
	 * Which means size= and blocks= are query-dependent: they carry the
	 * MDT inode's own numbers normally, and the *file's* numbers once a
	 * size predicate has caused trusted.som to be read.  That is
	 * deliberate — the record should report the best answer available for
	 * the work already done — but it does mean two scans of the same
	 * object can print different sizes, and a consumer comparing records
	 * across runs needs to know which question was asked.  A record format
	 * that named both fields separately would be better; that is a change
	 * to the output contract, not to this function.
	 */
	lay[0] = '\0';
	if (t1 != NULL && t1->have_lov)
		(void)snprintf(lay, sizeof(lay), " stripes=%u ssize=%u%s%s",
			       t1->stripe_count, t1->stripe_size,
			       t1->pool[0] ? " pool=" : "",
			       t1->pool[0] ? t1->pool : "");

	printf("%s[0x%" PRIx64 ":0x%x:0x%x] %s=%" PRIu64 " %c mode=%04o "
	       "nlink=%u uid=%u gid=%u projid=%u size=%" PRIu64
	       " blocks=%" PRIu64 " atime=%u mtime=%u%s%s%s%s%s\n",
	       prefix,
	       rec->fid.f_seq, rec->fid.f_oid, rec->fid.f_ver,
	       cx->ops->id_label, rec->id,
	       lfu_type_char(rec->mode), rec->mode & 07777, rec->nlink,
	       rec->uid, rec->gid, rec->projid,
	       (t1 != NULL && t1->have_som) ? t1->som_size : rec->size,
	       (t1 != NULL && t1->have_som) ? t1->som_blocks : rec->blocks,
	       rec->atime, rec->mtime, lay,
	       rec->has_ext_ea ? " +extea" : "",
	       (rec->lma_incompat & LMAI_ORPHAN) ? " +orphan" : "",
	       (rec->lma_incompat & LMAI_ENCRYPT) ? " +encrypted" : "",
	       suffix);
}

void lfu_object(struct lfu_ctx *cx, struct lfu_rec *rec, int have_lma,
		const struct lfu_eas *eas)
{
	const struct lfu_filter *f = &cx->o->filter;
	enum lfu_class cls;
	enum lfu_match m = LFU_MATCH;

	cls = lfu_classify(rec, have_lma);
	cx->st->cls[cls]++;

	/*
	 * Decode the demanded xattrs once, into the record, so both the
	 * filter and the emitted line see the same values.  A pushdown
	 * backend hands them over already decoded (rec->t1_valid set).
	 */
	if (cx->needs != 0 && !rec->t1_valid) {
		lfu_ea_decode(&rec->t1, eas);
		rec->t1_valid = 1;
		if (eas != NULL && eas->external)
			cx->st->tier2_read++;
	}

	/*
	 * Diagnostic mode: one class-tagged line per classified object.
	 * This is how the no-lma population on a real target was found;
	 * there was previously no way to see it.  It shows objects before the
	 * tier-1 filter, deliberately — that is what makes it a diagnostic.
	 */
	if (cx->o->verbose && !cx->o->quiet) {
		char pfx[16];

		(void)snprintf(pfx, sizeof(pfx), "%-8s ",
		    lfu_class_name[cls]);
		lfu_emit(cx, pfx, rec, "");
	}

	if (cls != LFU_CLS_VISIBLE &&
	    !(cx->o->show_internal && cls == LFU_CLS_INTERNAL))
		return;

	/*
	 * §7 — tier 1, now that the demanded xattrs are in hand.  Run after
	 * classification so that internal objects, which are never emitted,
	 * do not inflate the filter counters or the unknown population.
	 */
	if (cx->ops->pushdown) {
		/* the backend already applied the filter; honour its verdict */
		m = rec->unknown ? LFU_UNKNOWN : LFU_MATCH;
	} else if (cx->needs != 0) {
		m = lfu_filter_tier1(f, rec, &rec->t1, eas);
		if (m == LFU_NOMATCH) {
			cx->st->filtered1++;
			return;
		}
		if (m == LFU_UNKNOWN) {
			cx->st->unknown++;
			if (!cx->o->emit_unknown)
				return;
		}
	}

	cx->st->emitted++;
	if (!cx->o->quiet && !cx->o->verbose)
		lfu_emit(cx, "", rec, m == LFU_UNKNOWN ? " +unknown" : "");

	if (cx->o->limit && cx->st->emitted >= cx->o->limit)
		cx->stop = 1;
}

/* ------------------------------------------------------------------ */
/* Stats merge                                                         */

static void lfu_stats_merge(struct lfu_stats *acc, const struct lfu_stats *s)
{
	int i;

	acc->seen += s->seen;
	acc->emitted += s->emitted;
	acc->filtered += s->filtered;
	acc->filtered1 += s->filtered1;
	acc->unknown += s->unknown;
	for (i = 0; i < LFU_CLS_MAX; i++)
		acc->cls[i] += s->cls[i];
	acc->free_ino += s->free_ino;
	acc->deleted += s->deleted;
	acc->in_use += s->in_use;
	acc->tier2 += s->tier2;
	acc->tier2_read += s->tier2_read;
	acc->csum_bad += s->csum_bad;
	acc->validate_bad += s->validate_bad;
	acc->not_znode += s->not_znode;
	acc->sa_fail += s->sa_fail;
	acc->unlinked += s->unlinked;
	acc->no_dxattr += s->no_dxattr;
	if (s->max_bonus > acc->max_bonus)
		acc->max_bonus = s->max_bonus;
}

/* ------------------------------------------------------------------ */
/* §8 — chunked parallel scan                                          */
/*
 * Work is handed out as chunk indices from a shared cursor rather than N
 * equal slices: object allocation is sparse and clustered on both backends,
 * so equal slices imbalance badly.  The backend maps an index onto its own
 * id space and sets *done when it has proved there is nothing at or beyond
 * that chunk.
 */

struct lfu_work {
	void *tgt;
	const struct lfu_target_ops *ops;
	const struct lfu_opts *o;
	pthread_mutex_t lock;
	uint64_t cursor;
	int done;
	int error;
	time_t now;
};

struct lfu_worker {
	struct lfu_work *w;
	struct lfu_stats st;
	pthread_t tid;
};

static int lfu_next_chunk(struct lfu_work *w, uint64_t *idx)
{
	int got = 0;

	pthread_mutex_lock(&w->lock);
	if (!w->done)
		*idx = w->cursor++, got = 1;
	pthread_mutex_unlock(&w->lock);
	return got;
}

static void lfu_set_done(struct lfu_work *w, int error)
{
	pthread_mutex_lock(&w->lock);
	w->done = 1;
	w->error |= error;
	pthread_mutex_unlock(&w->lock);
}

static void *lfu_worker_main(void *arg)
{
	struct lfu_worker *me = arg;
	struct lfu_work *w = me->w;
	struct lfu_ctx cx = {
		.o = w->o, .st = &me->st, .ops = w->ops, .now = w->now,
		.needs = lfu_filter_needs(&w->o->filter),
	};
	void *wctx;
	uint64_t idx;
	int done;

	wctx = w->ops->worker_init(w->tgt, w->o);
	if (wctx == NULL) {
		lfu_set_done(w, 1);
		return NULL;
	}

	while (!cx.stop && lfu_next_chunk(w, &idx)) {
		done = 0;
		if (w->ops->scan_chunk(w->tgt, wctx, &cx, idx, &done) != 0) {
			lfu_set_done(w, 1);
			break;
		}
		if (done || cx.stop) {
			lfu_set_done(w, 0);
			break;
		}
	}

	w->ops->worker_fini(w->tgt, wctx);
	return NULL;
}

static int lfu_scan(const struct lfu_target_ops *ops, void *tgt,
		    const struct lfu_opts *o, struct lfu_stats *st)
{
	struct lfu_work w = {
		.tgt = tgt, .ops = ops, .o = o, .now = time(NULL),
	};
	struct lfu_worker *workers;
	int nthreads = o->threads;
	int i, rc;

	pthread_mutex_init(&w.lock, NULL);

	workers = calloc(nthreads, sizeof(*workers));
	if (workers == NULL) {
		fprintf(stderr, "lfu: out of memory for %d workers\n",
			nthreads);
		return 1;
	}
	for (i = 0; i < nthreads; i++)
		workers[i].w = &w;

	if (nthreads == 1) {
		/* keep the single-threaded path free of thread setup */
		lfu_worker_main(&workers[0]);
	} else {
		for (i = 0; i < nthreads; i++) {
			if (pthread_create(&workers[i].tid, NULL,
			    lfu_worker_main, &workers[i]) != 0) {
				fprintf(stderr,
					"lfu: cannot start worker %d\n", i);
				nthreads = i;
				break;
			}
		}
		for (i = 0; i < nthreads; i++)
			pthread_join(workers[i].tid, NULL);
	}

	for (i = 0; i < nthreads; i++)
		lfu_stats_merge(st, &workers[i].st);

	rc = w.error;
	free(workers);
	pthread_mutex_destroy(&w.lock);
	return rc;
}

/* ------------------------------------------------------------------ */
/* CLI                                                                 */

static void usage(const struct lfu_target_ops *ops, const char *prog)
{
	fprintf(stderr,
"Usage: %s [options] [filters] %s\n"
"\n"
"Scan a Lustre %s target read-only and emit one record per\n"
"namespace-visible object.\n"
"\n"
"  -j, --threads N         parallel workers over object-id chunks (default 1;\n"
"                          record order is then unspecified)\n"
"  -i, --show-internal     also emit internal objects\n"
"  -n, --limit N           stop after N emitted records (forces -j 1)\n"
"  -q, --quiet             statistics only, no records\n"
"  -u, --emit-unknown      also emit records the filter cannot decide,\n"
"                          tagged +unknown (default: count them only)\n"
"  -v, --verbose           one class-tagged line per classified object\n"
"  -h, --help              this help\n"
"%s%s",
		prog, ops->usage_target, ops->name,
		lfu_filter_usage,
		ops->usage_extra ? ops->usage_extra : "");
}

int lfu_main(const struct lfu_target_ops *ops, int argc, char **argv)
{
	struct lfu_opts o = { .threads = 1 };
	struct lfu_stats st = { 0 };
	struct timespec t0, t1;
	struct option lopts[80];
	char optstring[64];
	uint32_t missing;
	void *tgt;
	int c, n = 0, rc;

	static const struct option common[] = {
		/* Legacy spellings, kept because the LUG 2026 slide-21 example
		 * and the test suites are written with them.  Each compiles
		 * into the same predicate its lfs find name does — except -b,
		 * which was and remains a test of the target's own block
		 * count, i.e. --dev-blocks (see docs/filter-levels.md §4).
		 */
		{ "atime-older",   required_argument, NULL, 'a' },
		{ "blocks-gt",     required_argument, NULL, 'b' },
		{ "threads",       required_argument, NULL, 'j' },
		{ "show-internal", no_argument,       NULL, 'i' },
		{ "limit",         required_argument, NULL, 'n' },
		{ "quiet",         no_argument,       NULL, 'q' },
		{ "emit-unknown",  no_argument,       NULL, 'u' },
		{ "verbose",       no_argument,       NULL, 'v' },
		{ "help",          no_argument,       NULL, 'h' },
	};

	for (size_t k = 0; k < sizeof(common) / sizeof(common[0]); k++)
		lopts[n++] = common[k];
	for (const struct option *p = lfu_filter_options; p->name != NULL; p++)
		lopts[n++] = *p;
	if (ops->lopts_extra != NULL)
		for (const struct option *p = ops->lopts_extra;
		     p->name != NULL; p++)
			lopts[n++] = *p;
	memset(&lopts[n], 0, sizeof(lopts[0]));

	/*
	 * A leading '-' makes getopt return non-option arguments as they come
	 * (code 1) instead of permuting them to the end.  That is how `!` is
	 * recognised in place, the same trick lfs find uses, and it also means
	 * the target can be collected here rather than from optind.
	 */
	(void)snprintf(optstring, sizeof(optstring), "-a:b:j:in:quvh%s",
	    ops->optstring_extra ? ops->optstring_extra : "");

	while ((c = getopt_long(argc, argv, optstring, lopts, NULL)) != -1) {
		switch (c) {
		case 1:		/* a non-option argument */
			if (strcmp(optarg, "!") == 0) {
				(void)lfu_filter_opt(&o.filter, LFU_OPT_NOT,
						     NULL);
				break;
			}
			if (o.target != NULL) {
				fprintf(stderr,
					"lfu: one target at a time (got '%s' "
					"after '%s')\n", optarg, o.target);
				return 2;
			}
			o.target = optarg;
			break;
		case 'a': {
			/* --atime-older SEC: seconds, and "older than" */
			char buf[32];

			(void)snprintf(buf, sizeof(buf), "+%ss", optarg);
			if (lfu_filter_opt(&o.filter, LFU_OPT_ATIME, buf) != 0)
				return 2;
			break;
		}
		case 'b': {
			/* --blocks-gt N: N in 512-byte units, "more than" */
			char buf[32];

			(void)snprintf(buf, sizeof(buf), "+%s", optarg);
			if (lfu_filter_opt(&o.filter, LFU_OPT_DEV_BLOCKS,
					   buf) != 0)
				return 2;
			break;
		}
		case 'j':
			o.threads = (int)strtol(optarg, NULL, 0);
			if (o.threads < 1) {
				fprintf(stderr, "lfu: -j must be >= 1\n");
				return 2;
			}
			break;
		case 'i': o.show_internal = 1; break;
		case 'n': o.limit = strtoull(optarg, NULL, 0); break;
		case 'q': o.quiet = 1; break;
		case 'u': o.emit_unknown = 1; break;
		case 'v': o.verbose = 1; break;
		case 'h': usage(ops, argv[0]); return 0;
		default:
			rc = lfu_filter_opt(&o.filter, c, optarg);
			if (rc == 0)
				break;
			if (rc == -2)
				return 2;
			if (ops->parse_opt != NULL &&
			    ops->parse_opt(c, optarg, &o) == 0)
				break;
			usage(ops, argv[0]);
			return 2;
		}
	}

	if (o.target == NULL || lfu_filter_check(&o.filter) != 0) {
		usage(ops, argv[0]);
		return 2;
	}

	/*
	 * §9 — refuse a filter this backend cannot answer, rather than run a
	 * scan that quietly tests fewer predicates than were asked for.
	 */
	missing = lfu_filter_needs(&o.filter) & ~ops->can_supply;
	if (missing != 0) {
		fprintf(stderr,
			"lfu: the %s backend cannot supply%s%s%s%s needed by "
			"this filter\n", ops->name,
			(missing & LFU_NEED_SOM) ? " trusted.som" : "",
			(missing & LFU_NEED_LOV) ? " trusted.lov" : "",
			(missing & LFU_NEED_LMV) ? " trusted.lmv" : "",
			(missing & LFU_NEED_LINK) ? " trusted.link" : "");
		return 2;
	}

	{
		uint32_t bad = lfu_filter_fields_used(&o.filter) &
			       ops->missing_fields;

		if (bad != 0) {
			fprintf(stderr, "lfu: the %s backend does not carry:",
				ops->name);
			for (int f = 0; f < LFU_F_MAX; f++)
				if (bad & LFU_FIELD_BIT(f))
					fprintf(stderr, " %s",
						lfu_field_name(f));
			fprintf(stderr, "\n");
			return 2;
		}
	}

	{
		uint32_t attrs = lfu_filter_attrs_used(&o.filter);

		if ((attrs & ~ops->attr_mask) != 0) {
			fprintf(stderr,
				"lfu: the %s backend cannot see%s%s of --attrs; "
				"no answer is better than a wrong one\n",
				ops->name,
				(attrs & ~ops->attr_mask & LFU_ATTR_COMPRESSED) ?
					" Compressed" : "",
				(attrs & ~ops->attr_mask & LFU_ATTR_ENCRYPTED) ?
					" Encrypted" : "");
			return 2;
		}
	}

	/* --limit counts emitted records; only well defined in one thread */
	if (o.limit && o.threads > 1) {
		fprintf(stderr, "lfu: --limit forces a single worker\n");
		o.threads = 1;
	}

	tgt = ops->open(&o);
	if (tgt == NULL)
		return 1;

	clock_gettime(CLOCK_MONOTONIC, &t0);
	rc = lfu_scan(ops, tgt, &o, &st);
	clock_gettime(CLOCK_MONOTONIC, &t1);

	ops->report(&st, (double)(t1.tv_sec - t0.tv_sec) +
		    (double)(t1.tv_nsec - t0.tv_nsec) / 1e9, tgt);

	ops->close(tgt);
	return rc;
}
