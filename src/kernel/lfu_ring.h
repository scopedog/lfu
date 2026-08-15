/* SPDX-License-Identifier: GPL-2.0 */
/*
 * lfu_ring — wire format shared between the lfu_ring kernel module and the
 * userspace kmdt backend (design step 4).
 *
 * One record per object, fixed size, natural alignment (all u64 fields
 * first; 88 bytes, no padding).  read() on the device returns an integral
 * number of records; EOF (read() == 0) means the scan completed.
 */
#ifndef LFU_RING_H
#define LFU_RING_H

#define LFU_RING_DEVNAME	"lfu_scan"

struct lfu_wire_rec {
	__u64	wr_oid;		/* backend object id (inode / dnode)   */
	__u64	wr_fid_seq;
	__u64	wr_valid;	/* LA_* mask of the fields below        */
	__u64	wr_size;
	__u64	wr_blocks;	/* 512-byte units                       */
	__s64	wr_atime;
	__s64	wr_mtime;
	__s64	wr_ctime;
	__u32	wr_fid_oid;
	__u32	wr_fid_ver;
	__u32	wr_mode;
	__u32	wr_nlink;
	__u32	wr_uid;
	__u32	wr_gid;
};

#endif /* LFU_RING_H */
