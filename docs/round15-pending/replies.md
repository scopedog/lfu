# Round 15 replies — drafts, posted after the push

One line per comment: `<change> <comment-id> | <reply>`.  Short by house rule
(see the Gerrit reply-brevity note); a decline says why, an accept says Done.

## 68094 — LU-20603

- `6c536114_fd65dacf` | Done. sp_padding is refused with -EINVAL beside the sp_flags check, documented must-be-zero in the header and in llapi_scan_namespace(3), and llapi_scan_test asserts the refusal.
- `8bd57add_8a6cdfa0` | Done. The case prints a note and skips itself rather than asserting, so a site whose TMP is on Lustre does not fail sanity 157c.
- `23db7a94_cd40b4c5` | Done. The comment now says "non-zero from ss_cb, or negative from ss_filter".
- `d372df8e_9ae5351d` | Declining. liblustreapi.map localises everything but llapi_*, cfs_* and a short list, so neither symbol is visible outside the library and there is no collision to prevent; renaming them would touch three later patches in the series for no reader's benefit.
- `80e63c0b_ea420fb4` | Done. Trailing slashes are trimmed when @path is copied, so the root record is named like any other; "/" keeps its slash.
- `2cf5202e_763a490c` | The wording changed rather than the default: the extra ioctl is per directory, not per object, and dropping LLAPI_SCAN_LMV would take sr_lmv from every consumer that does not name it. The header and the man page now say directories pay it.

## 68095 — LU-20605

- `e3438527_5b52c6bf` | Done. The comment now says the bits are the same and the convention for 0 is not, and what a caller passing it to sp_want has to do.
- `c3581abf_897e6747` | Done. The store and its comment are gone. They were already removed two patches later, in "split cb_find_init's decider out"; now no patch in the series carries them.

## 68156 — LU-20606

- `c3017715_28da9a5a` | Done, and thank you — it is the DNE remote-entry stand-in, not HSM. The enum comment and both places in llapi_scan_device.3 now say so, and the man page adds that a released file carries LMAC_HSM in lma_compat instead.
- `c289cb51_fa45c385` | Declining, for the reason you give about i_blocks: ext2fs_get_stat_i_blocks() is not the same sum, and keeping all three local keeps the file independent of which e2fsprogs the build finds.
- `1f9050ce_90319ba6` | Done in part. The skip arm now covers the errors that leave the scan advanced -- EXT2_ET_INODE_CSUM_INVALID and EXT2_ET_INODE_IS_GARBAGE as well, which were ending a worker's scan on one bad inode. EXT2_ET_NEXT_INODE_READ leaves nothing advanced, so retrying reads the same block forever; that one still ends the target's scan, and the man page now says so and lists -EIO.
- `11f5ac62_fad9af91` | Done. Both fields are removed.

## 68159 — LU-20611 (run find over a device scan)

- `0622b47e_fc0656bf` | Done. The V1/V3 arm bounds by the buffer, as llapi_layout_objects_in_lum() does, instead of by lmm_stripe_count.
- `e3632e13_2e5087ea` | Done. LOV_MAGIC_SEL is accepted as a composite and LOV_USER_MAGIC_SPECIFIC as a V3, and both are given the form a client would have been shown -- SEL as COMP_V1, SPECIFIC as V3 -- so the checks below read one shape.

## 68160 — LU-20611 (lfind)

- `88c740e3_df907405` | Done.
- `e64f6a47_c2693f06` | Done. The paragraph moves to the ZFS backend patch, which is what makes EBUSY reachable.
- `4a0a8d39_01c5cdb7` | Keeping lfind for now. The page is section 8, so `man 8 lfind` and lfind(3) are separable, and the name has been in review since the first round; happy to be overruled on it before it lands.

## 68163 — LU-20613

- `0a3d4f2a_a12b5cae` | Done.

## 68288 — LU-20637

- `51f1ddee_5cf2ed10` | Done, and -EINVAL was the whole story: a LAST_ID also classified as an OST object, because scan_classify() tested LMAC_FID_ON_OST before fid_is_last_id() and osd_object_create() sets that flag for it. Both are fixed -- the class first, and -EINVAL joins the no-name arm.
- `177699e4_52e78405` | Done. The separator is added rather than assumed, here and in llapi_scan_fid().

## 68413 — LU-20647

- `c69fe01b_489391e8` | Done. The comment now says the guard is for a record written before LU-19296.
- `970154ed_69b5d79a` | Done. 160y now asserts that an unregistered ID and an unregistered name are both refused.

## 68414 — LU-20648

- `123208c7_8d2cd4ef` | Done. Past tense.

## 68415 — LU-20649

- `ab9117f4_93aa7da9` | Done. The man page now says cr_prev is this FID's previous index.
- `bf87a92b_a672a1c1` | Done. It lives in lustreapi_internal.h with the other two.
- `0c4104fc_639f88b2` | Done. The shortcut tests a mask without LLAPI_SCAN_TYPE, since scan_cl_mode() answers it for four record types only.
- `5025f277_99133612` | Done. O_PATH first, and the real open only for the regular file whose size the resolve came for.
- `a55563fc_4c9183b0` | Done. co_pfid is taken only from an event that carries a sane one, so the bit and the value come from the same record.
- `c91e4c43_47c0cfd9` | Done. A failed copy leaves the bit clear for the job id and the rename source; sr_name is documented to allow NULL, so the name keeps that shape.
- `ee3d88ed_ff3f9806` | Done. A record whose cr_tfid is not sane is delivered per event instead of coalesced.
- `d6c18203_91815309` | Done. The batch test runs first; scan_cl_held_first() can only lower upto, so it cannot change the outcome.

## 68416 — LU-20650 (llapi_scan_fid)

- `6b484dfc_a428d328` | Done. The message says this patch adds the call and the search moves onto it in "lfs: find --changelog, the log as source".
- `e072cb82_0b055860` | Done. Two arguments, and the mount path is a literal.
- `222437c6_edacbf17` | Done. The comment names lfs find --changelog --resolve, which is the consumer that does it.
- `739e9e5b_7c633c8e` | Done. A plain mode_t, with the struct stat scoped to the non-statx branch.
- `caab8020_38b7ed70` | Done. LLAPI_SCAN_WANT_DEFAULT in lustreapi_internal.h, used by both.
- `dc1c19a4_762f0f58` | Done. Same fix as llapi_scan_rec_path()'s.
- `84ed5f95_8d3d4cf4` | Done. A positive filter value is a skip and the call returns 0.
- `64391b19_a0d511c2` | Done. The FID in the record is checked against the one asked for, and a mismatch is -ESTALE. The --since path already treats -ESTALE as "gone since the event".

## 68417 — LU-20650 (--since)

- `13f3f631_b2f6fc11` | Done. fp_since_kind joins find_device_supported()'s refusals.
- `cf6eb371_df61f708` | Done. The parameter arrives with its second caller, in the --changelog patch.

## 68418 — LU-20650 (--changelog)

- `e0ff17e0_2a90d138` | Done. -projid is tested before find_check_lmm_info(), so it names itself.
- `24e1b435_2c37c92c` | Done. --mdt-count, --hash-type and --hash-flag are refused, and a record with no type at all counts undecided rather than being compared against a mode of zero.
- `a281fec0_31dc6c20` | Done. The gather is widened for -printf the way cb_find_init() widens it.
- `6a18ffa2_84d49838` | Done. fc_fdp is a descriptor of our own, as on the --since path.
- `b6603d20_602a8409` | Done. llapi_find_since() ends with the same `rc = st.fss_path_rc` llapi_find_device() has.

## 68419 — LU-20650 (--since-cookie)

- `43232860_057ea123` | Done. More than one path is refused: the anchors describe the whole run, and reading once and writing once around the list would still report one subtree's matches against another's anchor.
- `67b53d67_9dd9b7d0` | Done.
- `4fcc9092_1b9df75b` | Done. The cookie is proved writable in the same pre-pass that proves the anchors are not stale.
- `5f2f8d98_c1975641` | Done. fsync() on the temp file before the rename, and on the directory after it.
- `15a120c9_ac4a7d0b` | Done. The message names the recorded index and says separately where the run would resume.

## 68420 — LU-20650 (tests)

- `727c1e0a_59bd3e79` | Done. The paragraph was a leftover; it now describes what 160ab asserts.
- `4d890972_ca97e6e6` | Done. A second Test-Parameters line runs the four cases with mdscount=2 mdtcount=4.
- `e83e6902_8139a3d5` | Done. --xattr is in the list, and so are --mdt-count, --hash-type and --hash-flag, which this round refuses as well.
- `50d80a1c_d0f51506` | Done. The three examples moved into EXAMPLES, in the .PP/.EX/.RS style the page uses.
- `fd32c13f_2babaa1d` | Done. 160ab runs --changelog against a named MDT.
