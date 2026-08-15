// SPDX-License-Identifier: LGPL-2.1+
/*
 * LFU ZFS Device Input Scanner — libzpool backend.
 *
 * Reads a Lustre-on-ZFS MDT/OST dataset (or, preferably, a snapshot of one)
 * from userspace via libzpool, the way zdb does: own the objset read-only,
 * walk allocated dnodes with dmu_object_next(), read attributes from the SA
 * bonus buffer, and recover the FID from trusted.lma inside the SA_ZPL_DXATTR
 * packed nvlist.  Classification, filtering and emission live in the common
 * core (lfu_core.c); this file owns the device access only.
 *
 * Design references (docs/design-zfs-scanner.md):
 *   §4.1 dmu_object_next()          — enumeration, allocation implicit
 *   §4.2 SA registry via sa_setup() — per-dataset slot numbers, never fixed
 *   §4.3 SA_ZPL_DXATTR nvlist       — all Lustre xattrs in one unpack
 *   §6   snapshot-first             — live datasets miss the open txg
 *
 * Verified against a real osd-zfs MDT 2026-08-07
 * (docs/zfs-mdt-verification-2026-08-07.md).  The read path is the same
 * sequence as osd_scrub.c:395-407 and osd_xattr.c:47-70.
 */
#include <sys/zfs_context.h>
#include <sys/spa.h>
#include <sys/dmu.h>
/* dmu_objset.h needs zfs_ioctl.h, which distro dev packages omit; dmu.h
 * declares every objset call we use. */
#include <sys/zap.h>
#include <sys/sa.h>
#include <sys/dnode.h>
#include <sys/zfs_acl.h>
#include <sys/zfs_sa.h>
#include <sys/zfs_znode.h>
#include <sys/nvpair.h>
#include <libzutil.h>

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lfu_scan.h"

/* libzpool's FTAG expands to __func__, so own/disown from different
 * functions would mismatch and trip the ds_owner assert — use one tag. */
static const char *lfu_tag = "lfu_scan_zfs";

/*
 * §8 chunk size in object IDs.  The core hands out chunk indices; this
 * backend maps index n to dnodes [n*LFU_CHUNK, (n+1)*LFU_CHUNK).
 */
#define LFU_CHUNK	(64ULL * 1024)

struct lfu_zfs {
	objset_t *os;
	sa_attr_type_t *atable;	/* §4.2: per-dataset SA slots, from sa_setup */
	int is_snapshot;
};

/* ------------------------------------------------------------------ */
/* Pool import                                                         */

/*
 * Find the pool by reading vdev labels and import it into this process.
 *
 * Needed for any real Lustre target, for two reasons found on an osd-zfs
 * MDT and not on the synthetic rig:
 *
 *   1. Lustre creates its pools with `cachefile=none` (HA failover must not
 *      depend on a stale /etc/zfs/zpool.cache), so the spa_config_load() that
 *      kernel_init() performs finds nothing and dmu_objset_own() returns
 *      ENOENT.  The pool has to be located by scanning devices, as `zpool
 *      import` and `zdb -e` do.
 *
 *   2. Lustre sets multihost=on on its pools (MMP is how HA failover keeps two
 *      servers from mounting one target).  libzpool has no hostid of its own,
 *      and spa_ld_check_features() refuses a multihost pool to a zero-hostid
 *      caller with EREMOTEIO unless ZFS_IMPORT_SKIP_MMP is set.  MMP exists to
 *      stop a second *writer*; this scanner holds the pool read-only
 *      (SPA_MODE_READ), so skipping it is sound — it is what `zdb -e` does
 *      unconditionally.
 *
 * Skipping MMP does mean losing ZFS's own "someone else has this pool" guard,
 * so we make that check ourselves from the label: refuse a pool whose state is
 * ACTIVE (imported elsewhere, or left dirty by a crash) unless --force-active
 * says to read it anyway.
 */
static int lfu_zfs_import(const struct lfu_opts *o)
{
	libpc_handle_t lpch = {
		.lpc_lib_handle = NULL,
		.lpc_ops = &libzpool_config_ops,
		.lpc_printerr = B_TRUE,
	};
	importargs_t args = { 0 };
	nvlist_t *cfg = NULL;
	char pool[ZFS_MAX_DATASET_NAME_LEN];
	uint64_t state = POOL_STATE_EXPORTED;
	char *sep;
	int err;

	/* target is pool/dataset[@snap]; the import takes the pool alone */
	(void)snprintf(pool, sizeof(pool), "%s", o->target);
	sep = strpbrk(pool, "/@");
	if (sep != NULL)
		*sep = '\0';

	static char *defsearch[] = { (char *)"/dev" };

	if (o->nsearch > 0) {
		args.paths = o->nsearch;
		args.path = (char **)(uintptr_t)o->search;
	} else {
		args.paths = 1;
		args.path = defsearch;
	}
	args.can_be_active = o->force_active ? B_TRUE : B_FALSE;

	err = zpool_find_config(&lpch, pool, &cfg, &args);
	if (err != 0 || cfg == NULL) {
		fprintf(stderr, "lfu: cannot find pool '%s': %s\n", pool,
		    libpc_error_description(&lpch));
		return -1;
	}

	/* Our own stand-in for the MMP guard we are about to skip. */
	if (nvlist_lookup_uint64(cfg, ZPOOL_CONFIG_POOL_STATE, &state) == 0 &&
	    state == POOL_STATE_ACTIVE && !o->force_active) {
		fprintf(stderr,
		    "lfu: pool '%s' is ACTIVE — it is imported by this or "
		    "another host, or was left dirty by a crash.  Export it "
		    "(zpool export %s) and rescan, or pass --force-active to "
		    "read it anyway; a forced read sees only what reached "
		    "disk, and a live target keeps moving under the scan.\n",
		    pool, pool);
		nvlist_free(cfg);
		return -1;
	}

	err = spa_import(pool, cfg, NULL,
	    ZFS_IMPORT_MISSING_LOG | ZFS_IMPORT_SKIP_MMP);
	nvlist_free(cfg);
	if (err != 0) {
		fprintf(stderr, "lfu: cannot import pool '%s': %d\n",
		    pool, err);
		return -1;
	}
	return 0;
}

/* ------------------------------------------------------------------ */
/* Per-object read: SA attributes + LMA from the DXATTR nvlist         */

static int sa_get_u64(sa_handle_t *hdl, sa_attr_type_t attr, uint64_t *out)
{
	return sa_lookup(hdl, attr, out, sizeof(*out));
}

static int sa_get_time(sa_handle_t *hdl, sa_attr_type_t attr, uint32_t *out)
{
	uint64_t t[2];
	int err = sa_lookup(hdl, attr, t, sizeof(t));

	*out = err ? 0 : (uint32_t)t[0];
	return err;
}

/*
 * Read one object.  Returns:
 *   0  — record filled and classified via lfu_object()
 *  -1  — not a znode (no SA bonus): ZFS-internal object
 *  -2  — SA read failure: counted, never interpreted
 *  -3  — rejected by the tier-0 prefilter (already counted)
 */
static int lfu_zfs_read_obj(struct lfu_zfs *z, uint64_t obj,
			    struct lfu_ctx *cx)
{
	sa_attr_type_t *a = z->atable;
	struct lfu_stats *st = cx->st;
	dmu_object_info_t doi;
	struct lfu_rec rec;
	sa_handle_t *hdl = NULL;
	dmu_buf_t *db = NULL;
	dnode_t *dn = NULL;
	uint64_t v;
	int have_lma = 0;
	int rc = 0;
	int err;

	memset(&rec, 0, sizeof(rec));

	/*
	 * One dnode hold for the whole object.
	 *
	 * The obvious spelling — dmu_object_info() then sa_handle_get() —
	 * takes two independent dnode holds per object, each walking
	 * dnode_hold_impl -> dbuf hash -> ARC with the mutex traffic that
	 * implies.  Profiling the 301k-object scan (2026-08-07) put
	 * dmu_object_info at 26.7% and sa_handle_get at 13.6%, both
	 * dominated by that shared path, while the DXATTR nvlist_unpack the
	 * design suspected cost 0.0%.  So hold the dnode once and use the
	 * by-dnode entry points for both.
	 */
	err = dnode_hold(z->os, obj, lfu_tag, &dn);
	if (err)
		return -2;

	dmu_object_info_from_dnode(dn, &doi);

	/* Master node, SA registry, ZAPs, delete queue: not znodes. */
	if (doi.doi_bonus_type != DMU_OT_SA) {
		dnode_rele(dn, lfu_tag);
		return -1;
	}

	if (doi.doi_bonus_size > st->max_bonus)
		st->max_bonus = doi.doi_bonus_size;

	/*
	 * Tag NULL: sa_handle_destroy() releases the bonus buffer with a
	 * NULL tag, exactly as sa_handle_get() would have held it.
	 */
	err = dmu_bonus_hold_by_dnode(dn, NULL, &db, 0);
	if (err) {
		dnode_rele(dn, lfu_tag);
		return -2;
	}
	err = sa_handle_get_from_db(z->os, db, NULL, SA_HDL_PRIVATE, &hdl);
	if (err) {
		dmu_buf_rele(db, NULL);
		dnode_rele(dn, lfu_tag);
		return -2;
	}

	rec.id = obj;
	if (sa_get_u64(hdl, a[ZPL_MODE], &v) != 0)
		goto sa_fail;
	rec.mode = (uint16_t)v;
	if (sa_get_u64(hdl, a[ZPL_LINKS], &v) != 0)
		goto sa_fail;
	rec.nlink = (uint32_t)v;
	if (sa_get_u64(hdl, a[ZPL_SIZE], &v) == 0)
		rec.size = v;
	if (sa_get_u64(hdl, a[ZPL_UID], &v) == 0)
		rec.uid = (uint32_t)v;
	if (sa_get_u64(hdl, a[ZPL_GID], &v) == 0)
		rec.gid = (uint32_t)v;
	/* ZPL_PROJID is a feature; absence simply means projid 0. */
	if (sa_get_u64(hdl, a[ZPL_PROJID], &v) == 0)
		rec.projid = (uint32_t)v;
	sa_get_time(hdl, a[ZPL_ATIME], &rec.atime);
	sa_get_time(hdl, a[ZPL_MTIME], &rec.mtime);
	sa_get_time(hdl, a[ZPL_CTIME], &rec.ctime);
	sa_get_time(hdl, a[ZPL_CRTIME], &rec.crtime);

	/* Space usage from dnode accounting, 512-byte units.  Note this is
	 * post-compression physical — a `blocks >` filter differs from
	 * ldiskfs semantics for compressible data (design §12). */
	rec.blocks = doi.doi_physical_blocks_512;

	/* links == 0 is NOT "pending delete" on osd-zfs: the OSD's own
	 * hierarchy carries links=0 while live (real-MDT finding, 08-07). */
	if (rec.nlink == 0)
		st->unlinked++;

	/*
	 * §7 — tier-0 prefilter before the DXATTR unpack, mirroring the
	 * ldiskfs tier ordering: a rejected object never costs the nvlist
	 * work.  (The unpack profiled at 0.0%, so this is for semantic
	 * parity more than speed.)
	 */
	if (!lfu_prefilter(cx, &rec)) {
		rc = -3;
		goto out;
	}

	/*
	 * §4.3 — one unpack yields every Lustre xattr.  ENOENT means the
	 * znode has no SA xattrs at all: a no-LMA object, not an error.
	 */
	{
		nvlist_t *nv = NULL;
		char *buf;
		int sz;

		err = sa_size(hdl, a[ZPL_DXATTR], &sz);
		if (err == ENOENT) {
			st->no_dxattr++;
			goto emit;
		}
		if (err != 0 || sz <= 0)
			goto sa_fail;

		buf = umem_alloc(sz, UMEM_NOFAIL);
		err = sa_lookup(hdl, a[ZPL_DXATTR], buf, sz);
		if (err == 0)
			err = nvlist_unpack(buf, sz, &nv, 0);
		umem_free(buf, sz);
		if (err)
			goto sa_fail;

		{
			uchar_t *val = NULL;
			uint_t vlen = 0;

			if (nvlist_lookup_byte_array(nv, XATTR_NAME_LMA,
			    &val, &vlen) == 0 &&
			    vlen >= sizeof(struct lustre_mdt_attrs)) {
				const struct lustre_mdt_attrs *lma =
				    (const struct lustre_mdt_attrs *)val;

				/* LMA is little-endian on disk, like ldiskfs */
				rec.lma_compat = lma->lma_compat;
				rec.lma_incompat = lma->lma_incompat;
				rec.fid = lma->lma_self_fid;
				have_lma = 1;
			}
		}
		nvlist_free(nv);
	}

emit:
	lfu_object(cx, &rec, have_lma);
out:
	sa_handle_destroy(hdl);	/* releases the bonus buffer */
	dnode_rele(dn, lfu_tag);
	return rc;

sa_fail:
	sa_handle_destroy(hdl);
	dnode_rele(dn, lfu_tag);
	return -2;
}

/* ------------------------------------------------------------------ */
/* lfu_target_ops                                                      */

static void *lfu_zfs_open(const struct lfu_opts *o)
{
	struct lfu_zfs *z;
	uint64_t sa_obj = 0;
	int err;

	z = calloc(1, sizeof(*z));
	if (z == NULL)
		return NULL;

	kernel_init(SPA_MODE_READ);

	if (o->import && lfu_zfs_import(o) != 0)
		goto fail;

	err = dmu_objset_own(o->target, DMU_OST_ANY, B_TRUE, B_FALSE, lfu_tag,
	    &z->os);
	if (err) {
		fprintf(stderr, "lfu: cannot own objset %s: %d%s\n",
		    o->target, err, (err == 2 && !o->import) ?
		    " — a Lustre pool has cachefile=none; use -e to import "
		    "by scanning devices" : "");
		goto fail;
	}

	if (dmu_objset_type(z->os) != DMU_OST_ZFS) {
		fprintf(stderr, "lfu: %s is not a ZPL/OSD dataset (type %d)\n",
		    o->target, (int)dmu_objset_type(z->os));
		dmu_objset_disown(z->os, B_FALSE, lfu_tag);
		goto fail;
	}

	/*
	 * §4.2 — resolve the SA registry for THIS dataset.  Slot numbers are
	 * per-dataset; assuming fixed offsets is the silent-wrong-attributes
	 * bug.  Same sequence as osd_handler.c:981-988.
	 */
	err = zap_lookup(z->os, MASTER_NODE_OBJ, ZFS_SA_ATTRS, 8, 1, &sa_obj);
	if (err == 0)
		err = sa_setup(z->os, sa_obj, zfs_attr_table, ZPL_END,
		    &z->atable);
	if (err) {
		fprintf(stderr, "lfu: SA registry setup failed: %d\n", err);
		dmu_objset_disown(z->os, B_FALSE, lfu_tag);
		goto fail;
	}

	z->is_snapshot = (strchr(o->target, '@') != NULL);
	if (!z->is_snapshot)
		fprintf(stderr, "lfu: warning: scanning a LIVE dataset; "
		    "the open txg is invisible (design §6.2) — prefer a "
		    "snapshot\n");
	return z;

fail:
	kernel_fini();
	free(z);
	return NULL;
}

static void lfu_zfs_close(void *tgt)
{
	struct lfu_zfs *z = tgt;

	if (z->atable != NULL)
		sa_tear_down(z->os);
	dmu_objset_disown(z->os, B_FALSE, lfu_tag);
	kernel_fini();
	free(z);
}

/* The DMU handle is thread-safe: every worker shares the objset. */
static void *lfu_zfs_worker_init(void *tgt, const struct lfu_opts *o)
{
	return tgt;
}

static void lfu_zfs_worker_fini(void *tgt, void *wctx)
{
}

static int lfu_zfs_scan_chunk(void *tgt, void *wctx, struct lfu_ctx *cx,
			      uint64_t idx, int *done)
{
	struct lfu_zfs *z = tgt;
	uint64_t start = idx * LFU_CHUNK;
	uint64_t end = start + LFU_CHUNK;
	uint64_t obj = start ? start - 1 : 0;

	for (;;) {
		int rc;

		if (cx->stop)
			return 0;

		if (dmu_object_next(z->os, &obj, B_FALSE, 0) != 0) {
			/*
			 * dmu_object_next() scans forward globally, so
			 * finding nothing at or beyond this chunk proves
			 * there is nothing beyond it at all.
			 */
			*done = 1;
			return 0;
		}
		if (obj >= end)
			return 0;

		cx->st->seen++;

		rc = lfu_zfs_read_obj(z, obj, cx);
		if (rc == -1)
			cx->st->not_znode++;
		else if (rc == -2)
			cx->st->sa_fail++;
	}
}

static void lfu_zfs_report(const struct lfu_stats *st, double secs, void *tgt)
{
	struct lfu_zfs *z = tgt;
	int i;

	fprintf(stderr, "scan complete in %.2fs (%s)\n", secs,
	    z->is_snapshot ? "snapshot: txg-consistent" :
	    "LIVE DATASET: open txg not visible, results are not atomic");
	fprintf(stderr, "  dnodes seen   : %" PRIu64 "\n", st->seen);
	fprintf(stderr, "  not znodes    : %" PRIu64 "\n", st->not_znode);
	fprintf(stderr, "  unlinked      : %" PRIu64 "\n", st->unlinked);
	fprintf(stderr, "  no sa-xattrs  : %" PRIu64 "\n", st->no_dxattr);
	for (i = 0; i < LFU_CLS_MAX; i++)
		if (st->cls[i])
			fprintf(stderr, "  %-14s: %" PRIu64 "\n",
			    lfu_class_name[i], st->cls[i]);
	fprintf(stderr, "  filtered      : %" PRIu64 "\n", st->filtered);
	fprintf(stderr, "emitted         : %" PRIu64 "\n", st->emitted);
	fprintf(stderr, "skipped: sa_fail=%" PRIu64 "\n", st->sa_fail);
	fprintf(stderr, "max bonus seen  : %" PRIu64 " bytes\n", st->max_bonus);
}

/* ------------------------------------------------------------------ */

static int lfu_zfs_parse_opt(int c, const char *arg, struct lfu_opts *o)
{
	switch (c) {
	case 'e':
		o->import = 1;
		return 0;
	case 'p':
		if (o->nsearch >= LFU_MAX_SEARCH) {
			fprintf(stderr, "lfu: at most %d search dirs\n",
			    LFU_MAX_SEARCH);
			exit(2);
		}
		o->search[o->nsearch++] = (char *)arg;
		o->import = 1;
		return 0;
	case 4:
		o->force_active = 1;
		o->import = 1;
		return 0;
	default:
		return -1;
	}
}

static const struct option lfu_zfs_lopts[] = {
	{ "import",       no_argument,       NULL, 'e' },
	{ "search",       required_argument, NULL, 'p' },
	{ "force-active", no_argument,       NULL,  4  },
	{ NULL, 0, NULL, 0 }
};

static const struct lfu_target_ops lfu_zfs_ops = {
	.name		= "zfs",
	.id_label	= "obj",
	.usage_target	= "pool/dataset[@snapshot]",
	.usage_extra	=
"  -e, --import            find the pool by scanning devices, as zpool\n"
"                          import does; required for Lustre pools, which\n"
"                          are created with cachefile=none\n"
"  -p, --search DIR        directory to search for pool devices (repeatable,\n"
"                          default /dev); implies -e\n"
"      --force-active      read a pool whose label is ACTIVE (imported\n"
"                          elsewhere, or crash-dirty); read-only, but only\n"
"                          what reached disk is visible\n"
"\n"
"Scan a snapshot where possible: a live dataset cannot show the open txg.\n",
	.optstring_extra = "ep:",
	.lopts_extra	= lfu_zfs_lopts,
	.parse_opt	= lfu_zfs_parse_opt,
	.open		= lfu_zfs_open,
	.close		= lfu_zfs_close,
	.worker_init	= lfu_zfs_worker_init,
	.worker_fini	= lfu_zfs_worker_fini,
	.scan_chunk	= lfu_zfs_scan_chunk,
	.report		= lfu_zfs_report,
};

int main(int argc, char **argv)
{
	return lfu_main(&lfu_zfs_ops, argc, argv);
}
