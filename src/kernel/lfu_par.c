// SPDX-License-Identifier: GPL-2.0
/*
 * lfu_par — step 5 of the Option 2 measurement plan: does *enumeration*
 * parallelize once the iterator is no longer a per-device singleton?
 *
 * Steps 1–4 established that the single otable iterator is the ceiling on
 * ldiskfs (~800k obj/s enumerate, attributes free, ring free) and the wall
 * on ZFS (~110–130k, fan-out breaks even).  Fan-out behind the singleton
 * cannot move either number because the enumerator itself stays single.
 *
 * This harness needs the DOIF_PARALLEL iterator (patches/parallel-it-*.patch):
 * a private otable iterator instance that neither registers as
 * dev->od_otable_it nor drives the scrub thread, so N of them can walk N
 * object ranges at once.  The harness shards the object-number space into
 * fixed chunks handed out from a shared cursor — dynamic, so a young MDT with
 * its inodes packed into the low block groups still keeps every thread busy —
 * and each thread runs init() → load(start-1) → rec()/next() until store()
 * leaves the chunk → fini(), then takes the next chunk.  End of table is
 * "load() or next() returned 1"; a chunk that finds nothing at or after its
 * start proves every later chunk empty and stops the run.
 *
 * private=0 runs the unpatched singleton path (DOIF_RESET|DOIF_OUTUSED,
 * one thread) in the same boot, for an A/B baseline that does not depend on
 * cross-lab warm-rate reproducibility (which we do not have).
 *
 * Correctness without a userspace dump: every run prints an order-
 * independent FID checksum.  Same MDT ⇒ same objects/attr_ok/fidsum at every
 * nthreads and in both modes, or the sharding is wrong.
 *
 * Usage:  insmod lfu_par.ko dev=lustre-MDT0000-osd nthreads=4 [chunk=65536]
 *                            [recattr=1] [private=1] [limit=N]
 * One-shot like lfu_it: runs at insmod, reports via dmesg, returns -ENODEV.
 */
#include <linux/module.h>
#include <linux/kthread.h>
#include <linux/ktime.h>
#include <linux/delay.h>
#include <linux/atomic.h>
#include <linux/slab.h>
#include <linux/wait.h>
#include <obd_class.h>
#include <dt_object.h>
#include <lustre_fid.h>

static char *dev = "lustre-MDT0000-osd";
module_param(dev, charp, 0444);
MODULE_PARM_DESC(dev, "OSD obd device name, e.g. lustre-MDT0000-osd");

static unsigned int nthreads = 4;
module_param(nthreads, uint, 0444);
MODULE_PARM_DESC(nthreads, "enumerator threads (private=1 only)");

static unsigned int chunk = 65536;
module_param(chunk, uint, 0444);
MODULE_PARM_DESC(chunk,
		 "object numbers per shard; a multiple of the inodes-per-group keeps shards group-aligned on ldiskfs");

static unsigned int recattr = 1;
module_param(recattr, uint, 0444);
MODULE_PARM_DESC(recattr, "1 = request attributes via rec() (DOIF_ATTR)");

static unsigned int priv_mode = 1;	/* "private=" on the command line */
module_param_named(private, priv_mode, uint, 0444);
MODULE_PARM_DESC(private,
		 "1 = DOIF_PARALLEL private iterators (sharded); 0 = the singleton otable iterator, one thread (baseline)");

static unsigned int limit;
module_param(limit, uint, 0444);
MODULE_PARM_DESC(limit, "stop after ~N objects (0 = all)");

/* Fallbacks so this harness also compiles against an unpatched tree.  There
 * the bits are ignored: rec() returns a bare FID, and private=1 fails with
 * -EALREADY on the second thread's init() -- which is itself the singleton
 * demonstrated.  private=0 works everywhere. */
#ifndef DOIF_ATTR
#define DOIF_ATTR	0x0010
#endif
#ifndef DOIF_PARALLEL
#define DOIF_PARALLEL	0x0020
#endif
#ifndef DORA_ATTR
#define DORA_ATTR	0x01
struct dt_otable_rec {
	struct lu_fid	dor_fid;
	struct lu_attr	dor_attr;
};
#endif

struct lfu_par_state {
	struct dt_object *obj;
	const struct dt_it_ops *iops;
	atomic64_t cursor;	/* next chunk index to hand out */
	atomic64_t objects;
	atomic64_t attr_ok;
	atomic64_t fidsum;	/* order-independent checksum of all FIDs */
	atomic64_t chunks;	/* chunks that returned ≥1 object */
	atomic_t   running;	/* worker threads not yet finished */
	int	   done;	/* end of table seen by someone */
	int	   err;		/* first error, if any */
	wait_queue_head_t wq;
};

static struct lfu_par_state st;

struct lfu_par_worker {
	struct task_struct *task;
	u64 objects;
	s64 ms;
	int rc;
};

static inline u64 lfu_fid_hash(const struct lu_fid *fid)
{
	/* commutative over the set, sensitive to every field */
	return fid->f_seq * 0x9E3779B97F4A7C15ULL + fid->f_oid * 0x2545F4914F6CDD1DULL +
	       fid->f_ver;
}

/*
 * One consumer of one iterator, bounded by [start, end).  Returns 0 when the
 * chunk is exhausted, 1 when the table is (nothing at or after start), <0 on
 * error.  Counts only objects inside the chunk; the object that ends it
 * belongs to the next chunk and is deliberately re-found there.
 */
static int lfu_par_scan_range(struct lu_env *env, u64 start, u64 end,
			      u64 *nobj)
{
	const struct dt_it_ops *iops = st.iops;
	struct dt_it *di;
	struct dt_otable_rec dor;
	__u32 flags = DOIF_OUTUSED | (recattr ? DOIF_ATTR : 0) |
		      (priv_mode ? DOIF_PARALLEL : DOIF_RESET);
	u64 n = 0, aok = 0, sum = 0;
	int rc;

	di = iops->init(env, st.obj, flags << DT_OTABLE_IT_FLAGS_SHIFT);
	if (IS_ERR(di))
		return PTR_ERR(di);

	rc = iops->load(env, di, start ? start - 1 : 0);
	while (rc == 0) {
		u64 pos = iops->store(env, di);

		if (pos >= end) {
			rc = 0;
			break;
		}

		rc = iops->rec(env, di, (struct dt_rec *)&dor,
			       recattr ? DORA_ATTR : 0);
		if (rc)
			break;
		n++;
		sum += lfu_fid_hash(&dor.dor_fid);
		if (recattr && (dor.dor_attr.la_valid & LA_MODE) &&
		    dor.dor_attr.la_mode != 0)
			aok++;

		if (limit && atomic64_read(&st.objects) + n >= limit) {
			rc = 1;
			break;
		}
		if ((n & 0x3fff) == 0)
			cond_resched();

		rc = iops->next(env, di);
	}

	iops->put(env, di);
	iops->fini(env, di);

	*nobj = n;
	atomic64_add(n, &st.objects);
	atomic64_add(aok, &st.attr_ok);
	atomic64_add(sum, &st.fidsum);
	if (n)
		atomic64_inc(&st.chunks);
	return rc;
}

static int lfu_par_worker(void *arg)
{
	struct lfu_par_worker *w = arg;
	struct lu_env env;
	ktime_t t0 = ktime_get();
	int rc;

	rc = lu_env_init(&env, LCT_MD_THREAD | LCT_DT_THREAD | LCT_LOCAL);
	if (rc)
		goto out;

	if (!priv_mode) {
		/* baseline: one iterator, the whole table */
		rc = lfu_par_scan_range(&env, 0, ~0ULL, &w->objects);
		if (rc > 0)
			rc = 0;
	} else {
		while (!READ_ONCE(st.done) && !READ_ONCE(st.err)) {
			u64 c = atomic64_fetch_inc(&st.cursor);
			u64 start = c * (u64)chunk;
			u64 nobj = 0;

			rc = lfu_par_scan_range(&env, start, start + chunk,
						&nobj);
			w->objects += nobj;
			if (rc > 0) {
				WRITE_ONCE(st.done, 1);
				rc = 0;
				break;
			}
			if (rc < 0)
				break;
		}
	}

	if (rc < 0 && !READ_ONCE(st.err))
		WRITE_ONCE(st.err, rc);
	lu_env_fini(&env);
out:
	w->rc = rc;
	w->ms = ktime_to_ms(ktime_sub(ktime_get(), t0));
	atomic_dec(&st.running);
	wake_up_all(&st.wq);
	return 0;
}

static int __init lfu_par_init(void)
{
	struct obd_device *obd;
	struct dt_device *dt;
	struct lfu_par_worker *workers = NULL;
	struct lu_env env;
	struct lu_fid fid;
	ktime_t t0, t1;
	u64 count, wmin = ~0ULL, wmax = 0;
	s64 ms;
	unsigned int i, n;
	int rc;

	if (!priv_mode)
		nthreads = 1;
	if (nthreads == 0 || chunk == 0)
		return -EINVAL;
	n = nthreads;

	obd = class_name2obd(dev);
	if (obd == NULL || obd->obd_lu_dev == NULL) {
		pr_err("lfu_par: no such osd device '%s'\n", dev);
		return -ENOENT;
	}
	dt = lu2dt_dev(obd->obd_lu_dev);

	rc = lu_env_init(&env, LCT_MD_THREAD | LCT_DT_THREAD | LCT_LOCAL);
	if (rc)
		return rc;

	fid.f_seq = FID_SEQ_LOCAL_FILE;
	fid.f_oid = OTABLE_IT_OID;
	fid.f_ver = 0;

	st.obj = dt_locate(&env, dt, &fid);
	if (IS_ERR(st.obj)) {
		rc = PTR_ERR(st.obj);
		pr_err("lfu_par: dt_locate otable object: rc = %d\n", rc);
		st.obj = NULL;
		goto out_env;
	}

	rc = st.obj->do_ops->do_index_try(&env, st.obj, &dt_otable_features);
	if (rc) {
		pr_err("lfu_par: do_index_try: rc = %d\n", rc);
		goto out_obj;
	}
	st.iops = &st.obj->do_index_ops->dio_it;

	atomic64_set(&st.cursor, 0);
	atomic64_set(&st.objects, 0);
	atomic64_set(&st.attr_ok, 0);
	atomic64_set(&st.fidsum, 0);
	atomic64_set(&st.chunks, 0);
	st.done = 0;
	st.err = 0;
	init_waitqueue_head(&st.wq);

	workers = kcalloc(n, sizeof(*workers), GFP_KERNEL);
	if (!workers) {
		rc = -ENOMEM;
		goto out_obj;
	}

	t0 = ktime_get();
	atomic_set(&st.running, n);
	for (i = 0; i < n; i++) {
		workers[i].task = kthread_run(lfu_par_worker, &workers[i],
					      "lfu_par%u", i);
		if (IS_ERR(workers[i].task)) {
			rc = PTR_ERR(workers[i].task);
			workers[i].task = NULL;
			atomic_sub(n - i, &st.running);
			WRITE_ONCE(st.err, rc);
			pr_err("lfu_par: kthread_run %u: rc = %d\n", i, rc);
			break;
		}
	}
	wait_event(st.wq, atomic_read(&st.running) == 0);
	t1 = ktime_get();

	count = atomic64_read(&st.objects);
	ms = ktime_to_ms(ktime_sub(t1, t0));
	for (i = 0; i < n; i++) {
		if (!workers[i].task)
			continue;
		wmin = min(wmin, workers[i].objects);
		wmax = max(wmax, workers[i].objects);
		pr_info("lfu_par:   thread %u: objects=%llu time=%lld.%03llds rc=%d\n",
			i, workers[i].objects, workers[i].ms / 1000,
			(u64)(workers[i].ms % 1000), workers[i].rc);
	}
	pr_info("lfu_par: dev=%s private=%u nthreads=%u chunk=%u recattr=%u objects=%llu attr_ok=%lld fidsum=%016llx chunks=%lld time=%lld.%03llds rate=%llu/s per-thread min=%llu max=%llu err=%d\n",
		dev, priv_mode, n, chunk, recattr, count,
		(long long)atomic64_read(&st.attr_ok),
		(unsigned long long)atomic64_read(&st.fidsum),
		(long long)atomic64_read(&st.chunks),
		ms / 1000, (u64)(ms % 1000),
		ms ? count * 1000 / (u64)ms : 0,
		wmin == ~0ULL ? 0 : wmin, wmax, READ_ONCE(st.err));

	rc = READ_ONCE(st.err);
	kfree(workers);
out_obj:
	if (st.obj)
		lu_object_put(&env, &st.obj->do_lu);
out_env:
	lu_env_fini(&env);
	/* one-shot: never stay loaded */
	return rc ? rc : -ENODEV;
}

module_init(lfu_par_init);
MODULE_AUTHOR("LFU project");
MODULE_DESCRIPTION("parallel otable enumeration harness (one-shot)");
MODULE_LICENSE("GPL");
