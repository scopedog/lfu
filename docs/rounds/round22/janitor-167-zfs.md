# 68288's Janitor −1: conf-sanity 167 on every ZFS config

Checked 2026-09-06. **Not resolved — instrumented**, and the earlier "resolved"
note was wrong.

## What the bot says

`Lustre Gerrit Janitor` gave Code-Review−1 on PS11:

    Newly added or changed test failed in initial testing:
    IMPORTANT: these tests appear to be new failures unique to this patch
    - conf-sanity4@zfs:test_167(Seen in reviews: 68416 68415)

and lists it failing on **21 ZFS sessions** — `conf-sanity4@zfs` plus every
`conf-sanity-special{1..10}@zfs` and `@zfs+DNE` — always as
`167(lfind --fid2path on a stopped lustre-ost1/ost1 failed)`. Every ldiskfs
session passed.

## The `--search` fix is in PS11, and it is not enough

`docs`/memory recorded this as resolved on 2026-09-03 by adding
`search="--search $(dirname $(ostvdevname 1))"`. PS11's `conf-sanity.sh`
carries that line, and the test still fails on every ZFS config. **The note
was wrong** and is corrected.

## What the CI artefacts do and do not say

From the janitor's own logs for `conf-sanity4@zfs`:

- 165, 166 and 168 all **SKIP** on ZFS (`zfs cannot be scanned while in
  service`), so **167 is the only ZFS coverage the scanner has in CI**.
- The ZFS event log shows `pool_export` at 18:51:41.9 — `export_zpool` did
  run — and the next pool event is the cleanup import 12 seconds later. The
  test failed inside that window.
- **The error text is nowhere.** test_167 redirected `lfind`'s stdout *and*
  stderr into `$got.raw`, which its own `stack_trap` deletes, so neither the
  suite log nor the test log carries a single word of why it failed.

## It passes here, on this VM

Built the lab tree with `--enable-zfs` (ZFS 2.2.11, el9.7) and ran the same
subtest against a ZFS filesystem:

    == conf-sanity test 167: lfind --fid2path names objects on a stopped OST
    offline --fid2path named 20 objects by their owner
    PASS 167 (3s)

So this is environment-dependent, and the two environments differ in at least
ZFS version (**CI 2.3.2**, here 2.2.11), distro (rocky8.10/9.6 vs el9.7) and
node layout (CI drives a separate server node through `do_facet`).

## What went in

The one thing that can be fixed without evidence: **the test now reports what
happened**. `stderr` goes to `$got.err`, kept apart from the answer in
`$got.raw`, and the failure quotes it —

    error "lfind --fid2path on stopped $ost1dev: $(cat $got.err)"

which is exactly what test_166 and test_168 already do. The next CI round will
say whether the pool could not be found, the plugin could not be loaded, or
the mount could not be reached, instead of only that it failed.

And the test now **asserts its own precondition**. `export_zpool()` in
test-framework is an `||` chain —

    ! $ZPOOL list -H $poolname || grep -q ^$poolname/ /proc/mounts ||
        $ZPOOL export $opts $poolname

— so a pool that is imported *and* has anything of itself in `/proc/mounts`
is left imported and the function still answers 0. A pool this host holds is
refused by the scan by design (`-EBUSY`, `/proc/spl/kstat/zfs/<pool>` is what
tells it), so that state fails on lfind and says nothing about why. After the
export the test now checks:

    do_facet ost1 "! $ZPOOL list -H $poolname >/dev/null 2>&1" ||
            error "$poolname is still imported after export_zpool"

Verified: PASS 167 on ZFS here with the stderr change, syntax clean on the
commit itself, checkpatch warnings unchanged, both amended into 68288. The
assertion itself is **not lab-run** — it is reached only where the export did
not happen, which is the state this VM never produced.

**No guess was applied to the code under test.** Three mechanisms are
plausible, ranked: the pool was never exported (`export_zpool`'s `||` chain,
which the new assertion now names outright); a libzpool 2.3 difference in
`zpool_find_config()`, where CI is 2.3.2 and this VM 2.2.11; and
`scan_zfs.so` not being reachable on the CI node. The first two are told
apart by one line of the next CI log.

One hypothesis **was** falsified from here rather than guessed at:
`ostvdevname()` returns `OSTDEV$num`, the vdev, while `ostdevname()` uses
`OSTZFSDEV$num`, the dataset — so `--search $(dirname $(ostvdevname 1))` is
well formed, and "the search path is garbage in CI" is out.
