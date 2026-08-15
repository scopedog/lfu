/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU kernel-MDT Input Scanner — the userspace half of Option 2 (step 4).
 *
 * Reads the Object Stream the lfu_ring kernel module produces from the
 * otable iterator of a MOUNTED MDT, and hands each record to the common
 * core (lfu_core.c).  This is the third lfu_target_ops backend: same
 * classification ladder, tier-0 filters, record format and stats as the
 * ldiskfs and ZFS device scanners — different device layer, and the only
 * one that works while the target is serving.
 *
 * Prototype honesty:
 *   - the wire record carries no LMA compat/incompat flags yet, so
 *     classification runs on the FID sequence alone: LMAC_NOT_IN_OI and
 *     LMAI_AGENT objects cannot be told apart from their sequence class.
 *     Extending the wire record (and dt_otable_rec) is the known fix.
 *   - the stream is inherently ordered and single-reader: -j is forced
 *     to 1.  Parallelism belongs behind the enumerator in the kernel
 *     (measured in step 2), not here.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/types.h>
#include <inttypes.h>

#include "lfu_scan.h"
#include "kernel/lfu_ring.h"

#define LFU_KMDT_BATCH	8192	/* records per read() */

struct lfu_kmdt {
	int fd;
	const char *path;
};

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

	fprintf(stderr,
		"note        : kernel-side stream; LMA flags not in the wire "
		"record yet — classification is by FID sequence only\n");
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
			fprintf(stderr, "lfu: stream read: %s\n",
				strerror(errno));
			free(wr);
			return -1;
		}
		if (got == 0)
			break;	/* EOF: scan complete */

		n = (size_t)got / sizeof(*wr);
		for (i = 0; i < n; i++) {
			struct lfu_rec rec;
			int have_lma;

			cx->st->seen++;

			memset(&rec, 0, sizeof(rec));
			rec.id = wr[i].wr_oid;
			rec.fid.f_seq = wr[i].wr_fid_seq;
			rec.fid.f_oid = wr[i].wr_fid_oid;
			rec.fid.f_ver = wr[i].wr_fid_ver;
			rec.mode = (uint16_t)wr[i].wr_mode;
			rec.nlink = wr[i].wr_nlink;
			rec.uid = wr[i].wr_uid;
			rec.gid = wr[i].wr_gid;
			rec.size = wr[i].wr_size;
			rec.blocks = wr[i].wr_blocks;
			rec.atime = (uint32_t)wr[i].wr_atime;
			rec.mtime = (uint32_t)wr[i].wr_mtime;
			rec.ctime = (uint32_t)wr[i].wr_ctime;

			/* No LMA flags on the wire (yet): the FID itself came
			 * from the object's LMA in the OSD, so its presence
			 * is the have_lma signal. */
			have_lma = (rec.fid.f_seq != 0);

			if (!lfu_prefilter(cx, &rec))
				continue;
			lfu_object(cx, &rec, have_lma);
		}
	}

	free(wr);
	*done = 1;
	return 0;
}

static void lfu_kmdt_report(const struct lfu_stats *st, double secs, void *tgt)
{
	int i;

	fprintf(stderr, "stream complete in %.2fs (live MDT via lfu_ring)\n",
		secs);
	fprintf(stderr, "  records seen  : %" PRIu64 "\n", st->seen);
	for (i = 0; i < LFU_CLS_MAX; i++)
		if (st->cls[i])
			fprintf(stderr, "  %-14s: %" PRIu64 "\n",
				lfu_class_name[i], st->cls[i]);
	fprintf(stderr, "  filtered      : %" PRIu64 "\n", st->filtered);
	fprintf(stderr, "emitted         : %" PRIu64 "\n", st->emitted);
	if (secs > 0.0)
		fprintf(stderr, "rate            : %.0f objects/sec\n",
			(double)st->seen / secs);
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
"stays mounted and serving.  The stream is single-reader: -j is forced to 1.\n",
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
