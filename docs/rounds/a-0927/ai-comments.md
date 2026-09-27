### 68156 PS28 b76d9fd4_2e3386c3 Documentation/man3/llapi_scan_device.3:449
(minor) If the patch is refreshed: scan_errcode() deliberately passes a missing device through as -ENOENT ("so a missing device says ENOENT rather than arriving as an I/O error"), and test6 exercises that case. ERRORS doesn't list -ENOENT, though, so a caller reading this page would expect -EINVAL or -EIO for a mistyped device path.

### 68156 PS28 bb99a795_99fcf358 Documentation/man3/llapi_scan_namespace.3:396
(minor) This says ss_skipped counts the objects dropped because a fetch failed for a reason *other than* the object having gone. llapi_scan_cb_init() also bumps ss_skipped on the -ENOENT/-ESTALE path, where the object was unlinked between readdir and the fetch.

So on a busy tree a nonzero ss_skipped doesn't mean anything was lost to an error. Should the page say ss_skipped includes vanished objects, or should the two cases be counted separately?

### 68156 PS28 7c1ae981_e7b19946 include/lustre/lustreapi.h:811
(minor) This follows up on the PS16 discussion about making the stats extensible. With ss_class[LLAPI_SCAN_CLS_MAX] as the last member, the struct can only grow in one direction.

Say a later release appends a scalar counter after ss_class (for example the total size/blocks mentioned in that thread). Its offset is then 64 + 8 * LLAPI_SCAN_CLS_MAX. If a later release also adds a class, that counter moves, so a caller built between the two releases reads a class count where it expects its counter. ss_size stops the library from writing past the caller's buffer, but it can't fix a field whose offset changed.

scan_stats_whole() and the `static_assert(SCAN_SF_END(ss_class) == sizeof(...))` also assume ss_class is the last member.

The commit message says the struct "can grow later", but today it can only grow by adding classes. Would a fixed-size array (e.g. `ss_class[16]`, independent of LLAPI_SCAN_CLS_MAX) avoid this? Moving ss_class behind a stored count or offset would work too. Either needs deciding before the layout becomes ABI.

### 68157 PS28 0a97f348_a6ecf4f4 lustre/utils/liblustreapi_pfind.c:1788
(suggestion) This changes what -printf prints for a directory off Lustre (%Lc, %Lh, %Li, %Lo now print nothing instead of 0, none, 0, [0]), but nothing seems to test it. sanity test_56El already builds a tmpfs subtree, but it sends the -printf output to /dev/null and only checks stderr. Could it also check that something like

    $LFS find $tmp -maxdepth 0 -printf '%Lc%Lh%Li%Lo'

prints an empty string, so this does not quietly go back to printing the stub?

### 68159 PS25 a3e82a81_b59aa3a7 lustre/utils/liblustreapi_pfind.c:3588
(defect) Can a UUID ever match here for a target whose label is not in the mounted `fsname-OST0001` form?

libscan_ldiskfs.c parses four separators and sets LLAPI_SCAN_TGT_INDEX for all of them: `fsname:OST0001` (never mounted), `fsname=OST0001` (after writeconf) and `fsname+OST0001` (--nolocallogs). llapi_uuid_match() drops `_UUID` and then does strncmp(), so

    llapi_uuid_match("lustre=OST0001", "lustre-OST0001_UUID") == 0

find_tgt_index() returns OBD_NOT_FOUND, find_device_targets() takes the result as "some other target" and returns 1, and llapi_find_device() returns 0 without scanning. So `--ost lustre-OST0001_UUID` run against OST0001 itself prints nothing and gives no warning, and `! --ost lustre-OST0001_UUID` prints every object. The same happens for --mdt. A device scan is exactly where an unmounted, writeconf'd target is likely to turn up.

Would it work to compare with the separator at tt_label[len - 8] normalised to '-', or to compare fsname, target type and tt_index directly? llapi_find_device.3 ("an index and the target's UUID both work without a mount") could then stay as written.

### 68159 PS25 d314fd23_6cfe7994 lustre/utils/liblustreapi_pfind.c:4299
(minor) If the probe fails here (a missing device, or ENOPKG), scan_device_target() has already printed the error through scan_open_error(). llapi_scan_device() then opens the same target, fails the same way and prints it a second time. For example, `--pool` against a mistyped device prints "cannot open" twice. If the patch is refreshed, returning the probe's rc here (the scan cannot succeed where the probe failed) would avoid the duplicate.

### 68160 PS26 56404866_88aa5b87 Documentation/man1/lfs-find.1:861
(minor) If the patch is refreshed: taken with the NOTES entry that says --ost applies to an OST and --mdt to an MDT, this reads as if `lfs find --local --ost NAME` would fail on every MDT of the node and exit non-zero. lfs_find_device() actually skips the other type in a --local or --fsname sweep. It also refuses --ost and --mdt together there, because no target would be left. The commit message describes both behaviours, but the page does not. Could a sentence here say so?

### 68160 PS26 6a512e82_e67c3061 lustre/utils/lfs.c:6369
(defect) lfs_find_is_device() now runs on every walk, so every path argument gets a stat() before llapi_find() starts. On Lustre that is not free for a regular file. stat() asks for STATX_BASIC_STATS, so ll_getattr_dentry() sets need_glimpse and sends glimpse RPCs to the file's OSTs, unless the MDT's size, blocks and mtime are all strict.

Before this patch, a walk with only MDT predicates (--uid, --name, --type, ...) or with --lazy did not contact any OST for its start paths. For example:

    lfs find --lazy file1 ... fileN --size +1G

This now costs a glimpse per argument. If an OST that holds one of the files is unreachable, it can block, where it used to answer from the MDT.

Only the file type is needed here. Would a probe that asks for just that avoid the glimpse? liblustreapi_pfind.c already does this under HAVE_STATX:

    statx(AT_FDCWD, argv[i], AT_STATX_DONT_SYNC, STATX_TYPE, &stx)

Then test S_ISBLK(stx.stx_mode). With neither STATX_SIZE, STATX_BLOCKS nor STATX_MTIME in the mask, need_glimpse is false in ll_getattr_dentry().

### 68163 PS25 4c284b09_a283a503 /COMMIT_MSG:133
(typo) SCAN_CHUNKS_MAX is DN_MAX_OBJECT / SCAN_CHUNK_OBJS, the number of chunks covering the object-id space, not DN_MAX_OBJECT itself. Maybe "SCAN_CHUNKS_MAX is derived from DN_MAX_OBJECT ...".

### 68163 PS25 b74d36b4_c03b5f99 Documentation/man1/lfs-find.1:1034
(minor) The EXAMPLES section still shows only the ldiskfs form of --device. A ZFS target is named differently: pool/dataset instead of a path, --search for file vdevs, and the pool must be exported first. If the page is refreshed, an example such as `lfs find --device lustre-mdt1/mdt1 --search /tmp --type f` (after `zpool export lustre-mdt1`) would show this new usage.

### 68163 PS25 a084a589_75405c9b lustre/utils/lfs_find_parse.c:1762
(suggestion) This isn't a bug, but --search now shares this branch, and the comment's reason ("one target per invocation") doesn't apply to it. A second --search is a second list of directories, not a second target. Users coming from `zpool import -d DIR1 -d DIR2` may expect repeats to add up rather than give "--search given twice". If the patch is refreshed, either join repeated values with ':' or word the comment and error to cover --search as well.

### 68163 PS25 dc43e70c_d66833f7 lustre/utils/libscan_zfs.c:819
(minor) Is this the same block count a client gets from the MDT or OST for this object? osd_attr_get() fills la_blocks from sa_object_size(), which ends in dmu_object_size_from_db():

    *nblk512 = ((DN_USED_BYTES(dn->dn_phys) + SPA_MINBLOCKSIZE/2) >> SPA_MINBLOCKSHIFT) + dn->dn_num_slots;

But doi_physical_blocks_512 is only (DN_USED_BYTES + 256) >> 9. So every object the scan reports with LLAPI_SCAN_BLOCKS comes out dn_num_slots lower: 1 for a 512-byte dnode, 2 for the 1K dnodes dnodesize=auto usually gives an MDT object. That covers directories, DoM files and OST objects. llapi_scan_device(3) calls those values authoritative and "as a client sees it", and an `lfs find --device ... --blocks` result would then differ from the same search over the mount. The ldiskfs backend reports i_blocks, which is what osd-ldiskfs returns, so only this backend differs.

The directory size just above already copies osd_attr_get(). If the patch is refreshed, would calling sa_object_size(hdl, &blksz, &nblk) on the handle already open here keep blocks in step with it too?

### 68288 PS19 41cdec96_964ad85b lustre/utils/liblustreapi_pfind.c:3529
(defect) With --internal, can this print a pathname for an object that no longer has one?

An open-unlinked file keeps its trusted.link. mdd_finish_unlink() only calls mdd_links_del() in the nlink != 0 branch; the nlink == 0 && mod_count branch goes to mdd_orphan_insert() and mdd_mark_orphan_object(). The linkea therefore still names the old parent and name. scan_classify() returns LLAPI_SCAN_CLS_ORPHAN for it, and LLAPI_SCAN_F_INTERNAL delivers it.

The map branch composes a name for any record that has lfsr_name and LLAPI_SCAN_PARENT, whatever its class. The old parent directory is still in the map, so

    lfs find --device $MDT --internal --paths

prints /dir/oldname for the PENDING orphan. That path no longer exists, or it now names a different, live file with the same name.

The lookup arm below is gated by find_rec_may_have_name(), whose comment says an orphan in PENDING has no name, but the map arm is not. Should the same class test apply before scan_dirmap_path() is called? Orphans left in PENDING after an unclean stop are exactly what an offline scan of a stopped MDT will find.

### 68288 PS19 df006952_f77ee05b lustre/utils/liblustreapi_pfind.c:4401
(minor) Only one linkea entry is composed: the one --name matched, or entry 0. If scan_dirmap_path() gives -ENOENT for that entry, the object is counted nameless, and its other entries are never tried.

With DNE this happens to an object that still has a local name. For example, a file in d0 on MDT0 gets a remote hardlink d1/g on MDT1, and the original name is then renamed. mdd_links_rename() deletes the old entry and linkea_add_buf() appends the new one, so entry 0 becomes d1/g. A scan of MDT0 then reports the file as having no pathname, though /d0/<newname> can be composed from the map.

The commit message says the nameless case is "an object whose parents are on another MDT" (plural). Should the fallback try the remaining entries before counting the object as unresolved?

### 68288 PS19 3d052c3f_e327a75c lustre/utils/liblustreapi_scan.c:717
(minor) This isn't accurate as written. The root [0x200000007:0x1:0x0] and .lustre (FID_SEQ_DOT_LUSTRE) are both below FID_SEQ_NORMAL and have pathnames, and so does every IGIF object on an upgraded filesystem. A PENDING orphan has a normal FID and no pathname. What the function actually goes by is the record's class plus the server's -ENOENT/-EINVAL. If the patch is refreshed, describing it that way would avoid misleading callers.

### 68415 PS17 0e770de9_ae4f9e17 include/lustre/lustreapi.h:859
(minor) What unit is lfsr_event_time in? Neither this header nor llapi_scan_changelog.3 says. scan_cl_absorb() stores `cr_time >> 30`, which is whole seconds, and drops the nanoseconds the low 30 bits of cr_time carry.

Every other time in this record is a struct statx_timestamp with tv_sec/tv_nsec. A consumer comparing this to stx_mtime has to guess seconds, and can't order two events within the same second by time. If the patch is refreshed, could this either say "seconds since the epoch" or carry the nanoseconds too? This is appended ABI, so it can't change after landing.

### 68415 PS17 9b2b5fa0_23ec8852 lustre/utils/liblustreapi_scan_changelog.c:53
(typo) "Held past this many times it, it is delivered" is hard to parse. Maybe "Held past this many times sc_min_age, it is delivered ...".

### 68415 PS17 a18d496d_23e2f959 lustre/utils/liblustreapi_scan_changelog.c:1169
(minor) Why does LLAPI_SCAN_CL_F_RESOLVE ask for the uidgid extension? The comment above and the commit message only explain the sc_want == 0 and LLAPI_SCAN_EVENT_UID cases. scan_cl_resolve() fills the owner from statx(), not from the event, and its own comment says the event uid is a different fact.

As written, a caller with _RESOLVE and sc_want = LLAPI_SCAN_SIZE gets LLAPI_SCAN_EVENT_UID set in lfsr_valid even though it never asked for it. It's harmless, but it looks left over from an earlier revision. If it is deliberate, a word in the comment would help.

### 68416 PS17 57365e9b_ebafc0b4 Documentation/man3/llapi_find_device.3:75
(minor) "cleared" could be read as *lfsp_got being set to 0. The code clears the local copy's pointer, so the caller's variable is never written and keeps whatever it held before the call, possibly uninitialized. If the patch is refreshed, "is not written" or "is left untouched" would say that.

### 68416 PS17 12eb5b6a_ae14b861 lustre/utils/liblustreapi_scan.c:749
(minor) Is the -EXDEV guarantee unconditional? mdt_fid2path() only refuses a foreign root when the export has exp_root_fid set:

    if (root_fid && !fid_is_zero(&info->mti_exp->exp_root_fid) && ...)
        RETURN(-EXDEV);

exp_root_fid is set only in mdt_get_root(), and lmv_get_root() sends that only to MDT0. On DNE, a FID served by another MDT with a non-root @mnt_fd gets mdt_path_current() instead: a path relative to that directory if the object is below it, or -ENOENT if it is not. That -ENOENT is the errno this kernel-doc tells a changelog consumer to read as "gone, not an error".

If the patch is refreshed, maybe say the MDT usually refuses it, and that on DNE a wrong root can also come back as -ENOENT or a mislabelled lfsr_path. The same sentence is in the commit message, and llapi_scan_fid.3 lists -EXDEV under ERRORS.

