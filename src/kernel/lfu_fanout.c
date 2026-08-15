// SPDX-License-Identifier: GPL-2.0
/*
 * lfu_fanout — step 2 of the Option 2 measurement plan: does per-object
 * work parallelize behind the otable iterator singleton?
 *
 * One enumerator thread owns the iterator (it is one-per-osd_device by
 * design) and pushes (oid, fid) pairs into a ring.  N worker threads pop
 * and do the per-object attribute work LFU needs — dt_locate(),
 * dt_attr_get(), dt_xattr_get(trusted.lma) — then drop the object.
 *
 * The dt_locate()-per-FID path is deliberately the naive one: it re-reads
 * objects the iterator's engine already had in hand, which is exactly the
 * waste the proposed rec()-attribute extension would remove.  Measuring the
 * fan-out with that waste bounds what the extension is worth.
 *
 * Matrix:
 *   nworkers=0            — enumerate + discard (lfu_it equivalent)
 *   nworkers=N, attrs=0   — fan-out overhead only (ring + wakeups)
 *   nworkers=N, attrs=1   — full per-object attribute read in workers
 *
 * One-shot like lfu_it: runs at insmod, reports via dmesg, returns -ENODEV.
 */
#include <linux/module.h>
#include <linux/kthread.h>
#include <linux/kfifo.h>
#include <linux/ktime.h>
#include <linux/delay.h>
#include <obd_class.h>
#include <dt_object.h>
#include <lustre_fid.h>
#include <uapi/linux/lustre/lustre_idl.h>

static char *dev = "lustre-MDT0000-osd";
module_param(dev, charp, 0444);
MODULE_PARM_DESC(dev, "OSD obd device name");

static unsigned int nworkers;
module_param(nworkers, uint, 0444);
MODULE_PARM_DESC(nworkers, "attribute worker threads (0 = enumerate only)");

static unsigned int attrs = 1;
module_param(attrs, uint, 0444);
MODULE_PARM_DESC(attrs, "1 = workers do locate+attr+LMA, 0 = workers discard");

struct lfu_ent {
	u64		oid;
	struct lu_fid	fid;
};

#define LFU_RING_ORDER	4096	/* entries; power of two for kfifo */
#define LFU_BATCH	64

struct lfu_state {
	struct dt_device *dt;
	DECLARE_KFIFO_PTR(ring, struct lfu_ent);
	spinlock_t lock;
	wait_queue_head_t wq_cons;
	wait_queue_head_t wq_prod;
	atomic64_t handled;	/* objects fully processed by workers */
	atomic64_t located;	/* dt_locate successes */
	atomic64_t missing;	/* locate failed / !exists */
	atomic_t   workers_up;
	int	   done;	/* enumerator finished */
	int	   abort;
};

static struct lfu_state st;

static int lfu_worker(void *arg)
{
	struct lu_env env;
	struct lfu_ent ent;
	struct lu_attr la;
	char xbuf[128];
	struct lu_buf lb = { .lb_buf = xbuf, .lb_len = sizeof(xbuf) };
	int rc;

	rc = lu_env_init(&env, LCT_MD_THREAD | LCT_DT_THREAD | LCT_LOCAL);
	if (rc) {
		st.abort = 1;
		atomic_dec(&st.workers_up);
		wake_up_all(&st.wq_prod);
		return rc;
	}

	for (;;) {
		unsigned int got;

		got = kfifo_out_spinlocked(&st.ring, &ent, 1, &st.lock);
		if (!got) {
			if (READ_ONCE(st.done) || READ_ONCE(st.abort))
				break;
			wait_event(st.wq_cons,
				   !kfifo_is_empty(&st.ring) ||
				   READ_ONCE(st.done) || READ_ONCE(st.abort));
			continue;
		}
		wake_up(&st.wq_prod);

		if (attrs) {
			struct dt_object *o;

			o = dt_locate(&env, st.dt, &ent.fid);
			if (!IS_ERR(o)) {
				if (dt_object_exists(o)) {
					atomic64_inc(&st.located);
					rc = dt_attr_get(&env, o, &la);
					if (rc == 0)
						rc = dt_xattr_get(&env, o, &lb,
							XATTR_NAME_LMA);
					(void)rc;	/* measured, not used */
				} else {
					atomic64_inc(&st.missing);
				}
				dt_object_put(&env, o);
			} else {
				atomic64_inc(&st.missing);
			}
		}
		atomic64_inc(&st.handled);
	}

	lu_env_fini(&env);
	atomic_dec(&st.workers_up);
	wake_up_all(&st.wq_prod);
	return 0;
}

static int __init lfu_fanout_init(void)
{
	struct obd_device *obd;
	struct dt_object *obj = NULL;
	const struct dt_it_ops *iops;
	struct dt_it *di = NULL;
	struct task_struct **tasks = NULL;
	struct lu_env env;
	struct lu_fid fid;
	u64 count = 0;
	ktime_t t0, t1;
	s64 ms;
	unsigned int i, started = 0;
	int rc, rc2 = 0;

	obd = class_name2obd(dev);
	if (obd == NULL || obd->obd_lu_dev == NULL) {
		pr_err("lfu_fanout: no such osd device '%s'\n", dev);
		return -ENOENT;
	}

	/* st is static and the module is loaded fresh per run (one-shot) */
	st.dt = lu2dt_dev(obd->obd_lu_dev);
	spin_lock_init(&st.lock);
	init_waitqueue_head(&st.wq_cons);
	init_waitqueue_head(&st.wq_prod);
	atomic64_set(&st.handled, 0);
	atomic64_set(&st.located, 0);
	atomic64_set(&st.missing, 0);
	st.done = 0;
	st.abort = 0;

	rc = kfifo_alloc(&st.ring, LFU_RING_ORDER, GFP_KERNEL);
	if (rc)
		return rc;

	rc = lu_env_init(&env, LCT_MD_THREAD | LCT_DT_THREAD | LCT_LOCAL);
	if (rc)
		goto out_fifo;

	fid.f_seq = FID_SEQ_LOCAL_FILE;
	fid.f_oid = OTABLE_IT_OID;
	fid.f_ver = 0;
	obj = dt_locate(&env, st.dt, &fid);
	if (IS_ERR(obj)) {
		rc = PTR_ERR(obj);
		obj = NULL;
		goto out_env;
	}
	rc = obj->do_ops->do_index_try(&env, obj, &dt_otable_features);
	if (rc)
		goto out_obj;
	iops = &obj->do_index_ops->dio_it;

	di = iops->init(&env, obj,
			(DOIF_RESET | DOIF_OUTUSED) << DT_OTABLE_IT_FLAGS_SHIFT);
	if (IS_ERR(di)) {
		rc = PTR_ERR(di);
		pr_err("lfu_fanout: it init: rc = %d (singleton busy?)\n", rc);
		di = NULL;
		goto out_obj;
	}
	rc = iops->load(&env, di, 0);
	if (rc < 0)
		goto out_it;

	if (nworkers) {
		tasks = kcalloc(nworkers, sizeof(*tasks), GFP_KERNEL);
		if (!tasks) {
			rc = -ENOMEM;
			goto out_it;
		}
	}

	t0 = ktime_get();
	atomic_set(&st.workers_up, nworkers);
	for (i = 0; i < nworkers; i++) {
		tasks[i] = kthread_run(lfu_worker, NULL, "lfu_wk%u", i);
		if (IS_ERR(tasks[i])) {
			atomic_sub(nworkers - i, &st.workers_up);
			st.abort = 1;
			break;
		}
		started++;
	}

	/* enumerator loop (this thread) */
	for (;;) {
		struct lfu_ent ent;

		if (READ_ONCE(st.abort))
			break;

		rc2 = iops->rec(&env, di, (struct dt_rec *)&ent.fid, 0);
		if (rc2 == 0) {
			ent.oid = iops->store(&env, di);
			count++;
			if (nworkers) {
				while (!kfifo_in_spinlocked(&st.ring, &ent, 1,
							    &st.lock)) {
					wake_up(&st.wq_cons);
					wait_event(st.wq_prod,
						!kfifo_is_full(&st.ring) ||
						READ_ONCE(st.abort));
					if (READ_ONCE(st.abort))
						break;
				}
				wake_up(&st.wq_cons);
			}
		}

		rc2 = iops->next(&env, di);
		if (rc2 != 0)
			break;
		if ((count & 0xffff) == 0)
			cond_resched();
	}

	WRITE_ONCE(st.done, 1);
	wake_up_all(&st.wq_cons);
	while (atomic_read(&st.workers_up) > 0) {
		wake_up_all(&st.wq_cons);
		usleep_range(500, 1000);
	}
	t1 = ktime_get();

	ms = ktime_to_ms(ktime_sub(t1, t0));
	pr_info("lfu_fanout: dev=%s workers=%u attrs=%u produced=%llu handled=%lld located=%lld missing=%lld time=%lld.%03llds rate=%llu/s next_rc=%d\n",
		dev, started, attrs, count,
		(long long)atomic64_read(&st.handled),
		(long long)atomic64_read(&st.located),
		(long long)atomic64_read(&st.missing),
		ms / 1000, (u64)(ms % 1000),
		ms ? count * 1000 / (u64)ms : 0, rc2);

	rc = 0;
	kfree(tasks);
out_it:
	iops->put(&env, di);
	iops->fini(&env, di);
out_obj:
	if (obj)
		lu_object_put(&env, &obj->do_lu);
out_env:
	lu_env_fini(&env);
out_fifo:
	kfifo_free(&st.ring);
	return rc ? rc : -ENODEV;	/* one-shot */
}

module_init(lfu_fanout_init);
MODULE_AUTHOR("LFU project");
MODULE_DESCRIPTION("otable iterator fan-out harness (one-shot)");
MODULE_LICENSE("GPL");
