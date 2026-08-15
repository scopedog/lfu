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
 *   include/uapi/linux/lustre/lustre_idl.h:278-310   (FID sequences)
 *   include/uapi/linux/lustre/lustre_idl.h:1283-1292 (xattr names)
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

/* lustre_idl.h:3493-3508 — linkea. Note lee_reclen is a 2-byte BIG-endian
 * value stored unaligned, and leh_magic/leh_len are big-endian too.
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

#endif /* LFU_LUSTRE_H */
