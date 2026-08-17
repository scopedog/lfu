/* SPDX-License-Identifier: GPL-2.0 */
/*
 * lfu_ring — wire format and control interface shared between the lfu_ring
 * kernel module and the userspace kmdt backend (design step 4, filter
 * pushdown 2026-08-17).
 *
 * Data path: read() on the device returns an integral number of fixed-size
 * struct lfu_wire_rec; EOF (read() == 0) means the scan completed.  One
 * record per object that PASSED the filter (or was undecided, if asked for).
 *
 * Control path: three ioctls on the same fd, all before the first read():
 *
 *   LFU_RING_IOC_INFO        what this module is: wire version, record size,
 *                            which xattrs its OSD can supply, which --attrs
 *                            bits its flag word carries.  A consumer checks
 *                            this before it trusts a single record.
 *   LFU_RING_IOC_SET_FILTER  the compiled filter (struct lfu_filter, from
 *                            lfu_filter.h) plus a flag word.  Evaluated in
 *                            kernel, immediately after rec(), before the ring:
 *                            tier 0 on the record, then the demanded xattrs
 *                            through rec(DORA_XATTR), then tier 1.  A
 *                            rejected object never enters the ring
 *                            (design-osd-scanner.md §4).
 *   LFU_RING_IOC_STATS       after EOF: how many objects each stage saw and
 *                            where the xattr bytes came from.  This is how
 *                            the tier-2 rate becomes a number.
 *
 * Everything here is UAPI.  Fields are only ever appended; the version is
 * bumped when the record grows so an old consumer refuses rather than
 * misparses.
 */
#ifndef LFU_RING_H
#define LFU_RING_H

#include <linux/types.h>
#include <linux/ioctl.h>

#include "../lfu_filter.h"

#define LFU_RING_DEVNAME	"lfu_scan"

/*
 * Wire version 2: version 1 was the 88-byte record with the nine fields
 * osd_raw_attr() originally filled.  Version 2 adds the three tier-0 fields
 * that were missing (btime, projid, flags), the LMA flags so classification
 * downstream is no longer by FID sequence alone, and the decoded tier-1 values
 * the kernel filter already paid for, so the consumer can print the file's
 * size and layout without a second read of anything.
 */
#define LFU_RING_WIRE_VERSION	2

/* wr_lfu bits */
#define LFU_WR_UNKNOWN		0x01	/* filter outcome was undecided (§4.4);
					 * only present with LFU_FILTER_EMIT_UNKNOWN */
#define LFU_WR_HAVE_SOM		0x02	/* wr_som_* are from trusted.som */
#define LFU_WR_HAVE_LOV		0x04	/* wr_stripe_*, wr_pool are from trusted.lov */
#define LFU_WR_HAVE_LMV		0x08	/* wr_lmv_* are from trusted.lmv */
#define LFU_WR_XA_EXTERNAL	0x10	/* at least one xattr came from outside
					 * the inode: a tier-2 object */

struct lfu_wire_rec {
	/* --- version 1: natural alignment, u64 first, 88 bytes --- */
	__u64	wr_oid;		/* backend object id (inode / dnode)   */
	__u64	wr_fid_seq;
	__u64	wr_valid;	/* LA_* mask of the fields below        */
	__u64	wr_size;	/* the MDT inode's own; see wr_som_size */
	__u64	wr_blocks;	/* 512-byte units, the MDT inode's own  */
	__s64	wr_atime;
	__s64	wr_mtime;
	__s64	wr_ctime;
	__u32	wr_fid_oid;
	__u32	wr_fid_ver;
	__u32	wr_mode;
	__u32	wr_nlink;
	__u32	wr_uid;
	__u32	wr_gid;
	/* --- version 2 --- */
	__s64	wr_btime;
	__u64	wr_som_size;	/* the FILE's size, if LFU_WR_HAVE_SOM */
	__u64	wr_som_blocks;	/* the FILE's blocks, 512-byte units */
	__u32	wr_projid;
	__u32	wr_flags;	/* la_flags: LUSTRE_*_FL, the STATX-compatible
				 * five of which are LFU_ATTR_* */
	__u32	wr_lma_compat;
	__u32	wr_lma_incompat;
	__u32	wr_lfu;		/* LFU_WR_* */
	__u32	wr_stripe_count;
	__u32	wr_stripe_size;
	__u32	wr_lmv_count;
	__u32	wr_lmv_hash;
	__u16	wr_som_valid;	/* SOM_FL_* */
	char	wr_pool[16];	/* LOV_MAXPOOLNAME + 1 */
	__u8	wr_pad[2];
};

/* 88 + 8*3 + 4*9 + 2 + 16 + 2 = 168, and 8-aligned: read() returns whole
 * records, so the size is part of the contract. */
_Static_assert(sizeof(struct lfu_wire_rec) == 168, "wire record size");

/* ------------------------------------------------------------------ */
/* Control                                                            */

#define LFU_RING_IOC_MAGIC	0xF4	/* not in Documentation/userspace-api/ioctl/ioctl-number.rst */

struct lfu_ring_info {
	__u32	ri_wire_version;	/* LFU_RING_WIRE_VERSION */
	__u32	ri_rec_size;		/* sizeof(struct lfu_wire_rec) */
	__u32	ri_can_supply;		/* lfu_needs bits rec(DORA_XATTR) can
					 * serve on this OSD; 0 = no tier 1 */
	__u32	ri_attr_mask;		/* LFU_ATTR_* bits wr_flags can carry */
	__u32	ri_max_pred;		/* LFU_MAX_PRED the module was built with */
	__u32	ri_flags;		/* LFU_RING_INFO_* */
	char	ri_dev[64];		/* the OSD device name being scanned */
};

#define LFU_RING_INFO_PRIVATE	0x01	/* DOIF_PARALLEL iterator: block parse */
#define LFU_RING_INFO_LDISKFS	0x02
#define LFU_RING_INFO_ZFS	0x04

/* SET_FILTER flags */
#define LFU_FILTER_EMIT_UNKNOWN	0x01	/* also emit undecided objects, tagged */

struct lfu_ring_filter {
	__u32	rf_magic;		/* LFU_RING_FILTER_MAGIC */
	__u32	rf_version;		/* LFU_RING_WIRE_VERSION */
	__u32	rf_size;		/* sizeof(struct lfu_filter) as built */
	__u32	rf_flags;		/* LFU_FILTER_* */
	struct lfu_filter rf_filter;
};

#define LFU_RING_FILTER_MAGIC	0x4c465546	/* "LFUF" */

struct lfu_ring_stats {
	__u64	rs_seen;	/* objects the iterator returned */
	__u64	rs_filtered0;	/* rejected at tier 0 */
	__u64	rs_filtered1;	/* rejected at tier 1 */
	__u64	rs_unknown;	/* undecided (§4.4) */
	__u64	rs_emitted;	/* entered the ring */
	__u64	rs_xa_inline;	/* DORA_XATTR served from the in-inode area */
	__u64	rs_xa_ext;	/* ... from an external block: tier 2 */
	__u64	rs_xa_iget;	/* ... through a live inode (no block held) */
	__u64	rs_xa_toolarge;	/* xattr larger than the scratch buffer */
	__u64	rs_xa_err;	/* DORA_XATTR failed for another reason */
	__u64	rs_raw;		/* objects the OSD decoded from the raw table */
	__u64	rs_fallback;	/* objects the raw parse declined (-EAGAIN) */
	__u64	rs_stalls;	/* producer waited for ring space */
	__s32	rs_err;		/* producer's final error, 0 if none */
	__u32	rs_pad;
};

#define LFU_RING_IOC_INFO	_IOR(LFU_RING_IOC_MAGIC, 1, struct lfu_ring_info)
#define LFU_RING_IOC_SET_FILTER	_IOW(LFU_RING_IOC_MAGIC, 2, struct lfu_ring_filter)
#define LFU_RING_IOC_STATS	_IOR(LFU_RING_IOC_MAGIC, 3, struct lfu_ring_stats)

#endif /* LFU_RING_H */
