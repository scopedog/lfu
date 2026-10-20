# a-1019 lreview fixes (LOCAL, UNPUSHED)

Applied 2026-10-19 by `forktx5.py b39fe0036b tx_1019d.py` in ~/lfs-fork-1014.
Backups before the rewrite: tags `k1019-<branch>`. Nothing pushed, nothing
posted, lreview not run.

## New tips

| branch | before (k1019-*) | after |
|---|---|---|
| fork-1014 | 7b24dd3149 | 9d3b9c8d7e |
| fork-69501 | 9ffadff6c0 | 7934cb6d70 |
| fork-69502 | d973a4f179 | 35866766af |
| fork-69503 | 185bb93cf6 | 25f6ef456e |
| rate-1017 | 7aac33ca4a | 5b00f2b723 |
| maxrate-1017 | 7d61eb12e0 | f6e216d6f8 |
| igif-1017 | 56ea5cdf37 | d34b11ba53 |

Trunk: 68156 e1bb15d00b, 68415 cf05bc2f92, 68416 97e9c05426, 68157 8647d144f9,
68158 a56c0078cf, 68159 0c8e6792be, 68160 03dd154c6c, 68163 5cfcf11173,
68288 349e577e02, 68417 085109cd90, 68418 3e7553d2ce, 68419 d9ad0e9e1b,
69443 4207f10947, 69500 9d3b9c8d7e.

**Content changed** (range-diff `!`): 68156, 68415, 68159, 68160, 68163,
68288, 68419, and 69729 (igif, its own sentence in llapi_find_device.3 now
carries the F1 text). Every other commit is `=` (reparented only): 68416,
68157, 68158, 68417, 68418, 69443, 69500, 69501, 69502, 69503, 69700, 69728.
Commit counts and Change-Id sets unchanged on all 7 branches. 68419's own
diff got smaller: the reflow restores two lines 68418 already had.

## Per item

| # | change | result |
|---|---|---|
| L1 | 68415 | VERIFIED (mdc_changelog.c: `crs_user_mask = in & out`, filters only if nonzero). Read loop drops a record whose type is not in lfsc_type_mask, after the endrec check and before ss_seen. Man caveat removed; entry now says only these types are delivered and the client filters where the two masks overlap. New test11 (asks CL_UNLINK; only UNLINK must come, and some must); sanity 56Eea runs it a second time with a user registered `-m creat`. Msg bullet updated. |
| L4 | 68419 | Three comment paragraphs reflowed (find_since_filter_cb, "What happens next", llapi_find_since() Return:). All three are in 68419's diff, so 68418 is untouched. |
| B1 | 68156 | VERIFIED in osd_handler.c: osd_create() without od_index_in_idif stores `ostid_to_fid(.., 0)`; osd_check_lma() takes an LMA IDIF with index 0 as old and compares it rebuilt with the real index. New scan_idif_set_index() puts tt_index back (OST label with index, idx != 0, fid_is_idif, idx in FID == 0). One line in llapi_scan_device.3 (CLS_OST_OBJ) and one msg bullet. |
| B2 | 68156 | VERIFIED (scan_errcode() maps every unmapped ext2fs error to -EIO; bitmap read; calloc -> -ENOMEM). -EIO lists superblock, group descriptors, inode bitmap, inode table (68163's ZFS version too); -ENOMEM added. |
| B3 | 68156 | fid_is_root() returns bool. |
| C2 | 68159 | Example: "the regular files over a gigabyte ... a file whose size the MDT does not hold ... is counted as undecided and not printed". |
| D1 | 68160 | VERIFIED (lfs_find_label_is() needs '-' before the role). Message: `'%s' is not a target name like FSNAME-MDT0000 or FSNAME-OST0000`. |
| E1 | 68163 | The two paragraphs (autotest/Test-Parameters, weak slot/131d) removed from the message. Rest kept. |
| F1 | 68288 | VERIFIED (--fid2path on an MDT uses the same dirmap, scan_dirmap_path() returns -ENOENT at sd_encrypted, no mount fallback when fc_dirmap is set). lfs-find.1: "On an MDT, neither option names an object below an encrypted directory"; llapi_find_device.3 NOTES list adds it. |
| F2 | 68288 | lfs_find_device() refuses -printf with --paths/--fid2path once, beside --xattr; library check kept. One msg sentence. |

Nothing declined after verification.

## Checks

- Script idempotent: a second DRY pass over the new tips maps every tip to itself.
- Build sweep (`sweep_d.sh`, sweep_d-dry.log): `SWEEP ee61b3f6dd..9d3b9c8d7e, 14 commits` + 69501/69502, 69503, 69700/69728, 69729 -- 20/20 build=0 hdr=0 tests=0 sh=0. (Swept the dry refs; the real run produced the same shas.)
- checkpatch per changed commit (checkpatch_d.txt): the finding set of every commit is identical to before.
- groff -ww: no new warnings on lfs-find.1 (1 old), llapi_find_device.3, llapi_scan_changelog.3, llapi_scan_device.3 at all four leaf tips.
- Range-diff: range-diff-d.txt (trunk); leaves all `=` except 69729.

## Lab

**B1, lift-and-compare** (tests/lab-1019d/b1/): scan_idif_set_index() lifted
from the new file, compared with the OSD's own computation (fid_to_ostid +
ostid_to_fid lifted from lustre/include/lustre_fid.h). Old (raw LMA) differs
from the OSD on 4 inputs, new on 1: an OST label without an index, which the
scan cannot know (documented "from the target's label").

**B1, real image, host, no root** (b1/image.sh): ext4 labelled lfst-OST0003,
LMAs written with debugfs, real ldiskfs plugin, `lfs find --device -printf %LO`:

    old: [0x100000000:0x1234:0x0] [0x100000001:0x5:0x0] [0x100030000:0x99:0x0] [0x2c0000401:0x10:0x0]
    new: [0x100030000:0x1234:0x0] [0x100030001:0x5:0x0] [0x100030000:0x99:0x0] [0x2c0000401:0x10:0x0]

Controls (same image as lfst-OST0000 and lfst-MDT0003): old == new.

**VM** (rhel9.7-server-mgs-mds-clone, arms t = 9d3b9c8d7e, o = 7b24dd3149; VM shut down after):

- L1 A/B (06-l1b.result.txt), user cl1 `-m creat`, ask CL_UNLINK only:
  - mdd mask MARK only (no UNLNK record exists): o `CREAT=3`, t none.
  - mdd mask with UNLNK: o `CREAT=6 UNLNK=3 CLOSE=3 SATTR=3`, t `UNLNK=3`.
  - control, user `-m all`: both `UNLNK=3`; mask 0: both identical.
  - (04-l1.sh, first try: test11 failed on BOTH arms -- the fixture had no
    UNLNK records, so the "some UNLINK" assert fired first. Fixture, not code.)
- F2/D1 by hand, 2 MDTs + 2 OSTs: `--local --paths -printf`, `--local --fid2path -printf`, `--fsname --paths -printf`: o prints the library error + "failed for" per target (2, 4, 2 times), t one line, rc 95 both. `--target MDT0000`: new wording.
- sanity 56E* (16 PASS, 2 SKIP need 2 MDTs) incl. 56Eea with test11 run twice (second with `-m creat` user cl2): PASS.
- sanity 160Aa-Af: 6/6 on MDSCOUNT=1 and 6/6 on MDSCOUNT=2.
- conf-sanity 300a 300b: PASS.

## Notes for the push-ask

- 69729 (igif) gets a new patchset for a text-only change (F1 in its own rewrite of the NOTES sentence).
- test11 needs UNLINK records in the log; in 56Eea the `-m ALL` user keeps them. The sanity block skips the second run below MDS 2.17.0 (as test9 does).
- .TH dates were not bumped (consistent with the previous rounds).
- Owed before a push: lreview of the changed commits (68156, 68415, 68159, 68160, 68163, 68288, 68419, 69729).

## 68415 lreview r2 (lreview/68415-r2.md), applied 10-20

Three findings, all taken, LOCAL ONLY. Script `tx_1019e.py` through
`forktx5.py` from 68415 (cf05bc2f92) up; backups `l1019-<branch>`.

1. sanity 56Eea: below MDS 2.17.0 skip test11 too (`skip_cases="9,11"`);
   test11 sets lfsc_type_mask, which takes the same MDS_GET_INFO
   (KEY_CHANGELOG_USER, LU-19296) path as test9. Comment above says so.
   The -e list already takes commas (`9,6` before).
2. Commit message: "has eleven cases" -> "has twelve cases".
3. Commit message: "test6, test9 and test11 need -u".

No later commit edits the 56Eea block (identical text at every tip
before the rewrite); the fix is carried to all 19 commits from 68415 up.

| branch | before | after |
|---|---|---|
| fork-1014 | 9d3b9c8d7e | 0a114635ae |
| fork-69501 | 7934cb6d70 | 5b5bcd9986 |
| fork-69502 | 35866766af | 51907c9108 |
| fork-69503 | 25f6ef456e | 362886bf33 |
| rate-1017 | 5b00f2b723 | 395f238177 |
| maxrate-1017 | f6e216d6f8 | e55448a62e |
| igif-1017 | d34b11ba53 | 6c43ee2168 |

68415 is now 103058b1ff.

- Dry run (tx_1019e-dry.log) = real run (tx_1019e.log), same shas; a
  second pass changes nothing (idempotent). Each rewritten commit differs
  from its original by the same 5/5 lines in sanity.sh only.
- Commit counts unchanged per branch; Change-Ids identical; message lines <= 75.
- `bash -n lustre/tests/sanity.sh` on every commit of every branch: clean.
- Build sweep (sweep_e.sh, sweep_e.log): `SWEEP ee61b3f6dd..0a114635ae,
  14 commits` + 69501/69502, 69503, 69700/69728, 69729 -- 20/20 build=0
  hdr=0 tests=0 sh=0.
- checkpatch 68415 (checkpatch_e.txt): same findings before and after
  (2 line-length CHECKs, lustreapi.7 section CHECK, MAINTAINERS, ARRAY_SIZE).
- Range-diff (range-diff-e.txt): on all seven branches only 68415 is `!`
  (the two message lines and the sanity hunk); every other commit `=`.
- Not lab-run (no MDS < 2.17.0 to hand); not re-lreviewed (user cancelled).

## R9 (68288) + R11 (68419) lreview r2, applied 10-20

Both verified first, both taken, LOCAL ONLY. Script `tx_1019f.py` through
`forktx5.py` from 68288 (ab1e0ea424) up; backups `m1019-<branch>`.

**R9 verified.** `llapi_scan_rec_path()` tests `LLAPI_SCAN_OWNER` before the
class, so an OST object (CLS_OST_OBJ) with an owner has a path; the
kernel-doc said every non-VISIBLE record has none. Now "Any other record
whose class is not LLAPI_SCAN_CLS_VISIBLE has no pathname: ...", as
llapi_scan_rec_path.3 words it. Comment only; carried to 68288 and every
commit above it (9 commits).

**R11 verified, with one correction to the scenario.** Kernel rule
(`may_delete()` -> `check_sticky()`): rename over an existing name in an
S_ISVTX directory fails EPERM unless fsuid owns the file or the directory,
or the caller has CAP_FOWNER (`capable_wrt_inode_uidgid`). Root passes on
ownership of /tmp or on CAP_FOWNER. The pre-pass probe (create + unlink our
own temp) passes there. **Correction:** on a default client a non-root
`lfs find --since-cookie` never reaches the cookie code: it fails ENODEV
first ("has no MDT this client can see": lmv target_obd is in debugfs,
0700), and even past that /dev/changelog-* is 0600 and the objects need
`-o user_fid2path`. So the lreview "cron job as another user" needs a
site that opened those up; the default-config way to hit the same EPERM
is root without CAP_FOWNER (container, systemd CapabilityBoundingSet).

Fix in `find_cookie_check()`: after the probe, if the cookie exists and
`find_cookie_may_replace()` says no, refuse with -EPERM and the same text
as the probe failure ("cannot write the cookie '%s'"). The helper: owner
== geteuid() -> yes; the cookie's directory not sticky or owned by
geteuid() -> yes; else CAP_FOWNER in the effective set (capget(2), no
libcap). Includes `<sys/syscall.h>`, `<linux/capability.h>`. Man pages:
lfs-find.1 (after "refused before the search prints anything": "So is
another user's FILE in a sticky directory such as /tmp, which the run
could not replace.") and llapi_find_since.3 -EPERM entry. Commit message
of 68419: one sentence added to the pre-pass paragraph. Gated on 68419's
Change-Id (the -EPERM man entry and the include block exist below it).

| branch | before (m1019-*) | after |
|---|---|---|
| fork-1014 | 0a114635ae | 14292fa6fc |
| fork-69501 | 5b5bcd9986 | 4322f54548 |
| fork-69502 | 51907c9108 | cfc0ed9365 |
| fork-69503 | 362886bf33 | unchanged (below 68288) |
| rate-1017 | 395f238177 | unchanged |
| maxrate-1017 | e55448a62e | unchanged |
| igif-1017 | 6c43ee2168 | 6845d93b35 |

68288 is now a775233eef, 68419 3fa29803eb.

- Dry run (tx_1019f-dry.log) = real run (tx_1019f.log), same shas; a
  second pass changes nothing. Commit counts and Change-Ids unchanged;
  no new message line over 75.
- Build sweep (sweep_f.sh, sweep_f.log): `SWEEP 4637f31c47..14292fa6fc,
  6 commits` + 69501/69502 (2) + 69729 (1): 9/9 build=0 hdr=0 tests=0 sh=0.
- checkpatch (checkpatch_f.txt): 68288 and 68419 same findings before and
  after (known noise only; 68419 none of its own).
- groff -ww: llapi_find_since.3 0; lfs-find.1 1, the upstream `-printf
  "%u %M %i \n"` example (present on master-1014 too).
- Range-diff (range-diff-f.txt): 68288 and 68419 `!`; bca3b301fc `!`
  for hunk context only; every other commit `=`.

**Lab** (tests/lab-1019f/, clone VM, modules 2.17.58_65_g8618869, arms
userspace-only: o = m1019-fork-1014 0a114635ae, t = fork-1014 14292fa6fc,
each lfs run with LD_PRELOAD of its arm lib, ld.so line logged; VM shut
down after). One fixture, cookies seeded by root then chowned
(04-sticky.result.txt):

| case | o (old) | t (new) |
|---|---|---|
| N: nishida, default perms | ENODEV before cookie code | same |
| A2: root-seeded /tmp/job.ck 0644, nishida (debugfs + changelog dev opened, -o user_fid2path), x2 alternated, 2 runs each | prints 3, "cannot rewrite ... the next run would repeat this one", rc 1; run 2 prints the same 3 | nothing printed, "cannot write the cookie '/tmp/job.ck': Operation not permitted", rc 1, both runs |
| F: root -cap_fowner, nishida's cookie in nobody's 1777 dir, x2 alternated | prints 3 then "cannot rewrite", same 3 again | refused, nothing printed |
| B: root, own cookie in /tmp | rc 0, 3 then 0 | same |
| C2: nishida, own cookie in /tmp | rc 0, 3 then 0 | same |
| D: root over nishida's cookie in /tmp | rc 0 | same |
| E: root over nishida's cookie in nobody's 1777 dir (CAP_FOWNER path) | rc 0 | same |
| G: root -cap_fowner, own cookie there | rc 0 | same |

(A, without user_fid2path: o "3 of 3 changed objects could not be read",
nothing printed; t the up-front EPERM.)

- sanity 160Aa-Af on t: 6/6 on MDSCOUNT=1 and 6/6 on MDSCOUNT=2
  (03-all.result.txt).

Notes: `~/lfs-fork-1014` has igif-1017 checked out, and the branch was
moved under it by update-ref (this round and the 68415 r2 one); its index
shows the l1019 state staged as a revert. Content only, nothing lost --
`git -C ~/lfs-fork-1014 reset --hard` syncs it. Not done: lreview (by
instruction), push.
