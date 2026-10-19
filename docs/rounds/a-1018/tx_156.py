# AI on 68156 PS37 d636e2aa: ext2fs_xattr_get() errors other than
#   EXT2_ET_EA_KEY_NOT_FOUND were read as "absent"; now they skip the object,
#   as the ZFS backend does.
# AI on 68159 PS37 2fee127e (#17, user chose (a)): SCAN_LMV_BUF covers
#   XATTR_SIZE_MAX, so any foreign LMV an MDT can store fits; the page says
#   an unconvertible trusted.lmv comes with LLAPI_SCAN_LMV clear.
LD = 'lustre/utils/libscan_ldiskfs.c'
SD = 'lustre/utils/liblustreapi_scan_device.c'
MAN = 'Documentation/man3/llapi_scan_device.3'
R = {
LD: [(
"""static void scan_ea_fetch(struct scan_ldiskfs_worker *wk,
			  struct ext2_xattr_handle *h, enum llapi_scan_xattr x,
			  struct llapi_scan_obj *obj)
{
	void *val = NULL;
	size_t len = 0;

	if (wk->sw_nbufs == SCAN_EA_BUFS)
		return;
	if (ext2fs_xattr_get(h, scan_xattr_name[x], &val, &len) != 0 ||
	    val == NULL)
		return;

	wk->sw_bufs[wk->sw_nbufs++] = val;
	obj->so_xattr[x].sv_buf = val;
	obj->so_xattr[x].sv_len = len;
	obj->so_xa_valid |= LLAPI_SCAN_XA_BIT(x);
}

static void scan_ea_fetch_set(struct scan_ldiskfs_worker *wk,
			      struct ext2_xattr_handle *h, __u32 want,
			      struct llapi_scan_obj *obj)
{
	int x;

	for (x = 0; x < LLAPI_SCAN_XA_MAX; x++) {
		if (want & LLAPI_SCAN_XA_BIT(x))
			scan_ea_fetch(wk, h, x, obj);
	}
}
""",
"""static int scan_ea_fetch(struct scan_ldiskfs_worker *wk,
			 struct ext2_xattr_handle *h, enum llapi_scan_xattr x,
			 struct llapi_scan_obj *obj)
{
	void *val = NULL;
	size_t len = 0;
	errcode_t err;

	if (wk->sw_nbufs == SCAN_EA_BUFS)
		return 0;
	err = ext2fs_xattr_get(h, scan_xattr_name[x], &val, &len);
	/* absent is normal; any other error leaves the object unread */
	if (err == EXT2_ET_EA_KEY_NOT_FOUND)
		return 0;
	if (err != 0)
		return -1;
	if (val == NULL)
		return 0;

	wk->sw_bufs[wk->sw_nbufs++] = val;
	obj->so_xattr[x].sv_buf = val;
	obj->so_xattr[x].sv_len = len;
	obj->so_xa_valid |= LLAPI_SCAN_XA_BIT(x);

	return 0;
}

static int scan_ea_fetch_set(struct scan_ldiskfs_worker *wk,
			     struct ext2_xattr_handle *h, __u32 want,
			     struct llapi_scan_obj *obj)
{
	int x;

	for (x = 0; x < LLAPI_SCAN_XA_MAX; x++) {
		if ((want & LLAPI_SCAN_XA_BIT(x)) &&
		    scan_ea_fetch(wk, h, x, obj) < 0)
			return -1;
	}

	return 0;
}
"""), (
"""	struct ext2_xattr_handle *h = NULL;

	if (ext2fs_xattrs_open(wk->sw_fs, ino, &h) != 0)
		return -1;
""",
"""	struct ext2_xattr_handle *h = NULL;
	int rc;

	if (ext2fs_xattrs_open(wk->sw_fs, ino, &h) != 0)
		return -1;
"""), (
"""	scan_ea_fetch_set(wk, h, want, obj);
	ext2fs_xattrs_close(&h);

	return 0;
}
""",
"""	rc = scan_ea_fetch_set(wk, h, want, obj);
	ext2fs_xattrs_close(&h);

	return rc;
}
""")],
SD: [(
""" * entries than the buffer holds.  The shard FIDs are not filled.  A foreign
 * LMV larger than this is left out of the record rather than truncated.
 */
#define SCAN_LMV_BUF	(sizeof(struct lmv_user_md) +		\\
			 LMV_MAX_STRIPE_COUNT *			\\
			 sizeof(struct lmv_user_mds_data))
""",
""" * entries than the buffer holds.  The shard FIDs are not filled.  It is
 * XATTR_SIZE_MAX, so any foreign LMV an MDT can store fits whole.
 */
#define SCAN_LMV_BUF	XATTR_SIZE_MAX
static_assert(sizeof(struct lmv_user_md) +
	      LMV_MAX_STRIPE_COUNT * sizeof(struct lmv_user_mds_data) <=
	      SCAN_LMV_BUF, "SCAN_LMV_BUF holds every stripe");
"""), (
"""	 * included.  The buffer holds LMV_MAX_STRIPE_COUNT entries, so the
	 * whole shard area the count claims is cleared.
""",
"""	 * included.  The buffer holds at least LMV_MAX_STRIPE_COUNT entries, so
	 * the whole shard area the count claims is cleared.
""")],
MAN: [(
""".B LMV_MAGIC_STRIPE
has no user form and is reported as no stripe at all.
""",
""".B LMV_MAGIC_STRIPE
has no user form and is reported as no stripe at all. So is a
.B trusted.lmv
that does not convert, which only a damaged target holds: an unknown magic,
a short value, or more than
.B LMV_MAX_STRIPE_COUNT
stripes. Both come with
.B LLAPI_SCAN_LMV
clear.
""")],
}
MISSES = []
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
S156 = "LU-20606 llapi: scan an ldiskfs target directly"
M156 = ("""  union of the two structures, so it has the right alignment.
""", """  union of the two structures, so it has the right alignment. It is
  XATTR_SIZE_MAX bytes, so a foreign LMV of any size an MDT can store
  is delivered whole.
- An xattr that cannot be read, for any reason but its absence, skips
  the object as LLAPI_SCAN_SKIP_XATTR. Taken as absent, a missing
  trusted.link or trusted.lma would misclassify the object, and a
  missing trusted.lov would give a striped file its own size.
""")
def msgfn(msg, subj):
    if subj == S156:
        assert M156[0] in msg, '156 msg anchor'
        msg = msg.replace(*M156)
    return msg
