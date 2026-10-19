# a-1019 fixes applied (LOCAL ONLY, nothing pushed, nothing posted)

Taken: #1 #2 #5 #6 #7 #8 #9 (triage.md). Not touched: #3 #4 #10 #11 #12
(user decisions pending). Done 2026-10-19 in ~/lfs-fork-1014.

## Method

`forktx4.py` (copy of a-1018/forktx3.py, new IDX/R288) rewrote every commit
from 68156 up on all seven branches with `tx_1019.py` (string transforms on
trees, message transforms on 68415/68416/68419). No rebase, no conflicts:
#2 and #7 overlap 68288's own edits, and the tree rewrite simply applies the
68156/68416 text where it is still present (68288's rewrite of the
WANT_MDT_ONLY comment now starts from the HSM line, so its diff shrank).
Run twice from the backups (the first run left a needless `(char *)` cast in
the unit test); a third DRY run over the result changes nothing
(idempotent). `forktx4.log` has the per-commit HITS.

## Backup tags (old tips, = a1018-pushed-* except maxrate)

| branch | backup tag | old tip | new tip |
|---|---|---|---|
| fork-1014 (trunk 68156..69500) | h1019-fork-1014 | 103aef57d1 | ce898ad309 |
| fork-69501 | h1019-fork-69501 | 11fd879e26 | f7d6d85424 |
| fork-69502 | h1019-fork-69502 | ee4609ee75 | 28edbfcf96 |
| fork-69503 | h1019-fork-69503 | 08ad951a4f | 32071ca21c |
| rate-1017 (69700) | h1019-rate-1017 | dfa074ae7d | 77c70ab428 |
| igif-1017 (69729) | h1019-igif-1017 | 7b4c5ebc8a | f2ff082958 |
| maxrate-1017 (69728, held) | h1019-maxrate-1017 | aeb51b77f8 | 8e2c7b2e2b |

Commit counts unchanged on every branch; every Change-Id identical.

## What changed (range-diff.txt: only these five commits show `!`)

| change | old -> new | item | change |
|---|---|---|---|
| 68156 | 4f2824972c -> 3ee121a15a | #1 | lustreapi_internal.h: the one-mask comment names the STOP_ON_ERROR exception (device scan accepts and ignores it, as llapi_scan_device(3) says). Comment only |
| 68156 | | #2 | WANT_MDT_ONLY comment adds "the HSM state" |
| 68415 | d1688b30b0 -> ab51ae86d5 | #5 | commit msg: RESOLVE bullet reflowed |
| 68415 | | #6 | scan_cl_user_is_id(): with _CLEAR, lfsc_user must be `cl<N>` or `cl<N>-name`, else -EINVAL before any read. Man: lfsc_user entry + ERRORS line. llapi_scan_changelog_test test4: "1", "cl", "cl1x", "name" give -EINVAL and no record ("fourteen bad calls") |
| 68416 | 6e240c6728 -> e30c9f3e0d | #7 | llapi_scan_fid.3 SEE ALSO: + llapi_fid2path_at, llapi_path2fid, llapi_root_path_open |
| 68416 | | #8 | llapi_scan_fid(): after the getinfo FID check, if the gather left an fd, llapi_fd2fid(fd) must equal @fid, else -ESTALE (existing retry). Kernel-doc and man: a regular file opened by name is checked; a special file's projid (parent + name) is not. Commit msg: "...checked against the one asked for, on the getinfo and on any descriptor the gather opened." |
| 68288 | 0798e095e9 -> 83f20c99e3 | (#2 carry) | its comment hunk is now one line smaller; its own text unchanged |
| 68419 | 8923d31cf4 -> 09f86d9452 | #9 | commit msg: lfs-find.1 paragraph lists SYNOPSIS, OPTIONS, the target-scan refusals and EXAMPLES; "moves up" gone |

All other commits on all branches: `=` in range-diff (carried, tree has the
fixes, patch unchanged).

## Verification

- **Build sweep** (`sweep.sh` -> `sweep.log`, ~/lrv2-sweep): 20/20 commits
  `build=0 hdr=0 tests=0 sh=0`, libscan_ldiskfs 20/20, conf-sanity `bash -n`
  ok at all 5 leaves. Ranges printed: ee61b3f6dd..ce898ad309 (14),
  30e906185a..28edbfcf96 (2), d571f6bc9d..32071ca21c (1),
  2c56137a8a..8e2c7b2e2b (2), 83f20c99e3..f2ff082958 (1).
- **checkpatch** (`checkpatch.txt`): the five changed commits have exactly
  the same findings as before (all known noise: MAINTAINERS, ARRAY_SIZE in
  moved code, .TH length, lustreapi.7 section, 8530b4b78c Fixes: line).
  `groff -ww` on llapi_scan_changelog.3 and llapi_scan_fid.3: 0 warnings.
- **Message widths**: no new line over 75 columns.

## Lab (clone VM 192.168.122.10, was shut off; started with virsh, shut down after)

Loaded modules 2.17.58_65_g8618869. Arms userspace-only from git archive:
o = h1019-fork-1014 103aef57d1 (lib md5 3b200896fcd2), n = fork-1014
ce898ad309 (3778fc0bc67a). Scripts and raw output: `tests/lab-1019/`
(00-pack.sh .. 04-all.sh, race_open.c, scanfid_race.c, 03-04.result.txt).
Harness per arm has DT_RPATH to its own arm lib (ldd confirmed).

**#8 A/B** (03-race.sh): `scanfid_race` calls llapi_scan_fid() on f (A,
100 B, projid 1001), want = TYPE|FID|SIZE|PROJID|MDT_INDEX. An LD_PRELOAD
shim renames f.new (B, 200 B, projid 2002) over f at the gather's first
open() of f by name. Fresh directory per run, arms alternated, 2 rounds,
identical both rounds:

| case | o (old) | n (new) |
|---|---|---|
| plain (no race) | rc 0, fid A, size 100, projid 1001, fd A | same |
| race (A unlinked by the rename) | **rc 0, fid A, size 100, projid 2002, fd = B** (mixed) | rc -ENOENT, no callback (-ESTALE, retry, A is gone) |
| backup (A moved to f.bak first) | **rc 0, path f, fid A, projid 2002, fd = B** (mixed) | rc 0, path f.bak, fid A, size 100, projid 1001, fd A (retry found A) |

**#6 A/B**: n's llapi_scan_changelog_test `-o 4` with LD_PRELOAD of each
lib, alternated x2: o FAILs "clear with user '1' delivered 29 records" (82
the second time); n PASSes "fourteen bad calls refused with -EINVAL".

**Sanity on n** (lfs, liblustreapi, llapi_scan*_test bound from arm n):
56Eea 157c 160Aa 160Ab 160Ac 160Ad 160Ae 160Af: 8/8 PASS (157c runs
test17 llapi_scan_fid). 56Ea..56El + 56Eea: 17/17 PASS.

## Not done

- lreview (not run, by instruction).
- Nothing pushed, no replies posted. Drafts in replies.md.
- docs/rounds/a-1019 and tests/lab-1019 are not committed to the lfu repo.
