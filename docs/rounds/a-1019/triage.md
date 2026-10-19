# AI review round 2026-10-19: triage (read-only)

Source: anonymous REST `/changes/<n>/comments` and `/detail`. Kept: author
`aireview`, thread unresolved with the AI comment last, on the change's
current PS, dated 2026-10-19. 10 inline comments plus 2 suggestions made only
in the patch-set message (#4, #10), 12 items in all. The inline counts match
the expected ones (68156 2, 68288 1, 68415 2, 68416 2, 68419 1, 69443 1,
69795 1). Nothing was posted and no tree was modified.

"Looks good to me", nothing inline: 68160 PS39, 68163 PS38, 69500 PS10,
69700 PS4, 69729 PS4. No AI review on the current PS yet: 68157, 68158,
68159, 68417, 68418, 69501, 69502, 69503, 69796. Older unresolved AI threads
were left alone because they were dealt with in earlier rounds: 68159
bd32462f (PS27), 68415 e058265d/6a004a15 (PS19/20), 68418 d5ea875d (PS19),
68419 a0eec5eb/927335fd (PS13) and 963dc2c7 (PS23, a-1018 #19, no reply by
user).

Verified against the pushed tags `a1018-pushed-*` (~/lfs-fork-1014, shared
object store), and for 69795 against ~/lfs-foreign-1018 08940f0ac9:

| change | PS | sha | subject |
|---|---|---|---|
| 68156 | 38 | 4f2824972c | scan an ldiskfs target directly |
| 68415 | 31 | d1688b30b0 | add llapi_scan_changelog() |
| 68416 | 31 | 6e240c6728 | fill a scan record for one FID |
| 68288 | 32 | 0798e095e9 | name a device scan's objects |
| 68419 | 24 | 8923d31cf4 | add find --since-cookie |
| 69443 | 12 | 143add57d0 | find --since-cookie, check each MDT when read |
| 69795 | 1 | 08940f0ac9 | fix 'lfs find --foreign' on directories (master) |

/COMMIT_MSG line numbers: Gerrit's line is `git log %B` line + 6.

## Verdict summary

| # | change | PS | file:line | id | verdict |
|---|---|---|---|---|---|
| 1 | 68156 | 38 | lustreapi_internal.h:300 | e75b10aa | NIT, comment only (decline the behaviour change) |
| 2 | 68156 | 38 | lustreapi_internal.h:550 | b8a84763 | NIT, take (68288 already fixes it later) |
| 3 | 68288 | 32 | liblustreapi_pfind.c:3688 | 274a2606 | VALID SUGGESTION, optional (one premise false) |
| 4 | 68288 | 32 | PATCHSET_LEVEL (tests) | (message) | SUGGESTION, user decides |
| 5 | 68415 | 31 | /COMMIT_MSG:34 | 46b2065c | NIT, take |
| 6 | 68415 | 31 | liblustreapi_scan_changelog.c:1169 | adfd872c | VALID MINOR, take |
| 7 | 68416 | 31 | man3/llapi_scan_fid.3:314 | 1cdbec45 | NIT, take |
| 8 | 68416 | 31 | liblustreapi_scan.c:1041 | 73b12b8e | REAL DEFECT (minor race), lab A/B |
| 9 | 68419 | 24 | /COMMIT_MSG:214 | 11b505e3 | NIT, take |
| 10 | 68419 | 24 | PATCHSET_LEVEL (160Ac DNE) | (message) | SUGGESTION (test gap is real), user decides |
| 11 | 69443 | 12 | liblustreapi_pfind.c:6589 | fafd6ecf | STYLE NIT, cheap |
| 12 | 69795 | 1 | liblustreapi_pfind.c:974 | e9a98930 | VALID, PRE-EXISTING upstream; decline for 69795, user decides on a follow-up |

Real defect: #8. Worth taking: #2 #5 #6 #7 #9, and #1 as a comment fix only.
For the user: #3, #4, #10, #11, #12.

---

## 1. 68156 PS38 `e75b10aa_c578be0c` lustre/utils/lustreapi_internal.h:300

AI: the comment says one mask per scanner "so that a flag only one of them can
act on cannot be quietly accepted by the other". But LLAPI_SCAN_F_KNOWN_DEV
accepts STOP_ON_ERROR, which the device scan never reads. Should the device
scan refuse it, or should the contract be relaxed for both scanners?

**Verdict: NIT, take as a comment fix only. Decline the behaviour change.**
The AI's facts are right: liblustreapi_scan_device.c tests only
LLAPI_SCAN_F_INTERNAL in `sd_flags`. But nothing is ignored silently.
llapi_scan_device.3 NOTES (:482-494) says "LLAPI_SCAN_F_STOP_ON_ERROR has no
effect here", explains why (an object that cannot be read is skipped and
counted in ss_skipped), and says it is accepted so that one lfsp_flags value
also works with llapi_scan_namespace(3). That reason still holds for every
value that does not include F_INTERNAL. The asymmetry is deliberate: it was
round 11 #8 ("a block shared with llapi_scan_device() ... came back -EINVAL";
fixed by accepting F_KNOWN_DEV). The only part that is wrong is the internal
header comment, which states a rule that has an exception.

Fix (68156 only, no later commit changes these lines): reword the comment to
"... cannot be quietly accepted by the other. The one exception is
LLAPI_SCAN_F_STOP_ON_ERROR: a device scan accepts it, and
llapi_scan_device(3) documents it as having no effect there." Reply: "The
device page documents it as having no effect (NOTES), so it is not silent.
The comment now names the exception."

## 2. 68156 PS38 `b8a84763_cbe30c3b` lustre/utils/lustreapi_internal.h:550

AI: the comment above LLAPI_SCAN_WANT_MDT_ONLY leaves out LLAPI_SCAN_HSM,
which the macro includes.

**Verdict: VALID NIT, take.** At 4f2824972c the comment lists layout,
directory stripe, lazy SOM size, MDT index and linkea/parent, but not HSM.
68288 (0798e095e9) rewrites the same comment and already adds "the HSM
state" (and the OST owner). So the fix belongs in 68156: add "the HSM state,"
after "the directory stripe,". The 68288 rebase then has a trivial conflict
that resolves to 68288's own text. Reply: "Done."

## 3. 68288 PS32 `274a2606_6176a46a` lustre/utils/liblustreapi_pfind.c:3688

AI: -EPERM from fid2path is per mount, not per object (ll_fid2path() checks
CAP_DAC_READ_SEARCH / user_fid2path before looking at the FID). An OST scan
with --fid2path run without the capability reads the whole target, fails one
ioctl per kept object, prints nothing, and exits EPERM only at the end. It
suggests returning prc for -EPERM (and -EBADF) from find_decide() so the scan
stops.

**Verdict: VALID SUGGESTION, optional. One premise is false.** Confirmed:
`ll_fid2path()` (llite/file.c:3594-3596) returns -EPERM before any RPC, so
once one lookup fails they all do. The MDT side has no per-object EPERM.
However "nothing is printed" is wrong. The first failure is reported at the
moment it happens, through the `*fc->fc_path_rc == 0` block (:3705-3729,
"cannot resolve DFID through '<mnt>'"). On an MDT with a built dirmap, names
come from the map and no ioctl runs, so in practice only OST scans, and MDT
objects the map cannot place, are affected. The setting is also narrow: a
device scan already needs read access to the block device, which usually
means root, and root has CAP_DAC_READ_SEARCH. The case is a non-root user
with device access (e.g. in the disk group) and no user_fid2path.

Fix, if taken (68288; check igif-1017 69729, whose base is 68288): in
find_decide(), after recording/printing the first failure, return prc when it
is -EPERM so that find_device_cb() returns it and the scan ends. -EBADF cannot
happen with a mount fd this code opened, so leave it out. An alternative with
no change to the per-object path: probe once in llapi_find_device() after the
fileset check, with llapi_fid2path_at() of the root FID, and refuse -EPERM
before the scan. Lab: a short check (non-root with device read access, OST,
--fid2path) showing one message and an early exit. A/B is not needed for
correctness. User: take now or leave?

## 4. 68288 PS32 patch-set message (no inline id): test coverage

AI: no subtest exercises the cross-filesystem -EXDEV refusal (the one silent
failure the message names), the fileset-mount -EINVAL refusal, or the
256-byte-inode LMA fallback in scan_owner(). It suggests a fileset mount in
conf-sanity and test_302 on an OST formatted `-I 256`.

**Verdict: SUGGESTION, and the gap is real; user decides.** conf-sanity
300a-302 at 0798e095e9 has no fileset, -EXDEV or `-I 256` case. Cost:
- fileset -EINVAL: cheap. Mount `$MGSNID:/$FSNAME/$tdir` on mds1 and expect
  `--fid2path` on it to be refused. Probably worth taking.
- -EXDEV (another filesystem's mount): needs a second filesystem in the
  framework, which is expensive. Decline or hold.
- `-I 256` LMA fallback: reformat. Round 20 (statx-port-down.md:121-153) hit
  the framework trap (OST_FS_MKFS_OPTS, not OSTOPT; a second call drops the
  OST). It was measured by hand then. Decline for now.
This is a patch-set message, so a reply is optional. If one is posted, give
it on the PS-level thread.

## 5. 68415 PS31 `46b2065c_12e2ffed` /COMMIT_MSG:34

AI: in the LLAPI_SCAN_CL_F_RESOLVE bullet, "object. It" ends a line early;
the paragraph should be reflowed.

**Verdict: VALID NIT, take (message only).** At `%B` lines 26-32: "...per
object. It" / "fills only what the record lacks...". Reflow the bullet. No
tree change. Reply: "Done."

## 6. 68415 PS31 `adfd872c_11cf9826` lustre/utils/liblustreapi_scan_changelog.c:1169

AI: _CLEAR only works when lfsc_user is in the cl<N> form. The kernel's
chlg_write() parses "clear:cl%u:%llu", so "1" or a bare name is accepted and
records are delivered, but the first clear fails -EINVAL (after
SCAN_CL_CLEAR_BATCH records under _FOLLOW, which ends the stream). Refuse up
front, or document it.

**Verdict: VALID MINOR, take.** Confirmed: mdc_changelog.c:604 has
`sscanf(kbuf, "clear:cl%u:%llu", ...)`. `llapi_changelog_clear()`
(liblustreapi_chlg.c:653-661) strips a "-name" suffix and passes the rest
unchanged. So "cl1" and "cl1-name" work, and "1" and "name" fail late. The
check at :1169 tests only for NULL. llapi_scan_changelog.3:195-197 says "as
cl1" but does not say the other forms fail. There is no data loss: the records
were delivered and stay in the log, and the run fails with -EINVAL at the
first clear. But a parameter error should be refused before any record is
read, which is what this function does for its other bad combinations.

Fix (68415): next to the NULL test, with _CLEAR, refuse an lfsc_user that is
not `cl` + digits, followed by the end of the string or by `-`: -EINVAL.
Add it to the ERRORS list (:492-509), and in the lfsc_user entry say "cl<N>
or cl<N>-<name>; clearing needs this form". Add a case to llapi_scan_test
(the "1" form with _CLEAR gives -EINVAL before the callback runs). No lab A/B
is needed: the unit case fails on the old library and passes on the new one.
Check later commits that touch this block or page before the rebase (68288
touches llapi_scan_changelog.3).

## 7. 68416 PS31 `1cdbec45_86ee0a52` Documentation/man3/llapi_scan_fid.3:314

AI: the page sends readers to llapi_root_path_open(3), llapi_fid2path_at(3)
and uses llapi_path2fid(3) in EXAMPLES. None of the three is in SEE ALSO.

**Verdict: VALID NIT, take.** References at :41, :243, :275, :298-300. All
three pages exist in the tree. SEE ALSO lists only llapi_fid2path,
llapi_scan_changelog, llapi_scan_device, llapi_scan_namespace and lustreapi.
Add them in alphabetical order (fid2path, fid2path_at, path2fid,
root_path_open, scan_*). 68288 adds llapi_scan_rec_path(3) to the same list,
so expect a trivial conflict there. Reply: "Done."

## 8. 68416 PS31 `73b12b8e_8a21b5b2` lustre/utils/liblustreapi_scan.c:1041

AI: the lfsr_fid check only covers what the getinfo returned. For a regular
file, scan_rec_gather_finish() opens the object again *by pathname* for
MDT_INDEX (`open(path, O_RDONLY)`), PROJID (get_projid through *fdp) and HSM
(`open(path, O_RDONLY|O_NONBLOCK)`). An atomic-save rename between the
getinfo and that open gives a record with A's FID, layout and size, B's
projid/HSM/MDT index, and lfsr_fd on B. The commit message says "a record
never describes a different object". Suggested fix: llapi_fd2fid() on fd and
-ESTALE on a mismatch.

**Verdict: REAL DEFECT, minor (narrow race, only with non-default fields).**
Confirmed at 6e240c6728: in scan_rec_gather_finish() (:340-441),
get_lmd_info_fd(path, p, ...) asks through the parent and the name. Then, for
S_ISREG with `d == -1`, `*fdp = open(path, ...)` at :381 and :428, and
get_projid(path, fdp, ...) at :413, and :437-438 publishes `lfsr_fd = *fdp`.
llapi_scan_fid() compares only `rec.lfsr_fid` (from the getinfo) at
:1040-1045. The default mask leaves out HSM, PROJID and MDT_INDEX, so the
claim holds by default. It fails for `lfs find --since` with --projid,
--hsm-state or --mdt-index, and for any llapi caller that asks for those.
Effect: A, already unlinked by the rename, is matched on B's attributes and
printed under the name "f", which B holds now. B's own changelog record
prints it again (the FID dedup does not catch it, since the FIDs differ).
Directories are not affected (d is opened first and every ioctl goes through
it). Special files take projid from the parent with the name, which no fd
check covers. That is a much rarer case; say so in the kernel-doc.

Fix (68416): after scan_rec_gather() returns, if `fd >= 0`, call
llapi_fd2fid(fd, &ofid) (LL_IOC_PATH2FID on the fd, no RPC). If it fails or
differs from `*fid`, return rc = -ESTALE and take the existing retry
(fid2path again, then -ENOENT if the object is gone). Narrow the commit
message sentence to "... checked against the one asked for, on the getinfo
and on any descriptor the gather opened". Alternative: open the regular file
by FID (llapi_open_by_fid_at(mnt_fd, fid, O_RDONLY|O_NONBLOCK)) before the
gather, so gather_finish reuses *fdp. That closes the race completely, but
changes the open flags the MDT_INDEX path uses today. The fd2fid check is
smaller and fits the -ESTALE contract already there.
Lab A/B: yes. A race needs forcing: a gdb breakpoint on the open in
scan_rec_gather_finish(), or an LD_PRELOAD shim that does the rename on the
first open of the path. Old library: mixed record (projid of B with FID A),
rc 0. New: retry, then -ENOENT/-ESTALE or the record for the right object.
Alternatively lift and compare. Later commits near this block: 69501
c04f587561 edits llapi_scan_fid up to about :970 (filter), not the FID check,
so the rebase should be clean. 69700 also touches liblustreapi_scan.c.

## 9. 68419 PS24 `11b505e3_37d86a3b` /COMMIT_MSG:214

AI: the lfs-find.1 paragraph counts five changes, but the diff has seven
hunks (SYNOPSIS, TIME spellings, --since-cookie OPTIONS entry, -name
paragraph, target-scan refusal list, two EXAMPLES). "--since-cookie moves up
beside --since" reads as if it already existed in the page.

**Verdict: VALID NIT, take (message only).** The man diff 8923d31cf4~1..
8923d31cf4 has 7 hunks, as stated. Before 68419 the page names --since-cookie
only in passing (the EACCES sentence, :785 at 68418). Its SYNOPSIS and
OPTIONS entries are new in this patch, so "moves up" is left over from an
older layout. The --since-cookie example and the target-scan refusal line
are not mentioned. Rewrite as: "lfs-find.1 documents --since-cookie in
SYNOPSIS, OPTIONS, the target-scan refusals and EXAMPLES. It also gives
TIME's spellings in full ..., says which name -name is tested against under
--changelog ..., and adds a plain --since example." Reply: "Done."

## 10. 68419 PS24 patch-set message (no inline id): 160Ac never tests DNE

AI: 160Ac creates everything on MDT0000 (mkdir_on_mdt0), so per-MDT
anchoring is never tested, even in the mdscount=2 mdtcount=4 session. It
suggests a DNE block: a file under `$LFS mkdir -i 1`, a second run that
returns it and not the MDT0000 file, a grep on both cookie lines, and
`--changelog $FSNAME-MDT0001 --since-cookie` keeping the MDT0000 line.

**Verdict: SUGGESTION; the coverage gap is real; user decides.** At the tip
103aef57d1, 160Ac (:23410-23586) uses only mkdir_on_mdt0 and checks only
MDT0000 lines. 160Aa-Af have no `mkdir -i 1`. The commit already carries
`Test-Parameters: testlist=sanity env=ONLY=160Ac mdscount=2 mdtcount=4`, so a
`(( MDSCOUNT > 1 ))` block would run in CI with no new session (Andreas's
rule is satisfied). Before writing the --changelog part, check in
find_changelog code (:6846-6861) that a single-MDT --changelog run rewrites
the cookie and keeps the other MDT's line. That is the behaviour the AI
assumes, and it is not verified here. Cost: test only, and it needs a DNE lab
run (MDSCOUNT=2 on the local VM) before any push. Hold unless the user wants
it in this round.

## 11. 69443 PS12 `fafd6ecf_12ea00a3` lustre/utils/liblustreapi_pfind.c:6589

AI: the new `seen[]` (indexed by position in mdts[], like reached[]; the
oldest record the pre-pass saw for an MDT anchored at 0) clashes with
find_cookie_write()'s `seen` parameter (indexed by MDT number, passed
starts[]) and st.fss_seen (the FID tree). Suggests `prepass_oldest`.

**Verdict: STYLE NIT, valid and cheap.** At 143add57d0: `__u64 *seen` at
:6589/:6735, passed at :6856 to find_cookie_check(..., seen) and used at
:6912 `seen[i]` for find_cookie_recheck(). find_cookie_write(..., const __u64
*seen, ...) at :5194-5241 is a different array with a different index.
Fix: rename the 69443 local and the find_cookie_check() / find_cookie_recheck()
parameters to `prepass_oldest` (and `oldest` in recheck), and update the
kernel-docs at :5396 and :5439. Nothing outside 69443 and the tip 69500 is
affected. Build only, no lab. User: the 10-05 style threads were left
unanswered by choice. This one is mechanical, so take it with the next 69443
respin.

## 12. 69795 PS1 `e9a98930_fce7716e` lustre/utils/liblustreapi_pfind.c:974

AI: correct for `--foreign` and `! --foreign`. With a type given, though,
`! --foreign=symlink` prints an unstriped directory (find_foreign_accepts()
shortcut), rejects a striped one (not foreign + type given -> -1), and
rejects a plain file (same rule in the S_ISREG branch). The lfs-find(1)
example "all but foreign files/dirs of symlink type" says non-foreign objects
should be printed. Which is intended? Add a typed-negation case to 27Kf; the
semantics could be fixed in a separate patch.

**Verdict: VALID, PRE-EXISTING upstream semantics. Decline it for 69795;
the user decides on a follow-up.** Confirmed at 08940f0ac9: both branches of
find_check_foreign() (:955-985) do `if (!foreign) { if (type == UNKNOWN)
return exclude ? 1 : -1; return -1; }`. So `! --foreign=TYPE` rejects every
non-foreign file, and has done so in the file branch since it was written.
The plain-directory path (find_lmv_rejects() :2651-2652 /
find_foreign_accepts() :2630-2635) accepts it without a type check.
lfs-find.1:934-939 promises the opposite for files. 69795 only restores the
negation, so a striped directory now follows the file rule. That is
consistent with files, though not with the man example. Correct semantics
would be `if (!foreign) return exclude ? 1 : -1;` whatever the type, in both
branches. That is a behaviour change to a separate upstream rule, so it does
not belong in a one-line Fixes: patch.
Reply (if the user agrees): "The typed-negation rule is older than this
patch and is the same for files; this patch only restores the negation.
Making `! --foreign=TYPE` print non-foreign objects is left for a separate
change." User: (a) file a new LU for `! --foreign=TYPE` dropping non-foreign
files and striped directories (lab-confirm on stock master first), or (b)
just reply and leave it. Do not add a typed case to 27Kf in 69795: it would
pin the behaviour that is about to be questioned.
