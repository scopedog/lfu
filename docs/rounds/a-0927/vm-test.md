# 2026-09-27: VM test of r0927-tip (the 09-27 local fixes)

**Verdict: every suite is green on the tip, and all 8 A/B arms show the fix
on new and the defect on old. Nothing here blocks the next push.** Nothing
was pushed and nothing was posted to Gerrit.

The arms script scored 18 PASS / 4 FAIL. All 4 FAILs were mistakes in my
checks, not in the code:

- the glimpse check traced nothing, so it was re-run on its own;
- the duplicate-error check counted a line that both arms print;
- two MDT checks assumed `! --mdt` works, and upstream it is a no-op.

Each is explained under its arm below. None of them is a defect in the new
arm.

## Setup

- VM `rhel9.7-server-mgs-mds-clone`. It was shut off, so I started it, and
  shut it down again at the end. Its `~/lustre-release` was not touched,
  and neither was the EC rig.
- **Arms.** Both were built from `git archive` tarballs of
  `~/lfs-artem-0924`, whose work tree was not touched. They are userspace
  only (`--disable-modules --disable-server`). Each arm has its own private
  prefix. `scan_osd_ldiskfs.so` and `scan_osd_kernel.so` were built by hand
  into that prefix's PLUGIN_DIR:
  - **new** = `r0927-tip` **`73d04cd04d`**, tree `e7c85093df`. Tree
    `~/lab0927-new`, prefix `~/arm0927new`.
  - **old** = `backup/artem-0924-pre-0927` `b8c7d9c5b8` (r0926b-tip), tree
    `524f846172`. Tree `~/lab0927-old`, prefix `~/arm0927old`.
- **Which SHA each run used.** The tag moved during the lab. The first
  sanity run used the earlier tip `364133e009`: 93 PASS, 0 FAIL, the same
  56xc skip, kept in `raw/lab0927-sanity-364133/`. The new arm was then
  rebuilt from `73d04cd04d`, which adds only `find_device_entry()`
  (68288 df006952). **Every run reported below used `73d04cd04d`**: the
  second sanity run, the arms, the glimpse re-run, conf-sanity and the ZFS
  arms.
- **Proof of which files were loaded.** LD_TRACE shows each lfs loading its
  own `~/arm0927<arm>/lib/liblustreapi.so.1`. strace shows each opening its
  own `~/arm0927<arm>/lib/lustre/scan_osd_ldiskfs.so`, and in the ZFS arm
  its own `~/arm0927z<arm>/lib/lustre/scan_osd_zfs.so`.
- **Proof that the arms differ.** Only new's lfs has "join its directories
  with ':'": new 1, old 0. "ss_class has no room" is a static_assert, so it
  is in neither binary, as expected. The `find_device_entry()` rebuild is
  inlined, so it has no symbol. It is proven by the source grep (new 2, old
  0) and by the remote-hardlink arm. The two ZFS plugins' `.text` differ.
  The make logs have 0 errors.
- **Modules and framework:** the installed ones. `lctl get_param -n
  version` = `2.17.58_65_g8618869`; it was non-empty and checked in every
  run. lfu.ko was not loaded during the arms, so mounted targets were read
  by the device backend. conf-sanity 305 loads lfu.ko itself.
- **Fixture:** `FSNAME=lfst`, MDSCOUNT=2, OSTCOUNT=2, formatted by the
  sanity run. The arms ran on it live, then on disposable **copies** of the
  quiescent images. `/tmp/lfst-mdt1` and `/tmp/lfst-ost2` had the same md5
  before and after (`md5sum -c` OK). The ZFS arm used its own
  `FSNAME=zfst` and `TMP=/tmp/zfslab27`, and the ldiskfs images' md5 was
  unchanged.
- In the suite runs, the tip's `lfs` and `llapi_scan_*` binaries were
  bind-mounted over the installed ones, and unmounted afterwards. No binds
  remain.

Scripts: [`vm-lab/`](vm-lab/). Raw logs: [`vm-lab/raw/`](vm-lab/raw/).

## Test suites, on the tip (73d04cd04d)

| suite | result |
|---|---|
| sanity 56 (whole group) | 86 PASS, 0 FAIL, 1 SKIP (56xc: needs 2 GB free) |
| sanity 56El | PASS, not skipped (tmpfs mounted). The new `%Lc%Lh%Li%Lo` check on `d1` ran inside it |
| sanity 157c | PASS: test0-test17 all pass |
| sanity 157d | PASS: "ten bad calls refused with -EINVAL"; "3 of 8 resolved when asked" (68415 _RESOLVE without EVENT_UID) |
| sanity 160aa, 160ab, 160ac, 160ad, 160ae | PASS, none skipped |
| conf-sanity 300, 301, 302, 303, 304, 305 | PASS. 305 really scanned through lfu.ko: "a scan of the mounted lfsc-MDT0000 named 20 objects" |

The sanity run gave `SANITY_RC=0`: 93 PASS, 0 FAIL. The two "SKIP" lines
are the same 56xc skip counted twice. conf-sanity gave `CS_RC=0`.
`scan_osd_kernel.so` was in the private PLUGIN_DIR from the start this
time, so 305 passed on the first run (the lesson from 09-26).

## Arms (new = 73d04cd04d, old = b8c7d9c5b8)

### 1. 68159 a3e82a81: the label separator in --ost / --mdt

On a **copy** of `/tmp/lfst-ost2` (lfst-OST0001; 63 objects), I relabelled
the copy with `tune2fs -L` and counted the lines printed:

| label | `--ost lfst-OST0001_UUID` new / old | `! --ost …_UUID` new / old | `--ost 1` new / old |
|---|---|---|---|
| `lfst-OST0001` (control) | 63 / 63 | 0 / 0 | 63 / 63 |
| `lfst=OST0001` | **63 / 0** | **0 / 63** | 63 / 63 |
| `lfst:OST0001` | **63 / 0** | **0 / 63** | 63 / 63 |
| `lfst+OST0001` | **63 / 0** | **0 / 63** | 63 / 63 |

On a copy of `/tmp/lfst-mdt1`, with `-type f` (9 files):

| label | `--mdt lfst-MDT0000_UUID` new / old | `! --mdt …_UUID` new / old | `--mdt 0` new / old |
|---|---|---|---|
| `lfst-MDT0000` (control) | 9 / 9 | 9 / 9 | 9 / 9 |
| `lfst=MDT0000` | **9 / 0** | 9 / 0 | 9 / 9 |
| `lfst:MDT0000` | **9 / 0** | 9 / 0 | 9 / 9 |

- **PASS.** On new, every separator matches the UUID. On old, none of the
  three does.
- The two FAILs in the tally are the `! --mdt` column. My check expected 0
  there. But `! --mdt` is a no-op upstream: nothing sets `fp_exclude_mdt`
  (this is in [[lfu-tickets-to-file]] item 4). The control row shows this:
  with the ordinary label, both arms print 9 for `! --mdt`. So the column
  shows the known upstream bug, not this fix. The fix is in the positive
  column.

### 2. 68159 d314fd23: a failed probe says it once

`lfs find --device /nonexistent/dev --pool foo` (and `--stripe-count 1`
gives the same):

    new:  lfs find: cannot scan '/nonexistent/dev': No such file or directory (2)
          lfs: failed for '/nonexistent/dev': No such file or directory
    old:  lfs find: cannot scan '/nonexistent/dev': No such file or directory (2)
          lfs find: cannot scan '/nonexistent/dev': No such file or directory (2)
          lfs: failed for '/nonexistent/dev': No such file or directory

- **PASS.** In new the library error appears once; in old it appears twice.
  Both arms exit with rc 2.
- The trailing `lfs: failed for` line is lfs's own summary. The control
  (`-type f`, no layout option) prints it in both arms, and its stderr is
  identical in new and old. My check wrongly counted all stderr lines, which
  is the third FAIL in the tally.

### 3. 68160 6a512e82: no glimpse when probing a start path

Two 2 MB files on OST0000. I ran `lfs find --lazy g1 g2 --size +1G` under
strace. Before each run I cleared the client's OSC lock LRU. The arms
alternated twice ([`lab0927-glimpse.sh`](vm-lab/lab0927-glimpse.sh)):

| run | first syscall on each start path | OST `ldlm_glimpse_enqueue` | client OST0000 locks |
|---|---|---|---|
| new, round 1 | `statx(AT_FDCWD, ".../g1", AT_STATX_DONT_SYNC, STATX_TYPE, …)` | 2 -> 2 | 0 -> 0 |
| old, round 1 | `newfstatat(AT_FDCWD, ".../g1", {… st_size=2097152 …}, 0)` | 2 -> **4** | 0 -> **2** |
| new, round 2 | statx, same as round 1 | 4 -> 4 | 0 -> 0 |
| old, round 2 | newfstatat | 4 -> **6** | 0 -> **2** |

- **PASS.** New asks for the type only and causes no glimpse. Old does a
  full stat, which costs one glimpse per file.
- The first tally FAIL was my check: it traced with `-e trace=%stat`, and
  strace 6.12 on the VM matched no call at all in either arm. The re-run
  names the syscalls.
- **A bare block device still selects a device scan.** `lfs find
  /dev/mapper/mds1_flakey --type f` gives the same 7 lines as `--device`.
  So does a read-only loop device of the MDT copy (9 lines). **PASS.**

### 4. 68288 41cdec96: an orphan in PENDING is not given its old path

I created `/mnt/lfst/dorph/f` and held it open in a background sleeper
(`exec 7<`), then ran `rm` and `sync`. `debugfs -c` showed the orphan on the
live MDT device: `/PENDING/0x200000402:0x934:0x0`. Then I ran
`lfs find --device /dev/mapper/mds1_flakey --internal --paths`:

| | new | old |
|---|---|---|
| all | `/dorph /dorph/keep`; "269 matching objects have no pathname" | `/dorph /dorph/f /dorph/keep`; "268 …" |
| `--name f` | nothing; "1 matching objects have no pathname and were not printed" | **`/dorph/f`** |
| `--name f` without `--paths` | `[0x200000402:0x934:0x0]` | the same |

**PASS.** New still delivers the orphan's record (its FID) and counts it as
nameless. Old names it by the link it had. The sleeper was closed
afterwards.

### 4b. 68288 df006952: a remote hardlink as linkea entry 0 (DNE), added mid-lab

I ran `lfs mkdir -i 0 dh0` and `lfs mkdir -i 1 dh1`, then `echo > dh0/f`,
`ln dh0/f dh1/g` and `mv dh0/f dh0/f2`. The file is on MDT0 with 2 links.

The premise is proven, not assumed. `trusted.link` on MDT0, read with
`debugfs -c -R 'ea_get /ROOT/dh0/f2 trusted.link'`, is
`df f1 ea 11 02 00 00 00 …`. Its entry 0 is parent `[0x240000402:0x618]`
(MDT1's sequence) with name `67` = "g". Its entry 1 is parent
`[0x200000402:0x936]` with name `66 32` = "f2". `lfs fid2path` lists them in
the same order: `/mnt/lfst/dh1/g /mnt/lfst/dh0/f2`.

Then `lfs find --device <MDT0> --paths --type f`:

| args | new | old |
|---|---|---|
| none | **`/dh0/f2`** | nothing; "1 matching objects have no pathname and were not printed" |
| `--name f2` | `/dh0/f2` | `/dh0/f2` (already fine: --name picked entry 1) |
| `--name g` | nothing, 1 nameless | the same (only the remote entry matches) |

**PASS.**

### 5. 68415 a18d496d: _RESOLVE without EVENT_UID

This is covered by the suites. sanity 157d passed ("3 of 8 resolved when
asked"; "want 0x2000100000200 -> got 0x2000100000000 without a resolve"),
and so did 160aa-160ae. **PASS.**

### 6. 68156 7c1ae981: the size of struct llapi_scan_stats

[`sizeof.c`](vm-lab/sizeof.c), compiled against each arm's header:

    new: sizeof(struct llapi_scan_stats)=168 ss_class=16 entries, offsetof(ss_class)=40, LLAPI_SCAN_CLS_MAX=7
    old: sizeof(struct llapi_scan_stats)=96 ss_class=7 entries, offsetof(ss_class)=40, LLAPI_SCAN_CLS_MAX=7

- **The numbers are 168 and 96, not the 160 and 104 in the brief.** The
  struct is `ss_size` and `ss_padding` (8 bytes), then four `__u64`
  counters (32 bytes), then `ss_class`. So new is 40 + 16x8 = 168, and old
  is 40 + 7x8 = 96. The header change is exactly what 7c1ae981 describes.
  No page or commit message states a byte size, so nothing needs
  correcting.
- 157c and 157d passed, including the stats checks.

### 7. 68163 dc43e70c: ZFS blocks include the dnode slots

I used separate ZFS-capable arm builds (`--with-zfs=/usr/src/zfs-2.2.11`,
in `~/lab0927z-*` and `~/arm0927z*`), from the same two tarballs. `make -k`
failed only in the known upstream `libmount_utils_zfs.c`. `llmount.sh` with
`FSTYPE=zfs FSNAME=zfst` made the fixture. I read `stat -c %b` from the
client while the fs was mounted, then exported the pools
(`zpool list` empty). Then I ran `lfs find --device zfst-mdt1/mdt1 --search
/tmp/zfslab27 -type d -printf '%LF %b\n'`:

| dir | client `stat %b` | new | old |
|---|---|---|---|
| zsmall (1 file) | 14 | **14** | 12 |
| zmid (300) | 66 | **66** | 64 |
| zbig (3000) | 814 | **814** | 812 |

- **PASS.** New equals the client on 3 of 3 directories. Old is exactly 2
  lower on every object, including the 4 internal directories (13 vs 12);
  2 is `dn_num_slots` for these dnodes.
- My first attempt used `-printf … --paths`, which lfs refuses by design
  ("-printf cannot be used with --paths or --fid2path"). Its log is in
  `raw/lab0927-zfs-try1/`.

## VM state after the tests

- lfst, lfsc and zfst were cleaned up. No Lustre mount, no pool, no flakey
  dm device, no loop device and no bind remains. The Lustre modules are
  unloaded.
- The disposable image copies were deleted, and the ZFS vdev dir
  `/tmp/zfslab27` was removed.
- The arm trees `~/lab0927-{new,old}` and `~/lab0927z-{new,old}`, and the
  prefixes `~/arm0927{new,old,znew,zold}`, were left in place. `/home` has
  2.0 GB free.
- The VM was shut down, as it was off at the start.

## Not covered

- Kernel code at the tip: none was built. 305 ran against the installed
  lfu.ko.
- `! --mdt` stays a no-op. That is upstream and ticket-owed, not ours.
- 68288 df006952 on a stopped MDT image (it ran on the live MDT0 device),
  and under `--fid2path`.

## 09-27 follow-up: 68163 ZFS test changes

**Verdict: PASS.** With the plugin in place, ZFS conf-sanity 300 passes and
runs the new `--target` check. With a present-but-broken plugin it FAILs; it
does not SKIP. With the plugin absent it SKIPs with "no zfs scan backend in
this build". ldiskfs conf-sanity 300-305 still passes.

- **SHA.** The ZFS runs used `r0927-tip` = **`719b60f73e`**, with 68163 =
  `0439ba0ba2`, built with `lab0927-zbuild.sh`; the ZFS arm is in
  `~/lab0927z-new` and `~/arm0927znew`. `llapi_scan_device_test` was built
  separately there, because `make -k` stops before `lustre/tests`. The tag
  moved again afterwards to `133643bd9e`. That move changes only 68415's
  `liblustreapi_scan_changelog.c` and man pages, so 68163's code under test
  is the same. The ldiskfs regression ran on `133643bd9e`.
- **Harness.** Script [`lab0927-confz.sh`](vm-lab/lab0927-confz.sh), with
  `MODE=ok|broken|garbage|absent`. It uses `FSTYPE=zfs FSNAME=lfsc
  TMP=/tmp/zfslab27c`, so the vdev files are the ones test-framework makes.
  It bind-mounts the tip's `lfs` and `llapi_scan_*` binaries. `LFS` is a
  shim that logs every call's rc and stderr (`lfs-calls.txt`). The shim is
  what proves the new check ran: the test prints nothing when that check
  passes. LD_TRACE shows `~/arm0927znew/lib/liblustreapi.so.1`, and the
  PLUGIN_DIR is `~/arm0927znew/lib/lustre`. `$LUSTRE/utils` is
  `/usr/lib64/lustre/utils`, which does not exist.

| mode | PLUGIN_DIR | conf-sanity 300 | the new `--target` check (shim log) |
|---|---|---|---|
| ok | the arm's `scan_osd_zfs.so` | **PASS** (85 s), `CS_RC=0` | `lfs find --target lfsc-MDT0000 --type f -> rc 16`: "lfs find: lfsc-mdt1/mdt1: in use: pool imported, or dataset held". The "no zfs scan backend" echo is absent. The later `--device ... --search` scan: rc 0 |
| broken (first 4096 bytes of the .so) | truncated | **FAIL**: "--target lfsc-MDT0000 was not refused as in use" | rc **135**: lfs died of SIGBUS inside dlopen(), with no message |
| garbage (18-byte text file) | not ELF | **FAIL**: same error | rc 95: "no zfs device scan backend: .../arm0927znew/lib/lustre/scan_osd_zfs.so: file too short; /usr/lib64/lustre/utils/scan_osd_zfs.so: cannot open shared object file: No such file or directory". Both reasons appear, and zfs_scan_unbuilt() says "not unbuilt" |
| absent (empty dir bound over PLUGIN_DIR) | empty | **SKIP**: "no zfs scan backend in this build". The echo "lfs has no zfs scan backend in this build" appears first | rc 95: both reasons are "cannot open shared object file" |

After every mode the plugin was restored (md5 `55d96cd9492e`), no bind was
left, no pool was left imported, and nothing was left mounted.

- **The "broken" row.** A truncated ELF kills lfs with SIGBUS in the
  dynamic loader, before `scan_backend_load()` can report anything. The
  test still FAILs, as it should, but that row does not exercise the new
  two-reason message. The "garbage" row does. The SIGBUS is the loader
  mapping a file shorter than its program headers say; it is not the
  change under test.
- **ldiskfs conf-sanity 300-305, on `133643bd9e`:** all 6 PASS, `CS_RC=0`.
  305 reported "a scan of the mounted lfsc-MDT0000 named 20 objects".

Raw logs: `vm-lab/raw/lab0927f-confz-{ok,broken,garbage,absent}/`
(`run.txt`, `cs.txt`, `lfs-calls.txt`) and `vm-lab/raw/lab0927g-conf/`.
Build logs: [`build-followup.txt`](vm-lab/build-followup.txt).

## 09-27 follow-up 2: 68415 lreview fixes

**Verdict: PASS on all three code changes.** One limit: the nanosecond half
of (2) cannot be shown on Lustre. Lustre keeps whole-second mtimes, so both
arms answer `.000000000`, and so does the client's own `stat`. The btime
half does show the fix.

- **SHA.** new = `r0927-tip` **`133643bd9e`** (68415 = `62507e5a43`),
  rebuilt into `~/lab0927-new` / `~/arm0927new`. old = `b8c7d9c5b8`, the
  existing build.
- **Harness.** [`clres.c`](vm-lab/clres.c) calls `llapi_scan_changelog()`
  in event mode with `LLAPI_SCAN_CL_F_RESOLVE` and prints one line per
  record delivered. It was compiled against each arm's header, with the
  RPATH set to that arm's prefix; LD_TRACE confirms each arm loads its own
  library. Script: [`lab0927g-cl.sh`](vm-lab/lab0927g-cl.sh), on
  `FSNAME=lfst`, MDSCOUNT=2, with changelog user `cl7` on MDT0000
  (deregistered afterwards).
- **The script's tally (0 PASS, 3 FAIL) is wrong, and the mistake is mine.**
  Its checks grepped for FIDs such as `[0x…]` as regexes, where the
  brackets become a character class. The migrate check also used the
  directory's FID, but the record is about the file. I read the raw
  harness output instead; it is below. I corrected the checks in the
  script afterwards but did not re-run it.

### a. Regression: sanity 157c, 157d, 160aa-160ae on 133643bd9e

7 PASS, 0 FAIL, 0 SKIP (`SANITY_RC=0`). 157d printed "3 of 8 resolved when
asked", "ten bad calls refused with -EINVAL", and "want 0x2000100000200 ->
got 0x2000100000000 without a resolve".

### b. CL_MIGRATE delivers the migrated object once

`lfs mkdir -i 0 cm/mdir`, then `echo > mdir/mf`, then `lfs migrate -m 1
cm/mdir` (rc 0). The premise, from `lfs changelog lfst-MDT0000`:

    188 20MIGRT ... t=[0x240000402:0x3:0x0] ... p=[0x200000402:0x9e:0x0] mf s=[0x200000402:0x9f:0x0] sp=[0x240000402:0x2:0x0] mf

The harness from record 188, `sc_want = 0`:

    new: idx=188 type=MIGRT fid=[0x240000402:0x3:0x0] ... stx_mask=0xeff size=2 blocks=8 ...
    old: idx=188 type=MIGRT fid=[0x240000402:0x3:0x0] ... stx_mask=0x6ff size=2 blocks=8 ...
    old: idx=188 type=MIGRT fid=[0x200000402:0x9f:0x0] ... stx_mask=0 size=0 blocks=0 ...

**PASS.** New delivers one object, under its new FID. Old also delivers the
old FID, `s=`, and that record cannot be resolved (`stx_mask=0`).

### c. A lazy size of 0 is not an answer

A second client mount, `/mnt/lfst2`, was the writer. It kept `cm/lz` open
for write after writing 11 bytes, so there was no close and no SOM
(`trusted.som: No such attribute`). `/mnt/lfst` had never seen the file.
The control, `cm/lzc`, was written and closed. The harness ran with
`sc_want = LLAPI_SCAN_LAZY_SIZE` only:

| file | new | old |
|---|---|---|
| lz, open `[0x200000403:0x2]`, CREAT/OPEN | `lazy_size=0 lazy_blocks=0 size=0` | **`lazy_size=1 lazy_blocks=1 size=0`** |
| lzc, closed (control) `[0x200000403:0x1]` | `lazy_size=1 lazy_blocks=0 size=12 blocks=0` | `lazy_size=1 lazy_blocks=1 size=12 blocks=0` |

**PASS.** For the open file, new leaves both bits clear, and old marks a
size of 0 as a lazy answer. On the control, both arms mark the real lazy
size of 12. The control's `blocks` is 0, and new rightly leaves
LAZY_BLOCKS clear for it.

### d. Nanoseconds and btime

I ran `touch -m -d '2026-09-27 07:00:00.123456789' cm/ns`. **The client
itself then reported `07:00:00.000000000`**: Lustre stores whole-second
times, so no Lustre file has a nonzero `tv_nsec` to carry. The harness
(`sc_want = 0`) gave:

    new: ... stx_mask=0xeff ... mtime=1790517600.000000000 btime=1790520273.000000000
    old: ... stx_mask=0x6ff ... mtime=1790517600.000000000 btime=(absent)0.000000000

- **btime: PASS.** New fills it and sets STATX_BTIME (0x800 in stx_mask).
  Old does not.
- **Nanoseconds: not demonstrable on Lustre.** Both arms answer
  `.000000000`, which is correct, because the file has no fraction. The
  code path that copies `stx_mtime` whole is exercised, but it cannot be
  told apart from the old code here.

Raw logs: `vm-lab/raw/lab0927g-cl/` (`run.txt`, and `mig.*`, `lazy.*`,
`ns.*` per arm) and `vm-lab/raw/lab0927g-sanity/`.

### VM state after the follow-ups

Nothing is mounted. No pool, dm-flakey device, loop device or bind remains,
and the modules are unloaded. `/tmp/zfslab27c` and the broken, garbage and
empty stand-ins were removed. The VM was shut down.
