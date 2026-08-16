/*
 * Validate the raw inode-table parser from the block-parse patch against a
 * real ext4 image, in userspace.  osd_raw_lma() and osd_raw_attr() are
 * #included verbatim from the patched osd_scrub.c -- only the kernel types
 * they depend on are stubbed here, so what runs is the code that will run in
 * the kernel.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <linux/types.h>
#include <errno.h>
#include <stdbool.h>

#define le16_to_cpu(x) ((__u16)(x))
#define le32_to_cpu(x) ((__u32)(x))
#define le64_to_cpu(x) ((__u64)(x))
#define min_t(t, a, b) ((t)(a) < (t)(b) ? (t)(a) : (t)(b))
#define S_ISREG_MODE(m) (((m) & 0170000) == 0100000)

/* --- on-disk inode, ext4 layout (the kernel calls this ldiskfs_inode) --- */
struct ldiskfs_inode {
	__le16	i_mode;
	__le16	i_uid;
	__le32	i_size_lo;
	__le32	i_atime;
	__le32	i_ctime;
	__le32	i_mtime;
	__le32	i_dtime;
	__le16	i_gid;
	__le16	i_links_count;
	__le32	i_blocks_lo;
	__le32	i_flags;
	union { struct { __le32 l_i_version; } linux1; } osd1;
	__le32	i_block[15];
	__le32	i_generation;
	__le32	i_file_acl_lo;
	__le32	i_size_high;
	__le32	i_obso_faddr;
	union {
		struct {
			__le16	l_i_blocks_high;
			__le16	l_i_file_acl_high;
			__le16	l_i_uid_high;
			__le16	l_i_gid_high;
			__le16	l_i_checksum_lo;
			__le16	l_i_reserved;
		} linux2;
	} osd2;
	__le16	i_extra_isize;
	__le16	i_checksum_hi;
	__le32	i_ctime_extra;
	__le32	i_mtime_extra;
	__le32	i_atime_extra;
	__le32	i_crtime;
	__le32	i_crtime_extra;
	__le32	i_version_hi;
	__le32	i_projid;
};

_Static_assert(offsetof(struct ldiskfs_inode, i_uid) == 2, "i_uid");
_Static_assert(offsetof(struct ldiskfs_inode, i_size_lo) == 4, "i_size_lo");
_Static_assert(offsetof(struct ldiskfs_inode, i_atime) == 8, "i_atime");
_Static_assert(offsetof(struct ldiskfs_inode, i_dtime) == 20, "i_dtime");
_Static_assert(offsetof(struct ldiskfs_inode, i_links_count) == 26, "i_links");
_Static_assert(offsetof(struct ldiskfs_inode, i_blocks_lo) == 28, "i_blocks");
_Static_assert(offsetof(struct ldiskfs_inode, i_flags) == 32, "i_flags");
_Static_assert(offsetof(struct ldiskfs_inode, i_generation) == 100, "i_gen");
_Static_assert(offsetof(struct ldiskfs_inode, i_file_acl_lo) == 104, "i_facl");
_Static_assert(offsetof(struct ldiskfs_inode, i_size_high) == 108, "i_size_hi");
_Static_assert(offsetof(struct ldiskfs_inode, osd2) == 116, "osd2");
_Static_assert(offsetof(struct ldiskfs_inode, i_extra_isize) == 128, "extra");
_Static_assert(offsetof(struct ldiskfs_inode, i_ctime_extra) == 132, "ctimex");
_Static_assert(offsetof(struct ldiskfs_inode, i_atime_extra) == 140, "atimex");

/* --- the rest of the kernel surface these two functions touch --- */
static __u32 g_isize, g_bits = 12;
static int g_huge;

struct super_block { int s_blocksize_bits; };
#define LDISKFS_INODE_SIZE(sb)		(g_isize)
#define LDISKFS_GOOD_OLD_INODE_SIZE	128
#define LDISKFS_HUGE_FILE_FL		0x00040000
#define ldiskfs_has_feature_huge_file(sb) (g_huge)

struct lu_fid { __u64 f_seq; __u32 f_oid; __u32 f_ver; };
struct lustre_mdt_attrs {
	__u32 lma_compat;
	__u32 lma_incompat;
	struct lu_fid lma_self_fid;
};
struct lustre_ost_attrs {
	struct lustre_mdt_attrs loa_lma;
	struct lu_fid loa_parent_fid;
	__u32 loa_stripe_size;
	__u32 loa_comp_id;
	__u64 loa_comp_start;
	__u64 loa_comp_end;
};
#define LMA_INCOMPAT_SUPP 0x1f
static void lustre_loa_swab(struct lustre_ost_attrs *loa, int to_cpu) { }

struct lu_attr {
	__u64 la_size, la_blocks;
	__s64 la_mtime, la_atime, la_ctime;
	__u32 la_mode, la_uid, la_gid, la_nlink, la_valid;
};
#define LA_MODE 1
#define LA_NLINK 2
#define LA_UID 4
#define LA_GID 8
#define LA_SIZE 16
#define LA_BLOCKS 32
#define LA_ATIME 64
#define LA_MTIME 128
#define LA_CTIME 256

#include "extracted.c"

int main(int argc, char **argv)
{
	const char *img = argv[1];
	__u32 ino = atoi(argv[2]);
	__u64 itable = atoll(argv[3]);
	__u32 ipg = atoi(argv[4]);
	struct super_block sb = { .s_blocksize_bits = 12 };
	struct lustre_ost_attrs loa;
	struct lu_attr la;
	struct ldiskfs_inode *raw;
	__u32 index, ipb, off;
	__u64 blk;
	struct stat st;
	char *map;
	int fd, rc;

	g_isize = atoi(argv[5]);
	g_huge = atoi(argv[6]);

	fd = open(img, O_RDONLY);
	if (fd < 0 || fstat(fd, &st))
		return perror("open"), 1;
	map = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (map == MAP_FAILED)
		return perror("mmap"), 1;

	/* the arithmetic osd_iit_iget_raw() does, with gbase for group 0 */
	index = ino - 1;			/* gbase == 1 for group 0 */
	ipb = 4096 / g_isize;
	blk = itable + index / ipb;
	off = (index % ipb) * g_isize;
	raw = (struct ldiskfs_inode *)(map + blk * 4096 + off);

	printf("block=%llu off=%u extra_isize=%u file_acl=%u links=%u\n",
	       (unsigned long long)blk, off, le16_to_cpu(raw->i_extra_isize),
	       le32_to_cpu(raw->i_file_acl_lo),
	       le16_to_cpu(raw->i_links_count));

	rc = osd_raw_lma(&sb, raw, &loa);
	printf("osd_raw_lma rc=%d\n", rc);
	if (rc == 0)
		printf("FID [0x%llx:0x%x:0x%x] compat=%#x incompat=%#x\n",
		       (unsigned long long)loa.loa_lma.lma_self_fid.f_seq,
		       loa.loa_lma.lma_self_fid.f_oid,
		       loa.loa_lma.lma_self_fid.f_ver,
		       loa.loa_lma.lma_compat, loa.loa_lma.lma_incompat);

	osd_raw_attr(&sb, raw, &la);
	printf("mode=0%o nlink=%u uid=%u gid=%u size=%llu blocks=%llu\n",
	       la.la_mode, la.la_nlink, la.la_uid, la.la_gid,
	       (unsigned long long)la.la_size,
	       (unsigned long long)la.la_blocks);
	printf("atime=%lld mtime=%lld ctime=%lld\n",
	       (long long)la.la_atime, (long long)la.la_mtime,
	       (long long)la.la_ctime);
	return 0;
}
