/* SPDX-License-Identifier: LGPL-2.1+ */
/*
 * LFU Input Scanners — on-disk Lustre structures (backend-neutral).
 *
 * Local mirrors of the Lustre UAPI definitions needed to interpret MDT/OST
 * inode xattrs.  A production build must include the real UAPI headers from
 * lustre-devel instead of these; they are duplicated here only so the
 * prototype builds without a Lustre installation.
 *
 * Cross-checked against lustre-release v2_17_55:
 *   include/uapi/linux/lustre/lustre_user.h:460-534  (LMA, LMAC/LMAI flags)
 *   include/uapi/linux/lustre/lustre_user.h:544-562  (SOM)
 *   include/uapi/linux/lustre/lustre_user.h:791-807  (LOV patterns)
 *   include/uapi/linux/lustre/lustre_user.h:1099-1180 (composite layout)
 *   include/uapi/linux/lustre/lustre_idl.h:278-310   (FID sequences)
 *   include/uapi/linux/lustre/lustre_idl.h:1203-1320 (LOV magics, LOV EA)
 *   include/uapi/linux/lustre/lustre_idl.h:1283-1292 (xattr names)
 *   include/uapi/linux/lustre/lustre_idl.h:2354-2407 (LMV)
 *   include/uapi/linux/lustre/lustre_idl.h:3493-3508 (linkea)
 */
#ifndef LFU_LUSTRE_H
#define LFU_LUSTRE_H

#include <stdint.h>

/* Lustre xattr names — lustre_idl.h:1283-1292 */
#define XATTR_NAME_LMA		"trusted.lma"
#define XATTR_NAME_LOV		"trusted.lov"
#define XATTR_NAME_LMV		"trusted.lmv"
#define XATTR_NAME_LINK		"trusted.link"
#define XATTR_NAME_HSM		"trusted.hsm"
#define XATTR_NAME_SOM		"trusted.som"
#define XATTR_NAME_FID		"trusted.fid"

/* lustre_user.h — packed, 16 bytes, little-endian on disk */
struct lu_fid {
	uint64_t f_seq;
	uint32_t f_oid;
	uint32_t f_ver;
} __attribute__((packed));

/* lustre_user.h:495 — 24 bytes, little-endian on disk */
struct lustre_mdt_attrs {
	uint32_t lma_compat;
	uint32_t lma_incompat;
	struct lu_fid lma_self_fid;
} __attribute__((packed));

/* lustre_user.h:460-468 — lma_compat */
enum lma_compat {
	LMAC_HSM		= 0x00000001,
	LMAC_NOT_IN_OI		= 0x00000004,
	LMAC_FID_ON_OST		= 0x00000008,
	LMAC_STRIPE_INFO	= 0x00000010,
	LMAC_COMP_INFO		= 0x00000020,
	LMAC_IDX_BACKUP		= 0x00000040,
};

/* lustre_user.h:477-486 — lma_incompat */
enum lma_incompat {
	LMAI_RELEASED		= 0x00000001,
	LMAI_AGENT		= 0x00000002,
	LMAI_REMOTE_PARENT	= 0x00000004,
	LMAI_STRIPED		= 0x00000008,
	LMAI_ORPHAN		= 0x00000010,
	LMAI_ENCRYPT		= 0x00000020,
	LMA_INCOMPAT_SUPP	= (LMAI_AGENT | LMAI_REMOTE_PARENT |
				   LMAI_STRIPED | LMAI_ORPHAN | LMAI_ENCRYPT),
};

/* --- trusted.som — lustre_user.h:544-562 --------------------------------
 *
 * 24 bytes, and one of the four EAs mkfs.lustre sizes an MDT inode to hold
 * (libmount_utils_ldiskfs.c:860-890), so inline in the normal case.  This is
 * the only place an MDT knows the size of a striped regular file; see
 * docs/filter-levels.md §4.
 */
enum som_flags {
	SOM_FL_UNKNOWN	= 0x0000,
	SOM_FL_STRICT	= 0x0001,
	SOM_FL_STALE	= 0x0002,
	SOM_FL_LAZY	= 0x0004,
};

struct lustre_som_attrs {
	uint16_t lsa_valid;
	uint16_t lsa_reserved[3];
	uint64_t lsa_size;
	uint64_t lsa_blocks;
} __attribute__((packed));

/* --- trusted.lov — lustre_idl.h:1203-1320, lustre_user.h:791-1180 ------- */

#define LOV_MAGIC_MAGIC		0x0BD0
#define LOV_MAGIC_V1		(0x0BD10000 | LOV_MAGIC_MAGIC)
#define LOV_MAGIC_V3		(0x0BD30000 | LOV_MAGIC_MAGIC)
#define LOV_MAGIC_SPECIFIC	(0x0BD50000 | LOV_MAGIC_MAGIC)
#define LOV_MAGIC_COMP_V1	(0x0BD60000 | LOV_MAGIC_MAGIC)
#define LOV_MAGIC_FOREIGN	(0x0BD70000 | LOV_MAGIC_MAGIC)

#define LOV_MAXPOOLNAME		15

enum lov_pattern {
	LOV_PATTERN_NONE		= 0x000,
	LOV_PATTERN_RAID0		= 0x001,
	LOV_PATTERN_RAID1		= 0x002,
	LOV_PATTERN_PARITY		= 0x004,
	LOV_PATTERN_MDT			= 0x100,
	LOV_PATTERN_OVERSTRIPING	= 0x200,
	LOV_PATTERN_FOREIGN		= 0x400,
	LOV_PATTERN_COMPRESS		= 0x800,
};

#define LOV_PATTERN_F_MASK	0xffff0000
#define LOV_PATTERN_F_HOLE	0x40000000
#define LOV_PATTERN_F_RELEASED	0x80000000

/* 24 bytes: a 16-byte ost_id, then generation and OST index. */
struct lov_ost_data_v1 {
	unsigned char l_ost_oi[16];
	uint32_t l_ost_gen;
	uint32_t l_ost_idx;
} __attribute__((packed));

struct lov_mds_md_v1 {
	uint32_t lmm_magic;
	uint32_t lmm_pattern;
	unsigned char lmm_oi[16];
	uint32_t lmm_stripe_size;
	uint16_t lmm_stripe_count;
	uint16_t lmm_layout_gen;
	struct lov_ost_data_v1 lmm_objects[];
} __attribute__((packed));

struct lov_mds_md_v3 {
	uint32_t lmm_magic;
	uint32_t lmm_pattern;
	unsigned char lmm_oi[16];
	uint32_t lmm_stripe_size;
	uint16_t lmm_stripe_count;
	uint16_t lmm_layout_gen;
	char lmm_pool_name[LOV_MAXPOOLNAME + 1];
	struct lov_ost_data_v1 lmm_objects[];
} __attribute__((packed));

struct lu_extent {
	uint64_t e_start;
	uint64_t e_end;
} __attribute__((packed));

struct lov_comp_md_entry_v1 {
	uint32_t lcme_id;
	uint32_t lcme_flags;
	struct lu_extent lcme_extent;
	uint32_t lcme_offset;		/* from the start of lov_comp_md_v1 */
	uint32_t lcme_size;
	uint32_t lcme_layout_gen;
	uint64_t lcme_time_and_id;
	uint8_t lcme_dstripe_count;
	uint8_t lcme_cstripe_count;
	uint8_t lcme_compr_type;
	uint8_t lcme_compr_bits;
} __attribute__((packed));

struct lov_comp_md_v1 {
	uint32_t lcm_magic;
	uint32_t lcm_size;
	uint32_t lcm_layout_gen;
	uint16_t lcm_flags;
	uint16_t lcm_entry_count;
	/* actual mirrors minus 1: a non-FLR file stores 0 and has 1 mirror */
	uint16_t lcm_mirror_count;
	uint8_t lcm_ec_count;
	uint8_t lcm_padding3[1];
	uint16_t lcm_padding1[2];
	uint64_t lcm_padding2;
	struct lov_comp_md_entry_v1 lcm_entries[];
} __attribute__((packed));

/* --- trusted.lmv — lustre_idl.h:2354-2407 ------------------------------- */

#define LMV_MAGIC_V1		0x0CD20CD0UL
#define LMV_MAGIC_STRIPE	0x0CD40CD0UL
#define LMV_MAGIC_FOREIGN	0x0CD50CD0UL

#define LMV_HASH_TYPE_MASK	0x0000ffff

enum lmv_hash_type {
	LMV_HASH_TYPE_UNKNOWN	= 0,
	LMV_HASH_TYPE_ALL_CHARS	= 1,
	LMV_HASH_TYPE_FNV_1A_64	= 2,
	LMV_HASH_TYPE_CRUSH	= 3,
	LMV_HASH_TYPE_CRUSH2	= 4,
	LMV_HASH_TYPE_MAX,
};

struct lmv_mds_md_v1 {
	uint32_t lmv_magic;
	uint32_t lmv_stripe_count;
	uint32_t lmv_master_mdt_index;
	uint32_t lmv_hash_type;
	uint32_t lmv_layout_version;
	uint32_t lmv_migrate_offset;
	uint32_t lmv_migrate_hash;
	uint32_t lmv_padding2;
	uint64_t lmv_padding3;
	char lmv_pool_name[LOV_MAXPOOLNAME + 1];
	struct lu_fid lmv_stripe_fids[];
} __attribute__((packed));

/* lustre_idl.h:278-310 — FID sequence ranges */
#define FID_SEQ_OST_MDT0	0x0ULL
#define FID_SEQ_LLOG		0x1ULL
#define FID_SEQ_IGIF		0xcULL
#define FID_SEQ_IGIF_MAX	0x0ffffffffULL
#define FID_SEQ_IDIF		0x100000000ULL
#define FID_SEQ_IDIF_MAX	0x1ffffffffULL
#define FID_SEQ_START		0x200000000ULL
#define FID_SEQ_LOCAL_FILE	0x200000001ULL
#define FID_SEQ_DOT_LUSTRE	0x200000002ULL
#define FID_SEQ_ROOT		0x200000007ULL
#define FID_SEQ_NORMAL		0x200000400ULL

/*
 * lustre_idl.h:3493-3508 — linkea.  Two different byte-order rules in one
 * xattr, both verified against lustre/obdclass/linkea.c:
 *
 *   lee_reclen  — big-endian, byte by byte, stored unaligned (linkea.c:97).
 *   the header  — the WRITING host's own order.  linkea_init() stores
 *                 leh_magic natively (linkea.c:23) and a reader detects a
 *                 foreign order by comparing the magic against its own swab
 *                 (linkea.c:38-41), then swabs leh_reccount and leh_len to
 *                 match.  So the header must never be read as fixed-endian:
 *                 do what the kernel does and decide from the magic.
 */
#define LINK_EA_MAGIC		0x11EAF1DFUL

struct link_ea_header {
	uint32_t leh_magic;
	uint32_t leh_reccount;
	uint64_t leh_len;
	uint32_t leh_overflow_time;
	uint32_t leh_padding;
};

struct link_ea_entry {
	unsigned char lee_reclen[2];
	unsigned char lee_parent_fid[sizeof(struct lu_fid)];
	char lee_name[];
} __attribute__((packed));

/* --- FID classification, mirroring lustre_fid.h --- */

static inline int fid_seq_is_igif(uint64_t seq)
{
	return seq >= FID_SEQ_IGIF && seq <= FID_SEQ_IGIF_MAX;
}

static inline int fid_seq_is_idif(uint64_t seq)
{
	return seq >= FID_SEQ_IDIF && seq <= FID_SEQ_IDIF_MAX;
}

static inline int fid_seq_is_norm(uint64_t seq)
{
	return seq >= FID_SEQ_NORMAL;
}

static inline int fid_seq_is_root(uint64_t seq)
{
	return seq == FID_SEQ_ROOT;
}

static inline int fid_seq_is_dot(uint64_t seq)
{
	return seq == FID_SEQ_DOT_LUSTRE;
}

/* Internal/local objects: everything in the reserved range below
 * FID_SEQ_NORMAL that is not namespace-visible.
 */
static inline int fid_seq_is_internal(uint64_t seq)
{
	return seq >= FID_SEQ_START && seq < FID_SEQ_NORMAL &&
	       !fid_seq_is_root(seq) && !fid_seq_is_dot(seq);
}

/* lustre_fid.h:290 — fid_is_namespace_visible(), minus the last_id check,
 * which needs OST context we do not have on an MDT scan.
 */
static inline int fid_seq_is_namespace_visible(uint64_t seq)
{
	return fid_seq_is_norm(seq) || fid_seq_is_igif(seq) ||
	       fid_seq_is_root(seq) || fid_seq_is_dot(seq);
}

/*
 * On-disk layout is a contract, and every struct above is parsed straight out
 * of a device buffer, so assert the sizes rather than trusting the packing.
 */
_Static_assert(sizeof(struct lu_fid) == 16, "lu_fid");
_Static_assert(sizeof(struct lustre_mdt_attrs) == 24, "LMA");
_Static_assert(sizeof(struct lustre_som_attrs) == 24, "SOM");
_Static_assert(sizeof(struct lov_ost_data_v1) == 24, "lov_ost_data_v1");
_Static_assert(sizeof(struct lov_mds_md_v1) == 32, "lov_mds_md_v1");
_Static_assert(sizeof(struct lov_mds_md_v3) == 48, "lov_mds_md_v3");
_Static_assert(sizeof(struct lov_comp_md_entry_v1) == 48, "lcme_v1");
_Static_assert(sizeof(struct lov_comp_md_v1) == 32, "lov_comp_md_v1");
_Static_assert(sizeof(struct lmv_mds_md_v1) == 56, "lmv_mds_md_v1");

#endif /* LFU_LUSTRE_H */
