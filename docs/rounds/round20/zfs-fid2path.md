# test_167 on ZFS: the pool was never found

`conf-sanity test_167` failed on **every** ZFS configuration from PS10
onward.  The cause is one missing argument in the test, not a defect in
the scanner.

## What it actually was

The test scans a stopped OST with its pool exported.  An exported pool is
not in any config cache -- Lustre creates its pools with `cachefile=none`
-- so `scan_zfs_import()` finds it the way `zpool import` does, by reading
vdev labels under a search path.  That path defaults to `/dev`, and
`--search DIRS` exists to say otherwise.  `libscan_zfs.c` says so in its
own comment: *"a pool on file vdevs is not under /dev; the caller says
where"*.

The test framework's ZFS vdevs are **files in `$TMP`**:

    ostvdevname 1 -> /tmp/lustre-ost1

so `zpool_find_config()` looking under `/dev` found nothing,
`dmu_objset_own()` stayed at `ENOENT`, and `lfind` answered:

    lfind: cannot open lustre-ost1/ost1: No such file or directory (2)

test_167 never passed `--search`.  test_166 and test_168 are ldiskfs-only
by construction, which is why nothing else in the series showed it.

## The fix

test_167, in the branch that already exports the pool:

    search="--search $(dirname $(ostvdevname 1))"

`ostvdevname` returns the empty string on ldiskfs, so the ldiskfs arm is
unchanged.  Folded into `LU-20637 llapi: name a device scan's objects`,
the change that owns test_167.

## Verified

On `rhel9.7-server-mgs-mds-clone`, MDSCOUNT=1 OSTCOUNT=1:

| run | result |
|-----|--------|
| `FSTYPE=zfs ONLY=167` | **PASS 167 (20s)** -- "offline --fid2path named 20 objects by their owner" |
| `FSTYPE=ldiskfs ONLY="166 167 168"` | PASS 166 (16s), PASS 167 (1s), PASS 168 (71s) |

By hand, with the pool exported, before and after:

    lfind --device lustre-ost1/ost1 --fid2path ... --type f
      -> cannot open lustre-ost1/ost1: No such file or directory (2), exit 1
    lfind --device lustre-ost1/ost1 --search /tmp --fid2path ... --type f
      -> 5 of 5 names, exit 0

## Four hypotheses this replaces

All four were measured directly and all four are wrong.  Recording them
because each one was plausible enough to write code against:

1. **`kernel_init()` / `kernel_fini()` / `kernel_init()` deadlocks
   libzpool** -- the code's own comment said so.  A standalone program
   does it and returns.
2. **The full double open/close cycle** (`kernel_init`, `spa_import`,
   `dmu_objset_own`, disown, `spa_export`, `kernel_fini`, twice) against a
   real exported pool -- both cycles complete.
3. **`tt_label` unreadable, so the fsname check answers `-EXDEV`** --
   `dsl_prop_get(lustre:svname)` returns `lustre-OST0000`, strlen 14.
4. **The ZFS backend was not built** -- `ZFS_SCAN_ENABLED` is TRUE and
   `scan_zfs.so` is installed.

The thing that settled it was none of these: it was running the failing
command by hand and reading the errno.  The test writes `lfind`'s output
to `$got.raw`, which its own `stack_trap` deletes, so neither CI nor the
first local run ever showed the error text.  **The double open was never
implicated** -- the comparison arm without `--fid2path`, a single open,
failed identically.

## Note

`sh conf-sanity.sh` runs bash in POSIX mode and breaks `stack_trap`'s
`trap -p` merge:

    test-framework.sh: eval: line 7475: unexpected EOF while looking for
    matching `''

Run it with `bash`, not `sh`.
