// SPDX-License-Identifier: GPL-2.0
/*
 * lfu_ring — the otable iterator streamed to userspace through a batched
 * ring (the Object Stream producer for Option 2), with the filter evaluated
 * in kernel before a record enters the ring (design-osd-scanner.md §4).
 *
 * Shape: a misc char device.  open() allocates the ring; the first read()
 * starts an enumerator kthread that owns an otable iterator (a DOIF_PARALLEL
 * private one by default, so the block-parse path is used) and writes
 * fixed-size records into an SPSC ring; read() copies whole records out and
 * blocks when empty; EOF when the scan is done and the ring is drained.  One
 * reader at a time.  ioctls before the first read() set the filter and query
 * what the module can do; one after EOF reads the counters.
 *
 * Filter pushdown, cost-ordered exactly as the device scanners do it
 * (docs/filter-levels.md §7, §9):
 *
 *   rec(DORA_ATTR)                 -> tier 0 on the record; a reject costs
 *                                     nothing more and never touches the ring
 *   rec(DORA_XATTR) x demand mask  -> only what the compiled filter asked for,
 *                                     from the mapped inode-table block when
 *                                     the iterator holds one, at no I/O
 *   lfu_filter_tier1()             -> match / no-match / undecided
 *
 * The evaluator is the same source the userspace scanners link
 * (lfu_filter_eval.c, #included below): fixed predicate array, no allocation,
 * bounded by construction, which is what a filter program running in kernel
 * context has to be.  The parser never comes near the kernel; userspace
 * compiles lfs find syntax into struct lfu_filter and hands the bytes over,
 * and lfu_filter_validate() range-checks every index before anything is
 * evaluated.
 *
 * Two deliberate departures from ofd_access_log.c, both measured needs:
 *   - STALL, never drop: namespace enumeration cannot tolerate gaps, so a
 *     full ring blocks the producer (design §8.2 of the ldiskfs scanner:
 *     the access log's drop-on-full is wrong for LFU).
 *   - BATCHED wakeups: step 2's fan-out control rows showed per-entry
 *     wakeups collapsing the pipeline (4 idle workers slower than 2 busy
 *     ones).  Producer wakes the reader every `batch` records or at EOF;
 *     the reader wakes the producer only once `batch` slots are free.
 *
 * Prototype limits, recorded: single fixed target (module param), one
 * enumerator thread (parallel enumeration is behind the iterator, measured in
 * lfu_par; feeding N iterators into one ring is the next step), ldiskfs-first
 * (osd-zfs answers DORA_XATTR with -EOPNOTSUPP, so INFO reports no tier 1
 * there and SET_FILTER refuses a filter that needs it).
 */
#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/kthread.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>
#include <linux/wait.h>
#include <linux/mutex.h>
#include <linux/ktime.h>
#include <obd_class.h>
#include <dt_object.h>
#include <lustre_fid.h>

#include "lfu_ring.h"

/*
 * The evaluator, compiled into this module rather than built as a second
 * object, so Kbuild needs no out-of-directory rule and the source stays one
 * file shared with userspace.  It sees lfu_filter.h's kernel branch.
 */
#include "../lfu_filter_eval.c"

static char *dev = "testfs-MDT0000-osd";
module_param(dev, charp, 0444);
MODULE_PARM_DESC(dev, "OSD obd device name to scan");

static unsigned int ring_recs = 16384;	/* power of two */
module_param(ring_recs, uint, 0444);
MODULE_PARM_DESC(ring_recs, "ring capacity in records (power of two)");

static unsigned int batch = 2048;
module_param(batch, uint, 0444);
MODULE_PARM_DESC(batch, "wakeup granularity in records");

static bool private_it = true;
module_param_named(private, private_it, bool, 0644);
MODULE_PARM_DESC(private,
		 "1 = DOIF_PARALLEL private iterator (block parse, no scrub coupling); 0 = the singleton otable iterator");

/* Kept local until the extension lands upstream everywhere the harness
 * builds; mirrors the step-3 patch. */
#ifndef DORA_ATTR
#define DORA_ATTR	0x01
struct dt_otable_rec {
	struct lu_fid	dor_fid;
	struct lu_attr	dor_attr;
};
#endif
#ifndef DOIF_ATTR
#define DOIF_ATTR	0x0010
#endif
#ifndef DOIF_PARALLEL
#define DOIF_PARALLEL	0x0020
#endif

/* Tier 1 exists only against a tree with the otable-xattr patch: DORA_XATTR
 * comes from dt_object.h there.  Without it, this module still streams and
 * filters tier 0, and INFO says so. */
#ifdef DORA_XATTR
#define LFU_RING_HAVE_XATTR	1
#else
#define LFU_RING_HAVE_XATTR	0
#endif

/*
 * Scratch for the demanded xattrs, allocated once per open and reused per
 * object -- so evaluation allocates nothing.  Sizes: SOM is 24 bytes; a LOV
 * or LMV is bounded by XATTR_SIZE_MAX (64 KiB); linkea by MAX_LINKEA_SIZE
 * (4 KiB).  An xattr larger than its buffer is counted and the object's
 * outcome becomes "undecided", not "no".
 */
#define LFU_XA_SOM_MAX	64
#define LFU_XA_LOV_MAX	65536
#define LFU_XA_LMV_MAX	65536
#define LFU_XA_LINK_MAX	8192

struct lfu_ring {
	struct lfu_wire_rec	*buf;
	u64			head;		/* producer, free-running */
	u64			tail;		/* consumer, free-running */
	u64			last_wake;	/* head at last reader wake */
	wait_queue_head_t	wq_prod;
	wait_queue_head_t	wq_cons;
	struct task_struct	*task;
	struct mutex		lock;		/* start vs ioctl */
	int			started;
	int			done;		/* producer finished */
	int			err;		/* producer error, if any */
	u64			produced;

	/* the filter, if one was set, and its scratch */
	struct lfu_ring_filter	*filter;	/* NULL: pass everything */
	int			emit_unknown;
	u8			*xa_som;
	u8			*xa_lov;
	u8			*xa_lmv;
	u8			*xa_link;

	/* what the OSD under `dev` is; filled at open */
	u32			can_supply;
	u32			attr_mask;
	u32			info_flags;

	struct lfu_ring_stats	st;
};

static struct lfu_ring *lr;		/* one open at a time */
static atomic_t lfu_open_cnt = ATOMIC_INIT(0);

static u64 lfu_ring_avail(struct lfu_ring *r)
{
	return smp_load_acquire(&r->head) - r->tail;
}

static u64 lfu_ring_free(struct lfu_ring *r)
{
	return ring_recs - (r->head - smp_load_acquire(&r->tail));
}

/* ------------------------------------------------------------------ */
/* Records                                                            */

/*
 * The evaluator's view of an object, from the iterator's record.  The
 * conversions here are the ones every backend applies: la_flags is the
 * LUSTRE_*_FL word, whose STATX-compatible bits are exactly the LFU_ATTR_*
 * ones (lfu_filter.h), and the LMA orphan/encrypted bits ride in it too.
 */
static void lfu_rec_from_dor(struct lfu_rec *rec, u64 oid,
			     const struct dt_otable_rec *dor)
{
	const struct lu_attr *la = &dor->dor_attr;

	memset(rec, 0, sizeof(*rec));
	rec->fid = dor->dor_fid;
	rec->id = oid;
	rec->mode = (u16)la->la_mode;
	rec->nlink = la->la_nlink;
	rec->uid = la->la_uid;
	rec->gid = la->la_gid;
	rec->projid = la->la_projid;
	rec->flags = la->la_flags;
	rec->size = la->la_size;
	rec->blocks = la->la_blocks;
	rec->atime = (u32)la->la_atime;
	rec->mtime = (u32)la->la_mtime;
	rec->ctime = (u32)la->la_ctime;
	rec->crtime = (u32)la->la_btime;
	/* the wire carries no LMA yet beyond what la_flags encodes */
	if (la->la_flags & LUSTRE_ORPHAN_FL)
		rec->lma_incompat |= LMAI_ORPHAN;
	if (la->la_flags & LUSTRE_ENCRYPT_FL)
		rec->lma_incompat |= LMAI_ENCRYPT;
}

static void lfu_fill_rec(struct lfu_wire_rec *wr, u64 oid,
			 const struct dt_otable_rec *dor,
			 const struct lfu_rec *rec, u32 lfu_bits)
{
	memset(wr, 0, sizeof(*wr));
	wr->wr_oid = oid;
	wr->wr_fid_seq = dor->dor_fid.f_seq;
	wr->wr_fid_oid = dor->dor_fid.f_oid;
	wr->wr_fid_ver = dor->dor_fid.f_ver;
	wr->wr_valid = dor->dor_attr.la_valid;
	wr->wr_mode = dor->dor_attr.la_mode;
	wr->wr_nlink = dor->dor_attr.la_nlink;
	wr->wr_uid = dor->dor_attr.la_uid;
	wr->wr_gid = dor->dor_attr.la_gid;
	wr->wr_size = dor->dor_attr.la_size;
	wr->wr_blocks = dor->dor_attr.la_blocks;
	wr->wr_atime = dor->dor_attr.la_atime;
	wr->wr_mtime = dor->dor_attr.la_mtime;
	wr->wr_ctime = dor->dor_attr.la_ctime;
	/* version 2 */
	wr->wr_btime = dor->dor_attr.la_btime;
	wr->wr_projid = dor->dor_attr.la_projid;
	wr->wr_flags = dor->dor_attr.la_flags;
	wr->wr_lma_compat = rec->lma_compat;
	wr->wr_lma_incompat = rec->lma_incompat;
	wr->wr_lfu = lfu_bits;
	if (rec->t1_valid) {
		const struct lfu_tier1 *t1 = &rec->t1;

		if (t1->have_som) {
			wr->wr_lfu |= LFU_WR_HAVE_SOM;
			wr->wr_som_valid = t1->som_valid;
			wr->wr_som_size = t1->som_size;
			wr->wr_som_blocks = t1->som_blocks;
		}
		if (t1->have_lov) {
			wr->wr_lfu |= LFU_WR_HAVE_LOV;
			wr->wr_stripe_count = t1->stripe_count;
			wr->wr_stripe_size = t1->stripe_size;
			memcpy(wr->wr_pool, t1->pool, sizeof(wr->wr_pool));
		}
		if (t1->have_lmv) {
			wr->wr_lfu |= LFU_WR_HAVE_LMV;
			wr->wr_lmv_count = t1->lmv_count;
			wr->wr_lmv_hash = t1->lmv_hash;
		}
	}
}

/* ------------------------------------------------------------------ */
/* Tier 1: the demanded xattrs, through the iterator                  */

#if LFU_RING_HAVE_XATTR
/*
 * One demanded xattr into its scratch buffer.  Returns 1 if the value is in
 * hand, 0 if the object has no such attribute, -ERANGE if it exists but did
 * not fit (counted; the object becomes undecided), and any other negative
 * error is counted and treated as absent -- a scan should not die because one
 * inode's xattr block would not read.
 */
static int lfu_xa_get(struct lfu_ring *r, const struct lu_env *env,
		      const struct dt_it_ops *iops, struct dt_it *di,
		      const char *name, u8 *buf, u32 buflen, struct lfu_ea *ea,
		      int *external)
{
	struct dt_otable_xattr dox = {
		.dox_name = name, .dox_buf = buf, .dox_buflen = buflen,
	};
	int rc;

	ea->buf = NULL;
	ea->len = 0;

	rc = iops->rec(env, di, (struct dt_rec *)&dox, DORA_XATTR);
	if (rc >= 0) {
		ea->buf = buf;
		ea->len = dox.dox_len;
		if (dox.dox_where == DOX_EXTERNAL)
			*external = 1;
		return 1;
	}
	if (rc == -ENODATA)
		return 0;
	if (rc == -ERANGE) {
		r->st.rs_xa_toolarge++;
		return -ERANGE;
	}
	if (rc == -EOPNOTSUPP)
		return rc;
	r->st.rs_xa_err++;
	return 0;
}
#endif

/*
 * Apply the filter to one object.  Returns LFU_MATCH / LFU_NOMATCH /
 * LFU_UNKNOWN, with the counters advanced, and on MATCH/UNKNOWN fills
 * rec->t1 for the wire record.  -EOPNOTSUPP if the OSD cannot serve a
 * demanded xattr, which ends the scan: better no answer than a wrong one.
 */
static int lfu_filter_object(struct lfu_ring *r, const struct lu_env *env,
			     const struct dt_it_ops *iops, struct dt_it *di,
			     struct lfu_rec *rec, s64 now, u32 *lfu_bits)
{
	const struct lfu_filter *f;
	struct lfu_eas eas;
	u32 needs;
	int m;

	*lfu_bits = 0;
	if (r->filter == NULL)
		return LFU_MATCH;
	f = &r->filter->rf_filter;

	if (!lfu_filter_tier0(f, rec, now)) {
		r->st.rs_filtered0++;
		return LFU_NOMATCH;
	}

	needs = lfu_filter_needs(f);
	if (needs == 0)
		return LFU_MATCH;

	memset(&eas, 0, sizeof(eas));
	m = LFU_MATCH;
#if LFU_RING_HAVE_XATTR
	{
		int rc, ext = 0, toolarge = 0;

		if (needs & LFU_NEED_SOM) {
			rc = lfu_xa_get(r, env, iops, di, XATTR_NAME_SOM,
					r->xa_som, LFU_XA_SOM_MAX, &eas.som,
					&ext);
			if (rc == -EOPNOTSUPP)
				return rc;
			toolarge |= (rc == -ERANGE);
		}
		if (needs & LFU_NEED_LOV) {
			rc = lfu_xa_get(r, env, iops, di, XATTR_NAME_LOV,
					r->xa_lov, LFU_XA_LOV_MAX, &eas.lov,
					&ext);
			if (rc == -EOPNOTSUPP)
				return rc;
			toolarge |= (rc == -ERANGE);
		}
		if (needs & LFU_NEED_LMV) {
			rc = lfu_xa_get(r, env, iops, di, XATTR_NAME_LMV,
					r->xa_lmv, LFU_XA_LMV_MAX, &eas.lmv,
					&ext);
			if (rc == -EOPNOTSUPP)
				return rc;
			toolarge |= (rc == -ERANGE);
		}
		if (needs & LFU_NEED_LINK) {
			rc = lfu_xa_get(r, env, iops, di, XATTR_NAME_LINK,
					r->xa_link, LFU_XA_LINK_MAX, &eas.link,
					&ext);
			if (rc == -EOPNOTSUPP)
				return rc;
			toolarge |= (rc == -ERANGE);
		}
		eas.external = ext;
		if (ext)
			*lfu_bits |= LFU_WR_XA_EXTERNAL;
		if (toolarge)
			m = LFU_UNKNOWN;
	}
#else
	return -EOPNOTSUPP;
#endif

	lfu_ea_decode(&rec->t1, &eas);
	rec->t1_valid = 1;

	if (m == LFU_MATCH)
		m = lfu_filter_tier1(f, rec, &rec->t1, &eas);

	if (m == LFU_NOMATCH) {
		r->st.rs_filtered1++;
	} else if (m == LFU_UNKNOWN) {
		r->st.rs_unknown++;
		*lfu_bits |= LFU_WR_UNKNOWN;
	}
	return m;
}

/* ------------------------------------------------------------------ */
/* Producer                                                           */

static int lfu_producer(void *arg)
{
	struct lfu_ring *r = arg;
	struct obd_device *obd;
	struct dt_device *dt;
	struct dt_object *obj = NULL;
	const struct dt_it_ops *iops;
	struct dt_it *di = NULL;
	struct lu_env env;
	struct lu_fid fid;
	struct dt_otable_rec dor;
	struct lfu_rec rec;
	__u32 flags;
	s64 now;
	int rc, rc2 = 0;

	obd = class_name2obd(dev);
	if (obd == NULL || obd->obd_lu_dev == NULL)
		GOTO(fail, rc = -ENOENT);
	dt = lu2dt_dev(obd->obd_lu_dev);

	rc = lu_env_init(&env, LCT_MD_THREAD | LCT_DT_THREAD | LCT_LOCAL);
	if (rc)
		GOTO(fail, rc);

	fid.f_seq = FID_SEQ_LOCAL_FILE;
	fid.f_oid = OTABLE_IT_OID;
	fid.f_ver = 0;
	obj = dt_locate(&env, dt, &fid);
	if (IS_ERR(obj))
		GOTO(out_env, rc = PTR_ERR(obj));

	rc = obj->do_ops->do_index_try(&env, obj, &dt_otable_features);
	if (rc)
		GOTO(out_obj, rc);
	iops = &obj->do_index_ops->dio_it;

	/*
	 * A private iterator walks the raw inode table (block parse) and
	 * neither drives nor is paced by OI scrub; the singleton is kept as
	 * the A/B control and for trees without DOIF_PARALLEL.
	 */
	flags = DOIF_OUTUSED | DOIF_ATTR |
		(private_it ? DOIF_PARALLEL : DOIF_RESET);
	di = iops->init(&env, obj, flags << DT_OTABLE_IT_FLAGS_SHIFT);
	if (IS_ERR(di)) {
		rc = PTR_ERR(di);
		pr_err("lfu_ring: it init: rc = %d (singleton busy?)\n", rc);
		di = NULL;
		GOTO(out_obj, rc);
	}
	rc = iops->load(&env, di, 0);
	if (rc < 0)
		GOTO(out_it, rc);
	if (rc > 0)
		GOTO(out_it, rc = 0);	/* empty table */

	now = ktime_get_real_seconds();

	for (;;) {
		u32 lfu_bits;
		int m;

		if (kthread_should_stop())
			break;

		memset(&dor.dor_attr, 0, sizeof(dor.dor_attr));
		rc2 = iops->rec(&env, di, (struct dt_rec *)&dor, DORA_ATTR);
		if (rc2 == 0) {
			u64 oid = iops->store(&env, di);

			r->st.rs_seen++;
			lfu_rec_from_dor(&rec, oid, &dor);

			m = lfu_filter_object(r, &env, iops, di, &rec, now,
					      &lfu_bits);
			if (m < 0) {
				rc = m;
				pr_err("lfu_ring: the OSD cannot serve a demanded xattr: rc = %d\n",
				       rc);
				goto drained;
			}
			if (m == LFU_MATCH ||
			    (m == LFU_UNKNOWN && r->emit_unknown)) {
				/* stall, never drop */
				while (lfu_ring_free(r) == 0) {
					r->st.rs_stalls++;
					wake_up(&r->wq_cons);
					wait_event(r->wq_prod,
						   lfu_ring_free(r) >= batch ||
						   kthread_should_stop());
					if (kthread_should_stop())
						goto drained;
				}
				lfu_fill_rec(&r->buf[r->head & (ring_recs - 1)],
					     oid, &dor, &rec, lfu_bits);
				smp_store_release(&r->head, r->head + 1);
				r->produced++;
				r->st.rs_emitted++;

				if (r->head - r->last_wake >= batch) {
					r->last_wake = r->head;
					wake_up(&r->wq_cons);
				}
			}
		}

		rc2 = iops->next(&env, di);
		if (rc2 != 0)
			break;
		if ((r->st.rs_seen & 0xffff) == 0)
			cond_resched();
	}

drained:
#if LFU_RING_HAVE_XATTR
	{
		/* the iterator's own counters, if it keeps them */
		struct dt_otable_stats dos;

		memset(&dos, 0, sizeof(dos));
		if (iops->rec(&env, di, (struct dt_rec *)&dos, DORA_STATS) == 0) {
			r->st.rs_raw = dos.dos_raw;
			r->st.rs_fallback = dos.dos_fallback;
			r->st.rs_xa_inline = dos.dos_xa_inline;
			r->st.rs_xa_ext = dos.dos_xa_ext;
			r->st.rs_xa_iget = dos.dos_xa_iget;
		}
	}
#endif
out_it:
	iops->put(&env, di);
	iops->fini(&env, di);
out_obj:
	if (!IS_ERR_OR_NULL(obj))
		lu_object_put(&env, &obj->do_lu);
out_env:
	lu_env_fini(&env);
fail:
	r->err = rc;
	r->st.rs_err = rc;
	WRITE_ONCE(r->done, 1);
	wake_up_all(&r->wq_cons);
	pr_info("lfu_ring: producer done: seen=%llu emitted=%llu filtered0=%llu filtered1=%llu unknown=%llu rc=%d next_rc=%d\n",
		r->st.rs_seen, r->st.rs_emitted, r->st.rs_filtered0,
		r->st.rs_filtered1, r->st.rs_unknown, rc, rc2);

	/* park until kthread_stop() so the task_struct stays valid */
	while (!kthread_should_stop()) {
		set_current_state(TASK_INTERRUPTIBLE);
		if (!kthread_should_stop())
			schedule();
	}
	__set_current_state(TASK_RUNNING);
	return rc;
}

/* ------------------------------------------------------------------ */
/* Device                                                             */

/* Which OSD is under `dev`, and therefore what INFO promises. */
static void lfu_ring_probe(struct lfu_ring *r)
{
	struct obd_device *obd = class_name2obd(dev);
	const char *type = NULL;

	r->can_supply = 0;
	r->attr_mask = 0;
	r->info_flags = private_it ? LFU_RING_INFO_PRIVATE : 0;

	if (obd != NULL && obd->obd_type != NULL)
		type = obd->obd_type->typ_name;
	if (type == NULL)
		return;

	if (strcmp(type, LUSTRE_OSD_LDISKFS_NAME) == 0) {
		r->info_flags |= LFU_RING_INFO_LDISKFS;
		/* ext4 i_flags carries all five, and la_flags is that word */
		r->attr_mask = LFU_ATTR_ALL;
		if (LFU_RING_HAVE_XATTR)
			r->can_supply = LFU_NEED_SOM | LFU_NEED_LOV |
					LFU_NEED_LMV | LFU_NEED_LINK;
	} else if (strcmp(type, LUSTRE_OSD_ZFS_NAME) == 0) {
		r->info_flags |= LFU_RING_INFO_ZFS;
		/* z_pflags: no per-file compressed or encrypted bit */
		r->attr_mask = LFU_ATTR_IMMUTABLE | LFU_ATTR_APPEND |
			       LFU_ATTR_NODUMP;
		r->can_supply = 0;	/* rec(DORA_XATTR) is -EOPNOTSUPP there */
	}
}

static int lfu_ring_start(struct lfu_ring *r)
{
	struct task_struct *t;

	if (r->started)
		return 0;

	t = kthread_create(lfu_producer, r, "lfu_ring");
	if (IS_ERR(t))
		return PTR_ERR(t);
	get_task_struct(t);
	r->task = t;
	r->started = 1;
	wake_up_process(t);
	return 0;
}

static int lfu_ring_open(struct inode *inode, struct file *filp)
{
	struct lfu_ring *r;

	if (atomic_cmpxchg(&lfu_open_cnt, 0, 1) != 0)
		return -EBUSY;

	r = kzalloc(sizeof(*r), GFP_KERNEL);
	if (!r)
		goto fail_cnt;
	r->buf = vmalloc(array_size(ring_recs, sizeof(*r->buf)));
	if (!r->buf)
		goto fail_r;
	init_waitqueue_head(&r->wq_prod);
	init_waitqueue_head(&r->wq_cons);
	mutex_init(&r->lock);
	lfu_ring_probe(r);

	lr = r;
	filp->private_data = r;
	return 0;

fail_r:
	kfree(r);
fail_cnt:
	atomic_set(&lfu_open_cnt, 0);
	return -ENOMEM;
}

static int lfu_ring_alloc_scratch(struct lfu_ring *r)
{
	if (r->xa_som != NULL)
		return 0;
	r->xa_som = kmalloc(LFU_XA_SOM_MAX, GFP_KERNEL);
	r->xa_lov = vmalloc(LFU_XA_LOV_MAX);
	r->xa_lmv = vmalloc(LFU_XA_LMV_MAX);
	r->xa_link = vmalloc(LFU_XA_LINK_MAX);
	if (!r->xa_som || !r->xa_lov || !r->xa_lmv || !r->xa_link)
		return -ENOMEM;
	return 0;
}

static void lfu_ring_free_scratch(struct lfu_ring *r)
{
	kfree(r->xa_som);
	vfree(r->xa_lov);
	vfree(r->xa_lmv);
	vfree(r->xa_link);
	r->xa_som = NULL;
	r->xa_lov = r->xa_lmv = r->xa_link = NULL;
}

static long lfu_ring_ioctl(struct file *filp, unsigned int cmd,
			   unsigned long arg)
{
	struct lfu_ring *r = filp->private_data;
	void __user *uarg = (void __user *)arg;
	long rc = 0;

	switch (cmd) {
	case LFU_RING_IOC_INFO: {
		struct lfu_ring_info info;

		memset(&info, 0, sizeof(info));
		info.ri_wire_version = LFU_RING_WIRE_VERSION;
		info.ri_rec_size = sizeof(struct lfu_wire_rec);
		info.ri_can_supply = r->can_supply;
		info.ri_attr_mask = r->attr_mask;
		info.ri_max_pred = LFU_MAX_PRED;
		info.ri_flags = r->info_flags;
		strscpy(info.ri_dev, dev, sizeof(info.ri_dev));
		if (copy_to_user(uarg, &info, sizeof(info)))
			rc = -EFAULT;
		break;
	}

	case LFU_RING_IOC_SET_FILTER: {
		struct lfu_ring_filter *rf;

		mutex_lock(&r->lock);
		if (r->started) {
			mutex_unlock(&r->lock);
			return -EBUSY;	/* the scan has begun */
		}
		rf = kmalloc(sizeof(*rf), GFP_KERNEL);
		if (rf == NULL) {
			mutex_unlock(&r->lock);
			return -ENOMEM;
		}
		if (copy_from_user(rf, uarg, sizeof(*rf))) {
			rc = -EFAULT;
			goto bad_filter;
		}
		/*
		 * The payload is UAPI from an untrusted caller: check that
		 * it is ours, the shape we were built with, and that every
		 * index the evaluator will use as one is in range.
		 */
		if (rf->rf_magic != LFU_RING_FILTER_MAGIC ||
		    rf->rf_version != LFU_RING_WIRE_VERSION ||
		    rf->rf_size != sizeof(struct lfu_filter) ||
		    lfu_filter_validate(&rf->rf_filter) != 0) {
			rc = -EINVAL;
			goto bad_filter;
		}
		/* refuse what this OSD cannot answer, before any object */
		if (lfu_filter_needs(&rf->rf_filter) & ~r->can_supply) {
			rc = -EOPNOTSUPP;
			goto bad_filter;
		}
		if (lfu_filter_attrs_used(&rf->rf_filter) & ~r->attr_mask) {
			rc = -EOPNOTSUPP;
			goto bad_filter;
		}
		if (lfu_filter_needs(&rf->rf_filter) != 0) {
			rc = lfu_ring_alloc_scratch(r);
			if (rc)
				goto bad_filter;
		}
		kfree(r->filter);
		r->filter = rf;
		r->emit_unknown = !!(rf->rf_flags & LFU_FILTER_EMIT_UNKNOWN);
		mutex_unlock(&r->lock);
		break;
bad_filter:
		kfree(rf);
		mutex_unlock(&r->lock);
		break;
	}

	case LFU_RING_IOC_STATS:
		if (copy_to_user(uarg, &r->st, sizeof(r->st)))
			rc = -EFAULT;
		break;

	default:
		rc = -ENOTTY;
	}

	return rc;
}

static ssize_t lfu_ring_read(struct file *filp, char __user *ubuf,
			     size_t len, loff_t *ppos)
{
	struct lfu_ring *r = filp->private_data;
	size_t want = len / sizeof(struct lfu_wire_rec);
	u64 avail, idx, run;
	size_t done = 0;
	int rc;

	if (want == 0)
		return -EINVAL;

	/* the first read() starts the scan, so ioctls could precede it */
	mutex_lock(&r->lock);
	rc = lfu_ring_start(r);
	mutex_unlock(&r->lock);
	if (rc)
		return rc;

	for (;;) {
		avail = lfu_ring_avail(r);
		if (avail > 0)
			break;
		if (READ_ONCE(r->done))
			return r->err ? r->err : 0;	/* EOF */
		rc = wait_event_interruptible(r->wq_cons,
			lfu_ring_avail(r) > 0 || READ_ONCE(r->done));
		if (rc)
			return rc;
	}

	run = min_t(u64, avail, want);
	/* cap at the wrap point; the next read picks up the rest */
	idx = r->tail & (ring_recs - 1);
	run = min_t(u64, run, ring_recs - idx);
	if (copy_to_user(ubuf, &r->buf[idx],
			 run * sizeof(struct lfu_wire_rec)))
		return -EFAULT;
	done = run;

	smp_store_release(&r->tail, r->tail + done);
	if (lfu_ring_free(r) >= batch)
		wake_up(&r->wq_prod);

	return done * sizeof(struct lfu_wire_rec);
}

static int lfu_ring_release(struct inode *inode, struct file *filp)
{
	struct lfu_ring *r = filp->private_data;

	if (r->task != NULL) {
		kthread_stop(r->task);
		put_task_struct(r->task);
	}
	lfu_ring_free_scratch(r);
	kfree(r->filter);
	vfree(r->buf);
	kfree(r);
	lr = NULL;
	atomic_set(&lfu_open_cnt, 0);
	return 0;
}

static const struct file_operations lfu_ring_fops = {
	.owner		= THIS_MODULE,
	.open		= lfu_ring_open,
	.read		= lfu_ring_read,
	.unlocked_ioctl	= lfu_ring_ioctl,
	.release	= lfu_ring_release,
};

static struct miscdevice lfu_ring_misc = {
	.minor	= MISC_DYNAMIC_MINOR,
	.name	= LFU_RING_DEVNAME,
	.fops	= &lfu_ring_fops,
};

static int __init lfu_ring_init(void)
{
	if (!is_power_of_2(ring_recs) || batch == 0 || batch > ring_recs / 2)
		return -EINVAL;
	return misc_register(&lfu_ring_misc);
}

static void __exit lfu_ring_exit(void)
{
	misc_deregister(&lfu_ring_misc);
}

module_init(lfu_ring_init);
module_exit(lfu_ring_exit);
MODULE_AUTHOR("LFU project");
MODULE_DESCRIPTION("otable iterator to userspace via a batched ring, filter evaluated in kernel");
MODULE_LICENSE("GPL");
