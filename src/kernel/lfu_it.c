// SPDX-License-Identifier: GPL-2.0
/*
 * lfu_it — one-shot harness measuring the OSD otable iterator with a
 * minimal consumer (design step 1, scrub-decomposition-2026-08-07.md).
 *
 * Why this exists: `lctl lfsck_start -t scrub` measures the LFSCK-engine
 * pipeline, not the iterator — the scrub producer paces itself to LFSCK's
 * consumer window (osd_scrub_next: wait_var_event when !os_full_speed &&
 * !osd_scrub_has_window), so removing per-object work on the producer
 * changes nothing.  Verified empirically: an OI-verification-skip knob left
 * ZFS scrub wall time at 22s with the scrub thread at ~0% CPU.
 *
 * This module is the consumer LFU would be: dt_locate the otable-it object,
 * do_index_try(dt_otable_features), then a tight rec()/next() loop that
 * counts FIDs and discards them.  Producer + trivial consumer = the Option 2
 * pipeline floor.  Runs at insmod and returns -ENODEV so nothing stays
 * loaded; results go to dmesg.
 *
 * Usage:  insmod lfu_it.ko dev=lustre-MDT0000-osd [limit=N]
 */
#include <linux/module.h>
#include <linux/ktime.h>
#include <obd_class.h>
#include <dt_object.h>
#include <lustre_fid.h>

static char *dev = "lustre-MDT0000-osd";
module_param(dev, charp, 0444);
MODULE_PARM_DESC(dev, "OSD obd device name, e.g. lustre-MDT0000-osd");

static unsigned int limit;
module_param(limit, uint, 0444);
MODULE_PARM_DESC(limit, "stop after N objects (0 = all)");

static unsigned int recattr;
module_param(recattr, uint, 0444);
MODULE_PARM_DESC(recattr, "1 = request attributes via rec() (DOIF_ATTR OSDs)");

/* Fallbacks so this harness also compiles against an unpatched tree; the
 * flag bit is simply ignored there and rec() returns a bare FID. */
#define LFU_DOIF_ATTR	0x0010
#ifndef DORA_ATTR
#define DORA_ATTR	0x01
struct dt_otable_rec {
	struct lu_fid	dor_fid;
	struct lu_attr	dor_attr;
};
#endif

static int __init lfu_it_init(void)
{
	struct obd_device *obd;
	struct dt_device *dt;
	struct dt_object *obj = NULL;
	const struct dt_it_ops *iops;
	struct dt_it *di = NULL;
	struct lu_env env;
	struct lu_fid fid;
	u64 count = 0;
	ktime_t t0, t1;
	s64 ms;
	int rc, rc2;

	obd = class_name2obd(dev);
	if (obd == NULL || obd->obd_lu_dev == NULL) {
		pr_err("lfu_it: no such osd device '%s'\n", dev);
		return -ENOENT;
	}
	dt = lu2dt_dev(obd->obd_lu_dev);

	rc = lu_env_init(&env, LCT_MD_THREAD | LCT_DT_THREAD | LCT_LOCAL);
	if (rc)
		return rc;

	fid.f_seq = FID_SEQ_LOCAL_FILE;
	fid.f_oid = OTABLE_IT_OID;
	fid.f_ver = 0;

	obj = dt_locate(&env, dt, &fid);
	if (IS_ERR(obj)) {
		rc = PTR_ERR(obj);
		pr_err("lfu_it: dt_locate otable object: rc = %d\n", rc);
		obj = NULL;
		goto out_env;
	}

	rc = obj->do_ops->do_index_try(&env, obj, &dt_otable_features);
	if (rc) {
		pr_err("lfu_it: do_index_try: rc = %d\n", rc);
		goto out_obj;
	}
	iops = &obj->do_index_ops->dio_it;

	/* DOIF_RESET: scan from object 0.  DOIF_OUTUSED: consumer outside
	 * the OSD, exactly LFSCK's mode of use.
	 */
	di = iops->init(&env, obj,
			(DOIF_RESET | DOIF_OUTUSED |
			 (recattr ? LFU_DOIF_ATTR : 0))
			<< DT_OTABLE_IT_FLAGS_SHIFT);
	if (IS_ERR(di)) {
		rc = PTR_ERR(di);
		pr_err("lfu_it: it init: rc = %d (is scrub/LFSCK running? "
		       "the iterator is a per-device singleton)\n", rc);
		di = NULL;
		goto out_obj;
	}

	rc = iops->load(&env, di, 0);
	if (rc < 0) {
		pr_err("lfu_it: it load: rc = %d\n", rc);
		goto out_it;
	}

	t0 = ktime_get();
	{
	struct dt_otable_rec dor;
	u64 attr_ok = 0;

	for (;;) {
		rc2 = iops->rec(&env, di, (struct dt_rec *)&dor,
				recattr ? DORA_ATTR : 0);
		if (rc2 == 0) {
			count++;
			if (recattr && (dor.dor_attr.la_valid & LA_MODE) &&
			    dor.dor_attr.la_mode != 0)
				attr_ok++;
		}

		if (limit && count >= limit)
			break;

		rc2 = iops->next(&env, di);
		if (rc2 != 0)
			break;	/* > 0: end of table; < 0: error */

		if ((count & 0xffff) == 0)
			cond_resched();
	}
	t1 = ktime_get();

	ms = ktime_to_ms(ktime_sub(t1, t0));
	pr_info("lfu_it: dev=%s recattr=%u objects=%llu attr_ok=%llu time=%lld.%03llds rate=%llu/s next_rc=%d\n",
		dev, recattr, count, attr_ok, ms / 1000, (u64)(ms % 1000),
		ms ? count * 1000 / (u64)ms : 0, rc2);
	}

	rc = 0;
out_it:
	iops->put(&env, di);
	iops->fini(&env, di);
out_obj:
	if (obj)
		lu_object_put(&env, &obj->do_lu);
out_env:
	lu_env_fini(&env);
	/* one-shot: never stay loaded */
	return rc ? rc : -ENODEV;
}

module_init(lfu_it_init);
MODULE_AUTHOR("LFU project");
MODULE_DESCRIPTION("otable iterator throughput harness (one-shot)");
MODULE_LICENSE("GPL");
