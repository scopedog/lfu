# adilger on 68156, 2026-10-19 21:03 UTC: what was done

The user's call was to follow all six comments. Everything is local: nothing
pushed, nothing posted. The draft replies are in `replies.md`, section
"adilger 68156".

| # | id | where | what he asked |
|---|---|---|---|
| A1 | a59a8bba | /COMMIT_MSG:87 (PS36) | "with fixes": the message must not talk about earlier versions |
| A2 | 4bbe6d43 | conf-sanity.sh:13370 (PS30) | `%LF` should print the MDT FID; add `%LO` for OST object FIDs |
| A3 | 92f32c7a | conf-sanity.sh:13593 (PS36) | test with `lfs find --device`, not with a dedicated tool |
| A4 | c2744717 | conf-sanity.sh:13611 (PS36) | use `-printf '%LF'`, not one path2fid per path |
| A5 | 69637d7f | libscan_ldiskfs.c:77 (PS36) | the comment overstates: last_rcvd and CONFIGS/mountdata also name the target |
| A6 | 4257d2cf | liblustreapi_scan_device.c:823 (PS30) | "Seems reasonable." Nothing to do |

## The design of %LO (A2)

| directive | walk, or MDT device scan | OST device scan, data object | OST scan, other objects |
|---|---|---|---|
| `%LF` | the file's FID (unchanged) | **the FID of the file the object belongs to** (`ff_parent` from `trusted.fid`, or the LMA on a 256-byte-inode OST); nothing if no file owns it yet | the object's own FID (unchanged) |
| `%LO` (new) | the FIDs of the file's OST objects, from the layout: `[f1,f2]` per component, concatenated as `%Lo` does (`[a][b,c]`) | `[own FID]` | nothing |

- A FID is printed as `%LF` prints it, `DFID_NOBRACE` (`0x...:0x...:0x...`).
  The list is built like `%Lo`: comma-separated, one bracketed list per
  component.
- A stripe with no object yet (object id 0) is left out. A component with
  no objects (not instantiated, DoM, foreign, a default) prints nothing,
  not `[]`. A directory prints nothing, as do an object with no layout and
  an object off Lustre.
- An OST data object is `lfsr_class == LLAPI_SCAN_CLS_OST_OBJ`. Every
  device scan asks for the class already.
- Object FID: an internal `layout_ost_fid_get()` in liblustreapi_layout.c,
  declared in lustreapi_internal.h, calls `ostid_to_fid(l_ost_oi,
  l_ost_idx)`, which is what `lfs getstripe -y` prints as `l_fid`. No
  public API was added.
- `printf_format_want()`: `%LO` asks for the layout. From 68288 on, `%LF`
  also asks for `LLAPI_SCAN_OWNER`, which reads `trusted.fid`.
- `validate_printf_fmt()` in liblustreapi.c accepts `O`. Without that,
  lfs warned "unrecognized format directive '%LO'" while it printed the
  right answer. The first lab pass showed this.
- `lfsr_fid` keeps its meaning (the object's own FID). This is the
  answer already given on the PS30 thread. Only the `-printf` directive
  changes.

### Choices for the user (each changes visible output)

1. **The `%LO` shape.** It uses the `%Lo` form: brackets per component,
   commas inside. An OST scan also prints brackets, `[fid]`, so that one
   parser reads both cases. Alternative: a bare FID on an OST.
2. **`%LF` on an OST object with no `trusted.fid`** (precreated, never
   written) prints **nothing**. This matches "nothing for an object the scan
   has no FID for" and the `--fid2path` rule that such an object has no
   name. Alternative: fall back to the OST FID. That would mix two kinds
   of FID in one column.
3. **Before 68288, `%LF` prints nothing for an OST data object.** The
   owner is read only from 68288 on ("name a device scan's objects"), so
   68159-68163 cannot print the MDT FID. Moving `LLAPI_SCAN_OWNER` down to
   68159 would put a UAPI struct field in the middle of `llapi_scan_rec`,
   below 68415's changelog fields, and would also move backend code. That
   was judged too invasive. The man page and message of each commit say
   what it prints.
4. **The default output (no `-printf`) of an OST scan still prints each
   object's own FID.** He commented only on `%LF`. But his PS30 comment of
   10-14 said MDT FIDs "should be the default", and that could mean the
   default line too. Making that change would drop every ownerless object
   from the listing, so it was left for the user to decide.
5. **`%LO` works on a walk too** (sanity 56Ea), because the code path is
   the same. It is a general new `lfs find` directive, which is what he
   suggested.

## Which commit got what (A3/A4: the tests move)

Before, 68156 added `llapi_scan_device_test` and conf-sanity 300a/300b,
and 300a's oracle was the tool's `-l` FID list. Now:

| commit | change |
|---|---|
| 68156 LU-20606 | no conf-sanity tests and no tool: `llapi_scan_device_test.c`, its Makefile.am and .gitignore lines, and the `run_test_tbl()` split in llapi_test_utils.{c,h} all move to 68160. The label comment is fixed (A5). Message: "with fixes by Artem" becomes "by Artem" (A1); the test paragraphs are replaced by "The tests come with lfs find --device ..." |
| 68415, 68416, 68157, 68158 | tree only: the tool is not in them now (no message change) |
| 68159 LU-20611 run find over a device scan | `%LO` (walk + scan), `%LF` prints nothing for an OST data object, `layout_ost_fid_get()`, the validator, sanity 56Ea checks `%LO` against `lfs getstripe -y`, lfs-find.1 `%LO` entry, llapi_find_device.3 paragraph; message paragraph |
| 68160 LU-20611 lfs find --device | adds the tool (without `-l`) and conf-sanity 300a/300b. 300a: the device list is `lfs find --device -printf '%LF\n'` (it was the tool's `-l`); both sides use `-printf` (A4); a striped file checks `%LO` against `getstripe -y`; `--type f -printf '%LF %LO'` on the MDT must match the walk. 300b: 20 written files on ost1, and `lfs find --device ost1 -printf '%LO'` must give back each object FID the client printed. lfs-find.1 says what `%LF`/`%LO` print on an OST. Message: test paragraph rewritten, `run_tests()` split sentence moved here |
| 68163 ZFS | the same test edits in its ZFS-aware form (`--search $sdir/$odir`, zfs skip); Makefile.am comment "drives this as the oracle" becomes "runs this against" |
| 68288 LU-20637 | `%LF` prints the owner (`LLAPI_SCAN_OWNER`) for an OST data object; `printf_format_want()` asks for the owner for `%LF`; 300b checks `-printf '%LF %LO'` (the file's MDT FID plus the object's own) against the walk; lfs-find.1 and llapi_find_device.3 text; message paragraph |
| above (68417-69500, 69501-69503, 69700, 69728, 69729) | carried (same text as their base) |

The tool keeps its API checks (stats invariant, thread counts,
pre-filter, stop, bad arguments, and 69700's test7 rate). `lfs find` cannot
show those. It is a choice for the user whether to drop the tool
altogether, since he said "rather than a dedicated test tool"; here only
its FID-oracle role was replaced.

### A1: other messages checked for patch-history talk

Every message in the tree was grepped (previous/earlier version, patch set,
review, "with fixes", "no longer", "now", "used to", ...). Only 68156's
"with fixes by Artem" talks about earlier versions of the patch. Every
"no longer"/"now"/"before" elsewhere compares with the parent tree (upstream
code or an earlier commit of the series), which is what a commit message
should do. Nothing else was changed. Borderline but left: 68156 "The
scanner is new here, so these are how it is written rather than fixes to
anything in the tree", and 68288 "Measured on an OST formatted with -I 256:
without this, none of 33 objects had an owner."

## Mechanics

- `docs/rounds/a-1019/tx_1019c.py` (transforms) with the driver
  `forktx5.py`: forktx4.py plus ANC (Change-Ids of the commit's ancestry,
  used for the 68159/68160/68288 gates), file deletion, `ALWAYS` paths and
  DRY into `refs/tx1019c/*`. The transforms are idempotent: a re-run on the
  result maps every commit to itself, and a run from the `j1019-*` originals
  reproduces the branches exactly.
- Backups: tags `j1019-<branch>` (= the trunk 8afc606951 and the six leaves
  as the 160Ac agent left them).
- Branches now: fork-1014 **7b24dd3149** (68156 b39fe0036b, 68159
  0751092444, 68160 ab2cf69fe0, 68163 48a6b6d5c9, 68288 4e053e7953),
  fork-69501 9ffadff6c0, fork-69502 d973a4f179, fork-69503 185bb93cf6,
  rate-1017 7aac33ca4a, maxrate-1017 7d61eb12e0, igif-1017 56ea5cdf37.
  Commit counts are unchanged and every Change-Id survives. Logs:
  `tx_1019c.log`, `tx_1019c-2.log` (the validator added in a second pass).
- `~/lfs-fork-1014` (igif-1017) and `~/lfs-maxrate-1015` (maxrate-1017)
  were `reset --hard` to their moved branch. The staged "M" files in
  lfs-maxrate-1015 were left over from earlier ref moves: its HEAD was
  still aeb51b77f8 = h1019, and the files were a subset of h1019..i1019.

## Verification

- Build sweep (`sweep_c.sh`, `sweep_c.log`): all 20 rewritten commits
  `build=0 hdr=0 tests=0 sh=0`, and libscan_ldiskfs.c compiles at each
  (ldiskfs=0). `bash -n` on conf-sanity.sh passes at every leaf.
- checkpatch (`checkpatch_c.txt`): every commit has the same findings as
  before, except two known-noise additions. 68159 gets lfs-find.1's
  upstream warnings ("BASH COMPLETION" section, short-opt header), because
  68159 now touches that page. 68160 gets "MAINTAINERS" for the new file
  it carries. groff `-ww`: the only warning is the pre-existing register
  `"` warning in upstream lfs-find.1. No message line is over 75 columns.
- Lab (`tests/lab-1019c/`, VM rhel9.7-server-mgs-mds-clone, modules
  2.17.58_65_g8618869, arm lfs + library + PLUGIN_DIR + hand-built
  scan_osd_ldiskfs.so per arm, ld.so line in each run; VM shut down after):

| run | lib | conf-sanity.sh | result |
|---|---|---|---|
| t-300, t-300r | tip b4279c1085 (before the validator) | tip | 300a PASS, 300b PASS (with the '%LO' warning noise) |
| **t2-300** | tip **7b24dd3149** | tip | **300a PASS, 300b PASS**, no warnings |
| **c2-300** | 68160 **ab2cf69fe0** | 68160 | **300a PASS, 300b PASS** |
| o-300 | old tip 8afc606951 (no %LO) | tip | 300a **FAIL** "%LO of striped is not [..]: ... %LO" (negative control) |
| o-300b | old tip | tip | 300b **FAIL** (prints a literal %LO) |
| ct-300b | 68160 (no owner yet) | tip | 300b **FAIL** "20 objects not given back": the 68288 `%LF` check needs the owner |

  The hand check (`04-hand.sh` and `06-hand-mdt.sh`, results in
  05-all.result.txt and 06-hand-mdt.result.txt) used FSNAME=lfsh, one
  MDT, two OSTs, arm t. It had six files: f0 and f1 (one stripe on each
  OST), s2 (-c 2), pfl (1M on OST0, then -c 2), pfl1 (second component
  never instantiated) and nowrite (never written).
  - The MDT image scan, `--type f -printf '%LF %LO'`, gives **6/6 lines
    equal to the client walk**. The walk in turn equals `lfs path2fid` plus
    `getstripe -y l_fid`. pfl prints `[a][b,c]`, and pfl1 lists only its
    instantiated object. A directory prints an empty `%LO`.
  - The OST scans give **7 of 9 objects as `<file FID> [<own FID>]`**,
    matching path2fid and getstripe. The two others print ` [own]` with an
    empty `%LF`: nowrite's object, and pfl's second object on OST0
    (0x240000400:0x5). debugfs shows that neither has a `trusted.fid`. pfl's
    second component has a 4M stripe size, so the 3 MB write never reached
    stripe 1. That is the "no file owns it yet" case, and it is correct.
  - OST internal objects and precreated objects print ` [fid]`. The default
    output still prints `[own FID]`.
  - Also: 04-hand.sh's MDT mount-point match missed (the mount is
    `lfsh-mds1`), so 06-hand-mdt.sh read the left-over MDT image instead.

Not done: lreview of the changed commits (owed before any push, with the
other a-1019 items); a ZFS run of 300a/300b.
