# AI review round 2026-10-18: triage (read-only)

Source: anonymous REST `/changes/<n>/comments`. Kept: author "Gerrit AI
review for Lustre", on the listed PS, unresolved, dated 2026-10-18. 21
comments, which matches the expected counts (1+2+1+3+2+1+3+5+3).
Verified against ~/lfs-fork-1014 at each change's current_revision (all
present locally; branch igif-1017, clean). Nothing was posted and no tree
was modified.

| change | PS | sha | subject |
|---|---|---|---|
| 68156 | 37 | 9a5ba1d20d | scan an ldiskfs target directly |
| 68415 | 30 | ab5b91126f | add llapi_scan_changelog() |
| 68416 | 30 | bacb6c3c8c | fill a scan record for one FID |
| 68158 | 35 | eba27ca5dc | share find's predicate parsing |
| 68159 | 37 | 9eb0237d62 | run find over a device scan |
| 68160 | 38 | fcbf2ccd31 | find over a target, with --device |
| 68163 | 37 | 2ee402aae0 | ZFS backend |
| 68288 | 31 | 9cfddeaaf3 | name a device scan's objects |
| 68419 | 23 | c7440bf581 | find --since-cookie |

Other stack commits named below: 68157 2b24c83ecc, 68417 286c9a20fa,
68418 6a65c5f87e, 69443 3a7bd23244, 69500 f9034db8d7 (tip of the
--since branch), 69501 c04f587561, 69502 ef203223ca, 69700 b0d98641fe,
69729 a9e9c7faf2.

Note on /COMMIT_MSG line numbers: Gerrit's are `git log %B` line + 6.

## Verdict summary

| # | change | id | file:line | verdict |
|---|---|---|---|---|
| 1 | 68156 | d636e2aa_7810f44a | libscan_ldiskfs.c:494 | REAL DEFECT (narrow: ENOMEM only) |
| 2 | 68415 | f5001c3d_79a7a1f1 | man3/llapi_scan_changelog.3:57 | VALID (doc inaccuracy) |
| 3 | 68415 | 568c239a_2aa4b6f5 | sanity.sh:10881 | DUPLICATE (decided a-0926: idiom stays) |
| 4 | 68416 | 4d6e64ad_c1f1dd87 | /COMMIT_MSG:99 | VALID NIT |
| 5 | 68416 | 4df24fc4_84c74c03 | liblustreapi_scan.c:853 | WRONG (premise false; would undo a lab-proven fix) |
| 6 | 68416 | 1360e218_543e97db | liblustreapi_scan.c:1013 | VALID (undocumented -EACCES) |
| 7 | 68158 | 80b7eeb7_6af36526 | lfs_find_parse.h:142 | VALID NIT, low value (decline) |
| 8 | 68160 | 768567ff_f7b15737 | conf-sanity.sh:13756 | VALID NIT |
| 9 | 68160 | 20098768_5da9a980 | conf-sanity.sh:13812 | VALID (test guard missing) |
| 10 | 68163 | f8d7ad60_6508299b | libscan_zfs.c:325 | VALID NIT (stale comment) |
| 11 | 68288 | 8ac62df6_b32ea242 | PATCHSET_LEVEL (llapi_scan_namespace.3:71) | VALID NIT |
| 12 | 68288 | 9c17e029_accf7832 | man3/llapi_scan_rec_path.3:66 | VALID (doc) |
| 13 | 68288 | cf29a8b3_d89f9234 | lustreapi_internal.h:723 | VALID SUGGESTION (optional refactor) |
| 14 | 68159 | 85bb9fc5_096d9840 | /COMMIT_MSG:136 | VALID NIT |
| 15 | 68159 | 64f8e0e0_b6a46bba | liblustreapi_pfind.c:3139 | REAL DEFECT, UPSTREAM (since 2.14.53) |
| 16 | 68159 | d55e3e04_b65d5ec4 | liblustreapi_pfind.c:3693 | VALID SUGGESTION (lreview raised it 10-13, held) |
| 17 | 68159 | 2fee127e_b9be2f21 | liblustreapi_pfind.c:3890 | VALID (minor, edge cases) |
| 18 | 68159 | 13021777_d0514133 | liblustreapi_pfind.c:4365 | VALID NIT |
| 19 | 68419 | 963dc2c7_f94f2e0d | man1/lfs-find.1:758 | VALID SUGGESTION; same kind as the 68418 "move hunks" thread the user said to ignore |
| 20 | 68419 | 6b5da815_881fe259 | sanity.sh:23478 | VALID NIT |
| 21 | 68419 | 397172d9_5d095b24 | liblustreapi_pfind.c:5431 | REAL DEFECT (silent loss) |

Real defects: #1, #15 (upstream), #21. Documentation and test fixes: #2,
#6, #9, #12. Nits: the rest. Decline: #3 (duplicate), #5 (wrong), #7.

---

## 1. 68156 PS37 `d636e2aa_7810f44a` lustre/utils/libscan_ldiskfs.c:494

AI: "Every non-zero return from ext2fs_xattr_get() is treated as 'not
there' ... could this treat only EXT2_ET_EA_KEY_NOT_FOUND as absent, and
return any other error so the caller takes the LLAPI_SCAN_SKIP_XATTR path?"

**Verdict: REAL DEFECT, narrow.** `scan_ea_fetch()` returns void and
drops any error:

    if (ext2fs_xattr_get(h, scan_xattr_name[x], &val, &len) != 0 ||
        val == NULL)
            return;

In e2fsprogs, ext2fs_xattr_get() returns EXT2_ET_EA_KEY_NOT_FOUND for a
missing key, and otherwise only an error from ext2fs_get_mem() (the value
copy), the handle magic check, or the POSIX ACL conversion (not one of
our names). So in practice the only bad case is ENOMEM. That breaks the
rule in the comment above `scan_read_xattrs()` (an object whose Lustre
state cannot be read is skipped and counted). The AI's two results are
right: no trusted.link means `scan_classify()` returns CLS_INTERNAL for a
user file on an MDT (`mdt && !have_link`). No trusted.lov means
`scan_size()` takes the inode size. Its list leaves out a third: no
trusted.lma gives CLS_NO_LMA. The ZFS backend already gets this right
(`libscan_zfs.c:626`: ENOENT means absent, any other error returns -1).
So ldiskfs is the odd one out.

Fix: make `scan_ea_fetch()` return int. Return 0 for a value read or for
EXT2_ET_EA_KEY_NOT_FOUND, and -1 otherwise. `scan_ea_fetch_set()` stops
at the first -1. `scan_read_xattrs()` closes the handle and returns -1,
and the caller at :671 already takes the SKIP_XATTR path. The
`sw_nbufs == SCAN_EA_BUFS` early return cannot be reached
(SCAN_EA_BUFS == LLAPI_SCAN_XA_MAX, one buffer per xattr). Leave it. The
lines are the same in every later commit (9cfddeaaf3/a9e9c7faf2/
f9034db8d7 shift them by one line), so the fix goes only in 68156 and
the rebase carries it.

## 2. 68415 PS30 `f5001c3d_79a7a1f1` Documentation/man3/llapi_scan_changelog.3:57

AI: "Size, blocks, mode, nlink, owner and the object times are lfsr_stx
fields, so their answer is in lfsr_stx.stx_mask, not lfsr_valid ... could
it say which mask reports which half?"

**Verdict: VALID (doc).** Lines 52-57 say the fields arrive "with their
*lfsr_valid* bit clear". `liblustreapi_scan_changelog.c:229-230` splits
co_valid between `lfsr_valid` (high half) and `lfsr_stx.stx_mask`
(low/STATX half). llapi_scan_namespace.3:129-137 and :230-237 say which
mask reports which field. A reader of this page alone would test
lfsr_valid for size, which is always 0, even after RESOLVE fills the size
in stx_mask. The line-164 sentence "LLAPI_SCAN_TYPE is set" is less wrong,
because the namespace page says the low LLAPI_SCAN_* constants are the
STATX_* values. Even so it should say "in lfsr_stx.stx_mask".

Fix: in the page, write "with their bit clear: in lfsr_stx.stx_mask for
the first six, in lfsr_valid for the rest, as in llapi_scan_namespace(3)",
and at :164 write "LLAPI_SCAN_TYPE (STATX_TYPE) is set in
lfsr_stx.stx_mask". Make the same change in the commit message ("their
lfsr_valid bits are clear") and in the file header comment at
`liblustreapi_scan_changelog.c:19`. The page text is unchanged through
69500. Check whether 68288 (9cfddeaaf3, 4 lines of llapi_scan_changelog.3)
touches these lines before rebasing.

## 3. 68415 PS30 `568c239a_2aa4b6f5` lustre/tests/sanity.sh:10881

AI: "the precondition reads better in the positive `check || skip` form
..., e.g. `! remote_mds_nodsh || skip`".

**Verdict: DUPLICATE, decline.** The same point was in lreview a-1005
(`lreview2/68415.md:32`). The decision is in a-0926/notes.md:263:
"`remote_mds_nodsh && skip` is the tree's own idiom and stays." Count at
ab5b91126f: 108 uses of `remote_mds_nodsh && skip` in sanity.sh and 0 of
`! remote_mds_nodsh ||`. Reply, if any: "The tree uses this form for
remote_mds_nodsh (108 times, never the negated one), so it stays."

## 4. 68416 PS30 `4d6e64ad_c1f1dd87` /COMMIT_MSG:99

AI: "the patch also changes test6: the `big` union initialiser becomes a
memset() ... nothing in the message mentions it."

**Verdict: VALID NIT.** The diff in llapi_scan_test.c test6 replaces
`} big = { .sp = { .lfsp_size = sizeof(big) } };` with memset + assignment.
The message paragraph at %B:93-99 covers test17 only. For an automatic
union, C sets only the named member, so the bytes of `buf` past `sp` are
not required to be zero, and scan_param_copyin() refuses non-zero tail
bytes. So this is a real test fix with no mention in the message.

Fix: add one sentence after the llapi_scan_test paragraph: "test6 now
zeroes its oversized parameter block with memset(): an initialiser need
not zero the bytes past .sp, which scan_param_copyin() refuses." This is
in the message only, so no later commit is touched.

## 5. 68416 PS30 `4df24fc4_84c74c03` lustre/utils/liblustreapi_scan.c:853

AI: "This shortcut applies only when the earlier attempt failed with
-ESTALE ... Since a rename always produces a different name, could the
same-name check cover every errno in `gone`?"

**Verdict: WRONG, decline.** The premise is false. A rename does not
always produce a different name *by the time fid2path is asked again*: a
directory renamed A->B->A between the statx and the next fid2path gives
the same name, and the retry then succeeds. This is the case the retry
was built for and proved on in the lab. BOARD 10-13 "68416 rename race
FIXED": tests/lab-1013/06, "directory flip-flopping, old 2427 x -ENOENT,
new 0". That fix deliberately kept "-ESTALE at the same name stands" and
nothing more. If the same-name shortcut also applied to -ENOENT and
-ENOTDIR, a flip-flop would answer -ENOENT for a live object again.

The cost the AI cites (4 fid2path + 4 statx before -ENOENT) is bounded by
SCAN_FID_RETRIES = 3. Its persistent example, the DNE relative answer, is
the misuse the kernel-doc (:749-751) and llapi_scan_fid.3 -EXDEV describe
(mnt_fd not the mount root). An unlinked FID ends at fid2path -ENOENT on
the first retry (line 850-851), not after four rounds. Reply: "Declined: a
directory renamed away and back gives the same name with the object
reachable again; that is the flip-flop case the retry was made for
(tests/lab-1013/06). The cost is bounded at SCAN_FID_RETRIES."

## 6. 68416 PS30 `1360e218_543e97db` lustre/utils/liblustreapi_scan.c:1013

AI: "On a client mounted with -o user_fid2path ... this O_RDONLY openat()
of the parent fails with EACCES. The whole call then returns -EACCES ...
Should llapi_scan_fid.3 list -EACCES in ERRORS ...? Another option is to
fall back to the name-only record here."

**Verdict: VALID (doc gap).** Confirmed: `mdt_path_current()`
(lustre/mdt/mdt_handler.c:7739) makes no permission check. The statx at
:896 needs only search permission. The parent open at :1004/:1008 (and
the directory open at :984) is O_RDONLY|O_DIRECTORY, which needs read
permission, so a 1733 or a foreign-owned 0711 parent gives -EACCES. That
is not in the retry set (:1063), so it is returned. The code comment at
:960-962 already knows this ("a FID under a 0711 directory the caller does
not own answers -EACCES") but only uses it to argue for the name-only
mode. llapi_scan_fid.3 RETURN VALUES and ERRORS list no -EACCES.

Fix: document it. Do not add a fallback: a name-only record when the
caller asked for MDT_MASK fields would drop fields with no signal, and
lfsp_got is per-call, not per-record. Add to ERRORS: "-EACCES the gather
could not open the object (a directory) or its parent for reading. Only
without CAP_DAC_READ_SEARCH, on a mount with -o user_fid2path: the name
lookup itself checks no permission. A demand mask with no field in
LLAPI_SCAN_MDT_MASK opens nothing and is not affected." Later commits
that touch llapi_scan_fid.3 and liblustreapi_scan.c, so expect a rebase
conflict: 68157 2b24c83ecc (code), 68288 9cfddeaaf3 (man +28 lines),
69501 c04f587561 (filter block), 69700 b0d98641fe.

## 7. 68158 PS35 `80b7eeb7_6af36526` lustre/utils/lfs_find_parse.h:142

AI: "generic names such as arg_is_eof(), check_hashtype(), name2uid() and
str2quotaid() are global symbols in every program that compiles this file
... a shared prefix ... No need to re-spin just for this."

**Verdict: VALID NIT, low value. Decline or leave unanswered.** Only lfs
builds lfs_find_parse.c (`lustre/utils/Makefile.am:86/87` at every
commit up to the tips a9e9c7faf2 and f9034db8d7). The "second front end"
the commit message names is `lfs find --device`, which is also in lfs.
The names were in lfs.c before the move, so lfs's symbol space is the
same as before. A rename would touch lfs.c call sites across 68158 and
every later commit that uses them, which is churn for no current
collision. Reply if wanted: "Only lfs links this file, and these were
lfs.c's names already; left as they are."

## 8. 68160 PS38 `768567ff_f7b15737` lustre/tests/conf-sanity.sh:13756

AI: "`svc` gets the same `$(facet_svc mds1)` value that `mdt1svc` already
holds further up in this test."

**Verdict: VALID NIT.** test_300a (starts :13587) sets
`local mdt1svc=$(facet_svc mds1)` at :13632, and `local svc=$(facet_svc
mds1)` at :13756 is the same value. Fix: remove `svc` and use `$mdt1svc`
in the three lines :13758-13763. This is in 68160 only. Check that 68288's
conf-sanity.sh changes (+428 lines) do not edit these lines.

## 9. 68160 PS38 `20098768_5da9a980` lustre/tests/conf-sanity.sh:13812

AI: "test_300c runs `do_facet ost1 "$LFS find --local --ost ..."` but only
checks the mds1 side ... Would it be worth adding `remote_ost_nodsh &&
skip` ... and the matching `OST1_VERSION` check?"

**Verdict: VALID.** test_300c (:13808) checks `remote_mds_nodsh` and
MDS1_VERSION only. It then runs `do_facet ost1 "$LFS find --local --ost
$ostsvc ..."`, which needs dsh to ost1 and an lfs on ost1 that has
--local. test_300b next to it (:13786-13789) has both OST guards. Fix: add
`remote_ost_nodsh && skip "remote OST with nodsh"` (the tree's form, see
#3) and `(( OST1_VERSION >= $(version_code 2.17.58) )) || skip ...`.
300c was split in a-1017 (tx_300c_split.py), so check the current 300c
body on 68288 too, which adds to conf-sanity.

## 10. 68163 PS37 `f8d7ad60_6508299b` lustre/utils/libscan_zfs.c:325

AI: "can EEXIST here still mean another thread got in first? ... The code
handles that case correctly ... Only the comment is misleading."

**Verdict: VALID NIT (comment only).** scan_zfs_open() (:445-464) calls
dmu_objset_own() again under `scan_zfs_import_lock` before it calls
scan_zfs_import(). So when another thread finished an import of this
pool, the second own() succeeds unless the dataset is not in the pool.
EEXIST from spa_import() therefore means the pool is already in this
process's namespace (a scan still open) and the named dataset is not in
it. The own() after it then returns ENOENT, which is the right answer.
Fix: change the comment to "already imported in this process: own() below
answers whether the dataset is there". This is in 68163 only, and the line
is unchanged later.

## 11. 68288 PS31 `8ac62df6_b32ea242` PATCHSET_LEVEL, about Documentation/man3/llapi_scan_namespace.3:71

AI: "The new lfsp_fsname is not mentioned here. llapi_scan_namespace()
ignores it too, so a sentence next to the lfsp_search one ..."

**Verdict: VALID NIT.** At 9cfddeaaf3, llapi_scan_namespace.3:67-71
covers lfsp_search ("A namespace scan does not read it") and says nothing
of lfsp_fsname. llapi_scan_fid.3:82-87 lists it with the ignored fields,
and lustreapi.h:1118 says it is ignored. No namespace code reads it (grep:
only scan_device.c and pfind.c). Fix: add to llapi_scan_namespace.3
after :71: ".I lfsp_fsname is read only by llapi_scan_device(3), and is
ignored here for the same reason." This is in 68288 only.

## 12. 68288 PS31 `9c17e029_accf7832` Documentation/man3/llapi_scan_rec_path.3:66

AI: "'Otherwise its FID resolves to the file that owns it' reads as though
the object's own lfsr_fid is resolved ... In the code it is
lfsr_owner_fid ... only when LLAPI_SCAN_OWNER is in lfsr_valid ... a
caller that copies the llapi_scan_device(3) example (`.lfsp_want =
LLAPI_SCAN_MODE | LLAPI_SCAN_FID`) ... would see every object counted as
nameless."

**Verdict: VALID (doc).** Confirmed in `llapi_scan_rec_path()`: it uses
lfsr_owner_fid if LLAPI_SCAN_OWNER, otherwise it returns -ENOENT for any
class other than VISIBLE (an OST object is CLS_OST_OBJ). In
`scan_want_xattr()` the XA_PFID read happens only if `want &
LLAPI_SCAN_OWNER`. Without it, OWNER is set only from the LMA on a
256-byte-inode OST (LMAC_STRIPE_INFO). The device example at
llapi_scan_device.3:710 is MODE|FID. llapi_scan_device.3:169-177 does say
"With LLAPI_SCAN_OWNER asked for ... llapi_scan_rec_path(3) uses it", but
the rec_path page itself does not. lfs find asks for OWNER (pfind.c
:20597), so lfs is not affected. Only an API user who copies the example
is. Fix: in llapi_scan_rec_path.3 change "Otherwise its FID resolves..."
to "Otherwise it is named by lfsr_owner_fid, the file that owns it, which
the record carries only when LLAPI_SCAN_OWNER is set in lfsr_valid: ask
for LLAPI_SCAN_OWNER in lfsp_want (or leave lfsp_want 0). Without it an
OST object returns -ENOENT with no lookup." This is in 68288 only.

## 13. 68288 PS31 `cf29a8b3_d89f9234` lustre/utils/lustreapi_internal.h:723

AI: "want_fsname carries the same information as sp->lfsp_fsname ...
llapi_scan_device() has to repeat the lfsp_size/offsetof() test by hand
... have scan_device_run_prepass() read spl.lfsp_fsname, and have
llapi_find_device() set `spl.lfsp_fsname = mfs` ... Optional."

**Verdict: VALID SUGGESTION, optional.** Accurate. `llapi_scan_device()`
(scan_device.c:1685-1698) checks size and offsetof by hand before copyin.
`llapi_find_device()` (pfind.c:4910) passes `mfs[0] ? mfs :
spl.lfsp_fsname`. Its spl is already a private copy, so `spl.lfsp_fsname =
mfs` there would work. The only callers are those two, plus the
scan_device_run wrapper at :2020. This is not a defect: the hand check is
correct, and the pointer is not dereferenced before copyin. Taking it
would remove a parameter from two internal prototypes and the hand-rolled
check, in 68288 only (69729 a9e9c7faf2 and 69500 f9034db8d7 carry the
same lines unchanged). It is cheap and improves the code. Leave it to the
user.

## 14. 68159 PS37 `85bb9fc5_096d9840` /COMMIT_MSG:136

AI: "This holds only up to the scanner's own buffer. scan_lmv_to_user()
returns 0 for a foreign LMV larger than SCAN_LMV_BUF (about 48 KiB) ...
could this sentence state that limit?"

**Verdict: VALID NIT.** %B:130-131: "A foreign LMV larger than the
search's buffer grows the buffer, as a walk does". `scan_lmv_to_user()`
returns 0 when `len > outlen`, and the sink's outlen is SCAN_LMV_BUF
(sizeof(lmv_user_md) + LMV_MAX_STRIPE_COUNT * 24, about 48 KB). The
#define comment at scan_device.c:60 already says "A foreign LMV larger
than this is left out of the record rather than truncated." Fix: add to
the message "(up to the device scanner's own SCAN_LMV_BUF, about 48 KB;
llapi_scan_device() leaves a larger one out of the record)". Or, if #17
raises the buffer to XATTR_SIZE_MAX, the sentence is true as it stands.

## 15. 68159 PS37 `64f8e0e0_b6a46bba` lustre/utils/liblustreapi_pfind.c:3139

AI: "(defect) Over a scan, does --foreign ever match a foreign directory?
... The directory branch of find_check_foreign() is inverted ... The
original test was `lfm->lfm_magic != LMV_MAGIC_FOREIGN`. baba1fd07a ...
dropped the negation."

**Verdict: REAL DEFECT, UPSTREAM (landed 2.14.53, May 2021). Not ours,
but this series sends scanned directories into it.** Confirmed in the
code:
- baba1fd07a ("LU-14489 utils: fix 'lfs find --mdt-count'") changed
  `if (lfm->lfm_magic != LMV_MAGIC_FOREIGN)` into
  `if (lmv_is_foreign(lfm->lfm_magic))`, with
  `lmv_is_foreign(m) == (m == LMV_MAGIC_FOREIGN)`. The regular-file
  branch just above still has `!= LOV_USER_MAGIC_FOREIGN`.
- It is still inverted on master (ee61b3f6dd pfind.c:974) and at 68159
  (pfind.c:3122-3127 of the function).
- Result for a directory that has an LMV: a foreign one goes into the
  "not foreign" arm (`--foreign` gives -1, `! --foreign` gives 1), and a
  striped non-foreign one goes into the type-compare arm (`--foreign`
  gives 1). That is backwards. A walk is affected too, for every
  directory that has an LMV. Plain directories are handled earlier by
  `find_lmv_rejects()` (`!have_lmv && fp_check_foreign`), so they come
  out right, which is why nobody has seen it.
- No test covers it: no `lfs find ... --foreign` anywhere in
  lustre/tests at master. That is why it survived.
- The AI is right that 68159's `not_foreign` skip (pfind.c:3068-3084,
  :2955) works around the same inversion for unstriped directories on a
  scan.

This is code-read only. Before filing, confirm on the lab (both
`lfs setdirstripe --foreign=none` and a `-c 2` striped directory, then
`lfs find --foreign -type d` and `! --foreign`), and lift-and-compare.
Fix, as a separate upstream patch with its own LU ticket, landed under
the series or ahead of it: restore `!lmv_is_foreign(lfm->lfm_magic)`,
add `Fixes: baba1fd07a ("LU-14489 utils: fix 'lfs find --mdt-count'")`,
and add a sanity subtest. Then re-check whether 68159's `not_foreign`
workaround is still needed. Per the standing rule (lfu-to-file-upstream),
ask the user before filing the ticket. Reply on 68159 (after the user
agrees): "Yes, inverted since baba1fd07a; it breaks the walk too. Fixing
it in its own change with Fixes:, LU-xxxxx."

## 16. 68159 PS37 `d55e3e04_b65d5ec4` lustre/utils/liblustreapi_pfind.c:3693

AI: "this is find_check_lmm_info() minus fp_check_projid, as a second
hand-kept list ... consider defining find_check_lmm_info() as
find_asks_layout(param) || param->fp_check_projid".

**Verdict: VALID SUGGESTION. Raised before by lreview run6 (BOARD:370,
10-13 "find_asks_layout() duplicates find_check_lmm_info()") and left
unfixed as older code. It was never declined to a reviewer.** The two
lists at 9eb0237d62 are identical except for `fp_check_projid`.
find_check_lmm_info() is the upstream function, and it is defined earlier
in the file, so find_asks_layout() would have to move above it. That
helper is new in 68159, so the move is in our own code. A small, safe
change in 68159. Later commits that edit the area: 68288 9cfddeaaf3
(pfind.c +510), 68417+ (pfind.c). Rebase only. Take it.

## 17. 68159 PS37 `2fee127e_b9be2f21` lustre/utils/liblustreapi_pfind.c:3890

AI: "Is this grow reachable for every foreign LMV that a walk handles?
... returns 0 for a foreign LMV longer than SCAN_LMV_BUF ..., for an
LMV_MAGIC_V1 shorter than lmv_mds_md_v1 or with more than
LMV_MAX_STRIPE_COUNT stripes, and for an unknown magic ... the directory
is answered as unstriped ... Should an unconvertible trusted.lmv get the
same treatment [as an unreadable trusted.lov: undecided]?"

**Verdict: VALID, minor; the cases are rare.** Confirmed. At
scan_device.c:878-899, when `scan_lmv_to_user()` returns 0 the record
gets no LLAPI_SCAN_LMV (only LMV_SHARD for a stripe). `find_rec_to_lmv()`
zeroes the header and returns, and the directory is judged as unstriped.
In contrast, `find_rec_layout()` returns 1 (undecided) for a layout that
was present but did not parse. Only one of these cases happens on a
healthy filesystem: a foreign LMV between about 48 KB and XATTR_SIZE_MAX,
which needs ea_inode on the MDT. The others are corrupt or unknown-magic
xattrs.

Fix options, for the user to pick:
(a) Make SCAN_LMV_BUF cover XATTR_SIZE_MAX (64 KB, so +16 KB per
    worker). That closes the only legitimate case and makes #14's
    sentence true.
(b) For an unconvertible non-shard LMV, mark the record in the sink so
    find marks it undecided. That needs a record bit, which is a UAPI
    addition, so it is heavier.
Recommended: (a), and say in llapi_scan_device.3 that a corrupt
trusted.lmv is delivered without LLAPI_SCAN_LMV. (a) touches 68156
(SCAN_LMV_BUF is defined there) or 68159. Check round22 7e92da87 (the
shard-area clear depends on the buffer size: `room` is computed from
outlen, so a larger buffer is safe).

## 18. 68159 PS37 `13021777_d0514133` lustre/utils/liblustreapi_pfind.c:4365

AI: "This says lfsp_got is one of four fields overwritten whatever the
caller set. The code only clears it in the local copy ... consider
listing three overwritten fields and saying lfsp_got is ignored, to
match the man page."

**Verdict: VALID NIT.** The kernel-doc at :4365-4367 says "Four fields ...
are overwritten whatever the caller set: lfsp_want, lfsp_thread_count,
lfsp_filter and lfsp_got". The code sets `spl.lfsp_got = NULL` (:4462) on
the private copy. llapi_find_device.3:76-78 and the commit message
(%B:145) say "left untouched". Because every one of the four is changed
only in the copy, "overwritten" is loose for all of them. But for lfsp_got
the caller would expect a write-back, so the wording matters there. Fix:
"Three fields are the search's to decide and are replaced in its copy:
lfsp_want ..., lfsp_thread_count and lfsp_filter. lfsp_got is ignored and
the caller's is left untouched." This is in 68159 only. Check whether
68288 rewrites this kernel-doc.

## 19. 68419 PS23 `963dc2c7_f94f2e0d` Documentation/man1/lfs-find.1:758

AI: "The new TIME spellings here, and the rewritten -name paragraph ...,
document --since and --changelog rather than --since-cookie ... would
these hunks sit better in 68417/68418?"

**Verdict: VALID SUGGESTION. It is the same kind of point as the 68418
"move the --since-only hunks down into 68417" thread, which the user
chose to leave unanswered (BOARD:451, :523, "user: ignore").** Confirmed:
the TIME formats (`"%H:%M:%S"`, `"%H:%M"`, the space form) are parsed in
lfs_find_parse.c from 68417 286c9a20fa on, and 68419's code diff does not
touch them. Its lfs_find_parse.c diff only adds the --since-cookie option
and a comment. So the man hunk at :755-768 documents 68417's code. The
-name "burst" paragraph documents 68418's coalescing. Moving them is a
scripted hunk move across 68417/68418/68419 (lfu-scripted-rebase). The
tree hash at the end is the same, and only the intermediate commits
change. Recommend the same decision as for 68418: leave it, or do both
moves together in one rebase if the user wants them.

## 20. 68419 PS23 `6b5da815_881fe259` lustre/tests/sanity.sh:23478

AI: "'not for the reason it once said' describes an earlier revision of
the test rather than the test that lands."

**Verdict: VALID NIT.** sanity.sh:23477-23481: "which is the right order
but not for the reason it once said". Fix: "Both run while the cookie is
still fresh, though neither refusal can be preempted by the staleness
check: llapi_find_since() tests --since against --since-cookie in its
first block, and lfs_find() rejects a second path before it calls
llapi_find_since()." This is in 68419 only. Check that 69443 3a7bd23244
does not edit this block.

## 21. 68419 PS23 `397172d9_5d095b24` lustre/utils/liblustreapi_pfind.c:5431

AI: "An MDT whose log was empty on the previous run is never written to
the cookie, because find_cookie_write() skips seen[i] == 0. So on every
later run it reads as anchor 0 here and is not checked ... Records 1..100
are lost with nothing said ... Could a covered MDT with an empty log be
recorded explicitly, and a later oldest > 1 on it at least warn?"

**Verdict: REAL DEFECT (silent loss in the exact case the cookie exists to
catch).** Confirmed at c7440bf581 and still present at the tip of the
--since branch, 69500 f9034db8d7:
- `find_cookie_write()` (:5239-5243): `if (seen[i] == 0) continue; /*
  never anchored: same as absent */`.
- `find_cookie_check()` (:5430-5432, and :5534 at the tip):
  `reached[i] = anchor; if (anchor == 0) continue;`. No probe.
- 69443's per-MDT recheck (tip :6908-6913) is also gated on
  `starts[mdts[i]] != 0`.
- The cookie reader accepts index 0 lines but stores them in `starts[]`,
  where 0 means "absent", so "present with 0" and "absent" cannot be
  told apart.

Scenario (DNE, policy engine registered and clearing): run 1 reads an
idle MDT0001, its log is empty, and no line is written. Then MDT0001
writes records 1..100, the engine clears them, and 101..110 arrive. Run 2:
anchor 0, not probed, the scan starts at 101, rc 0, the cookie advances,
and 1..100 are gone with nothing said. This is common, not exotic: an
idle or newly added MDT on a site where Robinhood consumes the log. The
commit message's reason ("0 has nothing to be stale against, and that is
every MDT of a first run") holds only for a first run.

Fix: a run that covered an MDT has read through index 0 even when the
log was empty. So:
1. find_cookie_write() writes a line for every covered MDT, including
   "fsname-MDTxxxx 0".
2. The reader keeps a `present[]` bitmap, or a sentinel such as
   UINT64_MAX for absent, so that a present 0 is probed.
3. find_cookie_check() and the 69443 recheck probe present anchors,
   including 0. The existing test `oldest > anchor + 1` then gives
   `oldest > 1`, so -ESTALE for the scenario above, and a restarted log
   (oldest == 1) is accepted. The end-of-log restart probe
   (`find_cl_first(mdtname, anchor, &from)`) is fine at anchor 0.
4. Man page: a missing line still reads as a first run for that MDT, and
   say so (the AI's fallback suggestion).
5. sanity 160Ac: add the empty-MDT case. It needs MDSCOUNT >= 2, or it
   can be done on one MDT by clearing the whole log between runs.
Touches 68419 c7440bf581 (write, read, check), 69443 3a7bd23244 (the
recheck gate and find_cookie_purged's caller), and 69500 f9034db8d7
(context only: find_since_gap skips the cookie). Lab-prove it A/B before
the push (lfu-lift-and-compare: the old build loses the records, the new
one refuses).
