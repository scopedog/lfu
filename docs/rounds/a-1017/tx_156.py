# AI on 68156 PS36 485b1c07: the bitmap is read for the first worker, not
# at open; the errors that leave *ino unset are handled below, not above.
R = {
'lustre/utils/libscan_ldiskfs.c': [(
"""			 * the bitmap has it.  The bitmap is in another
			 * block, read at open, so it is still good here.
			 * ext2fs_get_next_inode_full() assigns *ino before
			 * it returns any of these three, so all can be
			 * asked here -- unlike the errors above, which
			 * leave it untouched.
""",
"""			 * the bitmap has it.  The bitmap is in another
			 * block, read for the first worker, so it is still
			 * good here.  ext2fs_get_next_inode_full() assigns
			 * *ino before it returns any of these three, so all
			 * can be asked here -- unlike the read failure
			 * handled below, which leaves it untouched.
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
