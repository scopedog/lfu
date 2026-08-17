/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU ldiskfs Device Input Scanner — libext2fs backend.
 *
 * Scans an ldiskfs (ext4) MDT/OST block device read-only via libext2fs,
 * recovers Lustre FIDs from the trusted.lma xattr, and hands each object to
 * the common core (lfu_core.c) for classification and emission.
 *
 * Design: docs/design-ldiskfs-scanner.md.  This file owns §8.2 (torn-read
 * defence) and §9.1 (device access, and now the parallel block-group scan);
 * §5 classification, §6/§7 cost tiers and the record format live in the core.
 *
 * Parallelism: libext2fs handles are not thread-safe, so each worker opens
 * its own read-only ext2_filsys and positions a private inode scan with
 * ext2fs_inode_scan_goto_blockgroup().  A chunk is a run of block groups.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <inttypes.h>

#include <ext2fs/ext2fs.h>

#include "lfu_scan.h"

/* ------------------------------------------------------------------ */
/* §8.2 — validate before trusting                                    */

/*
 * Heuristic validation of an inode read from a live device.  Cheap checks
 * that reject structures which cannot be legal, so a torn read is skipped
 * and counted rather than interpreted.  This is the fallback when
 * metadata_csum is unavailable (design §8.2, question M8).
 */
static int lfu_inode_plausible(const struct ext2_inode_large *ino,
			       unsigned int inode_size)
{
	uint16_t mode = ino->i_mode & LINUX_S_IFMT;

	if (ino->i_links_count == 0)
		return 0;

	switch (mode) {
	case LINUX_S_IFREG:
	case LINUX_S_IFDIR:
	case LINUX_S_IFLNK:
	case LINUX_S_IFBLK:
	case LINUX_S_IFCHR:
	case LINUX_S_IFIFO:
	case LINUX_S_IFSOCK:
		break;
	default:
		return 0;
	}

	/* i_extra_isize must fit inside the inode after the 128-byte base. */
	if (inode_size > EXT2_GOOD_OLD_INODE_SIZE) {
		if (ino->i_extra_isize > inode_size - EXT2_GOOD_OLD_INODE_SIZE)
			return 0;
		/* Must be at least large enough to contain itself. */
		if (ino->i_extra_isize != 0 &&
		    ino->i_extra_isize < sizeof(ino->i_extra_isize))
			return 0;
	}

	return 1;
}

/* ------------------------------------------------------------------ */
/* Attribute extraction                                                */

/* Tier 0 — everything here comes from the inode buffer we already hold. */
static void lfu_extract_tier0(const struct ext2_inode_large *in,
			      ext2_ino_t ino, unsigned int inode_size,
			      struct lfu_rec *rec)
{
	rec->id = ino;
	rec->mode = in->i_mode;
	rec->nlink = in->i_links_count;
	rec->uid = in->i_uid | ((uint32_t)in->osd2.linux2.l_i_uid_high << 16);
	rec->gid = in->i_gid | ((uint32_t)in->osd2.linux2.l_i_gid_high << 16);
	rec->size = in->i_size | ((uint64_t)in->i_size_high << 32);
	rec->blocks = in->i_blocks |
		      ((uint64_t)in->osd2.linux2.l_i_blocks_hi << 32);
	rec->atime = in->i_atime;
	rec->mtime = in->i_mtime;
	rec->ctime = in->i_ctime;

	/*
	 * i_flags feeds --attrs directly: ext4's on-disk bits and the
	 * STATX_ATTR_* values lfs find names are the same numbers for the five
	 * attributes LFU supports (lfu_lustre.h).
	 */
	rec->flags = in->i_flags;

	/* crtime and projid live in the extended part of a large inode and
	 * are only valid if i_extra_isize covers them.
	 */
	rec->crtime = 0;
	rec->projid = 0;
	if (inode_size > EXT2_GOOD_OLD_INODE_SIZE) {
		unsigned int have = EXT2_GOOD_OLD_INODE_SIZE + in->i_extra_isize;

		if (have >= offsetof(struct ext2_inode_large, i_crtime) +
			    sizeof(in->i_crtime))
			rec->crtime = in->i_crtime;
		if (have >= offsetof(struct ext2_inode_large, i_projid) +
			    sizeof(in->i_projid))
			rec->projid = in->i_projid;
	}

	/* i_file_acl != 0 means an external EA block — tier 2.  Testable with
	 * no extra I/O, which is what lets the filter layer avoid it (§6).
	 */
	rec->has_ext_ea = (in->i_file_acl != 0);
}

/*
 * Tier 1 — read trusted.lma and whatever else the compiled filter demands.
 *
 * Design question M9 — whether ext2fs_xattrs_read_inode() follows i_file_acl
 * to the external EA block — is **answered: it does.**  Measured 2026-08-17
 * against e2fsprogs 1.47.0 with tests/mkimage.sh's widelov1, a 60-stripe
 * 1472-byte trusted.lov that cannot fit a 1024-byte inode: all 60 stripes come
 * back from the first read_inode() pass, and debugfs confirms the value lives
 * in an external block.
 *
 * Two consequences, and they pull in opposite directions:
 *
 *  - Correctness is free.  A spilled xattr needs no second call and no
 *    hand-rolled inline parser, so every tier-1 predicate is answerable on
 *    every object.  The fallback below is therefore normally dead code, kept
 *    only for libext2fs builds that behave otherwise.
 *  - The *cost* is invisible.  The extra block read happens inside libext2fs,
 *    so it cannot be counted from out here.  What is countable is the
 *    condition: a filter that demands a tier-1 xattr from an object with
 *    i_file_acl set has necessarily paid for the block.  That is what
 *    st->tier2_read reports.
 */

/* Values handed back by libext2fs are ours to free. */
#define LFU_EA_BUFS	5

struct lfu_ea_bufs {
	void *p[LFU_EA_BUFS];
	int n;
};

static void lfu_ea_bufs_free(struct lfu_ea_bufs *b)
{
	while (b->n > 0)
		ext2fs_free_mem(&b->p[--b->n]);
}

static int lfu_ea_fetch(struct ext2_xattr_handle *h, const char *name,
			struct lfu_ea *ea, struct lfu_ea_bufs *bufs)
{
	void *val = NULL;
	size_t len = 0;

	if (bufs->n == LFU_EA_BUFS)
		return 0;
	if (ext2fs_xattr_get(h, name, &val, &len) != 0 || val == NULL)
		return 0;

	bufs->p[bufs->n++] = val;
	ea->buf = val;
	ea->len = len;
	return 1;
}

static void lfu_decode_lma(const void *val, size_t len,
			   struct lustre_mdt_attrs *lma, int *have_lma)
{
	const struct lustre_mdt_attrs *d = val;

	/* §8.2 item 4 — never trust a length field. */
	if (val == NULL || len < sizeof(*lma))
		return;

	/* On-disk LMA is little-endian; osd_get_lma() swabs on read. */
	lma->lma_compat = ext2fs_le32_to_cpu(d->lma_compat);
	lma->lma_incompat = ext2fs_le32_to_cpu(d->lma_incompat);
	lma->lma_self_fid.f_seq = ext2fs_le64_to_cpu(d->lma_self_fid.f_seq);
	lma->lma_self_fid.f_oid = ext2fs_le32_to_cpu(d->lma_self_fid.f_oid);
	lma->lma_self_fid.f_ver = ext2fs_le32_to_cpu(d->lma_self_fid.f_ver);
	*have_lma = 1;
}

/* Which demanded values are still missing after a pass over the handle? */
static uint32_t lfu_eas_missing(uint32_t needs, const struct lfu_eas *eas)
{
	uint32_t miss = 0;

	if ((needs & LFU_NEED_SOM) && eas->som.buf == NULL)
		miss |= LFU_NEED_SOM;
	if ((needs & LFU_NEED_LOV) && eas->lov.buf == NULL)
		miss |= LFU_NEED_LOV;
	if ((needs & LFU_NEED_LMV) && eas->lmv.buf == NULL)
		miss |= LFU_NEED_LMV;
	if ((needs & LFU_NEED_LINK) && eas->link.buf == NULL)
		miss |= LFU_NEED_LINK;
	return miss;
}

static void lfu_eas_fetch_set(struct ext2_xattr_handle *h, uint32_t want,
			      struct lfu_eas *eas, struct lfu_ea_bufs *bufs)
{
	if (want & LFU_NEED_SOM)
		lfu_ea_fetch(h, XATTR_NAME_SOM, &eas->som, bufs);
	if (want & LFU_NEED_LOV)
		lfu_ea_fetch(h, XATTR_NAME_LOV, &eas->lov, bufs);
	if (want & LFU_NEED_LMV)
		lfu_ea_fetch(h, XATTR_NAME_LMV, &eas->lmv, bufs);
	if (want & LFU_NEED_LINK)
		lfu_ea_fetch(h, XATTR_NAME_LINK, &eas->link, bufs);
}

static int lfu_read_xattrs(ext2_filsys fs, ext2_ino_t ino,
			   struct ext2_inode_large *inode, uint32_t needs,
			   struct lustre_mdt_attrs *lma, int *have_lma,
			   struct lfu_eas *eas, struct lfu_ea_bufs *bufs)
{
	struct ext2_xattr_handle *h = NULL;
	struct lfu_ea lma_ea = { NULL, 0 };
	uint32_t miss;
	int lma_missing;

	if (ext2fs_xattrs_open(fs, ino, &h) != 0)
		return -1;

	if (ext2fs_xattrs_read_inode(h, inode) != 0) {
		ext2fs_xattrs_close(&h);
		return -1;
	}

	lfu_ea_fetch(h, XATTR_NAME_LMA, &lma_ea, bufs);
	lfu_decode_lma(lma_ea.buf, lma_ea.len, lma, have_lma);
	lfu_eas_fetch_set(h, needs, eas, bufs);
	ext2fs_xattrs_close(&h);

	/*
	 * Per M9 above, that one pass already included the external block if
	 * there is one — so if this object has a block and the filter wanted a
	 * tier-1 value, the block was read.  Count it: this is the tier-2 rate
	 * design §9 asks to be visible rather than merely suffered.
	 */
	if (needs != 0 && inode->i_file_acl != 0)
		eas->external = 1;

	miss = lfu_eas_missing(needs, eas);
	lma_missing = !*have_lma;

	/*
	 * Nothing missing, or nothing outside the inode to go looking in: an
	 * absent xattr is normal (an unstriped file has no trusted.lov, a file
	 * never closed has no trusted.som) and must not cost a second read.
	 */
	if ((miss == 0 && !lma_missing) || inode->i_file_acl == 0)
		return 0;

	/* Tier 2: the external EA block, read only for what is still missing */
	if (ext2fs_xattrs_open(fs, ino, &h) != 0)
		return 0;
	if (ext2fs_xattrs_read(h) != 0) {
		ext2fs_xattrs_close(&h);
		return 0;
	}

	if (lma_missing) {
		struct lfu_ea again = { NULL, 0 };

		lfu_ea_fetch(h, XATTR_NAME_LMA, &again, bufs);
		lfu_decode_lma(again.buf, again.len, lma, have_lma);
	}
	lfu_eas_fetch_set(h, miss, eas, bufs);
	ext2fs_xattrs_close(&h);
	return 0;
}

/* ------------------------------------------------------------------ */
/* Backend state                                                       */

/*
 * Open flags (design §9.1):
 *   no EXT2_FLAG_RW      — this tool has no write path, ever
 *   SKIP_MMP             — Lustre targets enable MMP; we are read-only
 *   SOFTSUPP_FEATURES    — tolerate ldiskfs features this libext2fs
 *                          build does not fully implement
 *   64BITS               — Lustre targets are formatted with 64bit
 *   IGNORE_CSUM_ERRORS   — a live device yields torn reads; count them
 *                          rather than aborting the scan
 */
#define LFU_EXT2_FLAGS	(EXT2_FLAG_SKIP_MMP | EXT2_FLAG_SOFTSUPP_FEATURES | \
			 EXT2_FLAG_64BITS | EXT2_FLAG_IGNORE_CSUM_ERRORS)

struct lfu_ldiskfs {
	ext2_filsys fs;			/* main handle: banner + geometry */
	const char *device;
	unsigned int groups_per_chunk;
};

struct lfu_ldiskfs_worker {
	ext2_filsys fs;			/* private handle, private bitmap */
	ext2_inode_scan scan;
	struct ext2_inode_large *inode;
	unsigned int bufsize;
};

static void lfu_report_super(ext2_filsys fs)
{
	struct ext2_super_block *sb = fs->super;

	fprintf(stderr, "device      : %s\n", fs->device_name);
	fprintf(stderr, "inode size  : %u bytes\n", EXT2_INODE_SIZE(sb));
	fprintf(stderr, "inodes      : %u (%u per group, %u groups)\n",
		sb->s_inodes_count, sb->s_inodes_per_group, fs->group_desc_count);
	fprintf(stderr, "block size  : %u bytes\n", EXT2_BLOCK_SIZE(sb));
	fprintf(stderr, "features    :%s%s%s%s%s%s\n",
		ext2fs_has_feature_metadata_csum(sb) ? " metadata_csum" : "",
		ext2fs_has_feature_gdt_csum(sb) ? " uninit_bg" : "",
		ext2fs_has_feature_ea_inode(sb) ? " ea_inode" : "",
		ext2fs_has_feature_dirdata(sb) ? " dirdata" : "",
		ext2fs_has_feature_mmp(sb) ? " mmp" : "",
		ext2fs_has_feature_project(sb) ? " project" : "");

	/* §8.2 — this determines whether torn reads are detected exactly. */
	if (!ext2fs_has_feature_metadata_csum(sb))
		fprintf(stderr,
			"warning     : metadata_csum is OFF — torn reads can only be "
			"detected heuristically (design M8)\n");

	/* §8.3 — an unreplayed journal means we may see pre-crash state. */
	/*
	 * The RECOVER flag stays set for as long as the filesystem is mounted
	 * read-write and is cleared only on a clean unmount.  On a live target
	 * it therefore means "mounted", not "crashed" — firing a scary warning
	 * on every live scan would just train people to ignore it.  Either way
	 * the scan sees un-replayed on-disk state, so say that plainly.
	 */
	if (ext2fs_has_feature_journal_needs_recovery(sb))
		fprintf(stderr,
			"note        : journal not clean — target is mounted, or was "
			"not unmounted cleanly; scan sees un-replayed on-disk state\n");

	/* §10.2 — wide striping pushes every layout to an external EA block. */
	if (EXT2_INODE_SIZE(sb) < 1024)
		fprintf(stderr,
			"warning     : inode size %u < 1024 — Lustre xattrs likely "
			"external; expect high tier-2 rate (design §10.2)\n",
			EXT2_INODE_SIZE(sb));
}

/* ------------------------------------------------------------------ */
/* lfu_target_ops                                                      */

static void *lfu_ldiskfs_open(const struct lfu_opts *o)
{
	struct lfu_ldiskfs *t;
	unsigned int ipg;
	errcode_t err;

	t = calloc(1, sizeof(*t));
	if (t == NULL)
		return NULL;

	add_error_table(&et_ext2_error_table);

	err = ext2fs_open(o->target, LFU_EXT2_FLAGS, 0, 0, unix_io_manager,
			  &t->fs);
	if (err) {
		fprintf(stderr, "lfu: cannot open %s: %s\n",
			o->target, error_message(err));
		free(t);
		return NULL;
	}

	t->device = o->target;

	/*
	 * A chunk is enough block groups to cover ~64K inodes, so the chunk
	 * count stays in the thousands and the hand-out cursor is not a
	 * contention point.
	 */
	ipg = t->fs->super->s_inodes_per_group;
	t->groups_per_chunk = ipg ? (65536 + ipg - 1) / ipg : 1;
	if (t->groups_per_chunk < 1)
		t->groups_per_chunk = 1;

	lfu_report_super(t->fs);
	return t;
}

static void lfu_ldiskfs_close(void *tgt)
{
	struct lfu_ldiskfs *t = tgt;

	ext2fs_close_free(&t->fs);
	remove_error_table(&et_ext2_error_table);
	free(t);
}

static void *lfu_ldiskfs_worker_init(void *tgt, const struct lfu_opts *o)
{
	struct lfu_ldiskfs *t = tgt;
	struct lfu_ldiskfs_worker *wk;
	unsigned int inode_size;
	errcode_t err;

	wk = calloc(1, sizeof(*wk));
	if (wk == NULL)
		return NULL;

	/* Private handle: libext2fs is not thread-safe across a shared one. */
	err = ext2fs_open(t->device, LFU_EXT2_FLAGS, 0, 0, unix_io_manager,
			  &wk->fs);
	if (err) {
		fprintf(stderr, "lfu: worker open %s: %s\n",
			t->device, error_message(err));
		goto fail;
	}

	/* The allocation bitmap gates everything below (design §9.1). */
	err = ext2fs_read_inode_bitmap(wk->fs);
	if (err) {
		fprintf(stderr, "lfu: cannot read inode bitmap: %s\n",
			error_message(err));
		goto fail;
	}

	/* The scan buffer must be at least the on-disk inode size so the
	 * inline xattr region comes back with the inode (§6.1).
	 */
	inode_size = EXT2_INODE_SIZE(wk->fs->super);
	wk->bufsize = inode_size > sizeof(*wk->inode) ?
		      inode_size : sizeof(*wk->inode);
	err = ext2fs_get_memzero(wk->bufsize, &wk->inode);
	if (err) {
		fprintf(stderr, "lfu: cannot allocate inode buffer\n");
		goto fail;
	}

	err = ext2fs_open_inode_scan(wk->fs,
				     EXT2_INODE_SCAN_DEFAULT_BUFFER_BLOCKS,
				     &wk->scan);
	if (err) {
		fprintf(stderr, "lfu: ext2fs_open_inode_scan: %s\n",
			error_message(err));
		goto fail;
	}

	/* A checksum failure on a live device is very likely a torn read, not
	 * corruption — count it and carry on rather than aborting the scan.
	 */
	ext2fs_inode_scan_flags(wk->scan, EXT2_SF_SKIP_MISSING_ITABLE, 0);
	return wk;

fail:
	if (wk->inode)
		ext2fs_free_mem(&wk->inode);
	if (wk->fs)
		ext2fs_close_free(&wk->fs);
	free(wk);
	return NULL;
}

static void lfu_ldiskfs_worker_fini(void *tgt, void *wctx)
{
	struct lfu_ldiskfs_worker *wk = wctx;

	if (wk->scan)
		ext2fs_close_inode_scan(wk->scan);
	if (wk->inode)
		ext2fs_free_mem(&wk->inode);
	if (wk->fs)
		ext2fs_close_free(&wk->fs);
	free(wk);
}

static int lfu_ldiskfs_scan_chunk(void *tgt, void *wctx, struct lfu_ctx *cx,
				  uint64_t idx, int *done)
{
	struct lfu_ldiskfs *t = tgt;
	struct lfu_ldiskfs_worker *wk = wctx;
	struct lfu_stats *st = cx->st;
	ext2_filsys fs = wk->fs;
	unsigned int inode_size = EXT2_INODE_SIZE(fs->super);
	uint64_t ipg = fs->super->s_inodes_per_group;
	uint64_t g0 = idx * t->groups_per_chunk;
	uint64_t end_ino;
	ext2_ino_t ino;
	errcode_t err;

	if (g0 >= fs->group_desc_count) {
		*done = 1;
		return 0;
	}
	/* group g holds inodes [g*ipg + 1, (g+1)*ipg] */
	end_ino = (g0 + t->groups_per_chunk) * ipg;
	if (end_ino > fs->super->s_inodes_count) {
		end_ino = fs->super->s_inodes_count;
		*done = 1;
	}

	err = ext2fs_inode_scan_goto_blockgroup(wk->scan, (int)g0);
	if (err) {
		fprintf(stderr, "lfu: goto blockgroup %" PRIu64 ": %s\n",
			g0, error_message(err));
		return -1;
	}

	for (;;) {
		if (cx->stop)
			return 0;

		err = ext2fs_get_next_inode_full(wk->scan, &ino,
						 (struct ext2_inode *)wk->inode,
						 wk->bufsize);
		if (err == EXT2_ET_BAD_BLOCK_IN_INODE_TABLE) {
			st->csum_bad++;
			continue;
		}
		if (err) {
			fprintf(stderr, "lfu: inode scan: %s\n",
				error_message(err));
			return -1;
		}
		if (ino == 0) {
			*done = 1;	/* end of the whole table */
			return 0;
		}
		if ((uint64_t)ino > end_ino)
			return 0;	/* chunk finished */

		st->seen++;

		/* ext4 reserved inodes; the Lustre objects start above these. */
		if (ino < EXT2_FIRST_INODE(fs->super))
			continue;

		/*
		 * The allocation bitmap is the authority on which inodes exist
		 * (design §9.1) — ext2fs_get_next_inode() walks the inode table
		 * and happily returns freed inodes, whose contents are stale
		 * but still parseable.  The kernel's osd_iit_next() consults
		 * the bitmap for exactly this reason.
		 */
		if (!ext2fs_test_inode_bitmap2(fs->inode_map, ino)) {
			st->free_ino++;
			continue;
		}

		/* Belt and braces: a non-zero deletion time means the inode is
		 * gone even if the bitmap bit has not yet been cleared on disk.
		 */
		if (wk->inode->i_dtime != 0) {
			st->deleted++;
			continue;
		}

		if (!lfu_inode_plausible(wk->inode, inode_size)) {
			st->validate_bad++;
			if (cx->o->verbose)
				fprintf(stderr,
					"reject ino=%u mode=0%o nlink=%u "
					"extra_isize=%u dtime=%u\n",
					ino, wk->inode->i_mode,
					wk->inode->i_links_count,
					wk->inode->i_extra_isize,
					wk->inode->i_dtime);
			continue;
		}
		st->in_use++;

		struct lfu_rec rec;
		struct lustre_mdt_attrs lma;
		struct lfu_eas eas;
		struct lfu_ea_bufs bufs;
		int have_lma = 0;

		memset(&rec, 0, sizeof(rec));
		memset(&lma, 0, sizeof(lma));
		memset(&eas, 0, sizeof(eas));
		memset(&bufs, 0, sizeof(bufs));

		lfu_extract_tier0(wk->inode, ino, inode_size, &rec);
		if (rec.has_ext_ea)
			st->tier2++;

		/*
		 * §7 — tier-0 predicates first.  An object rejected here never
		 * costs an xattr parse, which is the entire point of the tier
		 * ordering.
		 */
		if (!lfu_prefilter(cx, &rec))
			continue;

		(void)lfu_read_xattrs(fs, ino, wk->inode, cx->needs, &lma,
				      &have_lma, &eas, &bufs);
		rec.lma_compat = lma.lma_compat;
		rec.lma_incompat = lma.lma_incompat;
		if (have_lma)
			rec.fid = lma.lma_self_fid;

		lfu_object(cx, &rec, have_lma, &eas);
		lfu_ea_bufs_free(&bufs);
	}
}

static void lfu_ldiskfs_report(const struct lfu_stats *st, double secs,
			       void *tgt)
{
	int i;

	fprintf(stderr, "\n--- scan summary ---\n");
	fprintf(stderr, "inodes seen     : %" PRIu64 "\n", st->seen);
	fprintf(stderr, "  free (bitmap) : %" PRIu64 "\n", st->free_ino);
	fprintf(stderr, "  deleted       : %" PRIu64 "\n", st->deleted);
	fprintf(stderr, "inodes in use   : %" PRIu64 "\n", st->in_use);
	for (i = 0; i < LFU_CLS_MAX; i++)
		if (st->cls[i])
			fprintf(stderr, "  %-13s : %" PRIu64 "\n",
				lfu_class_name[i], st->cls[i]);
	fprintf(stderr, "filtered (t0)   : %" PRIu64 "\n", st->filtered);
	fprintf(stderr, "filtered (t1)   : %" PRIu64 "\n", st->filtered1);
	/* §4.4 — a size test no MDT-only scan can answer for this object. */
	fprintf(stderr, "undecided       : %" PRIu64 "\n", st->unknown);
	fprintf(stderr, "emitted         : %" PRIu64 "\n", st->emitted);
	fprintf(stderr, "tier-2 (ext EA) : %" PRIu64 " (%.1f%% of in-use)\n",
		st->tier2,
		st->in_use ? 100.0 * (double)st->tier2 / (double)st->in_use : 0.0);
	fprintf(stderr, "tier-2 (read)   : %" PRIu64 "\n", st->tier2_read);
	fprintf(stderr, "skipped: csum=%" PRIu64 " validate=%" PRIu64 "\n",
		st->csum_bad, st->validate_bad);
	if (secs > 0.0)
		fprintf(stderr, "elapsed         : %.2fs (%.0f inodes/sec)\n",
			secs, (double)st->seen / secs);
}

/* ------------------------------------------------------------------ */

static int lfu_ldiskfs_parse_opt(int c, const char *arg, struct lfu_opts *o)
{
	switch (c) {
	case 'p':	/* historical short option for --projid */
		return lfu_filter_opt(&o->filter, LFU_OPT_PROJID, arg) == 0 ?
		       0 : -1;
	default:
		return -1;
	}
}

static const struct lfu_target_ops lfu_ldiskfs_ops = {
	.name		= "ldiskfs",
	.id_label	= "ino",
	.usage_target	= "<device>",
	.usage_extra	=
"\n"
"  -p N                    short form of --projid (historical)\n"
"  -a SEC / -b N           historical --atime +SECs / --dev-blocks +N\n"
"\n"
"The LUG 2026 slide-21 example is two tier-0 predicates and one tier-1:\n"
"  lfu-scan-ldiskfs --atime +30d --blocks +1G --projid 1999 <device>\n"
"--blocks reads trusted.som, because an MDT inode's own block count says\n"
"nothing about a striped file's data (docs/filter-levels.md §4).\n",
	.optstring_extra = "p:",
	.parse_opt	= lfu_ldiskfs_parse_opt,
	/* Every Lustre xattr is reachable from the inode, plus the external
	 * block when one exists, so this backend can answer any tier-1
	 * predicate LFU compiles.
	 */
	.can_supply	= LFU_NEED_SOM | LFU_NEED_LOV | LFU_NEED_LMV |
			  LFU_NEED_LINK,
	/* ext4's i_flags uses the same bit values as STATX_ATTR_*, so all five
	 * --attrs names are answerable here (src/lfu_lustre.h).
	 */
	.attr_mask	= LFU_ATTR_COMPRESSED | LFU_ATTR_IMMUTABLE |
			  LFU_ATTR_APPEND | LFU_ATTR_NODUMP |
			  LFU_ATTR_ENCRYPTED,
	.open		= lfu_ldiskfs_open,
	.close		= lfu_ldiskfs_close,
	.worker_init	= lfu_ldiskfs_worker_init,
	.worker_fini	= lfu_ldiskfs_worker_fini,
	.scan_chunk	= lfu_ldiskfs_scan_chunk,
	.report		= lfu_ldiskfs_report,
};

int main(int argc, char **argv)
{
	return lfu_main(&lfu_ldiskfs_ops, argc, argv);
}
