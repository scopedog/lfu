// SPDX-License-Identifier: GPL-2.0
/*
 * lfu_ring — step 4: the otable iterator streamed to userspace through a
 * batched ring (the Object Stream producer for Option 2).
 *
 * Shape: a misc char device.  open() starts an enumerator kthread that owns
 * the otable iterator (DOIF_ATTR: attributes ride along in rec(), measured
 * free in step 3) and writes fixed-size records into an SPSC ring; read()
 * copies whole records out and blocks when empty; EOF when the scan is done
 * and the ring is drained.  One reader at a time — the iterator is a
 * per-device singleton anyway.
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
 * Prototype limits, recorded: single fixed target (module param), wire
 * record carries no LMA flags yet (classification downstream is by FID
 * sequence only), ldiskfs-first (DOIF_ATTR is a no-op elsewhere).
 */
#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/kthread.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>
#include <linux/wait.h>
#include <obd_class.h>
#include <dt_object.h>
#include <lustre_fid.h>

#include "lfu_ring.h"

static char *dev = "testfs-MDT0000-osd";
module_param(dev, charp, 0444);
MODULE_PARM_DESC(dev, "OSD obd device name to scan");

static unsigned int ring_recs = 16384;	/* power of two */
module_param(ring_recs, uint, 0444);
MODULE_PARM_DESC(ring_recs, "ring capacity in records (power of two)");

static unsigned int batch = 2048;
module_param(batch, uint, 0444);
MODULE_PARM_DESC(batch, "wakeup granularity in records");

/* Kept local until the extension lands upstream everywhere the harness
 * builds; mirrors the step-3 patch. */
#ifndef DORA_ATTR
#define DORA_ATTR	0x01
struct dt_otable_rec {
	struct lu_fid	dor_fid;
	struct lu_attr	dor_attr;
};
#endif
#define LFU_DOIF_ATTR	0x0010

struct lfu_ring {
	struct lfu_wire_rec	*buf;
	u64			head;		/* producer, free-running */
	u64			tail;		/* consumer, free-running */
	u64			last_wake;	/* head at last reader wake */
	wait_queue_head_t	wq_prod;
	wait_queue_head_t	wq_cons;
	struct task_struct	*task;
	int			done;		/* producer finished */
	int			err;		/* producer error, if any */
	u64			produced;
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

static void lfu_fill_rec(struct lfu_wire_rec *wr, u64 oid,
			 const struct dt_otable_rec *dor)
{
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
}

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

	di = iops->init(&env, obj,
			(DOIF_RESET | DOIF_OUTUSED | LFU_DOIF_ATTR)
			<< DT_OTABLE_IT_FLAGS_SHIFT);
	if (IS_ERR(di)) {
		rc = PTR_ERR(di);
		pr_err("lfu_ring: it init: rc = %d (singleton busy?)\n", rc);
		di = NULL;
		GOTO(out_obj, rc);
	}
	rc = iops->load(&env, di, 0);
	if (rc < 0)
		GOTO(out_it, rc);
	rc = 0;

	for (;;) {
		if (kthread_should_stop())
			break;

		memset(&dor.dor_attr, 0, sizeof(dor.dor_attr));
		rc2 = iops->rec(&env, di, (struct dt_rec *)&dor, DORA_ATTR);
		if (rc2 == 0) {
			/* stall, never drop */
			while (lfu_ring_free(r) == 0) {
				wake_up(&r->wq_cons);
				wait_event(r->wq_prod,
					   lfu_ring_free(r) >= batch ||
					   kthread_should_stop());
				if (kthread_should_stop())
					goto drained;
			}
			lfu_fill_rec(&r->buf[r->head & (ring_recs - 1)],
				     iops->store(&env, di), &dor);
			smp_store_release(&r->head, r->head + 1);
			r->produced++;

			if (r->head - r->last_wake >= batch) {
				r->last_wake = r->head;
				wake_up(&r->wq_cons);
			}
		}

		rc2 = iops->next(&env, di);
		if (rc2 != 0)
			break;
		if ((r->produced & 0xffff) == 0)
			cond_resched();
	}

drained:
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
	WRITE_ONCE(r->done, 1);
	wake_up_all(&r->wq_cons);
	pr_info("lfu_ring: producer done: produced=%llu rc=%d next_rc=%d\n",
		r->produced, rc, rc2);

	/* park until kthread_stop() so the task_struct stays valid */
	while (!kthread_should_stop()) {
		set_current_state(TASK_INTERRUPTIBLE);
		if (!kthread_should_stop())
			schedule();
	}
	__set_current_state(TASK_RUNNING);
	return rc;
}

static int lfu_ring_open(struct inode *inode, struct file *filp)
{
	struct lfu_ring *r;
	struct task_struct *t;

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

	t = kthread_create(lfu_producer, r, "lfu_ring");
	if (IS_ERR(t))
		goto fail_buf;
	get_task_struct(t);
	r->task = t;
	wake_up_process(t);

	lr = r;
	filp->private_data = r;
	return 0;

fail_buf:
	vfree(r->buf);
fail_r:
	kfree(r);
fail_cnt:
	atomic_set(&lfu_open_cnt, 0);
	return -ENOMEM;
}

static ssize_t lfu_ring_read(struct file *filp, char __user *ubuf,
			     size_t len, loff_t *ppos)
{
	struct lfu_ring *r = filp->private_data;
	size_t want = len / sizeof(struct lfu_wire_rec);
	u64 avail, idx, run;
	size_t n, done = 0;
	int rc;

	if (want == 0)
		return -EINVAL;

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

	n = min_t(u64, avail, want);
	/* cap at the wrap point; the next read picks up the rest */
	idx = r->tail & (ring_recs - 1);
	run = min_t(u64, n, ring_recs - idx);
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

	kthread_stop(r->task);
	put_task_struct(r->task);
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
MODULE_DESCRIPTION("otable iterator to userspace via a batched ring");
MODULE_LICENSE("GPL");
