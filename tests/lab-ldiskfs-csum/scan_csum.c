/* Scan an ext4 image the way libscan_ldiskfs's worker does.  argv[2]=1 is the
 * fix: checksums verified on the worker's handle, garbage reported. */
#include <stdio.h>
#include <stdlib.h>
#include <ext2fs/ext2fs.h>
int main(int argc, char **argv)
{
	int fix = atoi(argv[2]);
	ext2_filsys fs; ext2_inode_scan scan; ext2_ino_t ino;
	int flags = EXT2_FLAG_SKIP_MMP | EXT2_FLAG_SOFTSUPP_FEATURES |
		    EXT2_FLAG_64BITS | EXT2_FLAG_IGNORE_CSUM_ERRORS;
	unsigned long ok = 0, csum = 0, garbage = 0, other = 0;
	errcode_t err = ext2fs_open(argv[1], flags, 0, 0, unix_io_manager, &fs);
	if (err) { com_err("open", err, "%s", argv[1]); return 1; }
	if (fix)
		fs->flags &= ~EXT2_FLAG_IGNORE_CSUM_ERRORS;
	int sz = EXT2_INODE_SIZE(fs->super);
	struct ext2_inode *buf = calloc(1, sz);
	ext2fs_open_inode_scan(fs, 0, &scan);
	ext2fs_inode_scan_flags(scan, EXT2_SF_SKIP_MISSING_ITABLE |
				(fix ? EXT2_SF_WARN_GARBAGE_INODES : 0), 0);
	for (;;) {
		err = ext2fs_get_next_inode_full(scan, &ino, buf, sz);
		if (err == 0 && ino == 0) break;
		if (err == 0) ok++;
		else if (err == EXT2_ET_INODE_CSUM_INVALID) { csum++; printf("  csum invalid: ino %u\n", ino); }
		else if (err == EXT2_ET_INODE_IS_GARBAGE) { garbage++; printf("  garbage: ino %u\n", ino); }
		else { other++; com_err("next", err, "ino %u", ino); if (other > 5) break; }
	}
	printf("fix=%d ok=%lu csum_invalid=%lu garbage=%lu other=%lu\n", fix, ok, csum, garbage, other);
	return 0;
}
